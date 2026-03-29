import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

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

// ── Shared sheet layer ────────────────────────────────────────────────────────

import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';

// ── SE-module-local widgets ───────────────────────────────────────────────────

import 'widgets/item_form_sheet/rack_section.dart';

enum StockEntrySource { manual, materialRequest, posUpload }

/// Lightweight view-model that merges one MR line with the summed scanned qty.
class MrItemRow {
  final String itemCode;
  final double requestedQty;
  final double scannedQty;
  final String materialRequest;
  final String materialRequestItem;

  const MrItemRow({
    required this.itemCode,
    required this.requestedQty,
    required this.scannedQty,
    required this.materialRequest,
    required this.materialRequestItem,
  });

  bool get isCompleted => scannedQty >= requestedQty;
  bool get isPending   => scannedQty < requestedQty;
}

class StockEntryFormController extends GetxController
    with OptimisticLockingMixin {
  // ── Dependencies ─────────────────────────────────────────────────────────────
  final StockEntryProvider  _provider       = Get.find<StockEntryProvider>();
  final ApiProvider         _apiProvider    = Get.find<ApiProvider>();
  final PosUploadProvider   _posProvider    = Get.find<PosUploadProvider>();
  final StorageService      _storageService = Get.find<StorageService>();
  final ScanService         _scanService    = Get.find<ScanService>();
  final DataWedgeService    _dataWedgeService = Get.find<DataWedgeService>();

  // ── Arguments ─────────────────────────────────────────────────────────────────
  String name = Get.arguments?['name'] ?? '';
  String mode = Get.arguments?['mode'] ?? 'view';
  final String? argStockEntryType    = Get.arguments?['stockEntryType'];
  final String? argCustomReferenceNo = Get.arguments?['customReferenceNo'];

  // ── Document state ────────────────────────────────────────────────────────────
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

  // ── Context data ──────────────────────────────────────────────────────────────
  var mrReferenceItems = <Map<String, dynamic>>[];

  var posUpload              = Rx<PosUpload?>(null);
  var posUploadSerialOptions = <String>[].obs;
  var expandedInvoice        = ''.obs;

  // ── MR filter ─────────────────────────────────────────────────────────────────
  var mrItemFilter = 'All'.obs;

  // ── Form fields ───────────────────────────────────────────────────────────────
  var selectedFromWarehouse    = RxnString();
  var selectedToWarehouse      = RxnString();
  final customReferenceNoController = TextEditingController();
  String _initialReferenceNo   = '';

  var stockEntryTypes      = <String>[].obs;
  var isFetchingTypes      = false.obs;
  var selectedStockEntryType = 'Material Transfer'.obs;

  var warehouses          = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── Sheet & scan context ──────────────────────────────────────────────────────
  final TextEditingController barcodeController = TextEditingController();
  var isItemSheetOpen = false.obs;

  var currentItemCode  = '';
  var currentVariantOf = '';
  var currentItemName  = '';
  var currentUom       = '';
  var currentScannedEan = '';

  // ── Item feedback ─────────────────────────────────────────────────────────────
  var recentlyAddedItemName = ''.obs;
  final Map<String, GlobalKey> itemKeys = {};
  var itemFormKey = GlobalKey<FormState>();
  final ScrollController scrollController = ScrollController();

  Timer?  _autoSubmitTimer;
  Worker? _scanWorker;

  bool get isEditable => (stockEntry.value?.docstatus ?? 1) == 0;

  // ── Domain helpers ────────────────────────────────────────────────────────────

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

  // ── POS qty-cap helpers ───────────────────────────────────────────────────────
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
  ///
  /// Without [excludeItemName]:
  ///   = Item1.qty + Item2.qty + Item3.qty + … + ItemN.qty  (for that serial)
  ///
  /// With [excludeItemName]:
  ///   = same sum but skipping the named row (used for projection checks
  ///     during edits so the row's OLD qty is not double-counted).
  double scannedQtyForSerial(String serial, {String? excludeItemName}) {
    return (stockEntry.value?.items ?? [])
        .where((i) =>
            (i.customInvoiceSerialNumber ?? '0') == serial &&
            i.name != excludeItemName)
        .fold(0.0, (sum, i) => sum + i.qty);
  }

  /// Remaining qty available for [serial] under the POS Upload cap.
  ///
  /// Implements the canonical formula:
  ///   Remaining = Cap − (Item1.qty + Item2.qty + … + ItemN.qty)
  ///
  /// Returns [double.infinity] when there is no POS context so callers
  /// can safely use it on non-POS entries without a guard.
  double remainingQtyForSerial(String serial) {
    final cap = posQtyCapForSerial(serial);
    if (cap == double.infinity) return double.infinity;
    return (cap - scannedQtyForSerial(serial)).clamp(0.0, cap);
  }

  // ── MR helpers ────────────────────────────────────────────────────────────────

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

  // ── POS helpers ───────────────────────────────────────────────────────────────

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

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
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

    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) scanBarcode(code);
    });

    ever(selectedFromWarehouse,    (_) => _markDirty());
    ever(selectedToWarehouse,      (_) => _markDirty());
    ever(selectedStockEntryType,   (_) => _markDirty());

    customReferenceNoController.addListener(() {
      final current = customReferenceNoController.text;
      if (current != _initialReferenceNo) _markDirty();
      if (entrySource == StockEntrySource.manual &&
          selectedStockEntryType.value == 'Material Issue' &&
          current.isNotEmpty) {
        if (current.startsWith('KX') || current.startsWith('MX')) {
          fetchPosUpload(current);
        }
      }
    });
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
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

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }

  // ── New entry init ────────────────────────────────────────────────────────────

  Future<void> _initNewStockEntry() async {
    isLoading.value = true;
    final now  = DateTime.now();
    final type = argStockEntryType    ?? 'Material Transfer';
    final ref  = argCustomReferenceNo ?? '';

    selectedStockEntryType.value     = type;
    customReferenceNoController.text = ref;
    _initialReferenceNo              = ref;

    determineSource(type, ref);

    if (entrySource == StockEntrySource.materialRequest) {
      await _initMaterialRequestFlow(ref);
    } else if (entrySource == StockEntrySource.posUpload) {
      await fetchPosUpload(ref);
    }

    stockEntry.value = StockEntry(
      name:          'New Stock Entry',
      purpose:        selectedStockEntryType.value,
      totalAmount:    0.0,
      postingDate:    DateFormat('yyyy-MM-dd').format(now),
      modified:       '',
      creation:       now.toString(),
      status:         'Draft',
      docstatus:      0,
      stockEntryType: selectedStockEntryType.value,
      postingTime:    DateFormat('HH:mm:ss').format(now),
      customTotalQty: 0.0,
      customReferenceNo: ref,
      currency:       'AED',
      items:          [],
    );

    isLoading.value = false;
    isDirty.value   = true;
  }

  void determineSource(String type, String ref) {
    if (Get.arguments?['items'] != null) {
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
            selectedStockEntryType.value = data['material_request_type'];
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

  // ── Fetch document ────────────────────────────────────────────────────────────

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;

        selectedStockEntryType.value = entry.stockEntryType ?? 'Material Transfer';
        selectedFromWarehouse.value  = entry.fromWarehouse;
        selectedToWarehouse.value    = entry.toWarehouse;

        final ref = entry.customReferenceNo ?? '';
        _initialReferenceNo              = ref;
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
    }
  }

  Future<void> reloadDocument() async {
    await fetchStockEntry();
    isStale.value    = false;
    isScanning.value = false;
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  // ── Warehouse helpers ─────────────────────────────────────────────────────────

  bool get requiresSourceWarehouse {
    final t = selectedStockEntryType.value;
    return t == 'Material Transfer' ||
        t == 'Material Transfer for Manufacture' ||
        t == 'Material Issue';
  }

  bool get requiresTargetWarehouse {
    final t = selectedStockEntryType.value;
    return t == 'Material Transfer' ||
        t == 'Material Transfer for Manufacture' ||
        t == 'Material Receipt';
  }

  bool enforceWarehouseBeforeScan() {
    if (requiresSourceWarehouse &&
        (selectedFromWarehouse.value == null ||
            selectedFromWarehouse.value!.isEmpty)) {
      return true;
    }
    if (requiresTargetWarehouse &&
        (selectedToWarehouse.value == null ||
            selectedToWarehouse.value!.isEmpty)) {
      return true;
    }
    return false;
  }

  bool _validateHeaderBeforeScan() {
    if (requiresSourceWarehouse &&
        (selectedFromWarehouse.value == null ||
            selectedFromWarehouse.value!.isEmpty)) {
      GlobalSnackbar.warning(
          message: 'Please set the Source Warehouse (Details tab) before scanning.');
      return false;
    }
    if (requiresTargetWarehouse &&
        (selectedToWarehouse.value == null ||
            selectedToWarehouse.value!.isEmpty)) {
      GlobalSnackbar.warning(
          message: 'Please set the Target Warehouse (Details tab) before scanning.');
      return false;
    }
    return true;
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
      owner:       item.owner,
      creation:    item.creation,
      modified:    item.modified,
      modifiedBy:  item.modifiedBy,
    );
  }

  // ── Item CRUD ─────────────────────────────────────────────────────────────────

  void updateItemLocally(
    String uniqueId, double qty, String? batch,
    String? sourceRack, String? targetRack,
    String? sWarehouse, String? tWarehouse, String? serial,
  ) {
    final items = stockEntry.value?.items.toList() ?? [];
    final idx   = items.indexWhere((i) => i.name == uniqueId);
    if (idx == -1) return;

    // ── Hard block: POS qty cap ───────────────────────────────────────────────
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

    // ── Hard block: POS qty cap ───────────────────────────────────────────────
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

  // ── addItem coordinator ───────────────────────────────────────────────────────

  Future<void> addItem() async {
    _autoSubmitTimer?.cancel();
    final child = Get.find<StockEntryItemFormController>();
    await child.submit();
    final items = stockEntry.value?.items ?? [];
    final String highlightKey = child.editingItemName.value ??
        (items.lastOrNull?.name ?? '');
    barcodeController.clear();
    triggerHighlight(highlightKey);
    if (Get.isBottomSheetOpen == true) Get.back();
    if (mode == 'new') {
      saveStockEntry();
    } else {
      isDirty.value = true;
      saveStockEntry().catchError((e) => debugPrint('Background save: $e'));
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────────

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

  // ── Sheet lifecycle ───────────────────────────────────────────────────────────

  void _openNewItemSheet({String? scannedBatch}) {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    final child = Get.put(StockEntryItemFormController());
    child.initialise(
      parent:           this,
      code:             currentItemCode,
      name:             currentItemCode,
      variantOf:        currentVariantOf,
      itemName:         currentItemName,
      batchNo:          scannedBatch,
      mrReferenceItems: mrReferenceItems,
      scannedEan8:      currentScannedEan,
    );

    child.setupAutoSubmit(
      enabled:       _storageService.getAutoSubmitEnabled(),
      delaySeconds:  _storageService.getAutoSubmitDelay(),
      isSheetOpen:   isItemSheetOpen,
      isSubmittable: () => isEditable,
      onAutoSubmit:  () async {
        isAddingItem.value = true;
        await Future.delayed(const Duration(milliseconds: 500));
        await addItem();
        isAddingItem.value = false;
      },
    );

    _openItemSheet(child);
  }

  Future<void> editItem(StockEntryItem item) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;

    try {
      currentItemCode  = item.itemCode;
      currentVariantOf = item.customVariantOf ?? '';
      currentItemName  = item.itemName ?? '';

      final child = Get.put(StockEntryItemFormController());
      child.initialise(
        parent:           this,
        code:             item.itemCode,
        name:             item.itemCode,
        variantOf:        currentVariantOf,
        itemName:         currentItemName,
        editingItem:      item,
        mrReferenceItems: mrReferenceItems,
        scannedEan8:      currentScannedEan,
      );

      child.setupAutoSubmit(
        enabled:      _storageService.getAutoSubmitEnabled(),
        delaySeconds: _storageService.getAutoSubmitDelay(),
        isSheetOpen:  isItemSheetOpen,
        isSubmittable: () => isEditable,
        onAutoSubmit: () async {
          isAddingItem.value = true;
          await Future.delayed(const Duration(milliseconds: 500));
          await addItem();
          isAddingItem.value = false;
        },
      );

      ensureItemKey(item);
      _openItemSheet(child);
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }
  }

  Future<void> _openItemSheet(StockEntryItemFormController child) async {
    isItemSheetOpen.value = true;
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
          itemSubtext:      currentVariantOf,
          isSaveEnabled:    isEditable,
          customFields: [
            SharedBatchField(
              c:               child,
              accentColor:     Colors.purple,
              balanceOverride: () => child.batchBalance.value,
            ),
            SharedSerialField(
              controller:  child,
              accentColor: Colors.blueGrey,
            ),
            RackSection(controller: child),
          ],
        ),
      ),
      isScrollControlled: true,
    );
    isItemSheetOpen.value = false;
    Get.delete<StockEntryItemFormController>();
  }

  // ── Scan routing ──────────────────────────────────────────────────────────────

  Future<void> scanBarcode(String barcode) async {
    if (isClosed) return;
    if (checkStaleAndBlock()) return;
    if (barcode.isEmpty) return;
    if (isScanning.value) return;

    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) {
      _handleSheetScan(barcode);
      return;
    }

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
        _openNewItemSheet(scannedBatch: result.batchNo);
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

  void _handleSheetScan(String barcode) async {
    barcodeController.clear();
    final child = Get.find<StockEntryItemFormController>();
    final contextItem = child.currentScannedEan.isNotEmpty
        ? child.currentScannedEan
        : currentItemCode;
    final result =
        await _scanService.processScan(barcode, contextItemCode: contextItem);

    if (result.type == ScanType.rack && result.rackId != null) {
      child.applyRackScan(result.rackId!);
    } else if ((result.type == ScanType.batch || result.type == ScanType.item) &&
        result.batchNo != null) {
      child.batchController.text = result.batchNo!;
      child.validateBatch(result.batchNo!);
    } else {
      if (child.needsRackScanFallback) {
        child.applyRackScan(barcode);
      } else {
        GlobalSnackbar.error(message: 'Invalid Scan');
      }
    }
  }

  // ── Warehouses ────────────────────────────────────────────────────────────────

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

  // ── Feedback / scroll ─────────────────────────────────────────────────────────

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

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    if (stockEntry.value != null && stockEntry.value!.items.isNotEmpty) {
      final first = stockEntry.value!.items.first;
      if (selectedFromWarehouse.value == null && first.sWarehouse != null) {
        selectedFromWarehouse.value = first.sWarehouse;
      }
      if (selectedToWarehouse.value == null && first.tWarehouse != null) {
        selectedToWarehouse.value = first.tWarehouse;
      }
    }
    if (selectedStockEntryType.value == 'Material Transfer') {
      if (selectedFromWarehouse.value == null ||
          selectedToWarehouse.value == null) {
        GlobalSnackbar.error(
            message: 'Source and Target Warehouses are required');
        return;
      }
    }

    isSaving.value = true;
    final Map<String, dynamic> data = {
      'stock_entry_type':   selectedStockEntryType.value,
      'posting_date':       stockEntry.value?.postingDate,
      'posting_time':       stockEntry.value?.postingTime,
      'from_warehouse':     selectedFromWarehouse.value,
      'to_warehouse':       selectedToWarehouse.value,
      'custom_reference_no': customReferenceNoController.text,
      'modified':           stockEntry.value?.modified,
    };

    final itemsJson = stockEntry.value?.items.map((i) {
          final json = i.toJson();
          if (json['name'] != null &&
              json['name'].toString().startsWith('local_')) {
            json.remove('name');
          }
          if (json['basic_rate'] == 0.0) json.remove('basic_rate');
          if (json['material_request'] == null &&
              entrySource == StockEntrySource.materialRequest &&
              mrReferenceItems.isNotEmpty) {
            final ref = mrReferenceItems.firstWhereOrNull((r) =>
                r['item_code'].toString().trim().toLowerCase() ==
                i.itemCode.trim().toLowerCase());
            if (ref != null) {
              json['material_request']      = ref['material_request'];
              json['material_request_item'] = ref['material_request_item'];
            }
          }
          if (i.materialRequest != null)
            json['material_request'] = i.materialRequest;
          if (i.materialRequestItem != null)
            json['material_request_item'] = i.materialRequestItem;
          json.removeWhere((key, value) => value == null);
          return json;
        }).toList() ??
        [];
    data['items'] = itemsJson;

    try {
      if (mode == 'new') {
        final response = await _provider.createStockEntry(data);
        if (response.statusCode == 200) {
          final createdDoc = response.data['data'];
          name = createdDoc['name'];
          mode = 'edit';
          await fetchStockEntry();
          _setSaveResult(SaveResult.success);
          GlobalSnackbar.success(message: 'Stock Entry created: $name');
        } else {
          _setSaveResult(SaveResult.error);
          GlobalSnackbar.error(
              message: 'Failed to create: '
                  '${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updateStockEntry(name, data);
        if (response.statusCode == 200) {
          final updatedDoc = response.data['data'];
          if (updatedDoc != null) {
            stockEntry.value = StockEntry.fromJson(updatedDoc);
          }
          _setSaveResult(SaveResult.success);
          isDirty.value = false;
          await fetchStockEntry();
        } else {
          _setSaveResult(SaveResult.error);
          GlobalSnackbar.error(
              message: 'Failed to update: '
                  '${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) {
        // handled by mixin
      } else {
        _setSaveResult(SaveResult.error);
        String msg = 'Save failed';
        if (e.response?.data is Map) {
          if (e.response!.data['exception'] != null) {
            msg = e.response!.data['exception']
                .toString().split(':').last.trim();
          } else if (e.response!.data['_server_messages'] != null) {
            msg = 'Validation Error: Check form details';
          }
        }
        GlobalSnackbar.error(message: msg);
      }
    } catch (e) {
      _setSaveResult(SaveResult.error);
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Misc ──────────────────────────────────────────────────────────────────────

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
