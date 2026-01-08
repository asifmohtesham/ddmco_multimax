import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
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
    validateSheet();
  }

  void _setupListeners() {
    qtyController.addListener(validateSheet);
    batchController.addListener(validateSheet);
    sourceRackController.addListener(validateSheet);
    targetRackController.addListener(validateSheet);

    // Update stock when warehouse changes
    ever(itemSourceWarehouse, (_) => _updateStockAvailability());
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

    // Default to SABB (0) unless specified otherwise, or logic derived from item meta
    useSerialBatchFields.value = false;

    if (batch != null) {
      addEntry(batch, 1.0);
      batchController.text = batch;
      validateBatch(batch);
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
      addEntry(result.batchNo!, 1.0);
      batchController.text = result.batchNo!;
      validateBatch(result.batchNo!);
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
  Future<List<Map<String, dynamic>>> searchBatches(String query) async {
    if (itemCode.value.isEmpty) return [];

    try {
      final response = await _apiProvider.getDocumentList('Batch',
          filters: {
            'item': itemCode.value,
            'name': ['like', '%$query%']
          },
          limit: 10
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        // Return the full data maps instead of just strings
        return List<Map<String, dynamic>>.from(response.data['data']);
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

  Future<void> validateBatch(String batch) async {
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
        // Bundle
        final response = await _apiProvider.getDocument('Serial and Batch Bundle', batch);

        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'];

          if (data['item_code'] == itemCode.value) {
            isBatchValid.value = true;
            isBatchReadOnly.value = true;

            originalBundle = SerialAndBatchBundle.fromJson(data);
            if (originalBundle != null) {
              currentBundleEntries.assignAll(originalBundle!.entries.map((e) =>
                  SerialAndBatchEntry.fromJson(e.toJson())).toList()); // Deep copy

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
    _recalcTotal();
  }

  void updateEntryQty(int index, double newQty) {
    if (newQty < 0) return;
    if (newQty == 0) {
      removeEntry(index);
      return;
    }
    currentBundleEntries[index].qty = newQty;
    currentBundleEntries.refresh();
    _recalcTotal();
  }

  void removeEntry(int index) {
    currentBundleEntries.removeAt(index);
    _recalcTotal();
  }

  void _recalcTotal() {
    final total = currentBundleEntries.fold(0.0, (sum, b) => sum + b.qty);
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

    // Sort and compare for deeper equality if order doesn't matter,
    // or simple strict check if index matters. Usually order matters less, but quantities do.
    // For simplicity, checking if sums or specific batches changed:
    for (var entry in currentBundleEntries) {
      final orig = originalBundle!.entries.firstWhereOrNull((e) => e.batchNo == entry.batchNo);
      if (orig == null || orig.qty != entry.qty) return true;
    }
    return false;
  }

  // --- Actions ---

  void submit() {
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