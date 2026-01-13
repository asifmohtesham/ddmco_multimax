import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart'; // Required for ListEquality
import 'package:intl/intl.dart';

// Models
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';

// Services & Providers
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

// Parent Controller
import '../stock_entry_form_controller.dart';

class StockEntryItemFormController extends GetxController {
  // --- Dependencies ---
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final StorageService _storageService = Get.find<StorageService>();

  late StockEntryFormController _parent;

  // --- Form Key ---
  final GlobalKey<FormState> itemFormKey = GlobalKey<FormState>();

  // --- Core State ---
  final qtyController = TextEditingController();
  final batchController = TextEditingController();
  final sourceRackController = TextEditingController();
  final targetRackController = TextEditingController();

  var itemCode = ''.obs;
  var itemName = ''.obs;
  var itemUom = ''.obs;
  var customVariantOf = '';

  // Metadata
  var itemOwner = RxnString();
  var itemCreation = RxnString();
  var itemModified = RxnString();
  var itemModifiedBy = RxnString();
  var currentItemNameKey = RxnString();

  // --- Validation & Status ---
  var useSerialBatchFields = false.obs;
  var isBatchValid = false.obs;
  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var maxQty = 0.0.obs;
  var rackError = RxnString();
  var batchError = RxnString();
  var isSheetValid = false.obs;
  var isValidatingBatch = false.obs;

  // Guard to prevent double submission / double nav
  var isSubmitting = false.obs;

  // --- Context & Warehouse ---
  var selectedSerial = RxnString();
  var itemSourceWarehouse = RxnString();
  var itemTargetWarehouse = RxnString();

  // --- Dirty State & Snapshot Management ---
  var isFormDirty = false.obs;

  // The snapshot represents the "Server Object" state when the form was opened.
  StockEntryItem? _initialSnapshot;

  // Computed property for UI Save Button:
  // Enabled ONLY if valid, dirty, AND not currently submitting.
  RxBool get isSaveEnabled => (isSheetValid.value && isFormDirty.value && !isSubmitting.value).obs;

  // --- Batches / SABB Entries ---
  var currentBundleEntries = <SerialAndBatchEntry>[].obs;
  var isBatchReadOnly = false.obs;
  SerialAndBatchBundle? originalBundle; // The server state of the bundle

  // --- Auto-Save Logic ---
  Timer? _autoSaveTimer;

  @override
  void onClose() {
    _autoSaveTimer?.cancel();
    qtyController.dispose();
    batchController.dispose();
    sourceRackController.dispose();
    targetRackController.dispose();
    super.onClose();
  }

  void initialise({
    required StockEntryFormController parentController,
    StockEntryItem? existingItem,
    String? initialItemCode,
    String? initialBatch,
    dynamic scannedItemData,
  }) {
    _parent = parentController;

    if (existingItem != null) {
      _loadExistingItem(existingItem);
    } else if (initialItemCode != null) {
      _loadNewItem(initialItemCode, initialBatch, scannedItemData);
    }

    _setupListeners();
    _captureSnapshot();
    validateSheet();
    _checkDirty();
  }

  /// Captures the baseline state of simple fields.
  void _captureSnapshot() {
    _initialSnapshot = StockEntryItem(
      name: currentItemNameKey.value,
      itemCode: itemCode.value,
      qty: double.tryParse(qtyController.text) ?? 0,
      basicRate: 0,
      batchNo: batchController.text,
      rack: sourceRackController.text,
      toRack: targetRackController.text,
      sWarehouse: itemSourceWarehouse.value,
      tWarehouse: itemTargetWarehouse.value,
      useSerialBatchFields: useSerialBatchFields.value ? 1 : 0,
    );
  }

  void _setupListeners() {
    qtyController.addListener(() { validateSheet(); _checkDirty(); });
    batchController.addListener(() { validateSheet(); _checkDirty(); });
    sourceRackController.addListener(() { validateSheet(); _checkDirty(); });
    targetRackController.addListener(() { validateSheet(); _checkDirty(); });

    ever(itemSourceWarehouse, (_) { _updateStockAvailability(); _checkDirty(); });
    ever(currentBundleEntries, (_) { _checkDirty(); });
  }

  void _checkDirty() {
    if (_initialSnapshot == null) return;

    final currentQty = double.tryParse(qtyController.text) ?? 0;

    bool fieldsDirty =
        currentQty != _initialSnapshot!.qty ||
            sourceRackController.text != (_initialSnapshot!.rack ?? '') ||
            targetRackController.text != (_initialSnapshot!.toRack ?? '') ||
            (useSerialBatchFields.value && batchController.text != (_initialSnapshot!.batchNo ?? '')) ||
            itemSourceWarehouse.value != _initialSnapshot!.sWarehouse ||
            itemTargetWarehouse.value != _initialSnapshot!.tWarehouse;

    bool bundleDirty = _isBundleDirty();
    isFormDirty.value = fieldsDirty || bundleDirty;
  }

  bool _isBundleDirty() {
    if (useSerialBatchFields.value) return false;
    if (originalBundle == null) return currentBundleEntries.isNotEmpty;
    if (originalBundle!.entries.length != currentBundleEntries.length) return true;

    final equality = const DeepCollectionEquality.unordered();

    final originalList = originalBundle!.entries.map((e) => {
      'batch': e.batchNo,
      'qty': e.qty
    }).toList();

    final currentList = currentBundleEntries.map((e) => {
      'batch': e.batchNo,
      'qty': e.qty
    }).toList();

    return !equality.equals(originalList, currentList);
  }

  // --- Loading Logic ---

  void _loadExistingItem(StockEntryItem item) {
    itemCode.value = item.itemCode;
    itemName.value = item.itemName ?? '';
    customVariantOf = item.customVariantOf ?? '';
    currentItemNameKey.value = item.name;

    itemOwner.value = item.owner;
    itemCreation.value = item.creation;
    itemModified.value = item.modified;
    itemModifiedBy.value = item.modifiedBy;

    useSerialBatchFields.value = (item.useSerialBatchFields == 1);
    qtyController.text = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();

    batchController.text = item.batchNo ?? '';
    if (useSerialBatchFields.value && item.batchNo != null && item.batchNo!.isNotEmpty) {
      isBatchValid.value = true;
      isBatchReadOnly.value = true;
    }

    sourceRackController.text = item.rack ?? '';
    targetRackController.text = item.toRack ?? '';
    if (sourceRackController.text.isNotEmpty) isSourceRackValid.value = true;
    if (targetRackController.text.isNotEmpty) isTargetRackValid.value = true;

    itemSourceWarehouse.value = item.sWarehouse;
    itemTargetWarehouse.value = item.tWarehouse;
    selectedSerial.value = item.customInvoiceSerialNumber;

    if (!useSerialBatchFields.value && item.serialAndBatchBundle != null) {
      if (_parent.unsavedBundles.containsKey(item.serialAndBatchBundle)) {
        originalBundle = _parent.unsavedBundles[item.serialAndBatchBundle];
        if (originalBundle != null) {
          currentBundleEntries.assignAll(originalBundle!.entries.map((e) =>
              SerialAndBatchEntry.fromJson(e.toJson())).toList());
        }
      } else {
        _fetchBundleDetails(item.serialAndBatchBundle!);
      }
    }
    _updateStockAvailability();
  }

  void _loadNewItem(String code, String? batch, dynamic data) {
    itemCode.value = code;
    itemName.value = data?.itemName ?? '';
    customVariantOf = data?.variantOf ?? '';

    if (currentItemNameKey.value == null) {
      currentItemNameKey.value = 'local_${DateTime.now().millisecondsSinceEpoch}';
    }

    useSerialBatchFields.value = false;

    if (batch != null) {
      validateAndAddBatch(batch);
    }

    if (_parent.entrySource == StockEntrySource.materialRequest) {
      selectedSerial.value = '0';
    }
  }

  // --- Scanning Logic ---
  Future<void> handleScan(String barcode) async {
    final result = await _scanService.processScan(barcode, contextItemCode: itemCode.value);

    if (result.type == ScanType.rack && result.rackId != null) {
      _handleRackScan(result.rackId!);
    } else if (result.batchNo != null) {
      validateAndAddBatch(result.batchNo!);
    }
  }

  void _handleRackScan(String rackId) {
    final type = _parent.selectedStockEntryType.value;
    final isSourceOp = ['Material Issue', 'Material Transfer'].contains(type);

    if (isSourceOp && sourceRackController.text.isEmpty) {
      sourceRackController.text = rackId;
      validateRack(rackId, isSource: true);
    } else {
      targetRackController.text = rackId;
      validateRack(rackId, isSource: false);
    }
  }

  // --- Validation ---
  void validateSheet() {
    isSheetValid.value = _isValidQty() &&
        _isValidBatch() &&
        _isValidContext() &&
        _isValidRacks();
  }

  bool _isValidQty() {
    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return false;
    if (maxQty.value > 0 && qty > maxQty.value) return false;
    return true;
  }

  bool _isValidBatch() {
    if (batchController.text.isNotEmpty && !isBatchValid.value) return false;
    if (_parent.entrySource == StockEntrySource.materialRequest && batchController.text.isEmpty) return false;
    return true;
  }

  bool _isValidContext() {
    if (_parent.entrySource == StockEntrySource.materialRequest) {
      if (selectedSerial.value == null || selectedSerial.value!.isEmpty) return false;
    }
    return true;
  }

  bool _isValidRacks() {
    final type = _parent.selectedStockEntryType.value;
    final needSource = ['Material Issue', 'Material Transfer'].contains(type);
    final needTarget = ['Material Receipt', 'Material Transfer'].contains(type);

    if (needSource) {
      if (sourceRackController.text.isEmpty && itemSourceWarehouse.value == null && _parent.selectedFromWarehouse.value == null) {
        return false;
      }
      if (sourceRackController.text.isNotEmpty && !isSourceRackValid.value) return false;
    }
    if (needTarget) {
      if (targetRackController.text.isNotEmpty && !isTargetRackValid.value) return false;
    }
    return true;
  }

  Future<void> validateBatch(String batch) async {
    batchError.value = null;
    if (batch.isEmpty) return;

    try {
      if (useSerialBatchFields.value) {
        final response = await _apiProvider.getDocumentList('Batch', filters: {
          'item': itemCode.value, 'name': batch
        });

        if (response.statusCode == 200 && (response.data['data'] as List).isNotEmpty) {
          isBatchValid.value = true;
          isBatchReadOnly.value = true;
          await _updateStockAvailability();
        } else {
          isBatchValid.value = false;
          batchError.value = 'Invalid Batch';
        }
      } else {
        // Bundle logic kept for compatibility
        final response = await _apiProvider.getDocument('Serial and Batch Bundle', batch);
        if (response.statusCode == 200 && response.data['data'] != null) {
          // Re-use logic for validation
          isBatchValid.value = true;
          isBatchReadOnly.value = true;
          // Note: We don't overwrite the bundle here if we are just validating a typed string in legacy mode
        } else {
          isBatchValid.value = false;
          batchError.value = 'Invalid Bundle';
        }
      }
    } catch (e) {
      isBatchValid.value = false;
      batchError.value = 'Validation Error';
    }
    validateSheet();
  }

  Future<List<Map<String, dynamic>>> searchBatches(String query) async {
    if (itemCode.value.isEmpty) return [];
    try {
      final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365 * 2)));
      final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response = await _apiProvider.getBatchWiseBalance(
          itemCode: itemCode.value,
          batchNo: null,
          warehouse: itemSourceWarehouse.value,
          fromDate: fromDate,
          toDate: toDate
      );
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        return result.where((e) {
          if (e is! Map) return false;
          final batch = (e['batch_no'] ?? '').toString().toLowerCase();
          final balance = (e['balance_qty'] ?? 0.0);
          final search = query.toLowerCase();
          return balance > 0 && batch.contains(search);
        }).map((e) => {
          'batch': e['batch'],
          'qty': e['balance_qty']
        }).toList();
      }
    } catch (e) {
      print('Batch search error: $e');
    }
    return [];
  }

  Future<void> _updateStockAvailability() async {
    final sWh = itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value;
    if (sWh == null) return;

    try {
      final response = await _apiProvider.getStockBalance(
          itemCode: itemCode.value,
          warehouse: sWh,
          batchNo: batchController.text.isNotEmpty ? batchController.text : null
      );

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        double total = 0.0;
        final rack = sourceRackController.text;

        for (var row in result) {
          if (row is! Map) continue;
          if (rack.isNotEmpty && row['rack'] != rack) continue;
          total += (row['bal_qty'] ?? 0 as num).toDouble();
        }
        maxQty.value = total;

        if (rack.isNotEmpty && total <= 0) {
          rackError.value = 'Insufficient stock in Rack';
          isSourceRackValid.value = false;
        }
      }
    } catch (e) {
      print('Stock fetch error: $e');
    }
  }

  Future<void> validateRack(String rack, {required bool isSource}) async {
    if (rack.isEmpty) return;
    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        if (isSource) itemSourceWarehouse.value = wh;
        else itemTargetWarehouse.value = wh;
      }
    }

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200) {
        if (isSource) {
          isSourceRackValid.value = true;
          await _updateStockAvailability();
        } else {
          isTargetRackValid.value = true;
        }
      } else {
        if (isSource) isSourceRackValid.value = false;
        else isTargetRackValid.value = false;
      }
    } catch (e) {
      // ignore
    }
    validateSheet();
  }

  // --- Batch Addition with Debounced Auto-Save ---

  Future<void> validateAndAddBatch(String batch) async {
    if (batch.isEmpty) return;
    batchError.value = null;
    isValidatingBatch.value = true;

    try {
      final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365 * 2)));
      final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final response = await _apiProvider.getBatchWiseBalance(
          itemCode: itemCode.value,
          batchNo: batch,
          warehouse: itemSourceWarehouse.value,
          fromDate: fromDate,
          toDate: toDate
      );

      bool isValid = false;

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        final match = result.firstWhereOrNull((e) =>
        e is Map && e['batch'] == batch && (e['balance_qty'] ?? 0) > 0
        );

        if (match != null) {
          isValid = true;
          addEntry(batch, 1.0);
          batchController.clear();
          _triggerAutoSave();
        }
      }

      if (!isValid) {
        batchError.value = 'Invalid Batch or Insufficient Stock';
      }

    } catch (e) {
      batchError.value = 'Validation Error: $e';
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  void _triggerAutoSave() {
    if (!_storageService.getAutoSubmitEnabled()) {
      validateSheet();
      _checkDirty();
      return;
    }

    _autoSaveTimer?.cancel();
    final delaySeconds = _storageService.getAutoSubmitDelay();

    _autoSaveTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (isSheetValid.value) {
        _parent.isDirty.value = true;
        submit(closeSheet: false);

        GlobalSnackbar.success(message: 'Auto-saved batch changes');
        await _parent.saveStockEntry();
      }
    });
  }

  void addEntry(String batch, double qty) {
    if (qty <= 0) return;
    final existing = currentBundleEntries.firstWhereOrNull((b) => b.batchNo == batch);
    if (existing != null) {
      existing.qty += qty;
      currentBundleEntries.refresh();
    } else {
      currentBundleEntries.add(SerialAndBatchEntry(batchNo: batch, qty: qty));
    }
    _handleBatchChange();
  }

  void updateEntryQty(int index, double newQty) {
    if (newQty == 0) {
      removeEntry(index);
      return;
    }
    currentBundleEntries[index].qty = newQty;
    currentBundleEntries.refresh();
    _handleBatchChange();
  }

  void removeEntry(int index) {
    currentBundleEntries.removeAt(index);
    _handleBatchChange();
  }

  void _handleBatchChange() {
    _recalcTotal();
    _checkDirty();
  }

  // --- Sync Logic ---

  Future<void> _updateExistingBundleSequence() async {
    final bundleId = originalBundle!.name!;
    final newTotal = double.tryParse(qtyController.text) ?? 0.0;
    final stockEntryId = _parent.stockEntry.value?.name;

    if (stockEntryId == null) return;

    try {
      final docResponse = await _apiProvider.getDocument('Stock Entry', stockEntryId);
      final remoteItems = (docResponse.data['data']['items'] as List)
          .map((e) => StockEntryItem.fromJson(e))
          .toList();

      final targetRow = remoteItems.firstWhereOrNull((i) => i.serialAndBatchBundle == bundleId);

      if (targetRow == null || targetRow.name == null) {
        GlobalSnackbar.error(message: 'Sync Error: Could not find item row on server. Please refresh.');
        return;
      }

      final realRowId = targetRow.name!;
      currentItemNameKey.value = realRowId;

      final unlinkItem = _reconstructItem(realRowId, targetRow.qty, null);
      _parent.upsertItem(unlinkItem);
      await _parent.saveStockEntry();

      final bundleData = {
        'voucher_no': null,
        'voucher_detail_no': null,
        'entries': currentBundleEntries.map((e) => e.toJson()).toList(),
        'total_qty': newTotal,
      };
      await _apiProvider.updateDocument('Serial and Batch Bundle', bundleId, bundleData);

      final relinkItem = _reconstructItem(realRowId, newTotal, bundleId);
      _parent.upsertItem(relinkItem);
      await _parent.saveStockEntry();

      _initialSnapshot = relinkItem;
      await _fetchBundleDetails(bundleId);

    } catch (e) {
      log('Error updating batch sequence: $e');
      GlobalSnackbar.error(message: 'Sync Error: $e');
      rethrow; // Pass error up so submit knows not to close
    }
  }

  StockEntryItem _reconstructItem(String rowId, double qty, String? bundleId) {
    return StockEntryItem(
      name: rowId,
      itemCode: itemCode.value,
      qty: qty.abs(),
      basicRate: _initialSnapshot?.basicRate ?? 0.0,
      serialAndBatchBundle: bundleId,
      batchNo: useSerialBatchFields.value ? batchController.text : null,
      rack: sourceRackController.text,
      toRack: targetRackController.text,
      sWarehouse: itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value,
      tWarehouse: itemTargetWarehouse.value ?? _parent.selectedToWarehouse.value,
      useSerialBatchFields: useSerialBatchFields.value ? 1 : 0,
      itemName: itemName.value,
      customVariantOf: customVariantOf,
      customInvoiceSerialNumber: selectedSerial.value,
      owner: itemOwner.value,
      creation: itemCreation.value,
      modified: itemModified.value,
      modifiedBy: itemModifiedBy.value,
    );
  }

  Future<void> _createAndLinkBundle() async {
    final warehouse = itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value ?? '';
    final newTotal = double.tryParse(qtyController.text) ?? 0.0;

    final typeOfTransaction = originalBundle?.typeOfTransaction ??
        (warehouse.isNotEmpty ? 'Outward' : 'Inward');

    final bundleData = {
      'item_code': itemCode.value,
      'warehouse': warehouse,
      'type_of_transaction': typeOfTransaction,
      'voucher_type': 'Stock Entry',
      'voucher_no': null,
      'total_qty': newTotal,
      'entries': currentBundleEntries.map((e) => e.toJson()).toList(),
      'docstatus': 0,
    };

    try {
      final response = await _apiProvider.createDocument('Serial and Batch Bundle', bundleData);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final newBundleId = response.data['data']['name'];
        await _upsertAndSave(newBundleId, newTotal);
      }
    } catch (e) {
      log('Error creating bundle: $e');
      GlobalSnackbar.error(message: 'Create Error: $e');
      rethrow;
    }
  }

  Future<void> _upsertAndSave(String bundleId, double qty) async {
    String? rowId = currentItemNameKey.value;
    final parentItems = _parent.stockEntry.value?.items ?? [];

    if (rowId == null || rowId.startsWith('local_')) {
      final match = parentItems.firstWhereOrNull((i) => i.serialAndBatchBundle == bundleId);
      if (match != null && match.name != null) {
        rowId = match.name;
        currentItemNameKey.value = rowId;
      }
    }

    StockEntryItem itemToSave;
    if (_initialSnapshot != null) {
      itemToSave = _initialSnapshot!.copyWith(
        name: rowId,
        qty: qty,
        serialAndBatchBundle: bundleId,
        batchNo: useSerialBatchFields.value ? batchController.text : null,
      );
    } else {
      // Basic construction if snapshot missing
      itemToSave = StockEntryItem(
        name: rowId,
        itemCode: itemCode.value,
        qty: qty,
        basicRate: 0,
        serialAndBatchBundle: bundleId,
        batchNo: useSerialBatchFields.value ? batchController.text : null,
        rack: sourceRackController.text,
        toRack: targetRackController.text,
        sWarehouse: itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value,
        tWarehouse: itemTargetWarehouse.value ?? _parent.selectedToWarehouse.value,
        useSerialBatchFields: useSerialBatchFields.value ? 1 : 0,
        itemName: itemName.value,
        customVariantOf: customVariantOf,
        customInvoiceSerialNumber: selectedSerial.value,
      );
    }

    _parent.upsertItem(itemToSave);
    await _parent.saveStockEntry();

    final updatedItem = _parent.stockEntry.value?.items.firstWhereOrNull(
            (i) => i.serialAndBatchBundle == bundleId
    );

    if (updatedItem != null) {
      if (updatedItem.name != null) currentItemNameKey.value = updatedItem.name;
      _initialSnapshot = updatedItem;
    }

    await _fetchBundleDetails(bundleId);
  }

  void _recalcTotal() {
    final total = currentBundleEntries.fold(0.0, (sum, b) => sum + b.qty.abs());
    qtyController.text = total.toStringAsFixed(2);
    validateSheet();
  }

  Future<void> _fetchBundleDetails(String bundleId) async {
    try {
      final response = await _apiProvider.getDocument('Serial and Batch Bundle', bundleId);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        originalBundle = SerialAndBatchBundle.fromJson(data);
        if (originalBundle != null) {
          currentBundleEntries.assignAll(originalBundle!.entries.map((e) =>
              SerialAndBatchEntry.fromJson(e.toJson())).toList());
        }
      } else {
        GlobalSnackbar.error(message: 'Error fetching bundle: ${response.statusCode}');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Could not load batch details: $e');
    }
  }

  // --- SUBMIT ---
  Future<void> submit({bool closeSheet = true}) async {
    // 1. Guard against double submission / race conditions
    if (isSubmitting.value) return;
    if (!isSheetValid.value) return;

    // 2. Allow programmatic save even if clean (Auto-Save), but Manual Save checks dirty
    if (!isFormDirty.value && closeSheet) {
      Get.back();
      return;
    }

    isSubmitting.value = true;

    try {
      SerialAndBatchBundle? dirtyBundle;

      if (_isBundleDirty()) {
        dirtyBundle = SerialAndBatchBundle(
          name: originalBundle?.name,
          itemCode: itemCode.value,
          warehouse: itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value ?? '',
          totalQty: double.tryParse(qtyController.text) ?? 0,
          entries: List.from(currentBundleEntries),
        );
      }

      final newItem = StockEntryItem(
        name: currentItemNameKey.value ?? (_parent.itemKeys.keys.contains(itemCode.value) ? null : 'local_${DateTime.now().millisecondsSinceEpoch}'),
        itemCode: itemCode.value,
        itemName: itemName.value,
        qty: double.tryParse(qtyController.text) ?? 0,
        basicRate: 0.0,
        batchNo: useSerialBatchFields.value ? batchController.text : null,
        useSerialBatchFields: useSerialBatchFields.value ? 1 : 0,
        rack: sourceRackController.text,
        toRack: targetRackController.text,
        sWarehouse: itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value,
        tWarehouse: itemTargetWarehouse.value ?? _parent.selectedToWarehouse.value,
        customVariantOf: customVariantOf,
        customInvoiceSerialNumber: selectedSerial.value,
        serialAndBatchBundle: originalBundle?.name,
        owner: itemOwner.value,
        creation: itemCreation.value,
        modified: itemModified.value,
        modifiedBy: itemModifiedBy.value,
      );

      StockEntryItem finalItem = _enrichWithContext(newItem);

      // Local UI Update
      _parent.upsertItem(finalItem, bundle: dirtyBundle);

      // Server Logic (Wait for this before closing sheet!)
      if (originalBundle != null && originalBundle!.name != null && dirtyBundle != null) {
        await _updateExistingBundleSequence();
      } else if (dirtyBundle != null && originalBundle == null) {
        await _createAndLinkBundle();
      }

      // Close only after success
      if (closeSheet) Get.back();

    } catch (e) {
      log('Submit failed: $e');
      // Do NOT close sheet on error so user can retry
    } finally {
      isSubmitting.value = false;
    }
  }

  StockEntryItem _enrichWithContext(StockEntryItem item) {
    String? matReq;
    String? matReqItem;

    if (_parent.entrySource == StockEntrySource.materialRequest && _parent.mrReferenceItems.isNotEmpty) {
      final ref = _parent.mrReferenceItems.firstWhereOrNull((r) =>
      r['item_code'].toString().trim().toLowerCase() == item.itemCode.trim().toLowerCase());

      if (ref != null) {
        matReq = ref['material_request'];
        matReqItem = ref['material_request_item'];
      }
    }

    return StockEntryItem(
      name: item.name, itemCode: item.itemCode, qty: item.qty, basicRate: item.basicRate,
      itemGroup: item.itemGroup, customVariantOf: item.customVariantOf,
      batchNo: item.batchNo, useSerialBatchFields: item.useSerialBatchFields,
      itemName: item.itemName, rack: item.rack, toRack: item.toRack, sWarehouse: item.sWarehouse,
      tWarehouse: item.tWarehouse, customInvoiceSerialNumber: item.customInvoiceSerialNumber,
      serialAndBatchBundle: item.serialAndBatchBundle,
      materialRequest: matReq ?? item.materialRequest,
      materialRequestItem: matReqItem ?? item.materialRequestItem,
      owner: item.owner, creation: item.creation, modified: item.modified, modifiedBy: item.modifiedBy,
    );
  }

  void deleteItem() {
    if (currentItemNameKey.value != null) {
      _parent.deleteItem(currentItemNameKey.value!);
      Get.back();
    }
  }

  StockEntryFormController get parent => _parent;
}