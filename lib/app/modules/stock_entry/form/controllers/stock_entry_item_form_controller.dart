import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';

// Models
import 'package:multimax/app/data/models/stock_entry_model.dart' hide SerialAndBatchBundle, SerialAndBatchEntry;
import 'package:multimax/app/data/models/scan_result_model.dart';
// Import Common Bundle Models & Controller
import 'package:multimax/app/data/models/serial_batch_bundle_model.dart';
import 'package:multimax/app/modules/common/serial_batch_bundle/controllers/serial_batch_bundle_controller.dart';
import 'package:multimax/app/modules/common/serial_batch_bundle/views/serial_batch_bundle_sheet.dart';

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
  var useSerialBatchFields = false.obs; // Legacy field, mostly false now
  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var maxQty = 0.0.obs;
  var rackError = RxnString();
  var isSheetValid = false.obs;

  // Guard to prevent double submission
  var isSubmitting = false.obs;

  // --- Context & Warehouse ---
  var selectedSerial = RxnString();
  var itemSourceWarehouse = RxnString();
  var itemTargetWarehouse = RxnString();

  // --- Dirty State & Snapshot Management ---
  var isFormDirty = false.obs;
  StockEntryItem? _initialSnapshot;

  RxBool get isSaveEnabled => (isSheetValid.value && isFormDirty.value && !isSubmitting.value).obs;

  // --- Common Bundle State ---
  // We store the ID and the visual entries for the UI summary
  var currentBundleId = RxnString();
  var currentBundleEntries = <SerialAndBatchEntry>[].obs;

  // To detect if bundle was modified via the common sheet
  var isBundleDirty = false.obs;

  @override
  void onClose() {
    qtyController.dispose();
    sourceRackController.dispose();
    targetRackController.dispose();
    super.onClose();
  }

  void initialise({
    required StockEntryFormController parentController,
    StockEntryItem? existingItem,
    String? initialItemCode,
    String? initialBatch, // Kept for legacy compatibility
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

  void _captureSnapshot() {
    _initialSnapshot = StockEntryItem(
      name: currentItemNameKey.value,
      itemCode: itemCode.value,
      qty: double.tryParse(qtyController.text) ?? 0,
      basicRate: 0,
      rack: sourceRackController.text,
      toRack: targetRackController.text,
      sWarehouse: itemSourceWarehouse.value,
      tWarehouse: itemTargetWarehouse.value,
      serialAndBatchBundle: currentBundleId.value,
    );
  }

  void _setupListeners() {
    qtyController.addListener(() { validateSheet(); _checkDirty(); });
    sourceRackController.addListener(() { validateSheet(); _checkDirty(); });
    targetRackController.addListener(() { validateSheet(); _checkDirty(); });
    ever(itemSourceWarehouse, (_) { _updateStockAvailability(); _checkDirty(); });
    ever(currentBundleId, (_) { _checkDirty(); });
  }

  void _checkDirty() {
    if (_initialSnapshot == null) return;

    final currentQty = double.tryParse(qtyController.text) ?? 0;

    bool fieldsDirty =
        currentQty != _initialSnapshot!.qty ||
            sourceRackController.text != (_initialSnapshot!.rack ?? '') ||
            targetRackController.text != (_initialSnapshot!.toRack ?? '') ||
            itemSourceWarehouse.value != _initialSnapshot!.sWarehouse ||
            itemTargetWarehouse.value != _initialSnapshot!.tWarehouse ||
            currentBundleId.value != _initialSnapshot!.serialAndBatchBundle ||
            isBundleDirty.value;

    isFormDirty.value = fieldsDirty;
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

    qtyController.text = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();

    sourceRackController.text = item.rack ?? '';
    targetRackController.text = item.toRack ?? '';
    if (sourceRackController.text.isNotEmpty) isSourceRackValid.value = true;
    if (targetRackController.text.isNotEmpty) isTargetRackValid.value = true;

    itemSourceWarehouse.value = item.sWarehouse;
    itemTargetWarehouse.value = item.tWarehouse;
    selectedSerial.value = item.customInvoiceSerialNumber;

    // Load Bundle ID
    currentBundleId.value = item.serialAndBatchBundle;

    // Fetch visual details if bundle exists
    if (item.serialAndBatchBundle != null && item.serialAndBatchBundle!.isNotEmpty) {
      _fetchBundleDetails(item.serialAndBatchBundle!);
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

    if (_parent.entrySource == StockEntrySource.materialRequest) {
      selectedSerial.value = '0';
    }

    // If a batch was scanned to initiate this item, immediately try to open manager or add it
    // For now, we just let the user open the manager to confirm.
  }

  // --- Scanning Logic ---
  Future<void> handleScan(String barcode) async {
    final result = await _scanService.processScan(barcode, contextItemCode: itemCode.value);

    if (result.type == ScanType.rack && result.rackId != null) {
      _handleRackScan(result.rackId!);
    } else if (result.batchNo != null) {
      // Optional: Could auto-open bundle manager with this batch pre-filled
      GlobalSnackbar.info(title: "Batch Scanned", message: "Please open Batch Manager to add ${result.batchNo}");
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
        _isValidContext() &&
        _isValidRacks();
  }

  bool _isValidQty() {
    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return false;
    if (maxQty.value > 0 && qty > maxQty.value) return false;
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

  Future<void> _updateStockAvailability() async {
    final sWh = itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value;
    if (sWh == null) return;

    try {
      final response = await _apiProvider.getStockBalance(
          itemCode: itemCode.value,
          warehouse: sWh,
          batchNo: null // We check global item stock in warehouse
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
        } else {
          rackError.value = null;
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

  // --- Common Bundle Integration ---

  void openBatchManager() async {
    // Determine context
    final warehouse = itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value ?? '';
    final typeOfTransaction = (warehouse.isNotEmpty) ? 'Outward' : 'Inward';

    Get.lazyPut(() => SerialBatchBundleController());

    final result = await Get.bottomSheet(
      const SerialBatchBundleSheet(),
      settings: RouteSettings(
          arguments: SerialBatchBundleArguments(
              itemCode: itemCode.value,
              warehouse: warehouse,
              existingBundleId: currentBundleId.value,
              typeOfTransaction: typeOfTransaction,
              voucherType: 'Stock Entry',
              requiredQty: double.tryParse(qtyController.text)
          )
      ),
      isScrollControlled: true,
    );

    if (result != null && result is Map) {
      // Extract data from common module
      final String bundleId = result['bundleId'];
      final double totalQty = result['totalQty'];
      final List<SerialAndBatchEntry> entries = result['entries'];

      // Update State
      currentBundleId.value = bundleId;
      currentBundleEntries.assignAll(entries);

      // Update Qty if changed in manager
      if (totalQty > 0) {
        qtyController.text = totalQty.toString();
      }

      isBundleDirty.value = true;
      _checkDirty();
      GlobalSnackbar.success(message: 'Batch Bundle Updated');
    }
  }

  Future<void> _fetchBundleDetails(String bundleId) async {
    try {
      final response = await _apiProvider.getDocument('Serial and Batch Bundle', bundleId);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        final bundle = SerialAndBatchBundle.fromJson(data);
        currentBundleEntries.assignAll(bundle.entries);
      }
    } catch (e) {
      print('Error fetching bundle preview: $e');
    }
  }

  // --- SUBMIT ---
  Future<void> submit({bool closeSheet = true}) async {
    if (isSubmitting.value) return;
    if (!isSheetValid.value) return;

    if (!isFormDirty.value && closeSheet) {
      Get.back();
      return;
    }

    isSubmitting.value = true;

    try {
      final newItem = StockEntryItem(
        name: currentItemNameKey.value ?? (_parent.itemKeys.keys.contains(itemCode.value) ? null : 'local_${DateTime.now().millisecondsSinceEpoch}'),
        itemCode: itemCode.value,
        itemName: itemName.value,
        qty: double.tryParse(qtyController.text) ?? 0,
        basicRate: 0.0,
        rack: sourceRackController.text,
        toRack: targetRackController.text,
        sWarehouse: itemSourceWarehouse.value ?? _parent.selectedFromWarehouse.value,
        tWarehouse: itemTargetWarehouse.value ?? _parent.selectedToWarehouse.value,
        customVariantOf: customVariantOf,
        customInvoiceSerialNumber: selectedSerial.value,
        serialAndBatchBundle: currentBundleId.value, // This is the key link
        owner: itemOwner.value,
        creation: itemCreation.value,
        modified: itemModified.value,
        modifiedBy: itemModifiedBy.value,
      );

      StockEntryItem finalItem = _enrichWithContext(newItem);

      // Upsert to Parent
      _parent.upsertItem(finalItem);

      // We don't need to manually save the bundle here because the Common Module
      // already saved it to the server when "Confirm" was clicked in the sheet.

      // Close only after success
      if (closeSheet) Get.back();

    } catch (e) {
      log('Submit failed: $e');
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

    return item.copyWith(
      materialRequest: matReq,
      materialRequestItem: matReqItem,
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