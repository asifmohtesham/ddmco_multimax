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

import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';

// 1. Define the Enum used by the screen
enum StockEntrySource {
  manual,
  materialRequest,
  posUpload
}

class StockEntryFormController extends GetxController with OptimisticLockingMixin {
  // --- Dependencies ---
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();
  final StorageService _storageService = Get.find<StorageService>();
  final ScanService _scanService = Get.find<ScanService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();

  // --- Arguments ---
  String name = Get.arguments?['name'] ?? '';
  String mode = Get.arguments?['mode'] ?? 'view';
  final String? argStockEntryType = Get.arguments?['stockEntryType'];
  final String? argCustomReferenceNo = Get.arguments?['customReferenceNo'];

  // --- State ---
  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var isAddingItem = false.obs;

  var stockEntry = Rx<StockEntry?>(null);

  // 2. Define the source variable accessed by the screen
  var entrySource = StockEntrySource.manual;

  // --- Context Data ---
  // 3. Define the reference items list accessed by the screen
  var mrReferenceItems = <Map<String, dynamic>>[];

  var posUpload = Rx<PosUpload?>(null);
  var posUploadSerialOptions = <String>[].obs;
  var expandedInvoice = ''.obs;

  // --- Form Fields ---
  var selectedFromWarehouse = RxnString();
  var selectedToWarehouse = RxnString();
  final customReferenceNoController = TextEditingController();

  var stockEntryTypes = <String>[].obs;
  var isFetchingTypes = false.obs;
  var selectedStockEntryType = 'Material Transfer'.obs;

  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // --- Item Form State ---
  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsSourceRackController = TextEditingController();
  final bsTargetRackController = TextEditingController();
  final TextEditingController barcodeController = TextEditingController();

  // New Item Level Warehouse Fields
  var bsItemSourceWarehouse = RxnString();
  var bsItemTargetWarehouse = RxnString();

  var bsMaxQty = 0.0.obs;
  var bsValidationMaxQty = 0.0.obs;

  var isItemSheetOpen = false.obs;
  var isSheetValid = false.obs;

  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs;
  var isValidatingBatch = false.obs;

  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var isValidatingSourceRack = false.obs;
  var isValidatingTargetRack = false.obs;

  var rackError = RxnString();
  var batchError = RxnString();

  var currentItemCode = '';
  var currentVariantOf = '';
  var currentItemName = '';
  var currentUom = '';
  var currentItemNameKey = RxnString();
  var selectedSerial = RxnString();
  var bsItemOwner = RxnString();
  var bsItemCreation = RxnString();
  var bsItemModified = RxnString();
  var bsItemModifiedBy = RxnString();

  var derivedSourceWarehouse = RxnString();
  var derivedTargetWarehouse = RxnString();

  String _initialQty = '';
  String _initialBatch = '';
  String _initialSourceRack = '';
  String _initialTargetRack = '';

  String currentScannedEan = '';
  var recentlyAddedItemName = ''.obs;

  var itemFormKey = GlobalKey<FormState>();
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  Timer? _autoSubmitTimer;
  Worker? _scanWorker;

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

    ever(selectedFromWarehouse, (_) => _markDirty());
    ever(selectedToWarehouse, (_) => _markDirty());
    ever(selectedStockEntryType, (_) => _markDirty());

    // Watch item warehouse changes to update stock balance
    ever(bsItemSourceWarehouse, (_) => _updateAvailableStock());

    customReferenceNoController.addListener(() {
      _markDirty();
      if (entrySource == StockEntrySource.manual &&
          selectedStockEntryType.value == 'Material Issue' &&
          customReferenceNoController.text.isNotEmpty) {
        final ref = customReferenceNoController.text;
        if (ref.startsWith('KX') || ref.startsWith('MX')) {
          _fetchPosUploadDetails(ref);
        }
      }
    });

    bsQtyController.addListener(validateSheet);
    bsBatchController.addListener(validateSheet);
    bsSourceRackController.addListener(validateSheet);
    bsTargetRackController.addListener(validateSheet);
    ever(selectedSerial, (_) => validateSheet());
    ever(bsItemSourceWarehouse, (_) => validateSheet());
    ever(bsItemTargetWarehouse, (_) => validateSheet());

    _setupAutoSubmit();
  }

  void _setupAutoSubmit() {
    ever(isSheetValid, (bool valid) {
      _autoSubmitTimer?.cancel();
      if (valid && isItemSheetOpen.value && stockEntry.value?.docstatus == 0) {
        if (_storageService.getAutoSubmitEnabled()) {
          final int delay = _storageService.getAutoSubmitDelay();
          _autoSubmitTimer = Timer(Duration(seconds: delay), () async {
            if (isSheetValid.value && isItemSheetOpen.value) {
              isAddingItem.value = true;
              await Future.delayed(const Duration(milliseconds: 500));
              await addItem();
              isAddingItem.value = false;
              if (Get.isBottomSheetOpen == true) Get.back();
            }
          });
        }
      }
    });
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    _autoSubmitTimer?.cancel();
    barcodeController.dispose();
    bsQtyController.dispose();
    bsBatchController.dispose();
    bsSourceRackController.dispose();
    bsTargetRackController.dispose();
    customReferenceNoController.dispose();
    super.onClose();
  }

  Future<void> _initNewStockEntry() async {
    isLoading.value = true;
    final now = DateTime.now();
    final type = argStockEntryType ?? 'Material Transfer';
    final ref = argCustomReferenceNo ?? '';

    selectedStockEntryType.value = type;
    customReferenceNoController.text = ref;

    _determineSource(type, ref);

    if (entrySource == StockEntrySource.materialRequest) {
      await _initMaterialRequestFlow(ref);
    } else if (entrySource == StockEntrySource.posUpload) {
      await _initPosUploadFlow(ref);
    }

    stockEntry.value = StockEntry(
      name: 'New Stock Entry',
      purpose: type,
      totalAmount: 0.0,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      modified: '',
      creation: now.toString(),
      status: 'Draft',
      docstatus: 0,
      stockEntryType: type,
      postingTime: DateFormat('HH:mm:ss').format(now),
      customTotalQty: 0.0,
      customReferenceNo: ref,
      currency: 'AED',
      items: [],
    );

    isLoading.value = false;
    isDirty.value = true;
  }

  void _determineSource(String type, String ref) {
    if (Get.arguments?['items'] != null) {
      entrySource = StockEntrySource.materialRequest;
    } else if (type == 'Material Issue' && (ref.startsWith('KX') || ref.startsWith('MX'))) {
      entrySource = StockEntrySource.posUpload;
    } else if (ref.isNotEmpty) {
      // If items are not passed but a reference exists (and not POS), treat as Material Request fetch
      entrySource = StockEntrySource.materialRequest;
    } else {
      entrySource = StockEntrySource.manual;
    }
  }

  Future<void> _initMaterialRequestFlow(String ref) async {
    if (Get.arguments?['items'] is List && Get.arguments?['items'].isNotEmpty) {
      final rawItems = Get.arguments['items'] as List;
      mrReferenceItems = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      // Fetch MR Items if not passed in arguments
      try {
        final response = await _apiProvider.getDocument('Material Request', ref);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'];
          final items = data['items'] as List? ?? [];
          mrReferenceItems = items.map((i) => {
            'item_code': i['item_code'],
            'qty': i['qty'],
            'material_request': ref,
            'material_request_item': i['name']
          }).toList();
        } else {
          GlobalSnackbar.error(message: 'Failed to fetch Material Request details');
        }
      } catch (e) {
        GlobalSnackbar.error(message: 'Error fetching Material Request: $e');
      }
    }
  }

  Future<void> _initPosUploadFlow(String ref) async {
    await _fetchPosUploadDetails(ref);
  }

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;

        selectedStockEntryType.value = entry.stockEntryType ?? 'Material Transfer';
        selectedFromWarehouse.value = entry.fromWarehouse;
        selectedToWarehouse.value = entry.toWarehouse;
        customReferenceNoController.text = entry.customReferenceNo ?? '';

        if (entry.stockEntryType == 'Material Issue' && entry.customReferenceNo != null) {
          final ref = entry.customReferenceNo!;
          if (ref.startsWith('KX') || ref.startsWith('MX')) {
            entrySource = StockEntrySource.posUpload;
            await _fetchPosUploadDetails(ref);
          } else if (entry.items.any((i) => i.materialRequest != null)) {
            entrySource = StockEntrySource.materialRequest;
            // If items are linked to a Material Request, fetch its details to restore context (like max qty)
            final firstLinkedItem = entry.items.firstWhereOrNull((i) => i.materialRequest != null);
            if (firstLinkedItem != null && firstLinkedItem.materialRequest!.isNotEmpty) {
              await _initMaterialRequestFlow(firstLinkedItem.materialRequest!);
            }
          } else {
            entrySource = StockEntrySource.manual;
          }
        } else {
          entrySource = StockEntrySource.manual;
        }

        isDirty.value = false;
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch stock entry');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _fetchPosUploadDetails(String posId) async {
    try {
      final response = await _posProvider.getPosUpload(posId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final pos = PosUpload.fromJson(response.data['data']);
        posUpload.value = pos;
        final count = pos.items.length;
        posUploadSerialOptions.value = List.generate(count, (index) => (index + 1).toString());
      }
    } catch (e) {
      print('Error fetching POS Upload: $e');
    }
  }

  bool _validateScanContext(ScanResult result) {
    if (entrySource == StockEntrySource.materialRequest) {
      if (mrReferenceItems.isEmpty) return true;

      final scannedItemCode = result.itemData?.itemCode ?? '';
      bool found = false;

      for (var item in mrReferenceItems) {
        if (item['item_code'].toString().trim().toLowerCase() == scannedItemCode.trim().toLowerCase()) {
          found = true;
          break;
        }
      }

      if (!found) {
        GlobalSnackbar.error(message: 'Item $scannedItemCode not found in Material Request');
        return false;
      }
    }
    return true;
  }

  /// Checks if the entered quantity exceeds the remaining quantity in the Material Request.
  bool _checkMrConstraints() {
    // If we have no reference items loaded, we cannot validate, so we assume true (or handle as error depending on strictness).
    if (mrReferenceItems.isEmpty) {
      print('Warning: mrReferenceItems is empty, skipping constraint check.');
      return true;
    }

    // Step 1: Find the item in the Reference List (loaded from the MR document)
    final ref = mrReferenceItems.firstWhereOrNull((r) =>
    r['item_code'].toString().trim().toLowerCase() == currentItemCode.trim().toLowerCase());

    // Step 2: If item exists in MR, validate quantity
    if (ref != null) {
      final double allowed = (ref['qty'] as num).toDouble();
      bsValidationMaxQty.value = allowed; // Update UI hint

      final current = double.tryParse(bsQtyController.text) ?? 0;

      print('MR Constraint Check: Item $currentItemCode | Current: $current | Allowed: $allowed');

      // Failure: User is trying to return/transfer more than the MR allowed.
      if (current > allowed) {
        print('[Context Failure] MR Qty Exceeded');
        return false;
      }
    } else {
      // Failure Check (Optional): If strict, you might want to return false here if the item isn't in the MR at all.
      // Currently, it allows items not in the MR (returns true).
      print('Info: Item $currentItemCode not found in MR reference list.');
    }

    return true;
  }

  /// Validates POS Upload specific logic.
  bool _checkPosConstraints() {
    // Only applies to 'Material Issue' types (Selling logic)
    if (selectedStockEntryType.value != 'Material Issue') return true;

    // Step 1: Check if Serial is missing
    if (selectedSerial.value == null || selectedSerial.value!.isEmpty) {

      // Step 2: Bypass for 'MAT-STE-' references (Legacy/Manual overrides)
      if (!customReferenceNoController.text.startsWith('MAT-STE-')) {

        // Step 3: Failure Condition
        // If we have Serial Options available (fetched from API) but none is selected, FAIL.
        // This forces the user to select which Invoice/Serial this item belongs to.
        if (posUploadSerialOptions.isNotEmpty) {
          print('[Context Failure] POS Upload: Serial Options available (${posUploadSerialOptions.length}) but none selected.');
          return false;
        }
      }
    }
    return true;
  }

  StockEntryItem _enrichItemWithSourceData(StockEntryItem item) {
    String? matReq = item.materialRequest;
    String? matReqItem = item.materialRequestItem;
    String? serial = item.customInvoiceSerialNumber;

    if (entrySource == StockEntrySource.materialRequest && mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems.firstWhereOrNull((r) =>
      r['item_code'].toString().trim().toLowerCase() == item.itemCode.trim().toLowerCase());

      if (ref != null) {
        matReq = ref['material_request'];
        matReqItem = ref['material_request_item'];
        serial = "0";
      }
    } else if (entrySource == StockEntrySource.posUpload) {
      serial = selectedSerial.value;
    }

    return StockEntryItem(
      name: item.name,
      itemCode: item.itemCode,
      qty: item.qty,
      basicRate: item.basicRate,
      itemGroup: item.itemGroup,
      customVariantOf: item.customVariantOf,
      batchNo: item.batchNo,
      itemName: item.itemName,
      rack: item.rack,
      toRack: item.toRack,
      sWarehouse: item.sWarehouse,
      tWarehouse: item.tWarehouse,
      customInvoiceSerialNumber: serial,
      materialRequest: matReq,
      materialRequestItem: matReqItem,
      owner: item.owner,
      creation: item.creation,
      modified: item.modified,
      modifiedBy: item.modifiedBy,
    );
  }

  Future<void> addItem() async {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch = bsBatchController.text;
    final sourceRack = bsSourceRackController.text;
    final targetRack = bsTargetRackController.text;

    // Updated Logic: Prefer Item Level Warehouse, fallback to Derived (scan), fallback to Header
    final sWh = bsItemSourceWarehouse.value ?? derivedSourceWarehouse.value ?? selectedFromWarehouse.value;
    final tWh = bsItemTargetWarehouse.value ?? derivedTargetWarehouse.value ?? selectedToWarehouse.value;

    final String uniqueId = currentItemNameKey.value ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
    final currentItems = stockEntry.value?.items.toList() ?? [];
    final existingIndex = currentItems.indexWhere((i) => i.name == uniqueId);

    var newItem = StockEntryItem(
      name: uniqueId,
      itemCode: currentItemCode,
      qty: qty,
      basicRate: 0.0,
      itemGroup: null,
      customVariantOf: currentVariantOf,
      batchNo: batch,
      itemName: currentItemName,
      rack: sourceRack,
      toRack: targetRack,
      sWarehouse: sWh,
      tWarehouse: tWh,
      customInvoiceSerialNumber: selectedSerial.value,
    );

    if (existingIndex != -1) {
      final existing = currentItems[existingIndex];
      newItem = StockEntryItem(
        name: existing.name,
        itemCode: existing.itemCode,
        qty: qty,
        basicRate: existing.basicRate,
        itemGroup: existing.itemGroup,
        customVariantOf: existing.customVariantOf,
        batchNo: batch,
        itemName: existing.itemName,
        rack: sourceRack,
        toRack: targetRack,
        sWarehouse: sWh,
        tWarehouse: tWh,
        customInvoiceSerialNumber: selectedSerial.value,
        materialRequest: existing.materialRequest,
        materialRequestItem: existing.materialRequestItem,
        owner: existing.owner,
        creation: existing.creation,
        modified: existing.modified,
        modifiedBy: existing.modifiedBy,
      );
    }

    newItem = _enrichItemWithSourceData(newItem);

    if (existingIndex != -1) {
      currentItems[existingIndex] = newItem;
    } else {
      currentItems.add(newItem);
    }

    stockEntry.update((val) {
      val?.items.assignAll(currentItems);
    });

    barcodeController.clear();
    triggerHighlight(uniqueId);

    if (mode == 'new') {
      saveStockEntry();
    } else {
      isDirty.value = true;
      saveStockEntry().then((_) {
        GlobalSnackbar.success(message: existingIndex != -1 ? 'Item updated' : 'Item added');
      }).catchError((e) {
        print("Background save error: $e");
      });
    }
  }

  void validateSheet() {
    // Aggregates validation results from isolated helpers
    // rackError is managed internally by _isValidRacks to preserve async stock errors
    log(name: 'Sheet', 'Validating sheet...');
    log(name: 'Sheet Qty', _isValidQty().toString());
    log(name: 'Sheet Batch', _isValidBatch().toString());
    log(name: 'Sheet Context', _isValidContext().toString());
    log(name: 'Sheet Racks', _isValidRacks().toString());
    isSheetValid.value = _isValidQty() &&
        _isValidBatch() &&
        _isValidContext() &&
        _isValidRacks() &&
        _hasChanges();
  }

  bool _isValidQty() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return false;
    if (bsMaxQty.value > 0 && qty > bsMaxQty.value) return false;
    return true;
  }

  bool _isValidBatch() {
    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value) return false;
    // MR Requirement: Batch cannot be empty if context is Material Request
    if (entrySource == StockEntrySource.materialRequest && bsBatchController.text.isEmpty) return false;
    return true;
  }

  /// Validates the context-specific rules for Material Requests or POS Uploads.
  /// If this returns false, the [Sheet] validation fails.
  bool _isValidContext() {
    print('--- Checking Context Validity ---');
    print('Current Entry Source: $entrySource');

    // SCENARIO 1: Material Request
    // Rules: Must have a valid Serial (Invoice/Ref), Item Code, and Qty within limits.
    if (entrySource == StockEntrySource.materialRequest) {

      // Step 1: Check Serial Number
      // Why it fails: The UI dropdown for 'Invoice Serial No' is empty or unselected.
      // Note: For MRs, we often default this to '0'. If it's null/empty, we block it.
      if (selectedSerial.value == null || selectedSerial.value!.isEmpty) {
        print('[Context Failure] Material Request: selectedSerial is empty/null');
        return false;
      }

      // Step 2: Check Item Code
      // Why it fails: The scan result didn't populate currentItemCode correctly.
      if (currentItemCode.isEmpty) {
        print('[Context Failure] Material Request: currentItemCode is empty');
        return false;
      }

      // Step 3: Check Limits vs Material Request Reference
      // See _checkMrConstraints below for details.
      bool mrValid = _checkMrConstraints();
      if (!mrValid) {
        print('[Context Failure] Material Request: _checkMrConstraints returned false');
      }
      return mrValid;
    }

    // SCENARIO 2: POS Upload (Point of Sale)
    // Rules: Must link to a specific invoice serial if available.
    else if (entrySource == StockEntrySource.posUpload) {
      bool posValid = _checkPosConstraints();
      if (!posValid) {
        print('[Context Failure] POS Upload: _checkPosConstraints returned false');
      }
      return posValid;
    }

    // SCENARIO 3: Manual Entry
    // No special context rules apply.
    print('--- Context Valid (Manual) ---');
    return true;
  }

  bool _isValidRacks() {
    final type = selectedStockEntryType.value;
    final requiresSource = ['Material Issue', 'Material Transfer', 'Material Transfer for Manufacture'].contains(type);
    final requiresTarget = ['Material Receipt', 'Material Transfer', 'Material Transfer for Manufacture'].contains(type);

    // 1. Source Rack Validation
    if (requiresSource) {
      if (bsSourceRackController.text.isNotEmpty) {
        // If rack entered, it must be valid (async check sets isSourceRackValid)
        if (!isSourceRackValid.value) return false;
      } else {
        // Updated: Check Item Level Warehouse as valid fallback
        final effectiveSWh = bsItemSourceWarehouse.value ?? selectedFromWarehouse.value;
        if (effectiveSWh == null || effectiveSWh.isEmpty) {
          rackError.value = 'Source Warehouse or Rack required';
          return false;
        } else if (rackError.value == 'Source Warehouse or Rack required' || rackError.value == 'No Warehouse Selected') {
          // Clear specific errors if resolved by warehouse selection
          rackError.value = null;
        }
      }
    }

    // 2. Target Rack Validation
    if (requiresTarget) {
      if (bsTargetRackController.text.isEmpty || !isTargetRackValid.value) return false;
    }

    // 3. Cross-Check (Source != Target)
    if (requiresSource && requiresTarget) {
      final source = bsSourceRackController.text.trim();
      final target = bsTargetRackController.text.trim();
      if (source.isNotEmpty && source == target) {
        rackError.value = "Source and Target Racks cannot be the same";
        return false;
      }
    }

    // Clear cross-check error if valid
    if (rackError.value == "Source and Target Racks cannot be the same") {
      rackError.value = null;
    }

    return true;
  }

  bool _hasChanges() {
    // New items are always considered "changed" / valid for submission
    if (currentItemNameKey.value == null) return true;

    if (bsQtyController.text != _initialQty) return true;
    if (bsBatchController.text != _initialBatch) return true;
    if (bsSourceRackController.text != _initialSourceRack) return true;
    if (bsTargetRackController.text != _initialTargetRack) return true;

    return false;
  }

  void _openQtySheet({String? scannedBatch}) {
    itemFormKey = GlobalKey<FormState>();
    bsQtyController.clear();
    bsBatchController.clear();
    bsSourceRackController.clear();
    bsTargetRackController.clear();
    derivedSourceWarehouse.value = null;
    derivedTargetWarehouse.value = null;
    bsMaxQty.value = 0.0;
    bsValidationMaxQty.value = 0.0;

    // Reset Item Warehouses
    bsItemSourceWarehouse.value = null;
    bsItemTargetWarehouse.value = null;

    if (entrySource == StockEntrySource.materialRequest && mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems.firstWhereOrNull((r) => r['item_code'] == currentItemCode);
      if (ref != null) {
        bsValidationMaxQty.value = (ref['qty'] as num).toDouble();
      }
    }

    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;
    isSourceRackValid.value = false;
    isTargetRackValid.value = false;
    isSheetValid.value = false;
    rackError.value = null;
    batchError.value = null;
    selectedSerial.value = null;
    currentItemNameKey.value = null;
    bsItemOwner.value = null;
    bsItemCreation.value = null;
    bsItemModified.value = null;
    bsItemModifiedBy.value = null;
    _initialQty = '';
    _initialBatch = '';
    _initialSourceRack = '';
    _initialTargetRack = '';

    if (scannedBatch != null) {
      bsBatchController.text = scannedBatch;
      validateBatch(scannedBatch);
    }

    if (entrySource == StockEntrySource.materialRequest) {
      selectedSerial.value = '0';
    }

    isItemSheetOpen.value = true;
    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StockEntryItemFormSheet(
            controller: this,
            scrollController: scrollController,
            // formKey: itemFormKey,
          );
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  void editItem(StockEntryItem item) {
    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) return;

    itemFormKey = GlobalKey<FormState>();
    currentItemCode = item.itemCode;
    currentVariantOf = item.customVariantOf ?? '';
    currentItemName = item.itemName ?? '';
    currentItemNameKey.value = item.name;
    bsItemOwner.value = item.owner;
    bsItemCreation.value = item.creation;
    bsItemModified.value = item.modified;
    bsItemModifiedBy.value = item.modifiedBy;
    String qtyStr = item.qty.toString();
    if (item.qty % 1 == 0) qtyStr = item.qty.toInt().toString();
    bsQtyController.text = qtyStr;
    bsBatchController.text = item.batchNo ?? '';
    bsSourceRackController.text = item.rack ?? '';
    bsTargetRackController.text = item.toRack ?? '';
    selectedSerial.value = item.customInvoiceSerialNumber;

    // Populate Item Warehouses
    bsItemSourceWarehouse.value = item.sWarehouse;
    bsItemTargetWarehouse.value = item.tWarehouse;

    // Ensure serial is '0' if null when editing MR items (handling legacy/uninitialised items)
    if (entrySource == StockEntrySource.materialRequest && (selectedSerial.value == null || selectedSerial.value!.isEmpty)) {
      selectedSerial.value = '0';
    }

    _initialQty = qtyStr;
    _initialBatch = item.batchNo ?? '';
    _initialSourceRack = item.rack ?? '';
    _initialTargetRack = item.toRack ?? '';
    derivedSourceWarehouse.value = item.sWarehouse;
    derivedTargetWarehouse.value = item.tWarehouse;

    bsValidationMaxQty.value = 0.0;
    if (entrySource == StockEntrySource.materialRequest && mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems.firstWhereOrNull((r) => r['item_code'] == item.itemCode);
      if (ref != null) {
        bsValidationMaxQty.value = (ref['qty'] as num).toDouble();
      }
    }

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;
    if (item.rack != null && item.rack!.isNotEmpty) isSourceRackValid.value = true;
    if (item.toRack != null && item.toRack!.isNotEmpty) isTargetRackValid.value = true;
    _updateAvailableStock();
    validateSheet();

    isItemSheetOpen.value = true;
    rackError.value = null;
    batchError.value = null;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StockEntryItemFormSheet(
            controller: this,
            scrollController: scrollController,
            // formKey: itemFormKey,
          );
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      currentItemNameKey.value = null;
      rackError.value = null;
      batchError.value = null;
    });
  }

  Future<void> scanBarcode(String barcode) async {
    if (isClosed) return;

    // 2. USE MIXIN GUARD
    if (checkStaleAndBlock()) return;

    if (barcode.isEmpty) return;

    // Prevent double processing if scan is already in progress
    if (isScanning.value) return;

    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) {
      _handleSheetScan(barcode);
      return;
    }

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);
      if (result.isSuccess && result.itemData != null) {
        if (!_validateScanContext(result)) {
          isScanning.value = false;
          return;
        }

        if (result.rawCode.contains('-') && !result.rawCode.startsWith('SHIPMENT')) {
          currentScannedEan = result.rawCode.split('-')[0];
        } else {
          currentScannedEan = result.rawCode;
        }
        final itemData = result.itemData!;
        currentItemCode = itemData.itemCode;
        currentVariantOf = itemData.variantOf ?? '';
        currentItemName = itemData.itemName;
        currentUom = itemData.stockUom ?? 'Nos';
        _openQtySheet(scannedBatch: result.batchNo);
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

  // 3. IMPLEMENT THE MIXIN METHOD (CORRECTLY OVERRIDDEN)
  @override
  Future<void> reloadDocument() async {
    await fetchStockEntry(); // This pulls the latest data
    isStale.value = false;   // Reset the flag from the mixin

    // Optional: If you had a pending item in the buffer (recentlyAddedItemName),
    // you might want to clear it or try to re-apply it here,
    // though safer to just clear.
    isScanning.value = false;
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  void _handleSheetScan(String barcode) async {
    barcodeController.clear();
    final String? contextItem = currentScannedEan.isNotEmpty ? currentScannedEan : currentItemCode;
    final result = await _scanService.processScan(barcode, contextItemCode: contextItem);

    if (result.type == ScanType.rack && result.rackId != null) {
      _handleSheetRackScan(result.rackId!);
    }
    else if ((result.type == ScanType.batch || result.type == ScanType.item) && result.batchNo != null) {
      bsBatchController.text = result.batchNo!;
      validateBatch(result.batchNo!);
    }
    else {
      _tryApplyAsRackFallback(barcode);
    }
  }

  void _handleSheetRackScan(String code) {
    final type = selectedStockEntryType.value;

    if (type == 'Material Transfer' || type == 'Material Transfer for Manufacture') {
      if (bsSourceRackController.text.isEmpty) {
        bsSourceRackController.text = code;
        validateRack(code, true);
      }
      else {
        if (code == bsSourceRackController.text) {
          rackError.value = 'Source and Target Racks cannot be the same';
          return;
        }
        bsTargetRackController.text = code;
        validateRack(code, false);
      }
    } else if (type == 'Material Issue') {
      bsSourceRackController.text = code;
      validateRack(code, true);
    } else if (type == 'Material Receipt') {
      bsTargetRackController.text = code;
      validateRack(code, false);
    }
  }

  void _tryApplyAsRackFallback(String code) {
    final type = selectedStockEntryType.value;
    bool needed = false;

    if (type == 'Material Issue' && bsSourceRackController.text.isEmpty) needed = true;
    if (type == 'Material Receipt' && bsTargetRackController.text.isEmpty) needed = true;
    if ((type == 'Material Transfer' || type == 'Material Transfer for Manufacture') &&
        (bsSourceRackController.text.isEmpty || bsTargetRackController.text.isEmpty)) needed = true;

    if (needed) {
      _handleSheetRackScan(code);
    } else {
      GlobalSnackbar.error(message: 'Invalid Scan');
    }
  }

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  Future<void> fetchStockEntryTypes() async {
    isFetchingTypes.value = true;
    try {
      final response = await _provider.getStockEntryTypes();
      if (response.statusCode == 200 && response.data['data'] != null) {
        stockEntryTypes.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      if (stockEntryTypes.isEmpty) {
        stockEntryTypes.assignAll(['Material Issue', 'Material Receipt', 'Material Transfer', 'Material Transfer for Manufacture']);
      }
    } finally {
      isFetchingTypes.value = false;
    }
  }

  Future<void> _updateAvailableStock() async {
    final type = selectedStockEntryType.value;
    final isSourceOp = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

    // If not a source operation, we don't need to validate stock balance against a warehouse
    if (!isSourceOp) {
      bsMaxQty.value = 999999.0;
      return;
    }

    // 1. Determine the effective warehouse
    // Default to the 'From Warehouse' selected in the Details tab
    // Prioritise Item Level Warehouse -> Derived -> Header
    String? effectiveWarehouse = bsItemSourceWarehouse.value ?? derivedSourceWarehouse.value ?? selectedFromWarehouse.value;

    // If a specific warehouse is derived from the scanned rack, use it
    if (derivedSourceWarehouse.value != null && derivedSourceWarehouse.value!.isNotEmpty) {
      effectiveWarehouse = derivedSourceWarehouse.value;
    }

    // 2. Validate Warehouse Existence
    // If no warehouse is determined (neither globally selected nor derived), we cannot fetch stock.
    // This prevents the "Failed to fetch Stock Balance report" error.
    if (effectiveWarehouse == null || effectiveWarehouse.isEmpty) {
      bsMaxQty.value = 0.0;
      // Optional: You might want to set a warning string here if needed,
      // but for now we just silently prevent the crash and 0 out the qty.
      rackError.value = 'No Warehouse Selected';
      return;
    }

    String batch = bsBatchController.text.trim();
    String rack = bsSourceRackController.text.trim();

    try {
      final response = await _apiProvider.getStockBalance(
          itemCode: currentItemCode,
          warehouse: effectiveWarehouse,
          batchNo: batch.isNotEmpty ? batch : null
      );

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        double totalBalance = 0.0;
        for (var row in result) {
          if (row is! Map) continue;
          // Filter by rack if specified in the Stock Balance row results
          if (rack.isNotEmpty && row['rack'] != null && row['rack'] != rack) continue;
          totalBalance += (row['bal_qty'] ?? 0 as num?)?.toDouble() ?? 0.0;
        }
        bsMaxQty.value = totalBalance;

        // Validation: If rack was specified but result is 0/neg
        if (rack.isNotEmpty && totalBalance <= 0) {
          rackError.value = 'Insufficient stock in Rack: $rack (Warehouse: $effectiveWarehouse)';
          GlobalSnackbar.error(message: 'Insufficient stock in Rack: $rack (Warehouse: $effectiveWarehouse)');
          isSourceRackValid.value = false;
        }
      }
    } catch (e) {
      print('Failed to fetch stock balance: $e');
      GlobalSnackbar.error(message: e.toString().contains('Session Defaults')
          ? 'Please set Session Defaults in Dashboard'
          : 'Failed to fetch stock for $effectiveWarehouse');
    }
  }

  Future<void> validateBatch(String batch) async {
    batchError.value = null; // Reset Error
    if (batch.isEmpty) return;

    if (batch.contains('-')) {
      final parts = batch.split('-');
      if (parts.length >= 2 && parts[0] == parts[1]) {
        bsIsBatchValid.value = false;
        batchError.value = "Invalid Batch: Batch ID cannot match EAN";
        validateSheet();
        return;
      }
    }

    isValidatingBatch.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Batch', filters: {
        'item': currentItemCode,
        'name': batch
      }, fields: ['name', 'custom_packaging_qty']);
      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        final batchData = response.data['data'][0];
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
        final double pkgQty = (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
        if (pkgQty > 0) {
          bsQtyController.text = pkgQty % 1 == 0 ? pkgQty.toInt().toString() : pkgQty.toString();
        }
        await _updateAvailableStock();
      } else {
        bsIsBatchValid.value = false;
        GlobalSnackbar.error(message: 'Batch not found for this item');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to validate batch: $e');
      bsIsBatchValid.value = false;
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  Future<void> validateRack(String rack, bool isSource) async {
    if (rack.isEmpty) {
      if (isSource) {
        isSourceRackValid.value = false;
        derivedSourceWarehouse.value = null;
      } else {
        isTargetRackValid.value = false;
        derivedTargetWarehouse.value = null;
      }
      validateSheet();
      return;
    }

    // Reset derived warehouse before parsing
    if (isSource) derivedSourceWarehouse.value = null;
    else derivedTargetWarehouse.value = null;

    // Parse Warehouse from Rack Code (Format: ZONE-WH-RACK or similar)
    // Updates the specific s_warehouse / t_warehouse field values if derived
    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        // Example logic: reconstructing warehouse name from rack parts
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        if (isSource) {
          derivedSourceWarehouse.value = wh;
          bsItemSourceWarehouse.value = wh; // Set s_warehouse field
        } else {
          derivedTargetWarehouse.value = wh;
          bsItemTargetWarehouse.value = wh; // Set t_warehouse field
        }
      }
    }

    if (isSource) isValidatingSourceRack.value = true;
    else isValidatingTargetRack.value = true;

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        if (isSource) {
          isSourceRackValid.value = true;
          // Refetch stock availability now that we have a valid rack and potentially new warehouse
          await _updateAvailableStock();
        } else {
          isTargetRackValid.value = true;
        }
      } else {
        if (isSource) isSourceRackValid.value = false;
        else isTargetRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      if (isSource) isSourceRackValid.value = false;
      else isTargetRackValid.value = false;
    } finally {
      if (isSource) isValidatingSourceRack.value = false;
      else isValidatingTargetRack.value = false;
      validateSheet();
    }
  }

  void resetSourceRackValidation() {
    isSourceRackValid.value = false;
    validateSheet();
  }

  void resetTargetRackValidation() {
    isTargetRackValid.value = false;
    validateSheet();
  }

  void resetBatchValidation() {
    bsIsBatchValid.value = false;
    bsIsBatchReadOnly.value = false;
    batchError.value = null;
    validateSheet();
  }

  void deleteItem(String uniqueName) {
    final item = stockEntry.value?.items.firstWhereOrNull((i) => i.name == uniqueName);
    if (item == null) return;
    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Are you sure you want to remove ${item.itemCode} from this entry?',
      onConfirm: () {
        final currentItems = stockEntry.value?.items.toList() ?? [];
        currentItems.removeWhere((i) => i.name == uniqueName);
        stockEntry.update((val) {
          val?.items.assignAll(currentItems);
        });
        isDirty.value = true;
        GlobalSnackbar.success(message: 'Item removed');
      },
    );
  }

  void triggerHighlight(String uniqueId) {
    recentlyAddedItemName.value = uniqueId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final key = itemKeys[uniqueId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.5,
          );
        }
      });
    });
    Future.delayed(const Duration(seconds: 2), () {
      recentlyAddedItemName.value = '';
    });
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta);

    double limit = 999999.0;
    if (bsMaxQty.value > 0) limit = bsMaxQty.value;
    if (bsValidationMaxQty.value > 0 && bsValidationMaxQty.value < limit) limit = bsValidationMaxQty.value;

    if (newVal >= 0 && newVal <= limit) {
      bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
      validateSheet();
    }
  }

  void toggleInvoiceExpand(String key) {
    if (expandedInvoice.value == key) {
      expandedInvoice.value = '';
    } else {
      expandedInvoice.value = key;
    }
  }

  Map<String, List<StockEntryItem>> get groupedItems {
    if (stockEntry.value == null || stockEntry.value!.items.isEmpty) {
      return {};
    }
    return groupBy(stockEntry.value!.items, (StockEntryItem item) {
      return item.customInvoiceSerialNumber ?? '0';
    });
  }

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;

    // 3. USE MIXIN GUARD
    if (checkStaleAndBlock()) return;

    if (stockEntry.value != null && stockEntry.value!.items.isNotEmpty) {
      final firstItem = stockEntry.value!.items.first;
      if (selectedFromWarehouse.value == null && firstItem.sWarehouse != null) {
        selectedFromWarehouse.value = firstItem.sWarehouse;
      }
      if (selectedToWarehouse.value == null && firstItem.tWarehouse != null) {
        selectedToWarehouse.value = firstItem.tWarehouse;
      }
    }
    if (selectedStockEntryType.value == 'Material Transfer') {
      if (selectedFromWarehouse.value == null || selectedToWarehouse.value == null) {
        GlobalSnackbar.error(message: 'Source and Target Warehouses are required');
        return;
      }
    }
    isSaving.value = true;
    final Map<String, dynamic> data = {
      'stock_entry_type': selectedStockEntryType.value,
      'posting_date': stockEntry.value?.postingDate,
      'posting_time': stockEntry.value?.postingTime,
      'from_warehouse': selectedFromWarehouse.value,
      'to_warehouse': selectedToWarehouse.value,
      'custom_reference_no': customReferenceNoController.text,
      // 2. CRITICAL: Pass 'modified' timestamp for Optimistic Locking
      'modified': stockEntry.value?.modified,
    };
    final itemsJson = stockEntry.value?.items.map((i) {
      final json = i.toJson();
      if (json['name'] != null && json['name'].toString().startsWith('local_')) {
        json.remove('name');
      }
      if (json['basic_rate'] == 0.0) {
        json.remove('basic_rate');
      }

      // Safety Patch: If material request link is missing in the item but exists in context, try to resolve it now
      if (json['material_request'] == null && entrySource == StockEntrySource.materialRequest && mrReferenceItems.isNotEmpty) {
        final ref = mrReferenceItems.firstWhereOrNull((r) =>
        r['item_code'].toString().trim().toLowerCase() == i.itemCode.trim().toLowerCase());
        if (ref != null) {
          json['material_request'] = ref['material_request'];
          json['material_request_item'] = ref['material_request_item'];
        }
      }

      // Explicitly preserve if present
      if (i.materialRequest != null) {
        json['material_request'] = i.materialRequest;
      }
      if (i.materialRequestItem != null) {
        json['material_request_item'] = i.materialRequestItem;
      }

      json.removeWhere((key, value) => value == null);
      return json;
    }).toList() ?? [];
    data['items'] = itemsJson;
    try {
      if (mode == 'new') {
        final response = await _provider.createStockEntry(data);
        if (response.statusCode == 200) {
          final createdDoc = response.data['data'];
          name = createdDoc['name'];
          mode = 'edit';
          await fetchStockEntry();
          GlobalSnackbar.success(message: 'Stock Entry created: $name');
        } else {
          GlobalSnackbar.error(message: 'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updateStockEntry(name, data);
        if (response.statusCode == 200) {
          // 3. UPDATE LOCAL TIMESTAMP ON SUCCESS
          // Frappe returns the updated document. We must update our local 'modified'
          // timestamp to match the server, otherwise the NEXT save will fail.
          final updatedDoc = response.data['data'];
          if (updatedDoc != null) {
            stockEntry.update((val) {
              val?.items.assignAll((updatedDoc['items'] as List).map((i) => StockEntryItem.fromJson(i)).toList());
              // Update the modified timestamp to the new valid one
              // You might need to add a setter or copyWith to your Model,
              // or just re-instantiate:
              stockEntry.value = StockEntry.fromJson(updatedDoc);
            });
          }

          GlobalSnackbar.success(message: 'Stock Entry updated');
          await fetchStockEntry();
        } else {
          GlobalSnackbar.error(message: 'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      String errorMessage = 'Save failed';
      // 5. USE MIXIN HANDLER instead of manual parsing for TimestampMismatch
      if (handleVersionConflict(e)) {
        // If it was a conflict, the mixin showed the dialog and set isStale=true.
        // We just exit.
      } else {
        if (e.response != null && e.response!.data != null) {
          if (e.response!.data is Map && e.response!.data['exception'] != null) {
            errorMessage = e.response!.data['exception'].toString().split(':').last.trim();
          } else if (e.response!.data is Map && e.response!.data['_server_messages'] != null) {
            errorMessage = 'Validation Error: Check form details';
          }
        }
        GlobalSnackbar.error(message: errorMessage);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value) {
      isDirty.value = true;
    }
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }
}