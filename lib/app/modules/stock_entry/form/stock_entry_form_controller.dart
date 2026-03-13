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

enum StockEntrySource { manual, materialRequest, posUpload }

class StockEntryFormController extends GetxController
    with OptimisticLockingMixin {
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

  var entrySource = StockEntrySource.manual;

  // --- Context Data ---
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

  var bsItemSourceWarehouse = RxnString();
  var bsItemTargetWarehouse = RxnString();

  var bsMaxQty = 0.0.obs;
  var bsValidationMaxQty = 0.0.obs;
  var bsBatchBalance = 0.0.obs;
  var bsRackBalance = 0.0.obs;

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
              await addItem(); // addItem() closes the sheet
              isAddingItem.value = false;
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
        Get.arguments?['items'].isNotEmpty) {
      final rawItems = Get.arguments['items'] as List;
      mrReferenceItems =
          rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      try {
        final response =
            await _apiProvider.getDocument('Material Request', ref);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final data = response.data['data'];
          final items = data['items'] as List? ?? [];
          mrReferenceItems = items
              .map((i) => {
                    'item_code': i['item_code'],
                    'qty': i['qty'],
                    'material_request': ref,
                    'material_request_item': i['name']
                  })
              .toList();
        } else {
          GlobalSnackbar.error(
              message: 'Failed to fetch Material Request details');
        }
      } catch (e) {
        GlobalSnackbar.error(
            message: 'Error fetching Material Request: $e');
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

        selectedStockEntryType.value =
            entry.stockEntryType ?? 'Material Transfer';
        selectedFromWarehouse.value = entry.fromWarehouse;
        selectedToWarehouse.value = entry.toWarehouse;
        customReferenceNoController.text = entry.customReferenceNo ?? '';

        if (entry.stockEntryType == 'Material Issue' &&
            entry.customReferenceNo != null) {
          final ref = entry.customReferenceNo!;
          if (ref.startsWith('KX') || ref.startsWith('MX')) {
            entrySource = StockEntrySource.posUpload;
            await _fetchPosUploadDetails(ref);
          } else if (entry.items.any((i) => i.materialRequest != null)) {
            entrySource = StockEntrySource.materialRequest;
            final firstLinkedItem = entry.items
                .firstWhereOrNull((i) => i.materialRequest != null);
            if (firstLinkedItem != null &&
                firstLinkedItem.materialRequest!.isNotEmpty) {
              await _initMaterialRequestFlow(
                  firstLinkedItem.materialRequest!);
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
        posUploadSerialOptions.value =
            List.generate(count, (index) => (index + 1).toString());
      }
    } catch (e) {
      debugPrint('Error fetching POS Upload: $e');
    }
  }

  bool _validateScanContext(ScanResult result) {
    if (entrySource == StockEntrySource.materialRequest) {
      if (mrReferenceItems.isEmpty) return true;
      final scannedItemCode = result.itemData?.itemCode ?? '';
      bool found = false;
      for (var item in mrReferenceItems) {
        if (item['item_code']
                .toString()
                .trim()
                .toLowerCase() ==
            scannedItemCode.trim().toLowerCase()) {
          found = true;
          break;
        }
      }
      if (!found) {
        GlobalSnackbar.error(
            message:
                'Item $scannedItemCode not found in Material Request');
        return false;
      }
    }
    return true;
  }

  bool _checkMrConstraints() {
    if (mrReferenceItems.isEmpty) return true;
    final ref = mrReferenceItems.firstWhereOrNull((r) =>
        r['item_code'].toString().trim().toLowerCase() ==
        currentItemCode.trim().toLowerCase());
    if (ref != null) {
      final double allowed = (ref['qty'] as num).toDouble();
      bsValidationMaxQty.value = allowed;
      final current = double.tryParse(bsQtyController.text) ?? 0;
      if (current > allowed) return false;
    }
    return true;
  }

  bool _checkPosConstraints() {
    if (selectedStockEntryType.value != 'Material Issue') return true;
    if (selectedSerial.value == null || selectedSerial.value!.isEmpty) {
      if (!customReferenceNoController.text.startsWith('MAT-STE-')) {
        if (posUploadSerialOptions.isNotEmpty) return false;
      }
    }
    return true;
  }

  StockEntryItem _enrichItemWithSourceData(StockEntryItem item) {
    String? matReq = item.materialRequest;
    String? matReqItem = item.materialRequestItem;
    String? serial = item.customInvoiceSerialNumber;

    if (entrySource == StockEntrySource.materialRequest &&
        mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems.firstWhereOrNull((r) =>
          r['item_code'].toString().trim().toLowerCase() ==
          item.itemCode.trim().toLowerCase());
      if (ref != null) {
        matReq = ref['material_request'];
        matReqItem = ref['material_request_item'];
        serial = '0';
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

    final sWh = bsItemSourceWarehouse.value ??
        derivedSourceWarehouse.value ??
        selectedFromWarehouse.value;
    final tWh = bsItemTargetWarehouse.value ??
        derivedTargetWarehouse.value ??
        selectedToWarehouse.value;

    final String uniqueId = currentItemNameKey.value ??
        'local_${DateTime.now().millisecondsSinceEpoch}';
    final currentItems = stockEntry.value?.items.toList() ?? [];
    final existingIndex =
        currentItems.indexWhere((i) => i.name == uniqueId);

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

    // Single source of truth: controller closes the sheet.
    if (Get.isBottomSheetOpen == true) Get.back();

    if (mode == 'new') {
      saveStockEntry();
    } else {
      isDirty.value = true;
      saveStockEntry().then((_) {
        GlobalSnackbar.success(
            message: existingIndex != -1 ? 'Item updated' : 'Item added');
      }).catchError((e) {
        debugPrint('Background save error: $e');
      });
    }
  }

  void validateSheet() {
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
    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value)
      return false;
    if (entrySource == StockEntrySource.materialRequest &&
        bsBatchController.text.isEmpty) return false;
    return true;
  }

  bool _isValidContext() {
    if (entrySource == StockEntrySource.materialRequest) {
      if (selectedSerial.value == null || selectedSerial.value!.isEmpty)
        return false;
      if (currentItemCode.isEmpty) return false;
      return _checkMrConstraints();
    } else if (entrySource == StockEntrySource.posUpload) {
      return _checkPosConstraints();
    }
    return true;
  }

  bool _isValidRacks() {
    final type = selectedStockEntryType.value;
    final requiresSource = [
      'Material Issue',
      'Material Transfer',
      'Material Transfer for Manufacture'
    ].contains(type);
    final requiresTarget = [
      'Material Receipt',
      'Material Transfer',
      'Material Transfer for Manufacture'
    ].contains(type);

    if (requiresSource) {
      if (bsSourceRackController.text.isNotEmpty) {
        if (!isSourceRackValid.value) return false;
      } else {
        final effectiveSWh =
            bsItemSourceWarehouse.value ?? selectedFromWarehouse.value;
        if (effectiveSWh == null || effectiveSWh.isEmpty) {
          rackError.value = 'Source Warehouse or Rack required';
          return false;
        } else if (rackError.value ==
                'Source Warehouse or Rack required' ||
            rackError.value == 'No Warehouse Selected') {
          rackError.value = null;
        }
      }
    }

    if (requiresTarget) {
      if (bsTargetRackController.text.isEmpty ||
          !isTargetRackValid.value) return false;
    }

    if (requiresSource && requiresTarget) {
      final source = bsSourceRackController.text.trim();
      final target = bsTargetRackController.text.trim();
      if (source.isNotEmpty && source == target) {
        rackError.value = 'Source and Target Racks cannot be the same';
        return false;
      }
    }

    if (rackError.value == 'Source and Target Racks cannot be the same') {
      rackError.value = null;
    }

    return true;
  }

  bool _hasChanges() {
    if (currentItemNameKey.value == null) return true;
    if (bsQtyController.text != _initialQty) return true;
    if (bsBatchController.text != _initialBatch) return true;
    if (bsSourceRackController.text != _initialSourceRack) return true;
    if (bsTargetRackController.text != _initialTargetRack) return true;
    return false;
  }

  void _resetSheetState() {
    itemFormKey = GlobalKey<FormState>();
    bsQtyController.clear();
    bsBatchController.clear();
    bsSourceRackController.clear();
    bsTargetRackController.clear();
    derivedSourceWarehouse.value = null;
    derivedTargetWarehouse.value = null;
    bsMaxQty.value = 0.0;
    bsValidationMaxQty.value = 0.0;
    bsBatchBalance.value = 0.0;
    bsRackBalance.value = 0.0;
    bsItemSourceWarehouse.value = null;
    bsItemTargetWarehouse.value = null;
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
  }

  void _openSheet() {
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

  void _openQtySheet({String? scannedBatch}) {
    // Guard: never open a second sheet while one is already live
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    _resetSheetState();

    if (entrySource == StockEntrySource.materialRequest &&
        mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems
          .firstWhereOrNull((r) => r['item_code'] == currentItemCode);
      if (ref != null) {
        bsValidationMaxQty.value = (ref['qty'] as num).toDouble();
      }
    }

    if (scannedBatch != null) {
      bsBatchController.text = scannedBatch;
      validateBatch(scannedBatch);
    }

    if (entrySource == StockEntrySource.materialRequest) {
      selectedSerial.value = '0';
    }

    _openSheet();
  }

  void editItem(StockEntryItem item) {
    // Guard: never open a second sheet while one is already live
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

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

    bsItemSourceWarehouse.value = item.sWarehouse;
    bsItemTargetWarehouse.value = item.tWarehouse;

    if (entrySource == StockEntrySource.materialRequest &&
        (selectedSerial.value == null || selectedSerial.value!.isEmpty)) {
      selectedSerial.value = '0';
    }

    _initialQty = qtyStr;
    _initialBatch = item.batchNo ?? '';
    _initialSourceRack = item.rack ?? '';
    _initialTargetRack = item.toRack ?? '';
    derivedSourceWarehouse.value = item.sWarehouse;
    derivedTargetWarehouse.value = item.tWarehouse;

    bsValidationMaxQty.value = 0.0;
    bsBatchBalance.value = 0.0;
    bsRackBalance.value = 0.0;
    if (entrySource == StockEntrySource.materialRequest &&
        mrReferenceItems.isNotEmpty) {
      final ref = mrReferenceItems
          .firstWhereOrNull((r) => r['item_code'] == item.itemCode);
      if (ref != null) {
        bsValidationMaxQty.value = (ref['qty'] as num).toDouble();
      }
    }

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;
    if (item.rack != null && item.rack!.isNotEmpty)
      isSourceRackValid.value = true;
    if (item.toRack != null && item.toRack!.isNotEmpty)
      isTargetRackValid.value = true;
    rackError.value = null;
    batchError.value = null;

    _updateAvailableStock();
    validateSheet();

    _openSheet();
  }

  Future<void> scanBarcode(String barcode) async {
    if (isClosed) return;
    if (checkStaleAndBlock()) return;
    if (barcode.isEmpty) return;
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
        if (result.rawCode.contains('-') &&
            !result.rawCode.startsWith('SHIPMENT')) {
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

  @override
  Future<void> reloadDocument() async {
    await fetchStockEntry();
    isStale.value = false;
    isScanning.value = false;
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  void _handleSheetScan(String barcode) async {
    barcodeController.clear();
    final String? contextItem =
        currentScannedEan.isNotEmpty ? currentScannedEan : currentItemCode;
    final result =
        await _scanService.processScan(barcode, contextItemCode: contextItem);

    if (result.type == ScanType.rack && result.rackId != null) {
      _handleSheetRackScan(result.rackId!);
    } else if ((result.type == ScanType.batch ||
            result.type == ScanType.item) &&
        result.batchNo != null) {
      bsBatchController.text = result.batchNo!;
      validateBatch(result.batchNo!);
    } else {
      _tryApplyAsRackFallback(barcode);
    }
  }

  void _handleSheetRackScan(String code) {
    final type = selectedStockEntryType.value;
    if (type == 'Material Transfer' ||
        type == 'Material Transfer for Manufacture') {
      if (bsSourceRackController.text.isEmpty) {
        bsSourceRackController.text = code;
        validateRack(code, true);
      } else {
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
    if (type == 'Material Issue' && bsSourceRackController.text.isEmpty)
      needed = true;
    if (type == 'Material Receipt' && bsTargetRackController.text.isEmpty)
      needed = true;
    if ((type == 'Material Transfer' ||
            type == 'Material Transfer for Manufacture') &&
        (bsSourceRackController.text.isEmpty ||
            bsTargetRackController.text.isEmpty)) needed = true;
    if (needed) {
      _handleSheetRackScan(code);
    } else {
      GlobalSnackbar.error(message: 'Invalid Scan');
    }
  }

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
        stockEntryTypes.value =
            (response.data['data'] as List)
                .map((e) => e['name'] as String)
                .toList();
      }
    } catch (e) {
      if (stockEntryTypes.isEmpty) {
        stockEntryTypes.assignAll([
          'Material Issue',
          'Material Receipt',
          'Material Transfer',
          'Material Transfer for Manufacture'
        ]);
      }
    } finally {
      isFetchingTypes.value = false;
    }
  }

  Future<void> _updateAvailableStock() async {
    final type = selectedStockEntryType.value;
    final isSourceOp = type == 'Material Issue' ||
        type == 'Material Transfer' ||
        type == 'Material Transfer for Manufacture';

    if (!isSourceOp) {
      bsMaxQty.value = 999999.0;
      bsRackBalance.value = 0.0;
      return;
    }

    String? effectiveWarehouse = bsItemSourceWarehouse.value ??
        derivedSourceWarehouse.value ??
        selectedFromWarehouse.value;

    if (derivedSourceWarehouse.value != null &&
        derivedSourceWarehouse.value!.isNotEmpty) {
      effectiveWarehouse = derivedSourceWarehouse.value;
    }

    if (effectiveWarehouse == null || effectiveWarehouse.isEmpty) {
      bsMaxQty.value = 0.0;
      bsRackBalance.value = 0.0;
      rackError.value = 'No Warehouse Selected';
      return;
    }

    final batch = bsBatchController.text.trim();
    final rack = bsSourceRackController.text.trim();

    try {
      final response = await _apiProvider.getStockBalance(
        itemCode: currentItemCode,
        warehouse: effectiveWarehouse,
        batchNo: batch.isNotEmpty ? batch : null,
      );

      if (response.statusCode == 200 &&
          response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        double totalBalance = 0.0;
        for (var row in result) {
          if (row is! Map) continue;
          if (rack.isNotEmpty &&
              row['rack'] != null &&
              row['rack'] != rack) continue;
          totalBalance +=
              (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
        }
        bsMaxQty.value = totalBalance;
        bsRackBalance.value = rack.isNotEmpty ? totalBalance : 0.0;

        if (rack.isNotEmpty && totalBalance <= 0) {
          rackError.value =
              'Insufficient stock in Rack: $rack (Warehouse: $effectiveWarehouse)';
          GlobalSnackbar.error(
              message:
                  'Insufficient stock in Rack: $rack (Warehouse: $effectiveWarehouse)');
          isSourceRackValid.value = false;
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch stock balance: $e');
      GlobalSnackbar.error(
          message: e.toString().contains('Session Defaults')
              ? 'Please set Session Defaults in Dashboard'
              : 'Failed to fetch stock for $effectiveWarehouse');
    }
  }

  Future<void> _updateBatchBalance() async {
    final batch = bsBatchController.text.trim();
    if (batch.isEmpty || currentItemCode.isEmpty) {
      bsBatchBalance.value = 0.0;
      return;
    }
    final String? warehouse = bsItemSourceWarehouse.value ??
        derivedSourceWarehouse.value ??
        selectedFromWarehouse.value;
    try {
      final response = await _apiProvider.getBatchWiseBalance(
          currentItemCode, batch,
          warehouse: warehouse);
      if (response.statusCode == 200 &&
          response.data['message']?['result'] != null) {
        final message = response.data['message'];
        final List<dynamic> result = message['result'] ?? [];
        double total = 0.0;
        for (final row in result) {
          if (row is Map) {
            final dynamic val = row['balance_qty'] ??
                row['bal_qty'] ??
                row['qty_after_transaction'] ??
                row['qty'];
            total += (val as num?)?.toDouble() ?? 0.0;
          } else if (row is List) {
            final cols = message['columns'];
            if (cols is List) {
              int idx = -1;
              for (int i = 0; i < cols.length; i++) {
                final col = cols[i];
                if (col is Map) {
                  final label =
                      (col['label'] ?? '').toString().toLowerCase();
                  final fieldname =
                      (col['fieldname'] ?? '').toString().toLowerCase();
                  if (label.contains('balance qty') ||
                      (fieldname.contains('balance') &&
                          fieldname.contains('qty'))) {
                    idx = i;
                    break;
                  }
                }
              }
              if (idx >= 0 && idx < row.length) {
                total += (row[idx] as num?)?.toDouble() ?? 0.0;
              }
            }
          }
        }
        bsBatchBalance.value = total;
      } else {
        bsBatchBalance.value = 0.0;
      }
    } catch (e) {
      debugPrint('Failed to fetch batch-wise balance: $e');
      bsBatchBalance.value = 0.0;
    }
  }

  Future<void> validateBatch(String batch) async {
    batchError.value = null;
    if (batch.isEmpty) return;

    if (batch.contains('-')) {
      final parts = batch.split('-');
      if (parts.length >= 2 && parts[0] == parts[1]) {
        bsIsBatchValid.value = false;
        batchError.value = 'Invalid Batch: Batch ID cannot match EAN';
        validateSheet();
        return;
      }
    }

    isValidatingBatch.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Batch',
          filters: {'item': currentItemCode, 'name': batch},
          fields: ['name', 'custom_packaging_qty']);
      if (response.statusCode == 200 &&
          response.data['data'] != null &&
          (response.data['data'] as List).isNotEmpty) {
        final batchData = response.data['data'][0];
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
        final double pkgQty =
            (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
        if (pkgQty > 0) {
          bsQtyController.text = pkgQty % 1 == 0
              ? pkgQty.toInt().toString()
              : pkgQty.toString();
        }
        await _updateAvailableStock();
        await _updateBatchBalance();
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

    if (isSource) derivedSourceWarehouse.value = null;
    else derivedTargetWarehouse.value = null;

    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        if (isSource) {
          derivedSourceWarehouse.value = wh;
          bsItemSourceWarehouse.value = wh;
        } else {
          derivedTargetWarehouse.value = wh;
          bsItemTargetWarehouse.value = wh;
        }
      }
    }

    if (isSource)
      isValidatingSourceRack.value = true;
    else
      isValidatingTargetRack.value = true;

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        if (isSource) {
          isSourceRackValid.value = true;
          await _updateAvailableStock();
        } else {
          isTargetRackValid.value = true;
        }
      } else {
        if (isSource)
          isSourceRackValid.value = false;
        else
          isTargetRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      if (isSource)
        isSourceRackValid.value = false;
      else
        isTargetRackValid.value = false;
    } finally {
      if (isSource)
        isValidatingSourceRack.value = false;
      else
        isValidatingTargetRack.value = false;
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
    final item = stockEntry.value?.items
        .firstWhereOrNull((i) => i.name == uniqueName);
    if (item == null) return;
    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message:
          'Are you sure you want to remove ${item.itemCode} from this entry?',
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
    final newVal = current + delta;

    double limit = 999999.0;
    if (bsMaxQty.value > 0) limit = bsMaxQty.value;
    if (bsValidationMaxQty.value > 0 &&
        bsValidationMaxQty.value < limit) limit = bsValidationMaxQty.value;

    if (newVal >= 0 && newVal <= limit) {
      bsQtyController.text =
          newVal == 0 ? '' : newVal.toStringAsFixed(0);
      validateSheet();
    }
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value =
        expandedInvoice.value == key ? '' : key;
  }

  Map<String, List<StockEntryItem>> get groupedItems {
    if (stockEntry.value == null || stockEntry.value!.items.isEmpty) {
      return {};
    }
    return groupBy(stockEntry.value!.items,
        (StockEntryItem item) => item.customInvoiceSerialNumber ?? '0');
  }

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    if (stockEntry.value != null &&
        stockEntry.value!.items.isNotEmpty) {
      final firstItem = stockEntry.value!.items.first;
      if (selectedFromWarehouse.value == null &&
          firstItem.sWarehouse != null) {
        selectedFromWarehouse.value = firstItem.sWarehouse;
      }
      if (selectedToWarehouse.value == null &&
          firstItem.tWarehouse != null) {
        selectedToWarehouse.value = firstItem.tWarehouse;
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
      'stock_entry_type': selectedStockEntryType.value,
      'posting_date': stockEntry.value?.postingDate,
      'posting_time': stockEntry.value?.postingTime,
      'from_warehouse': selectedFromWarehouse.value,
      'to_warehouse': selectedToWarehouse.value,
      'custom_reference_no': customReferenceNoController.text,
      'modified': stockEntry.value?.modified,
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
              json['material_request'] = ref['material_request'];
              json['material_request_item'] =
                  ref['material_request_item'];
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
          GlobalSnackbar.success(
              message: 'Stock Entry created: $name');
        } else {
          GlobalSnackbar.error(
              message:
                  'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response =
            await _provider.updateStockEntry(name, data);
        if (response.statusCode == 200) {
          final updatedDoc = response.data['data'];
          if (updatedDoc != null) {
            stockEntry.value = StockEntry.fromJson(updatedDoc);
          }
          GlobalSnackbar.success(message: 'Stock Entry updated');
          await fetchStockEntry();
        } else {
          GlobalSnackbar.error(
              message:
                  'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) {
        // conflict handled by mixin
      } else {
        String errorMessage = 'Save failed';
        if (e.response?.data is Map) {
          if (e.response!.data['exception'] != null) {
            errorMessage = e.response!.data['exception']
                .toString()
                .split(':')
                .last
                .trim();
          } else if (e.response!.data['_server_messages'] != null) {
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
    if (!isLoading.value && !isDirty.value) isDirty.value = true;
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
    DateTime initialDate;
    try {
      initialDate = current.postingDate != null &&
              current.postingDate!.isNotEmpty
          ? DateFormat('yyyy-MM-dd').parse(current.postingDate!)
          : DateTime.now();
    } catch (_) {
      initialDate = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      stockEntry.update((val) {
        val?.postingDate = DateFormat('yyyy-MM-dd').format(picked);
      });
      _markDirty();
    }
  }

  Future<void> pickPostingTime(BuildContext context) async {
    final current = stockEntry.value;
    if (current == null) return;
    TimeOfDay initialTime;
    try {
      if (current.postingTime != null &&
          current.postingTime!.isNotEmpty) {
        final parsed =
            DateFormat('HH:mm:ss').parse(current.postingTime!);
        initialTime = TimeOfDay.fromDateTime(parsed);
      } else {
        initialTime = TimeOfDay.now();
      }
    } catch (_) {
      initialTime = TimeOfDay.now();
    }
    final picked =
        await showTimePicker(context: context, initialTime: initialTime);
    if (picked != null) {
      final dt = DateTime(0, 1, 1, picked.hour, picked.minute);
      stockEntry.update((val) {
        val?.postingTime = DateFormat('HH:mm:ss').format(dt);
      });
      _markDirty();
    }
  }
}
