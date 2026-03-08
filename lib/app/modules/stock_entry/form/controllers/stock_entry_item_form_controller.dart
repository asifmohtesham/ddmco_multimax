import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart'; // Added for DateFormat
import 'package:multimax/app/data/models/scan_result_model.dart';

// Models
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/services/scan_service.dart';

// Providers & Widgets
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

// Parent Controller
import '../stock_entry_form_controller.dart';

class StockEntryItemFormController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();

  late StockEntryFormController _parent;

  // --- Form Key ---
  final GlobalKey<FormState> itemFormKey = GlobalKey<FormState>();

  // --- Toggle State ---
  var useSerialBatchFields = false.obs;

  // --- Form State ---
  final qtyController = TextEditingController();
  final batchController = TextEditingController();
  final sourceRackController = TextEditingController();
  final targetRackController = TextEditingController();

  var itemCode = ''.obs;
  var itemName = ''.obs;
  var itemUom = ''.obs;
  var customVariantOf = '';

  // Metadata for editing
  var itemOwner = RxnString();
  var itemCreation = RxnString();
  var itemModified = RxnString();
  var itemModifiedBy = RxnString();
  var currentItemNameKey = RxnString();

  // --- Validation State ---
  var isBatchValid = false.obs;
  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var maxQty = 0.0.obs;
  var rackError = RxnString();
  var batchError = RxnString();
  var isSheetValid = false.obs;
  var isValidatingBatch = false.obs;

  // --- Dirty State Management ---
  var isFormDirty = false.obs;
  StockEntryItem? _initialSnapshot;

  // Computed property for UI Save Button
  RxBool get isSaveEnabled => (isSheetValid.value && isFormDirty.value).obs;

  // --- Batches / SABB Entries ---
  // The working copy of entries
  var currentBundleEntries = <SerialAndBatchEntry>[].obs;
  var isBatchReadOnly = false.obs;

  // The original pristine bundle fetched from server or parent (for dirty checking)
  SerialAndBatchBundle? originalBundle;

  // --- Context & Warehouse ---
  var selectedSerial = RxnString();
  var itemSourceWarehouse = RxnString();
  var itemTargetWarehouse = RxnString();

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
    _captureSnapshot(); // Capture clean state after loading
    validateSheet();
    _checkDirty();      // Verify initial dirty state
  }

  void _captureSnapshot() {
    _initialSnapshot = StockEntryItem(
      name: currentItemNameKey.value, // FIX: Include Name so updates find the correct row
      itemCode: itemCode.value,
      qty: double.tryParse(qtyController.text) ?? 0,
      basicRate: 0, // Should ideally come from existing item if available
      batchNo: batchController.text,
      rack: sourceRackController.text,
      toRack: targetRackController.text,
      sWarehouse: itemSourceWarehouse.value,
      tWarehouse: itemTargetWarehouse.value,
      useSerialBatchFields: useSerialBatchFields.value ? 1 : 0,
    );
  }

  void _setupListeners() {
    // Listeners trigger dirty checks
    qtyController.addListener(() { validateSheet(); _checkDirty(); });
    batchController.addListener(() { validateSheet(); _checkDirty(); });
    sourceRackController.addListener(() { validateSheet(); _checkDirty(); });
    targetRackController.addListener(() { validateSheet(); _checkDirty(); });

    // Update stock when warehouse changes
    ever(itemSourceWarehouse, (_) { _updateStockAvailability(); _checkDirty(); });
  }

  void _checkDirty() {
    if (_initialSnapshot == null) return;

    final currentQty = double.tryParse(qtyController.text) ?? 0;

    // Check if basic fields have changed from snapshot
    bool fieldsDirty =
        currentQty != _initialSnapshot!.qty ||
            sourceRackController.text != (_initialSnapshot!.rack ?? '') ||
            targetRackController.text != (_initialSnapshot!.toRack ?? '') ||
            (useSerialBatchFields.value && batchController.text != (_initialSnapshot!.batchNo ?? '')) ||
            itemSourceWarehouse.value != _initialSnapshot!.sWarehouse ||
            itemTargetWarehouse.value != _initialSnapshot!.tWarehouse;

    isFormDirty.value = fieldsDirty || _isBundleDirty();
  }

  void _loadExistingItem(StockEntryItem item) {
    itemCode.value = item.itemCode;
    itemName.value = item.itemName ?? '';
    customVariantOf = item.customVariantOf ?? '';
    currentItemNameKey.value = item.name;

    itemOwner.value = item.owner;
    itemCreation.value = item.creation;
    itemModified.value = item.modified;
    itemModifiedBy.value = item.modifiedBy;

    // Determine mode based on usage flag or data presence
    useSerialBatchFields.value = (item.useSerialBatchFields == 1);

    // Qty
    qtyController.text = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();

    // Batch (Legacy)
    batchController.text = item.batchNo ?? '';
    if (useSerialBatchFields.value && item.batchNo != null && item.batchNo!.isNotEmpty) {
      isBatchValid.value = true;
      isBatchReadOnly.value = true;
    }

    // Racks
    sourceRackController.text = item.rack ?? '';
    targetRackController.text = item.toRack ?? '';
    if (sourceRackController.text.isNotEmpty) isSourceRackValid.value = true;
    if (targetRackController.text.isNotEmpty) isTargetRackValid.value = true;

    // Warehouses & Context
    itemSourceWarehouse.value = item.sWarehouse;
    itemTargetWarehouse.value = item.tWarehouse;
    selectedSerial.value = item.customInvoiceSerialNumber;

    // Load Bundle Data
    if (!useSerialBatchFields.value && item.serialAndBatchBundle != null) {
      // Check if parent has an unsaved dirty version of this bundle first
      if (_parent.unsavedBundles.containsKey(item.serialAndBatchBundle)) {
        originalBundle = _parent.unsavedBundles[item.serialAndBatchBundle];
        if (originalBundle != null) {
          currentBundleEntries.assignAll(originalBundle!.entries.map((e) =>
              SerialAndBatchEntry.fromJson(e.toJson())).toList()); // Deep copy for editing
        }
      } else {
        // Fetch from server
        _fetchBundleDetails(item.serialAndBatchBundle!);
      }
    }

    _updateStockAvailability();
  }

  void _loadNewItem(String code, String? batch, dynamic data) {
    itemCode.value = code;
    itemName.value = data?.itemName ?? '';
    customVariantOf = data?.variantOf ?? '';

    // FIX: Generate a local key immediately so subsequent autosaves update this same item
    if (currentItemNameKey.value == null) {
      currentItemNameKey.value = 'local_${DateTime.now().millisecondsSinceEpoch}';
    }

    // Default to SABB (0) unless specified otherwise
    useSerialBatchFields.value = false;

    if (batch != null) {
      validateAndAddBatch(batch);
    }

    // Default Serial for MR
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

    // Auto-assign based on type or empty fields
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
      // Max Qty check vs MR limit could be added here
    }
    return true;
  }

  bool _isValidRacks() {
    final type = _parent.selectedStockEntryType.value;
    final needSource = ['Material Issue', 'Material Transfer'].contains(type);
    final needTarget = ['Material Receipt', 'Material Transfer'].contains(type);

    if (needSource) {
      // Check Source Rack OR Source Warehouse presence
      if (sourceRackController.text.isEmpty && itemSourceWarehouse.value == null && _parent.selectedFromWarehouse.value == null) {
        return false;
      }
      if (sourceRackController.text.isNotEmpty && !isSourceRackValid.value) return false;
    }
    if (needTarget) {
      if (targetRackController.text.isNotEmpty && !isTargetRackValid.value) return false;
      // If strict checking required:
      // if (targetRackController.text.isEmpty && itemTargetWarehouse.value == null && _parent.selectedToWarehouse.value == null) return false;
    }
    return true;
  }

  // --- Business Logic ---

  /// Searches batches using Batch-Wise Balance History.
  /// Filters for batches with Qty > 0.
  Future<List<Map<String, dynamic>>> searchBatches(String query) async {
    if (itemCode.value.isEmpty) return [];

    try {
      // Wide date range to capture current balance history
      final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365 * 2)));
      final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Fetch batch balance history. We fetch all for the item + warehouse (if selected)
      // then filter client-side by query to support "contains" search and "qty > 0".
      final response = await _apiProvider.getBatchWiseBalance(
          itemCode: itemCode.value,
          batchNo: null,
          warehouse: itemSourceWarehouse.value, // Filter by source warehouse if available
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

          // Filter: Qty > 0 AND Matches Query
          return balance > 0 && batch.contains(search);
        }).map((e) => {
          'batch': e['batch'],
          'qty': e['balance_qty'] // Mapping 'balance_qty' to 'qty' for the View
        }).toList();
      }
    } catch (e) {
      print('Batch search error: $e');
    }
    return [];
  }

  /// Validates a manually entered batch against Batch-Wise Balance History (Qty > 0)
  /// If valid, adds it to the bundle entries.
  Future<void> validateAndAddBatch(String batch) async {
    if (batch.isEmpty) return;
    batchError.value = null;
    isValidatingBatch.value = true; // Show Loading

    try {
      final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365 * 2)));
      final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // We use the same report to validate existence and stock
      final response = await _apiProvider.getBatchWiseBalance(
          itemCode: itemCode.value,
          batchNo: batch, // Strict filter if API supports it, or we filter result
          warehouse: itemSourceWarehouse.value,
          fromDate: fromDate,
          toDate: toDate
      );

      bool isValid = false;

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];

        // Check if ANY record matches this batch with positive balance
        final match = result.firstWhereOrNull((e) =>
        e is Map &&
            e['batch'] == batch &&
            (e['balance_qty'] ?? 0) > 0
        );

        if (match != null) {
          isValid = true;
          addEntry(batch, 1.0);
          batchController.clear();

          // Auto-Save Flow
          _parent.isDirty.value = true;
          submit(closeSheet: false); // Commit to parent without closing sheet
          await _parent.saveStockEntry(); // Trigger API save
        }
      }

      if (!isValid) {
        batchError.value = 'Invalid Batch or Insufficient Stock (Qty must be > 0)';
      }

    } catch (e) {
      batchError.value = 'Validation Error: $e';
      print('Batch Add Error: $e');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
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

  Future<void> validateBatch(String batch) async {
    // This method is primarily for "Legacy" batch fields (useSerialBatchFields == true)
    // For Bundle/List mode, use validateAndAddBatch

    batchError.value = null;
    if (batch.isEmpty) return;

    try {
      if (useSerialBatchFields.value) {
        // Legacy Batch
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
        // Bundle - this block might be redundant if using the list UI,
        // but kept for compatibility with existing flows calling validateBatch
        final response = await _apiProvider.getDocument('Serial and Batch Bundle', batch);

        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'];

          if (data['item_code'] == itemCode.value) {
            isBatchValid.value = true;
            isBatchReadOnly.value = true;
            originalBundle = SerialAndBatchBundle.fromJson(data);
            if (originalBundle != null) {
              currentBundleEntries.assignAll(originalBundle!.entries.map((e) =>
                  SerialAndBatchEntry.fromJson(e.toJson())).toList());

              final total = originalBundle!.totalQty;
              if (total > 0) {
                qtyController.text = total % 1 == 0 ? total.toInt().toString() : total.toString();
              }
            }
            await _updateStockAvailability();
          } else {
            isBatchValid.value = false;
            batchError.value = 'Bundle belongs to different item';
          }
        } else {
          isBatchValid.value = false;
          batchError.value = 'Invalid Serial and Batch Bundle';
        }
      }
    } catch (e) {
      isBatchValid.value = false;
      batchError.value = 'Validation Error';
      print('Batch Validation Error: $e');
    }
    validateSheet();
  }

  Future<void> validateRack(String rack, {required bool isSource}) async {
    if (rack.isEmpty) return;

    // Warehouse Parsing logic from Rack ID (Specific to business rule)
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

  // --- Bundle Entry Management ---

  void addEntry(String batch, double qty) {
    if (qty <= 0) return;

    final existing = currentBundleEntries.firstWhereOrNull((b) => b.batchNo == batch);
    if (existing != null) {
      existing.qty += qty;
      currentBundleEntries.refresh();
    } else {
      currentBundleEntries.add(SerialAndBatchEntry(batchNo: batch, qty: qty));
    }
    _handleBatchChange(); // Trigger autosave logic
  }

  void updateEntryQty(int index, double newQty) {
    // if (newQty < 0) return; // Outward qty is negative
    if (newQty == 0) {
      removeEntry(index);
      return;
    }
    currentBundleEntries[index].qty = newQty;
    currentBundleEntries.refresh();
    _handleBatchChange(); // Trigger autosave logic
  }

  void removeEntry(int index) {
    currentBundleEntries.removeAt(index);
    _handleBatchChange(); // Trigger autosave logic
  }

  /// Handles batch updates: Recalcs total, Syncs to Server, Updates Parent, Autosaves Parent
  void _handleBatchChange() {
    _recalcTotal();
    _checkDirty();

    if (originalBundle != null && originalBundle!.name != null) {
      _updateExistingBundleSequence();
    } else {
      _createAndLinkBundle(); // Fallback for new items (handled in previous logic)
    }
  }

  /// Executes a 3-Step "Safe Update" to prevent validation deadlocks.
  /// 1. Detach Bundle from Stock Entry (Save SE) -> Valid state (Item Qty X, No Bundle).
  /// 2. Update Bundle on Server -> Valid state (Bundle Qty Y, Orphan).
  /// 3. Attach Bundle to Stock Entry & Update Qty (Save SE) -> Valid state (Item Qty Y, Bundle Qty Y).
  Future<void> _updateExistingBundleSequence() async {
    final bundleId = originalBundle!.name!;
    final newTotal = double.tryParse(qtyController.text) ?? 0.0;
    final stockEntryId = _parent.stockEntry.value?.name;

    if (stockEntryId == null) return;

    try {
      // 1. CRITICAL: Fetch fresh Stock Entry data to resolve the REAL Server Row ID.
      // Relying on local state is dangerous if the parent controller hasn't refreshed
      // its list after the last save.
      final docResponse = await _apiProvider.getDocument('Stock Entry', stockEntryId);
      final remoteItems = (docResponse.data['data']['items'] as List)
          .map((e) => StockEntryItem.fromJson(e))
          .toList();

      // Find the row that is currently linked to our Bundle
      final targetRow = remoteItems.firstWhereOrNull((i) => i.serialAndBatchBundle == bundleId);

      if (targetRow == null || targetRow.name == null) {
        GlobalSnackbar.error(message: 'Sync Error: Could not find item row on server. Please refresh.');
        return;
      }

      final realRowId = targetRow.name!;
      currentItemNameKey.value = realRowId; // Sync local key

      // Step 2: UNLINK the Bundle from the Stock Entry Item
      // Use the resolved 'realRowId' to ensure we update the existing row.
      final unlinkItem = _reconstructItem(realRowId, targetRow.qty, null);
      _parent.upsertItem(unlinkItem);
      await _parent.saveStockEntry();

      // Step 3: UPDATE the Serial and Batch Bundle
      // Clear voucher_detail_no to remove back-reference.
      final bundleData = {
        'voucher_no': null,
        'voucher_detail_no': null,
        'entries': currentBundleEntries.map((e) => e.toJson()).toList(),
        'total_qty': newTotal,
      };
      await _apiProvider.updateDocument('Serial and Batch Bundle', bundleId, bundleData);

      // Step 4: UPDATE Item Quantity & RELINK the Bundle
      // Now update the row to Qty 7 and link the Bundle (Qty 7).
      log(name: 'updateExistingBundleSequence', 'realRowId: $realRowId, newTotal: $newTotal, bundleId: $bundleId');
      final relinkItem = _reconstructItem(realRowId, newTotal, bundleId);
      _parent.upsertItem(relinkItem);
      await _parent.saveStockEntry();

      // Refresh Local State
      _initialSnapshot = relinkItem;
      await _fetchBundleDetails(bundleId);

    } catch (e) {
      log('Error updating batch sequence: $e');
      GlobalSnackbar.error(message: 'Sync Error: $e');
    }
  }

  /// Helper to create StockEntryItem with specific Qty and Bundle
  /// Avoids copyWith nullability issues (where passing null might be ignored)
  StockEntryItem _reconstructItem(String rowId, double qty, String? bundleId) {
    log(name: 'reconstructItem', 'rowId: $rowId, qty: $qty, bundleId: $bundleId');
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
    }
  }

  /// Helper to construct Item Row, Update Parent, Save, and Sync ID
  Future<void> _upsertAndSave(String bundleId, double qty) async {
    // RESOLVE ROW ID: Critical to prevent "Stale Row" errors.
    // If we rely on a local/null key, upsertItem might create a duplicate,
    // leaving the old row (Qty 1) linked to the modified Bundle (Qty 15), causing the error.

    String? rowId = currentItemNameKey.value;
    final parentItems = _parent.stockEntry.value?.items ?? [];

    // If local key is stale, find the REAL row on the server by matching the Bundle ID
    if (rowId == null || rowId.startsWith('local_')) {
      final match = parentItems.firstWhereOrNull((i) => i.serialAndBatchBundle == bundleId);
      if (match != null && match.name != null) {
        rowId = match.name;
        currentItemNameKey.value = rowId; // Sync for future updates
      }
    }

    // Construct Updated Item
    StockEntryItem itemToSave;
    if (_initialSnapshot != null) {
      itemToSave = _initialSnapshot!.copyWith(
        name: rowId, // Must use the resolved Server ID
        qty: qty,
        serialAndBatchBundle: bundleId,
        batchNo: useSerialBatchFields.value ? batchController.text : null,
      );
    } else {
      // Fallback manual construction
      itemToSave = StockEntryItem(
        name: rowId,
        itemCode: itemCode.value,
        qty: qty,
        basicRate: 0.0,
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

    // Update Parent State & Trigger Save
    // This now updates the correct row with Qty 15 + Bundle Link, passing validation.
    _parent.upsertItem(itemToSave);
    await _parent.saveStockEntry();

    // Post-Save: Refresh local state to ensure we stay in sync
    final updatedItem = _parent.stockEntry.value?.items.firstWhereOrNull(
            (i) => i.serialAndBatchBundle == bundleId
    );

    if (updatedItem != null) {
      if (updatedItem.name != null) currentItemNameKey.value = updatedItem.name;
      _initialSnapshot = updatedItem;
    }

    await _fetchBundleDetails(bundleId);
  }

  Future<void> _deleteOrphanBundle(String bundleId) async {
    if (bundleId.startsWith('local_')) return;
    try {
      await _apiProvider.deleteDocument('Serial and Batch Bundle', bundleId);
    } catch (e) {
      log('Failed to delete orphan bundle $bundleId: $e');
    }
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
              SerialAndBatchEntry.fromJson(e.toJson())).toList()); // Deep copy
        }
      } else {
        GlobalSnackbar.error(message: 'Error fetching bundle: ${response.statusCode}');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Could not load batch details: $e');
    }
  }

  bool _isBundleDirty() {
    if (useSerialBatchFields.value) return false;
    // If we have entries but no original bundle, it's a new bundle -> Dirty
    if (originalBundle == null) return currentBundleEntries.isNotEmpty;

    // Compare entries
    if (originalBundle!.entries.length != currentBundleEntries.length) return true;

    // Sort and compare for deeper equality
    for (var entry in currentBundleEntries) {
      final orig = originalBundle!.entries.firstWhereOrNull((e) => e.batchNo == entry.batchNo);
      if (orig == null || orig.qty != entry.qty) return true;
    }
    return false;
  }

  // --- Actions ---

  void submit({bool closeSheet = true}) {
    if (!isSheetValid.value) return;

    SerialAndBatchBundle? dirtyBundle;

    // If bundle is dirty, prepare the object to pass to parent
    if (_isBundleDirty()) {
      dirtyBundle = SerialAndBatchBundle(
        name: originalBundle?.name, // Keep existing ID if any (to trigger update), else null
        itemCode: itemCode.value,
        warehouse: itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value ?? '',
        totalQty: double.tryParse(qtyController.text) ?? 0,
        entries: List.from(currentBundleEntries),
      );
    }

    final newItem = StockEntryItem(
      // Use existing item name if available (editing), else generate temp key
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

      // We pass the existing Bundle ID if we have it, or let parent assign temp ID via dirtyBundle return
      serialAndBatchBundle: originalBundle?.name,

      // Metadata
      owner: itemOwner.value,
      creation: itemCreation.value,
      modified: itemModified.value,
      modifiedBy: itemModifiedBy.value,
    );

    // Enrich with Context Data from Parent if needed
    StockEntryItem finalItem = _enrichWithContext(newItem);

    // Pass the dirty bundle side-by-side with the item
    _parent.upsertItem(finalItem, bundle: dirtyBundle);
    Get.back();

    // Check named parameter before closing
    if (closeSheet) Get.back();
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