import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/barcode_scan_mixin.dart';
import 'package:multimax/app/data/models/mr_item_row.dart';

import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';

import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';

// ── Shared sheet layer ─────────────────────────────────────────────────────────────────────────────

import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';

// ── SE-module-local widgets ───────────────────────────────────────────────────────────────────────────

import 'widgets/item_form_sheet/rack_section.dart';

class StockEntryFormController extends GetxController
    with OptimisticLockingMixin, BarcodeScanMixin {
  // ── Dependencies ───────────────────────────────────────────────────────────────────────────────────
  final StockEntryProvider  _provider       = Get.find<StockEntryProvider>();
  final ApiProvider         _apiProvider    = Get.find<ApiProvider>();
  final PosUploadProvider   _posProvider    = Get.find<PosUploadProvider>();
  final StorageService      _storageService = Get.find<StorageService>();
  final ScanService         _scanService    = Get.find<ScanService>();
  final DataWedgeService    _dataWedgeService = Get.find<DataWedgeService>();

  // ── Arguments ───────────────────────────────────────────────────────────────────────────────────
  // NOTE: these MUST be assigned inside onInit(), not as field initializers.
  // Field initializers run at class instantiation time when Get.arguments still
  // points to the previous route (WorkOrderForm). By onInit() the route
  // transition is complete and Get.arguments reflects StockEntryForm's args.
  String name = '';
  String mode = 'view';
  String? argStockEntryType;
  String? argCustomReferenceNo;
  /// Work Order name passed from executeWorkOrder(). Non-null only for
  /// the 'Material Transfer for Manufacture' flow.
  String? argWorkOrderName;

  // ── Document state ────────────────────────────────────────────────────────────────────────────────

  var isLoading        = true.obs;
  var isScanning       = false.obs;
  var isSaving         = false.obs;
  var isDirty          = false.obs;
  var isAddingItem     = false.obs;
  var isLoadingItemEdit = false.obs;
  var loadingForItemName = RxnString();

  var saveResult      = SaveResult.idle.obs;
  Timer? _saveResultTimer;

  var stockEntry  = Rx<StockEntry?>(null);
  var entrySource = StockEntrySource.manual;

  // ── Context data ───────────────────────────────────────────────────────────────────────────────────
  var mrReferenceItems = <Map<String, dynamic>>[];

  var posUpload              = Rx<PosUpload?>(null);
  var posUploadSerialOptions = <String>[].obs;
  var expandedInvoice        = ''.obs;

  // ── MR filter ───────────────────────────────────────────────────────────────────────────────────
  var mrItemFilter = 'All'.obs;

  // ── Form fields ───────────────────────────────────────────────────────────────────────────────────
  var fromWarehouse    = RxnString();
  var toWarehouse      = RxnString();
  final customReferenceNoController = TextEditingController();

  var stockEntryTypes      = <String>[].obs;
  var isFetchingTypes      = false.obs;
  var stockEntryType = 'Material Transfer'.obs;

  var warehouses          = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── Sheet & scan context ─────────────────────────────────────────────────────────────────────────────────
  final TextEditingController barcodeController = TextEditingController();
  var isItemSheetOpen = false.obs;

  var currentItemCode  = '';
  var currentVariantOf = '';
  var currentItemName  = '';
  var currentUom       = '';
  var currentScannedEan = '';

  // ── Item feedback ───────────────────────────────────────────────────────────────────────────────────
  var recentlyAddedItemName = ''.obs;
  final Map<String, GlobalKey> itemKeys = {};
  var itemFormKey = GlobalKey<FormState>();
  final ScrollController scrollController = ScrollController();

  Timer?  _autoSubmitTimer;
  Worker? _scanWorker;

  bool get isEditable => (stockEntry.value?.docstatus ?? 1) == 0;

  // ── Domain helpers ───────────────────────────────────────────────────────────────────────────────────

  String getTypeHelperText(String type) {
    switch (type) {
      case 'Material Issue':   return 'Remove stock from a warehouse (outbound movement).';
      case 'Material Receipt': return 'Receive stock into a warehouse (inbound movement).';
      case 'Material Transfer':
      case 'Material Transfer for Manufacture':
        return 'Move stock between warehouses without changing valuation.';
      default: return 'Configure how this stock movement should behave.';
    }
  }

  void ensureItemKey(StockEntryItem item) {
    if (item.name != null && !itemKeys.containsKey(item.name)) {
      itemKeys[item.name!] = GlobalKey();
    }
  }

  // ── POS qty-cap helpers ─────────────────────────────────────────────────────────────────────────────────
  //
  // Canonical formula (all three helpers form a consistent chain):
  //
  //   posQtyCapForSerial(s)   → the allowed total from the POS Upload document
  //   scannedQtyForSerial(s)  → Item1.qty + Item2.qty + … + ItemN.qty  (on SE)
  //   remainingQtyForSerial(s)→ cap − scanned  (clamped to [0, cap])

  /// Returns the POS Upload qty cap for [serial] (the idx string),
  /// or [double.infinity] when there is no POS context.
  double posQtyCapForSerial(String serial) {
    final idx = int.tryParse(serial);
    if (idx == null || posUpload.value == null) return double.infinity;
    return posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == idx)
            ?.quantity ??
        double.infinity;
  }

  /// Returns the total qty already recorded on this SE for [serial],
  /// across ALL item codes — optionally excluding one row ([excludeItemName]).
  double scannedQtyForSerial(String serial, {String? excludeItemName}) {
    return (stockEntry.value?.items ?? [])
        .where((i) =>
            (i.customInvoiceSerialNumber ?? '0') == serial &&
            i.name != excludeItemName)
        .fold(0.0, (sum, i) => sum + i.qty);
  }

  /// Remaining qty available for [serial] under the POS Upload cap.
  ///
  /// Pass [excludeItemName] when computing the ceiling for a row that is
  /// currently being edited — otherwise that row's saved qty is subtracted
  /// from the cap and the user sees a lower Max than the serial actually allows.
  double remainingQtyForSerial(String serial, {String? excludeItemName}) {
    final cap = posQtyCapForSerial(serial);
    if (cap == double.infinity) return double.infinity;
    // Forward excludeItemName so the editing row's already-saved qty is not
    // deducted from the cap — the user is replacing that qty, not adding to it.
    // Previously this parameter was accepted but silently dropped, causing
    // "Max" to show cap − editingRowQty instead of cap.
    debugPrint(
      '[remainingQtyForSerial] serial=$serial '
          'cap=$cap '
          'scanned=${scannedQtyForSerial(serial, excludeItemName: excludeItemName)} '
          'excludeItemName=$excludeItemName '
          'result=${(cap - scannedQtyForSerial(serial, excludeItemName: excludeItemName)).clamp(0.0, cap)}',
    );
    return (cap - scannedQtyForSerial(serial, excludeItemName: excludeItemName))
        .clamp(0.0, cap);
  }

  // ── MR helpers ───────────────────────────────────────────────────────────────────────────────────

  bool get isMaterialRequestEntry =>
      customReferenceNoController.text.startsWith('MAT-MR-');

  List<MrItemRow> get mrAllItems {
    final entry = stockEntry.value;
    return mrReferenceItems.map((ref) {
      final code         = ref['item_code'] as String? ?? '';
      final requestedQty = (ref['qty'] as num?)?.toDouble() ?? 0.0;
      final matReq       = ref['material_request'] as String? ?? '';
      final matReqItem   = ref['material_request_item'] as String? ?? '';
      final scannedQty   = entry?.items
              .where((i) => i.itemCode.trim().toLowerCase() ==
                  code.trim().toLowerCase())
              .fold(0.0, (sum, i) => sum + i.qty) ??
          0.0;
      return MrItemRow(
        itemCode: code, requestedQty: requestedQty, scannedQty: scannedQty,
        materialRequest: matReq, materialRequestItem: matReqItem,
      );
    }).toList();
  }

  List<MrItemRow> get mrFilteredItems {
    final all = mrAllItems;
    switch (mrItemFilter.value) {
      case 'Pending':   return all.where((r) => r.isPending).toList();
      case 'Completed': return all.where((r) => r.isCompleted).toList();
      default:          return all;
    }
  }

  // ── POS helpers ───────────────────────────────────────────────────────────────────────────────────

  Future<void> fetchPosUpload(String posId) async {
    try {
      final response = await _posProvider.getPosUpload(posId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final pos = PosUpload.fromJson(response.data['data']);
        posUpload.value = pos;
        final count = pos.items.length;
        posUploadSerialOptions.value =
            List.generate(count, (i) => (i + 1).toString());
      }
    } on DioException catch (e) {
      if (isClosed) return;
      final reason = e.response?.statusCode == 404
          ? PosUploadErrorReason.notFound
          : PosUploadErrorReason.networkError;
      GlobalDialog.showPosUploadError(
        posId:   posId,
        reason:  reason,
        onRetry: () => fetchPosUpload(posId),
      );
    } catch (e) {
      if (isClosed) return;
      GlobalDialog.showPosUploadError(
        posId:   posId,
        reason:  PosUploadErrorReason.networkError,
        onRetry: () => fetchPosUpload(posId),
      );
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    // Read route arguments here — after the route transition is complete —
    // so Get.arguments reliably reflects StockEntryForm's own arguments.
    name                               = Get.arguments?['name']              ?? '';
    mode                               = Get.arguments?['mode']              ?? 'view';
    argStockEntryType                  = Get.arguments?['stockEntryType']    as String?;
    argCustomReferenceNo               = Get.arguments?['customReferenceNo'] as String?;
    argWorkOrderName                   = Get.arguments?['workOrderName']     as String?;
    final String? argWorkOrder         = Get.arguments?['workOrder'];

    initScanWiring();
    _initDependencies();
    if (mode == 'new') {
      _initNewStockEntry();
    } else {
      fetchStockEntry();
    }
  }

  void _initDependencies() {
    fetchWarehouses();
    fetchStockEntryTypes();

    // Doc-level scan worker: fires only when no item sheet is open.
    // Sheet-level scans are owned by BarcodeAwareMixin on the child controller.
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty && !isItemSheetOpen.value) scanBarcode(code);
    });

    ever(fromWarehouse,    (_) => _markDirty());
    ever(toWarehouse,      (_) => _markDirty());
    ever(stockEntryType,   (_) => _markDirty());

    // customReferenceNoController listener removed.
    // The reference number is read-only in the UI (set once from route arguments).
    // fetchPosUpload() is called directly in _initNewStockEntry() and
    // fetchStockEntry() where needed. No runtime listener is required.
  }

  @override
  void onClose() {
    disposeScanWiring();
    _autoSubmitTimer?.cancel();
    _saveResultTimer?.cancel();
    final bcc = barcodeController;
    final crc = customReferenceNoController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bcc.dispose();
      crc.dispose();
    });
    super.onClose();
  }

  // ── Scan behaviour ───────────────────────────────────────────────────────────────────────────────────

  @override
  bool shouldBlockScan() =>
      checkStaleAndBlock() || !_validateHeaderBeforeScan();

  @override
  Future<void> onScanResult(ScanResult result) async {
    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) {
      // _handleSheetScan(result.rawCode);
      return;
    }

    if (!result.isSuccess || result.itemData == null) {
      GlobalSnackbar.error(message: result.message ?? 'Scan failed');
      return;
    }

    if (!_validateScanContext(result)) return;

    if (result.rawCode.contains('-') &&
        !result.rawCode.startsWith('SHIPMENT')) {
      currentScannedEan = result.rawCode.split('-')[0];
    } else {
      currentScannedEan = result.rawCode;
    }

    final itemData   = result.itemData!;
    currentItemCode  = itemData.itemCode;
    currentVariantOf = itemData.variantOf ?? '';
    currentItemName  = itemData.itemName;
    currentUom       = itemData.stockUom ?? 'Nos';
    await _openNewItemSheet(scannedBatch: result.batchNo);
  }

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }

  // ── New entry init ───────────────────────────────────────────────────────────────────────────────────

  Future<void> _initNewStockEntry() async {
    isLoading.value = true;
    final type = argStockEntryType    ?? 'Material Transfer';
    final ref  = argCustomReferenceNo ?? '';

    stockEntryType.value             = type;
    customReferenceNoController.text = ref;
    determineSource(type, ref);

    final prefillItems = await _resolvePrefillItems(ref);
    _resolveHeaderWarehouses(prefillItems);

    stockEntry.value = _buildInitialStockEntry(
      type:         type,
      ref:          ref,
      prefillItems: prefillItems,
    );

    for (final item in prefillItems) ensureItemKey(item);
    isLoading.value = false;
    isDirty.value   = true;
  }

  /// Resolves the prefill items list based on [entrySource].
  /// Returns an empty list for manual entries.
  Future<List<StockEntryItem>> _resolvePrefillItems(String ref) async {
    switch (entrySource) {
      case StockEntrySource.workOrder:
        return _mapWorkOrderItems();
      case StockEntrySource.materialRequest:
        await _initMaterialRequestFlow(ref);
        return [];
      case StockEntrySource.posUpload:
        await fetchPosUpload(ref);
        return [];
      case StockEntrySource.manufacture:
        return await _fetchAndMapManufactureItems(); // ← fetch at init time
      case StockEntrySource.manual:
        return [];
    }
  }


  /// Maps raw route-argument items into [StockEntryItem] instances.
  List<StockEntryItem> _mapWorkOrderItems() {
    final argFrom = Get.arguments?['fromWarehouse'] as String?;
    final argTo   = Get.arguments?['toWarehouse']   as String?;
    if (argFrom != null) fromWarehouse.value = argFrom;
    if (argTo   != null) toWarehouse.value   = argTo;

    final rawItems = Get.arguments?['items'] as List? ?? [];
    return rawItems.asMap().entries.map((entry) {
      final e  = Map<String, dynamic>.from(entry.value as Map);
      final id = 'wo_prefill_${entry.key}_${DateTime.now().millisecondsSinceEpoch}';
      final sW = (e['s_warehouse'] as String?)?.isNotEmpty == true
          ? e['s_warehouse'] as String
          : argFrom;
      final tW = (e['t_warehouse'] as String?)?.isNotEmpty == true
          ? e['t_warehouse'] as String
          : argTo;
      return StockEntryItem(
        name: id, itemCode: e['item_code'] as String? ?? '',
        itemName:  e['item_name']   as String?,
        qty:       (e['qty']        as num?)?.toDouble() ?? 0.0,
        basicRate: (e['basic_rate'] as num?)?.toDouble() ?? 0.0,
        itemGroup: e['item_group']  as String?,
        customVariantOf: e['variant_of'] as String?,
        batchNo:   e['batch_no']    as String?,
        rack:      e['rack']        as String?,
        toRack: null, sWarehouse: sW, tWarehouse: tW,
        customInvoiceSerialNumber: null,
        materialRequest: null, materialRequestItem: null,
      );
    }).toList();
  }

  /// Falls back header warehouse fields from prefill items when not set by args.
  void _resolveHeaderWarehouses(List<StockEntryItem> items) {
    if (items.isEmpty) return;
    fromWarehouse.value ??= items.first.sWarehouse;
    toWarehouse.value   ??= items.first.tWarehouse;
  }

  /// Constructs the initial [StockEntry] value object for a new document.
  StockEntry _buildInitialStockEntry({
    required String type,
    required String ref,
    required List<StockEntryItem> prefillItems,
  }) {
    final now = DateTime.now();
    return StockEntry(
      name:              'New Stock Entry',
      purpose:           type,
      totalAmount:       0.0,
      postingDate:       DateFormat('yyyy-MM-dd').format(now),
      modified:          '',
      creation:          now.toString(),
      status:            'Draft',
      docstatus:         0,
      stockEntryType:    type,
      postingTime:       DateFormat('HH:mm:ss').format(now),
      customTotalQty:    0.0,
      customReferenceNo: ref,
      workOrder:         argWorkOrderName,
      currency:          'AED',
      items:             prefillItems,
      fromBom:           Get.arguments?['fromBom']        as bool?   ?? false,
      bomNo:             Get.arguments?['bomNo']           as String?,
      fgCompletedQty:   (Get.arguments?['fgCompletedQty'] as num?)?.toDouble() ?? 0.0,
    );
  }

  void _wireAutoSubmit(StockEntryItemFormController child) {
    final autoEnabled   = _storageService.getAutoSubmitEnabled();
    final autoDelaySecs = _storageService.getAutoSubmitDelay();
    child.setupAutoSubmit(
      onValid: () async {
        if (!autoEnabled)           return;
        if (!isItemSheetOpen.value) return;
        if (!isEditable)            return;
        isAddingItem.value = true;
        await Future.delayed(Duration(seconds: autoDelaySecs));
        await addItem();
        isAddingItem.value = false;
      },
    );
  }

  void determineSource(String type, String ref) {
    final rawItems = Get.arguments?['items'];
    final hasItems = rawItems is List && rawItems.isNotEmpty;
    final hasWo    = argWorkOrderName != null && argWorkOrderName!.isNotEmpty;

    if (hasWo && type == 'Manufacture') {
      // Finish flow: WO name present, no items — fetched after SE is saved.
      entrySource = StockEntrySource.manufacture;
    } else if (hasWo && hasItems) {
      // Execute flow: WO name + prefilled items (Material Transfer for Manufacture).
      entrySource = StockEntrySource.workOrder;
    } else if (hasItems) {
      entrySource = StockEntrySource.materialRequest;
    } else if (type == 'Material Issue' &&
        (ref.startsWith('KX') || ref.startsWith('MX'))) {
      entrySource = StockEntrySource.posUpload;
    } else if (ref.isNotEmpty) {
      entrySource = StockEntrySource.materialRequest;
    } else {
      entrySource = StockEntrySource.manual;
    }
  }

  Future<void> _initMaterialRequestFlow(String ref) async {
    if (Get.arguments?['items'] is List &&
        (Get.arguments?['items'] as List).isNotEmpty) {
      final rawItems = Get.arguments['items'] as List;
      mrReferenceItems =
          rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      try {
        final response =
            await _apiProvider.getDocument('Material Request', ref);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'];
          if (data['material_request_type'] != null) {
            stockEntryType.value = data['material_request_type'];
          }
          final items = data['items'] as List? ?? [];
          mrReferenceItems = items
              .map((i) => {
                    'item_code': i['item_code'],
                    'qty': i['qty'],
                    'material_request': ref,
                    'material_request_item': i['name'],
                  })
              .toList();
        } else {
          GlobalSnackbar.error(
              message: 'Failed to fetch Material Request details');
        }
      } catch (e) {
        GlobalSnackbar.error(message: 'Error fetching Material Request: $e');
      }
    }
  }

  /// Calls ERP's make_stock_entry whitelist API to resolve the full
  /// items list (BOM components + production item) for a Manufacture SE.
  ///
  /// Returns the items as [StockEntryItem] instances ready to be set as
  /// the initial items table — no SE document needs to exist yet.
  Future<List<StockEntryItem>> _fetchAndMapManufactureItems() async {
    final woName = argWorkOrderName;
    if (woName == null || woName.isEmpty) return [];

    final fgQty   = (Get.arguments?['fgCompletedQty'] as num?)?.toDouble() ?? 1.0;
    final argFrom = Get.arguments?['fromWarehouse'] as String?;
    final argTo   = Get.arguments?['toWarehouse']   as String?;

    try {
      final res = await _provider.getItemsForManufactureEntry(
        workOrderName:  woName,
        fgCompletedQty: fgQty,
      );

      if (res.statusCode != 200 || res.data['message'] == null) {
        GlobalSnackbar.warning(
          message: 'Could not load BOM items. Add them manually.',
        );
        return [];
      }

      final message  = res.data['message'] as Map<String, dynamic>;
      final rawItems = message['items'] as List? ?? [];

      if (rawItems.isEmpty) {
        GlobalSnackbar.warning(
          message: 'BOM returned no items. Check BOM is active.',
        );
        return [];
      }

      // ── NEW: fetch batch+rack from the linked Transfer SE ──────────────────
      // Silently skipped when no submitted Transfer SE exists (graceful
      // degradation — items still appear, batch/rack just remain blank).
      Map<String, TransferRow> transferLookup = {};
      try {
        final linkedSe = await _provider.getLinkedTransferSE(woName);
        if (linkedSe != null) {
          transferLookup = await _provider.getTransferSEItemLookup(linkedSe);
        }
      } catch (_) {
        // Non-fatal: BOM items still prefill correctly without batch/rack.
      }
      // ──────────────────────────────────────────────────────────────────────

      return rawItems.asMap().entries.map((entry) {
        final e          = Map<String, dynamic>.from(entry.value as Map);
        final id         = 'mfg_prefill_${entry.key}_${DateTime.now().millisecondsSinceEpoch}';
        final isFinished = e['is_finished_item'];

        final sW = (e['s_warehouse'] as String?)?.isNotEmpty == true
            ? e['s_warehouse'] as String
            : argFrom;
        final tW = (e['t_warehouse'] as String?)?.isNotEmpty == true
            ? e['t_warehouse'] as String
            : argTo;

        // ── NEW: pull batch + source rack from Transfer SE for raw
        //   material rows only. Finished good row keeps nulls so
        //   the user can enter the target rack manually.
        final isFinishedBool =
            isFinished == true || isFinished == 1;
        final transfer = isFinishedBool
            ? null
            : transferLookup[e['item_code'] as String? ?? ''];

        return StockEntryItem(
          name:            id,
          itemCode:        e['item_code']   as String? ?? '',
          itemName:        e['item_name']   as String?,
          qty:             (e['qty']        as num?)?.toDouble() ?? 0.0,
          basicRate:       (e['basic_rate'] as num?)?.toDouble() ?? 0.0,
          itemGroup:       e['item_group']  as String?,
          customVariantOf: e['variant_of']  as String?,
          // Transfer SE values take priority; BOM row values are the fallback.
          batchNo:         transfer?.batchNo ?? e['batch_no'] as String?,
          rack:            transfer?.rack    ?? e['rack']     as String?,
          toRack:          null,   // target rack: user fills for finished item
          sWarehouse:      sW,
          tWarehouse:      tW,
          customInvoiceSerialNumber: null,
          materialRequest:     null,
          materialRequestItem: null,
          isFinishedItem:  isFinished,
        );
      }).toList();
    } on DioException catch (e) {
      GlobalSnackbar.warning(
        message: 'Could not fetch BOM items: ${e.response?.statusCode}',
      );
      return [];
    }
  }

  // ── Fetch document ───────────────────────────────────────────────────────────────────────────────────

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;

        stockEntryType.value = entry.stockEntryType ?? 'Material Transfer';
        fromWarehouse.value  = entry.fromWarehouse;
        toWarehouse.value    = entry.toWarehouse;

        final ref = entry.customReferenceNo ?? '';
        customReferenceNoController.text = ref;

        if (entry.stockEntryType == 'Material Issue' &&
            entry.customReferenceNo != null) {
          final refNo = entry.customReferenceNo!;
          if (refNo.startsWith('KX') || refNo.startsWith('MX')) {
            entrySource = StockEntrySource.posUpload;
            await fetchPosUpload(refNo);
          } else if (entry.items.any((i) => i.materialRequest != null)) {
            entrySource = StockEntrySource.materialRequest;
            final first = entry.items
                .firstWhereOrNull((i) => i.materialRequest != null);
            if (first != null && first.materialRequest!.isNotEmpty) {
              await _initMaterialRequestFlow(first.materialRequest!);
            }
          } else {
            entrySource = StockEntrySource.manual;
          }
        } else {
          entrySource = StockEntrySource.manual;
        }

        isDirty.value = false;
      } else {
        GlobalDialog.showError(
          title:   'Could not load Stock Entry',
          message: 'The server returned an unexpected response. '
              'Check your connection and try again.',
          onRetry: fetchStockEntry,
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title:   'Could not load Stock Entry',
        message: e.toString(),
        onRetry: fetchStockEntry,
      );
    } finally {
      isLoading.value = false;
      isScanning.value = false; // safety: never leave scan-spinner active after a fetch
    }
  }

  @override
  Future<void> reloadDocument() async {
    isStale.value    = false;
    isScanning.value = false;
    await fetchStockEntry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) {
          GlobalSnackbar.success(message: 'Document reloaded successfully');
        }
      });
    });
  }

  // ── Warehouse helpers ──────────────────────────────────────────────────────────────────────────────────

  bool get requiresSourceWarehouse {
    final t = stockEntryType.value;
    return t == 'Material Transfer' ||
        t == 'Material Transfer for Manufacture' ||
        t == 'Material Issue';
  }

  bool get requiresTargetWarehouse {
    final t = stockEntryType.value;
    return t == 'Material Transfer' ||
        t == 'Material Transfer for Manufacture' ||
        t == 'Material Receipt';
  }

  bool enforceWarehouseBeforeScan() {
    if (requiresSourceWarehouse &&
        (fromWarehouse.value == null ||
            fromWarehouse.value!.isEmpty)) {
      return true;
    }
    if (requiresTargetWarehouse &&
        (toWarehouse.value == null ||
            toWarehouse.value!.isEmpty)) {
      return true;
    }
    return false;
  }

  bool _validateHeaderBeforeScan() {
    if (requiresSourceWarehouse &&
        (fromWarehouse.value == null ||
            fromWarehouse.value!.isEmpty)) {
      GlobalSnackbar.warning(
          message: 'Please set the Source Warehouse (Details tab) before scanning.');
      return false;
    }
    if (requiresTargetWarehouse &&
        (toWarehouse.value == null ||
            toWarehouse.value!.isEmpty)) {
      GlobalSnackbar.warning(
          message: 'Please set the Target Warehouse (Details tab) before scanning.');
      return false;
    }
    return true;
  }

  void propagateHeaderWarehouseToItems({required bool source}) {
    final entry = stockEntry.value;
    if (entry == null || entry.items.isEmpty) return;

    final newWarehouse = source
        ? fromWarehouse.value
        : toWarehouse.value;
    if (newWarehouse == null || newWarehouse.isEmpty) return;

    final updated = entry.items.map((item) {
      return StockEntryItem(
        name:       item.name,
        itemCode:   item.itemCode,
        qty:        item.qty,
        basicRate:  item.basicRate,
        itemGroup:  item.itemGroup,
        customVariantOf: item.customVariantOf,
        batchNo:    item.batchNo,
        itemName:   item.itemName,
        rack:       item.rack,
        toRack:     item.toRack,
        sWarehouse: source ? newWarehouse : item.sWarehouse,
        tWarehouse: source ? item.tWarehouse : newWarehouse,
        customInvoiceSerialNumber: item.customInvoiceSerialNumber,
        materialRequest:     item.materialRequest,
        materialRequestItem: item.materialRequestItem,
        isFinishedItem: item.isFinishedItem,
        owner:      item.owner,
        creation:   item.creation,
        modified:   item.modified,
        modifiedBy: item.modifiedBy,
      );
    }).toList();

    stockEntry.update((val) => val?.items.assignAll(updated));
    _markDirty();
  }

  bool _validateScanContext(ScanResult result) {
    if (entrySource == StockEntrySource.materialRequest) {
      if (mrReferenceItems.isEmpty) return true;
      final scanned = result.itemData?.itemCode ?? '';
      final found = mrReferenceItems.any((r) =>
          r['item_code'].toString().trim().toLowerCase() ==
          scanned.trim().toLowerCase());
      if (!found) {
        GlobalSnackbar.error(
            message: 'Item $scanned not found in Material Request');
        return false;
      }
    }
    return true;
  }

  StockEntryItem _enrichItemWithSourceData(StockEntryItem item) {
    String? matReq     = item.materialRequest;
    String? matReqItem = item.materialRequestItem;
    String? serial     = item.customInvoiceSerialNumber;

    if (entrySource == StockEntrySource.materialRequest &&
        mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems.firstWhereOrNull((r) =>
          r['item_code'].toString().trim().toLowerCase() ==
          item.itemCode.trim().toLowerCase());
      if (ref != null) {
        matReq     = ref['material_request'];
        matReqItem = ref['material_request_item'];
        serial     = '0';
      }
    } else if (entrySource == StockEntrySource.posUpload) {
      serial = item.customInvoiceSerialNumber;
    }

    return StockEntryItem(
      name:       item.name,
      itemCode:   item.itemCode,
      qty:        item.qty,
      basicRate:  item.basicRate,
      itemGroup:  item.itemGroup,
      customVariantOf: item.customVariantOf,
      batchNo:    item.batchNo,
      itemName:   item.itemName,
      rack:       item.rack,
      toRack:     item.toRack,
      sWarehouse: item.sWarehouse,
      tWarehouse: item.tWarehouse,
      customInvoiceSerialNumber: serial,
      materialRequest:     matReq,
      materialRequestItem: matReqItem,
      isFinishedItem: item.isFinishedItem,
      owner:       item.owner,
      creation:    item.creation,
      modified:    item.modified,
      modifiedBy:  item.modifiedBy,
    );
  }

  // ── Item CRUD ───────────────────────────────────────────────────────────────────────────────────

  void updateItemLocally(
    String uniqueId, double qty, String? batch,
    String? sourceRack, String? targetRack,
    String? sWarehouse, String? tWarehouse, String? serial,
  ) {
    final items = stockEntry.value?.items.toList() ?? [];
    final idx   = items.indexWhere((i) => i.name == uniqueId);
    if (idx == -1) return;

    final resolvedSerial = serial ?? '0';
    if (resolvedSerial != '0' && posUpload.value != null) {
      final cap           = posQtyCapForSerial(resolvedSerial);
      final othersQty     = scannedQtyForSerial(resolvedSerial,
          excludeItemName: uniqueId);
      final currentRowQty = items[idx].qty;

      if (othersQty + qty > cap) {
        final posItem = posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == int.tryParse(resolvedSerial));
        GlobalDialog.showQtyCapExceeded(
          serialNo:   int.parse(resolvedSerial),
          itemName:   posItem?.itemName ?? items[idx].itemName ?? '',
          scannedQty: othersQty + currentRowQty,
          capQty:     cap,
        );
        return;
      }
    }

    final existing = items[idx];
    var updated = StockEntryItem(
      name:       existing.name,
      itemCode:   existing.itemCode,
      qty:        qty,
      basicRate:  existing.basicRate,
      itemGroup:  existing.itemGroup,
      customVariantOf: existing.customVariantOf,
      batchNo:    batch,
      itemName:   existing.itemName,
      rack:       sourceRack,
      toRack:     targetRack,
      sWarehouse: sWarehouse,
      tWarehouse: tWarehouse,
      customInvoiceSerialNumber: serial,
      materialRequest:     existing.materialRequest,
      materialRequestItem: existing.materialRequestItem,
      isFinishedItem: existing.isFinishedItem,
      owner:      existing.owner,
      creation:   existing.creation,
      modified:   existing.modified,
      modifiedBy: existing.modifiedBy,
    );
    updated = _enrichItemWithSourceData(updated);
    items[idx] = updated;
    stockEntry.update((val) => val?.items.assignAll(items));
  }

  void addItemLocally(
    double qty, String? batch, String? sourceRack, String? targetRack,
    String? sWarehouse, String? tWarehouse, String? serial,
  ) {
    final resolvedSerial = serial ?? '0';

    if (resolvedSerial != '0' && posUpload.value != null) {
      final items       = stockEntry.value?.items.toList() ?? [];
      final cap         = posQtyCapForSerial(resolvedSerial);
      final alreadyUsed = scannedQtyForSerial(resolvedSerial);

      final existingIdx = items.indexWhere((i) =>
          i.itemCode.trim().toLowerCase() ==
              currentItemCode.trim().toLowerCase() &&
          (i.batchNo  ?? '') == (batch       ?? '') &&
          (i.rack     ?? '') == (sourceRack  ?? '') &&
          (i.customInvoiceSerialNumber ?? '0') == resolvedSerial);
      final mergeQty  = existingIdx != -1 ? items[existingIdx].qty : 0.0;
      final projected = alreadyUsed - mergeQty + qty;

      if (projected > cap) {
        final posItem = posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == int.tryParse(resolvedSerial));
        GlobalDialog.showQtyCapExceeded(
          serialNo:   int.parse(resolvedSerial),
          itemName:   posItem?.itemName ?? currentItemName,
          scannedQty: alreadyUsed,
          capQty:     cap,
        );
        return;
      }
    }

    final uniqueId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    var newItem = StockEntryItem(
      name:       uniqueId,
      itemCode:   currentItemCode,
      qty:        qty,
      basicRate:  0.0,
      itemGroup:  null,
      customVariantOf: currentVariantOf,
      batchNo:    batch,
      itemName:   currentItemName,
      rack:       sourceRack,
      toRack:     targetRack,
      sWarehouse: sWarehouse,
      tWarehouse: tWarehouse,
      customInvoiceSerialNumber: serial,
    );
    newItem = _enrichItemWithSourceData(newItem);
    ensureItemKey(newItem);
    final items = stockEntry.value?.items.toList() ?? [];
    items.add(newItem);
    stockEntry.update((val) => val?.items.assignAll(items));
  }

  // ── addItem coordinator ──────────────────────────────────────────────────────────────────────────────────
  bool _isClosingSheet = false;

  Future<void> addItem() async {
    _autoSubmitTimer?.cancel();
    final child = Get.find<StockEntryItemFormController>();

    // 1. Run submit() through the state machine so the button immediately
    //    transitions to the orange loading spinner while work is in progress.
    //    submitWithFeedback() sets saveButtonState → loading → success/error
    //    and returns false if validation or submit() itself throws.
    final success = await child.submitWithFeedback();
    if (!success) return; // button already shows error state for 1.5 s then resets

    // Guard: prevent double-close if auto-submit and manual tap race.
    if (_isClosingSheet) return;

    final items = stockEntry.value?.items ?? [];
    final String highlightKey = child.editingItemName.value ??
        (items.lastOrNull?.name ?? '');
    barcodeController.clear();
    triggerHighlight(highlightKey);

    // 2. Dismiss the keyboard BEFORE closing the sheet so the IME-dismiss
    //    frame has no live TextEditingControllers to rebuild against.
    //    FocusManager.instance.primaryFocus?.unfocus() works from the
    //    controller layer without needing a BuildContext.
    FocusManager.instance.primaryFocus?.unfocus();

    // 3. Wait one frame for the IME insets callback to fire and settle.
    //    This ensures Flutter's WindowInsets rebuild (triggered by the OS
    //    collapsing the keyboard) completes BEFORE we close the sheet and
    //    schedule controller disposal.
    await Future.delayed(Duration.zero);

    // 4. Execute the save WHILE the sheet (and its controllers) are still alive.
    //    The controllers are not disposed until after this returns.
    // 4. Save — keep sheet open on failure so user can retry.
    bool saved = false;
    if (mode == 'new') {
      try {
        await saveStockEntry();
        saved = true;
      } catch (_) {
        saved = false;
      }
    } else {
      isDirty.value = true;
      try {
        await saveStockEntry();
        saved = true;
      } catch (_) {
        saved = false;
      }
    }

    // 5. Only NOW close the sheet. GetX will call onDelete → disposeControllers()
    //    which defers TEC disposal to the next two frames via postFrameCallback.
    //    At this point the save is complete, the keyboard is fully dismissed,
    //    and no widget rebuild is in-flight that references qtyController.
    // 5. Close sheet only on success (or always close — your choice).
    if (saved && !_isClosingSheet && Get.isBottomSheetOpen == true) {
      _isClosingSheet = true;
      Get.back();
      // Reset the flag after the closing frame completes so the next
      // item scan can open a fresh sheet normally.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isClosingSheet = false;
      });
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────────────────────────

  void confirmAndDeleteItem(StockEntryItem item) {
    if (isItemSheetOpen.value) {
      if (Get.isBottomSheetOpen == true) Get.back();
    }
    GlobalDialog.showConfirmation(
      title:   'Remove Item?',
      message: 'Are you sure you want to remove ${item.itemCode} from this entry?',
      onConfirm: () {
        final items = stockEntry.value?.items.toList() ?? [];
        items.removeWhere((i) => i.name == item.name);
        stockEntry.update((val) => val?.items.assignAll(items));
        isDirty.value = true;
        GlobalSnackbar.success(message: 'Item removed');
      },
    );
  }

  // ── Sheet lifecycle ─────────────────────────────────────────────────────────────────────────────────

  /// Opens the item-form sheet for a NEW item.
  ///
  /// Made async (Commit 5) so that [child.initialise()] — which fetches
  /// item metadata from ERP and pre-loads the rack-stock map — fully
  /// completes before the bottom sheet is presented.
  ///
  /// Commit 6: setupAutoSubmit() call updated to match the base-class
  /// single-param signature. Auto-submit guard logic (enabled flag, delay,
  /// sheet-open check) is inlined into the [onValid] lambda.
  Future<void> _openNewItemSheet({String? scannedBatch}) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    final child = Get.put(StockEntryItemFormController());

    // ✔ Await initialise() so _parent is wired and item meta is ready.
    await child.initialise(
      parent:           this,
      code:             currentItemCode,
      name:             currentItemCode,
      variantOf:        currentVariantOf,
      itemName:         currentItemName,
      batchNo:          scannedBatch,
      mrReferenceItems: mrReferenceItems,
      scannedEan8:      currentScannedEan,
    );

    // Auto-submit wiring goes AFTER initialise() so the timer is not
    // started on an uninitialised controller.
    //
    // Commit 6: use the base-class signature setupAutoSubmit(onValid: ...).
    // The enabled-flag, delay, and sheet-open guard are inlined here so
    // the base Worker fires only when the sheet is still open and the
    // document is editable.
    final autoEnabled    = _storageService.getAutoSubmitEnabled();
    final autoDelaySecs  = _storageService.getAutoSubmitDelay();
    _wireAutoSubmit(child);
    await _openItemSheet(child);
  }

  /// Opens the item-form sheet to EDIT an existing item.
  ///
  /// Made async-await on initialise() (Commit 5) so _loadExistingItem
  /// and validateBatchOnInit run before the sheet is presented.
  ///
  /// Commit 6: setupAutoSubmit() call updated to match the base-class
  /// single-param signature.
  Future<void> editItem(StockEntryItem item) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;

    try {
      currentItemCode  = item.itemCode;
      currentVariantOf = item.customVariantOf ?? '';
      currentItemName  = item.itemName ?? '';

      final child = Get.put(StockEntryItemFormController());

      // ✔ Await initialise() so existing-item state is loaded before the sheet opens.
      await child.initialise(
        parent:           this,
        code:             item.itemCode,
        name:             item.itemCode,
        variantOf:        currentVariantOf,
        itemName:         currentItemName,
        editingItem:      item,
        mrReferenceItems: mrReferenceItems,
        scannedEan8:      currentScannedEan,
      );

      // Commit 6: use the base-class signature setupAutoSubmit(onValid: ...).
      final autoEnabled   = _storageService.getAutoSubmitEnabled();
      final autoDelaySecs = _storageService.getAutoSubmitDelay();
      _wireAutoSubmit(child);

      ensureItemKey(item);
      await _openItemSheet(child);
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }
  }

  // ── fix(se-form): wrap _openItemSheet in try/finally so isItemSheetOpen
  //   is always reset and the child controller is always cleaned up,
  //   regardless of how the sheet exits (normal dismiss, exception, or
  //   Flutter BuildContext error during the open animation).
  //
  //   Without this guard, any exception thrown by Get.bottomSheet() left
  //   isItemSheetOpen.value == true permanently.  Subsequent DataWedge
  //   scans then passed the isItemSheetOpen gate in scanBarcode() and
  //   _handleSheetScan() tried Get.find<StockEntryItemFormController>()
  //   on a controller that had already been deleted — crashing the scan
  //   handler instead of opening a new item sheet.
  //
  //   Resolves: #17 — barcode scan does not set field values in SE item form.
  Future<void> _openItemSheet(StockEntryItemFormController child) async {
    isItemSheetOpen.value = true;
    child.initBarcodeListener();   // BarcodeAwareMixin: attach sheet-level worker
    try {
      await Get.bottomSheet(
        DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize:     0.4,
          maxChildSize:     0.95,
          expand:           false,
          builder: (context, sc) => UniversalItemFormSheet(
            key:              ValueKey(child.editingItemName.value ?? 'new'),
            controller:       child,
            scrollController: sc,
            onSubmit:         addItem,
            onScan:           null,
            isSaveEnabled:    isEditable,
            customFields: [
              SharedInvoiceSerialNumberField(
                c:           child,
                accentColor: Colors.blueGrey,
                posItemQtyOverride: () {
                  final serial = child.selectedSerial.value;
                  if (serial == null || serial.isEmpty) return 0.0;
                  return posQtyCapForSerial(serial);
                },
              ),
              SharedBatchField(
                c:               child,
                accentColor:     Colors.blueGrey,
                editMode:        true,
                fieldKey:        'se_batch_edit',
                balanceOverride: () => child.batchBalance.value,
                onPickerTap:     child.openBatchPicker,
              ),
              RackSection(controller: child),
            ],
          ),
        ),
        isScrollControlled: true,
      );
    } finally {
      child.disposeBarcodeListener(); // BarcodeAwareMixin: detach before delete
      isItemSheetOpen.value = false;
      _isClosingSheet = false;
      Get.delete<StockEntryItemFormController>();
    }
  }

  // ── Scan routing ───────────────────────────────────────────────────────────────────────────────────

  Future<void> scanBarcode(String barcode) async {
    if (isClosed) return;
    if (checkStaleAndBlock()) return;
    if (barcode.isEmpty) return;
    if (isScanning.value) return;

    // Sheet-level scans are routed by BarcodeAwareMixin on the child controller.
    // The _scanWorker guard (isItemSheetOpen check) means this method is never
    // reached while a sheet is open. The branch below is removed.

    if (!_validateHeaderBeforeScan()) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);
      if (result.isSuccess && result.itemData != null) {
        if (!_validateScanContext(result)) {
          isScanning.value = false;
          return;
        }
        if (result.rawCode.contains('-') &&
            !result.rawCode.startsWith('SHIPMENT')) {
          currentScannedEan = result.rawCode.split('-')[0];
        } else {
          currentScannedEan = result.rawCode;
        }
        final itemData   = result.itemData!;
        currentItemCode  = itemData.itemCode;
        currentVariantOf = itemData.variantOf ?? '';
        currentItemName  = itemData.itemName;
        currentUom       = itemData.stockUom ?? 'Nos';
        await _openNewItemSheet(scannedBatch: result.batchNo);
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Scan failed');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan processing error: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ── Warehouses ───────────────────────────────────────────────────────────────────────────────────

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider
          .getDocumentList('Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  Future<void> fetchStockEntryTypes() async {
    isFetchingTypes.value = true;
    try {
      final response = await _provider.getStockEntryTypes();
      if (response.statusCode == 200 && response.data['data'] != null) {
        stockEntryTypes.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      if (stockEntryTypes.isEmpty) {
        stockEntryTypes.assignAll([
          'Material Issue', 'Material Receipt',
          'Material Transfer', 'Material Transfer for Manufacture',
        ]);
      }
    } finally {
      isFetchingTypes.value = false;
    }
  }

  // ── Feedback / scroll ──────────────────────────────────────────────────────────────────────────────────

  void triggerHighlight(String uniqueId) {
    recentlyAddedItemName.value = uniqueId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (isClosed) return;
        final key = itemKeys[uniqueId];
        final ctx = key?.currentContext;
        if (ctx == null) return;
        final ro = ctx.findRenderObject();
        if (ro == null || !ro.attached) return;
        Scrollable.ensureVisible(
          ctx,
          duration:  const Duration(milliseconds: 500),
          curve:     Curves.easeInOut,
          alignment: 0.5,
        );
      });
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!isClosed) recentlyAddedItemName.value = '';
    });
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }

  Map<String, List<StockEntryItem>> get groupedItems {
    if (stockEntry.value == null || stockEntry.value!.items.isEmpty) return {};
    return groupBy(
        stockEntry.value!.items,
        (StockEntryItem i) => i.customInvoiceSerialNumber ?? '0');
  }

  // ── Header validation ─────────────────────────────────────────────────────

  /// Returns true when the header is valid to proceed with save.
  /// Shows an error snackbar and returns false otherwise.
  bool _validateHeaderForSave() {
    // Resolve warehouses from first item if header fields are still null.
    final firstItem = stockEntry.value?.items.firstOrNull;
    if (fromWarehouse.value == null && firstItem?.sWarehouse != null) {
      fromWarehouse.value = firstItem!.sWarehouse;
    }
    if (toWarehouse.value == null && firstItem?.tWarehouse != null) {
      toWarehouse.value = firstItem!.tWarehouse;
    }
    if (stockEntryType.value == 'Material Transfer' &&
        (fromWarehouse.value == null || toWarehouse.value == null)) {
      GlobalSnackbar.error(
          message: 'Source and Target Warehouses are required');
      return false;
    }
    return true;
  }

  // ── Payload builders ──────────────────────────────────────────────────────

  Map<String, dynamic> _buildHeaderPayload() => {
    'stock_entry_type':    stockEntryType.value,
    'posting_date':        stockEntry.value?.postingDate,
    'posting_time':        stockEntry.value?.postingTime,
    'from_warehouse':      fromWarehouse.value,
    'to_warehouse':        toWarehouse.value,
    'custom_reference_no': customReferenceNoController.text,
    'modified':            stockEntry.value?.modified,
    if ((stockEntry.value?.workOrder ?? '').isNotEmpty)
      'work_order': stockEntry.value!.workOrder,
    if (argWorkOrderName != null && argWorkOrderName!.isNotEmpty)
      'work_order': argWorkOrderName,
    if (entrySource == StockEntrySource.workOrder ||
        entrySource == StockEntrySource.manufacture) ...{
      'from_bom':         stockEntry.value?.fromBom == true ? 1 : 0,
      if ((stockEntry.value?.bomNo ?? '').isNotEmpty)
        'bom_no':         stockEntry.value!.bomNo,
      'fg_completed_qty': stockEntry.value?.fgCompletedQty ?? 0.0,
    },
  };

  List<Map<String, dynamic>> _buildItemsPayload() {
    return (stockEntry.value?.items ?? []).map((item) {
      final json = item.toJson();
      _stripLocalName(json);
      _stripZeroRate(json);
      _injectMrFields(json, item);
      _injectWorkOrderField(json);
      json.removeWhere((_, v) => v == null);
      return json;
    }).toList();
  }

  void _stripLocalName(Map<String, dynamic> json) {
    final n = json['name']?.toString() ?? '';
    if (n.startsWith('local_') || n.startsWith('wo_prefill_')) {
      json.remove('name');
    }
  }

  void _stripZeroRate(Map<String, dynamic> json) {
    if (json['basic_rate'] == 0.0) json.remove('basic_rate');
  }

  void _injectMrFields(Map<String, dynamic> json, StockEntryItem item) {
    if (item.materialRequest != null) {
      json['material_request'] = item.materialRequest;
    }
    if (item.materialRequestItem != null) {
      json['material_request_item'] = item.materialRequestItem;
    }
    if (item.materialRequest == null &&
        entrySource == StockEntrySource.materialRequest &&
        mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems.firstWhereOrNull((r) =>
      r['item_code'].toString().trim().toLowerCase() ==
          item.itemCode.trim().toLowerCase());
      if (ref != null) {
        json['material_request']      = ref['material_request'];
        json['material_request_item'] = ref['material_request_item'];
      }
    }
  }

  void _injectWorkOrderField(Map<String, dynamic> json) {
    if (argWorkOrderName != null && argWorkOrderName!.isNotEmpty) {
      json['work_order'] = argWorkOrderName;
    }
  }

  // ── Create / update ───────────────────────────────────────────────────────

  Future<void> _createEntry(Map<String, dynamic> data) async {
    final res = await _provider.createStockEntry(data);
    if (res.statusCode == 200) {
      name = res.data['data']['name'];
      mode = 'edit';
      await fetchStockEntry();
      _setSaveResult(SaveResult.success);
      GlobalSnackbar.success(message: 'Stock Entry created: $name');
    } else {
      _setSaveResult(SaveResult.error);
      GlobalSnackbar.error(
          message: 'Failed to create: ${res.data['exception'] ?? 'Unknown error'}');
    }
  }

  Future<void> _updateEntry(Map<String, dynamic> data) async {
    final res = await _provider.updateStockEntry(name, data);
    if (res.statusCode == 200) {
      if (res.data['data'] != null) {
        stockEntry.value = StockEntry.fromJson(res.data['data']);
      }
      _setSaveResult(SaveResult.success);
      isDirty.value = false;
      await fetchStockEntry();
    } else {
      _setSaveResult(SaveResult.error);
      GlobalSnackbar.error(
          message: 'Failed to update: ${res.data['exception'] ?? 'Unknown error'}');
    }
  }

  // ── Error handler ─────────────────────────────────────────────────────────

  void _handleSaveDioError(DioException e) {
    if (handleVersionConflict(e)) return;
    _setSaveResult(SaveResult.error);
    String msg = 'Save failed';
    final data = e.response?.data;
    if (data is Map) {
      if (data['exception'] != null) {
        msg = data['exception'].toString().split(':').last.trim();
      } else if (data['_server_messages'] != null) {
        msg = 'Validation Error: Check form details';
      }
    }
    GlobalSnackbar.error(message: msg);
  }

  // ── saveStockEntry (orchestrator only, ~15 lines) ─────────────────────────

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;
    if (!_validateHeaderForSave()) return;

    isSaving.value = true;
    final data = _buildHeaderPayload()
      ..['items'] = _buildItemsPayload();
    try {
      if (mode == 'new') {
        await _createEntry(data);
      } else {
        await _updateEntry(data);
      }
    } on DioException catch (e) {
      _handleSaveDioError(e);
    } catch (e) {
      _setSaveResult(SaveResult.error);
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Misc ───────────────────────────────────────────────────────────────────────────────────

  void _markDirty() {
    if (!isLoading.value && !isDirty.value && isEditable) isDirty.value = true;
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  Future<void> pickPostingDate(BuildContext context) async {
    final current = stockEntry.value;
    if (current == null) return;
    DateTime initial;
    try {
      initial = current.postingDate != null && current.postingDate!.isNotEmpty
          ? DateFormat('yyyy-MM-dd').parse(current.postingDate!)
          : DateTime.now();
    } catch (_) {
      initial = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked != null) {
      stockEntry.update(
          (val) => val?.postingDate = DateFormat('yyyy-MM-dd').format(picked));
      _markDirty();
    }
  }

  Future<void> pickPostingTime(BuildContext context) async {
    final current = stockEntry.value;
    if (current == null) return;
    TimeOfDay initial;
    try {
      if (current.postingTime != null && current.postingTime!.isNotEmpty) {
        final parsed = DateFormat('HH:mm:ss').parse(current.postingTime!);
        initial = TimeOfDay.fromDateTime(parsed);
      } else {
        initial = TimeOfDay.now();
      }
    } catch (_) {
      initial = TimeOfDay.now();
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final dt = DateTime(0, 1, 1, picked.hour, picked.minute);
      stockEntry.update(
          (val) => val?.postingTime = DateFormat('HH:mm:ss').format(dt));
      _markDirty();
    }
  }
}
