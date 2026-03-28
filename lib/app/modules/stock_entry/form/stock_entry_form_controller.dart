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

// ── Shared sheet layer ────────────────────────────────────────────────────────────
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';

// ── SE-module-local widgets ─────────────────────────────────────────────────────
import 'widgets/item_form_sheet/rack_section.dart';
// (stock_entry_item_form_sheet.dart is now a stub re-export)
// (batch_field.dart retired — P4-2: replaced by SharedBatchField)

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
  // ── Dependencies ──────────────────────────────────────────────────────────
  final StockEntryProvider  _provider       = Get.find<StockEntryProvider>();
  final ApiProvider         _apiProvider    = Get.find<ApiProvider>();
  final PosUploadProvider   _posProvider    = Get.find<PosUploadProvider>();
  final StorageService      _storageService = Get.find<StorageService>();
  final ScanService         _scanService    = Get.find<ScanService>();
  final DataWedgeService    _dataWedgeService = Get.find<DataWedgeService>();

  // ── Arguments ───────────────────────────────────────────────────────────────
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

  // ── Form fields ────────────────────────────────────────────────────────────────
  var selectedFromWarehouse    = RxnString();
  var selectedToWarehouse      = RxnString();
  final customReferenceNoController = TextEditingController();
  String _initialReferenceNo   = '';

  var stockEntryTypes      = <String>[].obs;
  var isFetchingTypes      = false.obs;
  var selectedStockEntryType = 'Material Transfer'.obs;

  var warehouses          = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── Sheet & scan context ─────────────────────────────────────────────────────
  final TextEditingController barcodeController = TextEditingController();
  var isItemSheetOpen = false.obs;

  var currentItemCode  = '';
  var currentVariantOf = '';
  var currentItemName  = '';
  var currentUom       = '';
  var currentScannedEan = '';

  // ── Item feedback ──────────────────────────────────────────────────────────────
  var recentlyAddedItemName = ''.obs;
  final Map<String, GlobalKey> itemKeys = {};
  var itemFormKey = GlobalKey<FormState>();
  final ScrollController scrollController = ScrollController();

  Timer?  _autoSubmitTimer;
  Worker? _scanWorker;

  bool get isEditable => (stockEntry.value?.docstatus ?? 1) == 0;

  // ── Domain helpers ───────────────────────────────────────────────────────────────

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

  /// Returns the qty already recorded on this SE for [serial],
  /// optionally excluding a specific row being edited ([excludeItemName]).
  double scannedQtyForSerial(String serial, {String? excludeItemName}) {
    return (stockEntry.value?.items ?? [])
        .where((i) =>
            (i.customInvoiceSerialNumber ?? '0') == serial &&
            i.name != excludeItemName)
        .fold(0.0, (sum, i) => sum + i.qty);
  }

  // ── onInit / onClose ─────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _dataWedgeService.startListening();
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) {
        barcodeController.text = code;
        scanBarcode(code);
      }
    });
    _fetchStockEntryTypes();
    _fetchWarehouses();
    if (argStockEntryType != null) {
      selectedStockEntryType.value = argStockEntryType!;
    }
    if (argCustomReferenceNo != null) {
      customReferenceNoController.text = argCustomReferenceNo!;
      _initialReferenceNo = argCustomReferenceNo!;
    }
    if (name.isEmpty || name == 'new') {
      mode = 'new';
      _initNewStockEntry();
    } else {
      fetchStockEntry();
    }
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    _saveResultTimer?.cancel();
    _autoSubmitTimer?.cancel();
    barcodeController.dispose();
    customReferenceNoController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ── Stale-check (OptimisticLockingMixin) ─────────────────────────────────────

  @override
  Future<void> reloadDocument() async {
    await fetchStockEntry();
    isStale.value = false;
  }

  // ── Fetch ───────────────────────────────────────────────────────────────────

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;
        selectedFromWarehouse.value = entry.fromWarehouse;
        selectedToWarehouse.value   = entry.toWarehouse;
        selectedStockEntryType.value =
            entry.stockEntryType ?? selectedStockEntryType.value;
        customReferenceNoController.text = entry.customReferenceNo ?? '';
        _initialReferenceNo = entry.customReferenceNo ?? '';

        await _detectEntrySource(entry);
      } else {
        GlobalDialog.showError(
          title:   'Failed to load Stock Entry',
          message: 'Server returned an unexpected response.',
          onRetry: fetchStockEntry,
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title:   'Failed to load Stock Entry',
        message: 'Check your connection and try again.',
        onRetry: fetchStockEntry,
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _detectEntrySource(StockEntry entry) async {
    final refNo = entry.customReferenceNo ?? '';
    if (refNo.startsWith('MAT-STE-')) {
      final mr = await _fetchMrItems(refNo);
      if (mr.isNotEmpty) {
        entrySource    = StockEntrySource.materialRequest;
        mrReferenceItems = mr;
        return;
      }
    }
    if (refNo.startsWith('POS-UPL-')) {
      final loaded = await _loadPosUpload(refNo);
      if (loaded) {
        entrySource = StockEntrySource.posUpload;
        return;
      }
    }
    entrySource = StockEntrySource.manual;
  }

  Future<List<Map<String, dynamic>>> _fetchMrItems(String mrName) async {
    try {
      final response = await _apiProvider.getDocument(
          'Material Request', mrName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final items = response.data['data']['items'] as List?;
        if (items != null) {
          return items.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> _loadPosUpload(String posName) async {
    try {
      final response = await _posProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
        posUploadSerialOptions.value = posUpload.value!.items
            .map((i) => i.idx.toString())
            .toList();
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _initNewStockEntry() {
    stockEntry.value = StockEntry(
      name:            'New Stock Entry',
      stockEntryType:  selectedStockEntryType.value,
      docstatus:       0,
      items:           [],
      fromWarehouse:   null,
      toWarehouse:     null,
      customReferenceNo: argCustomReferenceNo,
    );
    isLoading.value = false;
  }

  Future<void> _fetchStockEntryTypes() async {
    isFetchingTypes.value = true;
    try {
      final response = await _apiProvider.getDocumentList(
          'Stock Entry Type', fields: ['name']);
      if (response.statusCode == 200 && response.data['data'] != null) {
        stockEntryTypes.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (_) {}
    isFetchingTypes.value = false;
  }

  Future<void> _fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList(
          'Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (_) {}
    isFetchingWarehouses.value = false;
  }

  // ── Item sheet orchestration ────────────────────────────────────────────────

  Future<void> openItemSheet({
    required String code,
    required String variantOf,
    required String itemName,
    String?  batchNo,
    StockEntryItem? editingItem,
    String   scannedEan8 = '',
  }) async {
    currentItemCode  = code;
    currentVariantOf = variantOf;
    currentItemName  = itemName;

    final child = Get.put(StockEntryItemFormController());
    child.initialise(
      parent:           this,
      code:             code,
      variantOf:        variantOf,
      name:             itemName,
      itemName:         itemName,
      batchNo:          batchNo,
      editingItem:      editingItem,
      scannedEan8:      scannedEan8,
      mrReferenceItems: mrReferenceItems,
    );

    child.setupAutoSubmit(
      enabled:       _storageService.getAutoSubmitEnabled(),
      delaySeconds:  _storageService.getAutoSubmitDelay(),
      isSheetOpen:   isItemSheetOpen,
      isSubmittable: () => isEditable,
      onAutoSubmit:  () async {
        isAddingItem.value = true;
        try {
          await child.submit();
          isDirty.value = true;
          await saveStockEntry();
        } finally {
          isAddingItem.value = false;
        }
        final nav = Get.key.currentState;
        if (nav != null && nav.canPop()) nav.pop();
      },
    );

    isItemSheetOpen.value = true;

    await Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize:     0.4,
        maxChildSize:     0.95,
        builder: (context, sc) {
          Future<void> onSubmit() async {
            isAddingItem.value = true;
            try {
              final bool saved = await child.submitWithFeedback();
              if (saved) {
                isDirty.value = true;
                await saveStockEntry();
                if (context.mounted) Navigator.of(context).pop();
              }
            } finally {
              isAddingItem.value = false;
            }
          }

          return UniversalItemFormSheet(
            controller:       child,
            scrollController: sc,
            onSubmit:         onSubmit,
            onScan:           (code) => scanBarcode(code),
            customFields: [
              SharedSerialField(
                controller:  child,
                accentColor: Colors.blueGrey,
              ),
              SharedBatchField(
                c:           child,
                accentColor: Colors.purple,
                editMode:    true,
                fieldKey:    'se_batch_field',
              ),
              SEDualRackSection(controller: child),
            ],
          );
        },
      ),
      isScrollControlled: true,
    );

    isItemSheetOpen.value = false;
    barcodeController.clear();
    if (Get.isRegistered<StockEntryItemFormController>()) {
      Get.delete<StockEntryItemFormController>();
    }
  }

  Future<void> editItem(StockEntryItem item) async {
    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;
    try {
      await openItemSheet(
        code:        item.itemCode ?? '',
        variantOf:   item.variantOf ?? '',
        itemName:    item.itemName  ?? '',
        batchNo:     item.batchNo,
        editingItem: item,
        scannedEan8: item.batchNo?.split('-').firstOrNull ?? '',
      );
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }
  }

  // ── Item CRUD ────────────────────────────────────────────────────────────────

  void addItemLocally(
      double qty, String batch, String sourceRack, String targetRack,
      String? sWh, String? tWh, String? invoiceSerial) {
    final items  = stockEntry.value?.items.toList() ?? [];
    final serial = invoiceSerial ?? '0';

    // ── Hard block: POS qty cap ──────────────────────────────────────────────
    if (serial != '0' && posUpload.value != null) {
      final cap = posQtyCapForSerial(serial);

      final existingIdx = items.indexWhere((i) =>
          (i.itemCode ?? '') == currentItemCode &&
          (i.batchNo  ?? '') == batch &&
          (i.rack     ?? '') == sourceRack &&
          (i.customInvoiceSerialNumber ?? '0') == serial);
      final mergeQty     = existingIdx != -1 ? items[existingIdx].qty : 0.0;
      final alreadyUsed  = scannedQtyForSerial(serial);
      final projectedTotal = alreadyUsed - mergeQty + qty;

      if (projectedTotal > cap) {
        final posItem = posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == int.tryParse(serial));
        GlobalDialog.showQtyCapExceeded(
          serialNo:   int.parse(serial),
          itemName:   posItem?.itemName ?? currentItemName,
          scannedQty: alreadyUsed - mergeQty,
          capQty:     cap,
        );
        return;
      }
    }

    final existingIdx = items.indexWhere((i) =>
        (i.itemCode ?? '') == currentItemCode &&
        (i.batchNo  ?? '') == batch &&
        (i.rack     ?? '') == sourceRack &&
        (i.customInvoiceSerialNumber ?? '0') == serial);

    if (existingIdx != -1) {
      final existing = items[existingIdx];
      items[existingIdx] = existing.copyWith(qty: existing.qty + qty);
    } else {
      final newItem = StockEntryItem(
        name:     'local_${DateTime.now().millisecondsSinceEpoch}',
        itemCode: currentItemCode,
        itemName: currentItemName,
        qty:      qty,
        batchNo:  batch.isNotEmpty ? batch : null,
        rack:     sourceRack.isNotEmpty ? sourceRack : null,
        toRack:   targetRack.isNotEmpty ? targetRack : null,
        sWarehouse: sWh,
        tWarehouse: tWh,
        customInvoiceSerialNumber: serial,
      );
      items.add(newItem);
    }
    stockEntry.update((val) => val?.items.assignAll(items));
    isDirty.value = true;
    recentlyAddedItemName.value = currentItemName;
    Future.delayed(const Duration(seconds: 2),
        () => recentlyAddedItemName.value = '');
  }

  void updateItemLocally(
      String itemNameID, double qty, String batch, String sourceRack,
      String targetRack, String? sWh, String? tWh, String? invoiceSerial) {
    final serial = invoiceSerial ?? '0';
    final items  = stockEntry.value?.items.toList() ?? [];
    final idx    = items.indexWhere((i) => i.name == itemNameID);
    if (idx == -1) return;

    // ── Hard block: POS qty cap ──────────────────────────────────────────────
    if (serial != '0' && posUpload.value != null) {
      final cap       = posQtyCapForSerial(serial);
      final othersQty = scannedQtyForSerial(serial,
          excludeItemName: itemNameID);
      if (othersQty + qty > cap) {
        final posItem = posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == int.tryParse(serial));
        GlobalDialog.showQtyCapExceeded(
          serialNo:   int.parse(serial),
          itemName:   posItem?.itemName ?? items[idx].itemName ?? '',
          scannedQty: othersQty,
          capQty:     cap,
        );
        return;
      }
    }

    items[idx] = items[idx].copyWith(
      qty:        qty,
      batchNo:    batch.isNotEmpty  ? batch       : null,
      rack:       sourceRack.isNotEmpty ? sourceRack : null,
      toRack:     targetRack.isNotEmpty ? targetRack : null,
      sWarehouse: sWh,
      tWarehouse: tWh,
      customInvoiceSerialNumber: invoiceSerial,
    );
    stockEntry.update((val) => val?.items.assignAll(items));
    isDirty.value = true;
  }

  Future<void> confirmAndDeleteItem(StockEntryItem item) async {
    GlobalDialog.showConfirmation(
      title:   'Delete Item?',
      message: 'Remove ${item.itemCode} from this entry?',
      onConfirm: () {
        final items = stockEntry.value?.items.toList() ?? [];
        items.remove(item);
        stockEntry.update((val) => val?.items.assignAll(items));
        isDirty.value = true;
      },
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;
    isSaving.value = true;
    _saveResultTimer?.cancel();
    try {
      final bool isNew = stockEntry.value?.name == 'New Stock Entry' ||
          (stockEntry.value?.name.isEmpty ?? true);

      final Map<String, dynamic> data = stockEntry.value!.toJson();
      data['stock_entry_type'] = selectedStockEntryType.value;
      if (selectedFromWarehouse.value != null)
        data['from_warehouse'] = selectedFromWarehouse.value;
      if (selectedToWarehouse.value != null)
        data['to_warehouse'] = selectedToWarehouse.value;
      final refNo = customReferenceNoController.text.trim();
      if (refNo.isNotEmpty) data['custom_reference_no'] = refNo;

      final response = isNew
          ? await _apiProvider.createDocument('Stock Entry', data)
          : await _apiProvider.updateDocument(
              'Stock Entry', stockEntry.value!.name, data);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final saved = StockEntry.fromJson(response.data['data']);
        stockEntry.value = saved;
        name             = saved.name;
        if (isNew) mode  = 'edit';
        isDirty.value    = false;
        saveResult.value = SaveResult.success;
        _saveResultTimer = Timer(const Duration(seconds: 2),
            () => saveResult.value = SaveResult.idle);
      } else {
        saveResult.value = SaveResult.error;
        _saveResultTimer = Timer(const Duration(seconds: 2),
            () => saveResult.value = SaveResult.idle);
        GlobalSnackbar.error(
            message:
                'Failed to save: ${response.data['exception'] ?? 'Unknown error'}');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) {
        // Handled by OptimisticLockingMixin.
      } else {
        saveResult.value = SaveResult.error;
        _saveResultTimer = Timer(const Duration(seconds: 2),
            () => saveResult.value = SaveResult.idle);
        GlobalSnackbar.error(message: 'Save failed: ${e.message}');
      }
    } catch (e) {
      saveResult.value = SaveResult.error;
      _saveResultTimer = Timer(const Duration(seconds: 2),
          () => saveResult.value = SaveResult.idle);
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Scan routing ───────────────────────────────────────────────────────────────

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    if (isItemSheetOpen.value) {
      _handleInsideSheetScan(barcode);
      return;
    }
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);
      if (result.isSuccess && result.itemData != null) {
        if (barcode.contains('-') && !barcode.startsWith('SHIPMENT')) {
          currentScannedEan = barcode.split('-').first;
        } else {
          currentScannedEan = barcode;
        }
        final itemData = result.itemData!;
        barcodeController.clear();
        await openItemSheet(
          code:        itemData.itemCode,
          variantOf:   itemData.variantOf ?? '',
          itemName:    itemData.itemName,
          batchNo:     result.batchNo,
          scannedEan8: currentScannedEan,
        );
      } else {
        GlobalSnackbar.error(
            message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan error: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void _handleInsideSheetScan(String barcode) {
    if (!Get.isRegistered<StockEntryItemFormController>()) return;
    final child = Get.find<StockEntryItemFormController>();
    child.applyRackScan(barcode);
  }

  // ── POS helpers ───────────────────────────────────────────────────────────────

  Map<String, List<StockEntryItem>> get groupedBySerial {
    if (stockEntry.value == null) return {};
    return groupBy(
      stockEntry.value!.items,
      (StockEntryItem i) => i.customInvoiceSerialNumber ?? '0',
    );
  }

  List<MrItemRow> get mrItemRows {
    if (mrReferenceItems.isEmpty) return [];
    final grouped = groupBy(
      stockEntry.value?.items ?? [],
      (StockEntryItem i) => i.itemCode ?? '',
    );
    return mrReferenceItems.map((ref) {
      final code       = ref['item_code'] as String;
      final requested  = (ref['qty'] as num).toDouble();
      final scanned    = (grouped[code] ?? [])
          .fold(0.0, (s, i) => s + i.qty);
      return MrItemRow(
        itemCode:            code,
        requestedQty:        requested,
        scannedQty:          scanned,
        materialRequest:     ref['parent']    as String? ?? '',
        materialRequestItem: ref['name']      as String? ?? '',
      );
    }).toList();
  }

  int get completedMrCount =>
      mrItemRows.where((r) => r.isCompleted).length;
  int get pendingMrCount   =>
      mrItemRows.where((r) => r.isPending).length;

  void setMrFilter(String f) => mrItemFilter.value = f;

  // ── Misc UI ───────────────────────────────────────────────────────────────────

  bool get isReferenceNoChanged =>
      customReferenceNoController.text.trim() != _initialReferenceNo;
}
