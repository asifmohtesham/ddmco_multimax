import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'dart:async';

class StockEntryFormController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();
  final StorageService _storageService = Get.find<StorageService>();
  final ScanService _scanService = Get.find<ScanService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  final String? argStockEntryType = Get.arguments['stockEntryType'];
  final String? argCustomReferenceNo = Get.arguments['customReferenceNo'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var isAddingItem = false.obs;
  var stockEntry = Rx<StockEntry?>(null);

  var posUpload = Rx<PosUpload?>(null);
  var expandedInvoice = ''.obs;

  var selectedFromWarehouse = RxnString();
  var selectedToWarehouse = RxnString();
  final customReferenceNoController = TextEditingController();

  var stockEntryTypes = <String>[].obs;
  var isFetchingTypes = false.obs;
  var selectedStockEntryType = 'Material Transfer'.obs;

  final TextEditingController barcodeController = TextEditingController();

  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var posUploadSerialOptions = <String>[].obs;

  var isFetchingPosUploads = false.obs;
  var posUploadsForSelection = <PosUpload>[].obs;

  var itemFormKey = GlobalKey<FormState>();

  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsSourceRackController = TextEditingController();
  final bsTargetRackController = TextEditingController();

  var bsItemOwner = RxnString();
  var bsItemCreation = RxnString();
  var bsItemModified = RxnString();
  var bsItemModifiedBy = RxnString();

  var derivedSourceWarehouse = RxnString();
  var derivedTargetWarehouse = RxnString();
  var isItemSheetOpen = false.obs;
  var bsMaxQty = 0.0.obs;
  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs;
  var isValidatingBatch = false.obs;
  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var isValidatingSourceRack = false.obs;
  var isValidatingTargetRack = false.obs;
  var rackError = RxnString();
  var isSheetValid = false.obs;
  var currentItemCode = '';
  var currentVariantOf = '';
  var currentItemName = '';
  var currentUom = '';
  var currentItemNameKey = RxnString();
  var selectedSerial = RxnString();

  // Focus Nodes
  final batchFocusNode = FocusNode();
  final sourceRackFocusNode = FocusNode();
  final targetRackFocusNode = FocusNode();

  String _initialQty = '';
  String _initialBatch = '';
  String _initialSourceRack = '';
  String _initialTargetRack = '';

  String currentScannedEan = '';
  var recentlyAddedItemName = ''.obs;

  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  Timer? _autoSubmitTimer;
  Worker? _scanWorker; // Track the listener

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    fetchStockEntryTypes();

    // Assign worker to variable for manual disposal
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) {
        scanBarcode(code);
      }
    });

    ever(selectedFromWarehouse, (_) => _markDirty());
    ever(selectedToWarehouse, (_) => _markDirty());
    ever(selectedStockEntryType, (_) => _markDirty());
    customReferenceNoController.addListener(() {
      _onReferenceNoChanged();
      _markDirty();
    });

    bsQtyController.addListener(validateSheet);
    bsBatchController.addListener(validateSheet);
    bsSourceRackController.addListener(validateSheet);
    bsTargetRackController.addListener(validateSheet);

    ever(selectedSerial, (_) => validateSheet());

    // Auto-Add logic
    ever(isSheetValid, (bool valid) {
      _autoSubmitTimer?.cancel();

      if (valid && isItemSheetOpen.value && stockEntry.value?.docstatus == 0) {
        final bool autoSubmit = _storageService.getAutoSubmitEnabled();
        if (autoSubmit) {
          final int delay = _storageService.getAutoSubmitDelay();
          _autoSubmitTimer = Timer(Duration(seconds: delay), () async {
            if (isSheetValid.value && isItemSheetOpen.value) {
              isAddingItem.value = true;
              await Future.delayed(const Duration(milliseconds: 500));
              await addItem();
              isAddingItem.value = false;
              if (Get.isBottomSheetOpen == true) {
                Get.back();
              }
            }
          });
        }
      }
    });

    if (mode == 'new') {
      _initNewStockEntry();
    } else {
      fetchStockEntry();
    }
  }

  @override
  void onClose() {
    // Explicitly dispose worker to stop listening to global events
    _scanWorker?.dispose();
    _autoSubmitTimer?.cancel();

    barcodeController.dispose();
    bsQtyController.dispose();
    bsBatchController.dispose();
    bsSourceRackController.dispose();
    bsTargetRackController.dispose();

    batchFocusNode.dispose();
    sourceRackFocusNode.dispose();
    targetRackFocusNode.dispose();

    customReferenceNoController.dispose();
    super.onClose();
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
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

  void _onReferenceNoChanged() {
    final ref = customReferenceNoController.text;
    if (ref.isNotEmpty) {
      _fetchPosUploadDetails(ref);
    } else {
      posUploadSerialOptions.clear();
      posUpload.value = null;
    }
  }

  void _initNewStockEntry() {
    isLoading.value = true;
    final now = DateTime.now();
    final type = argStockEntryType ?? 'Material Transfer';
    final ref = argCustomReferenceNo ?? '';
    selectedStockEntryType.value = type;
    customReferenceNoController.text = ref;
    stockEntry.value = StockEntry(
      name: 'New Stock Entry',
      purpose: 'Material Transfer',
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
      currency: '',
      items: [],
    );
    if (type == 'Material Issue' && ref.isNotEmpty) {
      _fetchPosUploadDetails(ref);
    }
    isLoading.value = false;
    isDirty.value = true;
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
          _fetchPosUploadDetails(entry.customReferenceNo!);
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

  void _openQtySheet({String? scannedBatch}) {
    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) {
      if (scannedBatch != null) {
        bsBatchController.text = scannedBatch;
        validateBatch(scannedBatch);
      }
      return;
    }

    itemFormKey = GlobalKey<FormState>();
    bsQtyController.clear();
    bsBatchController.clear();
    bsSourceRackController.clear();
    bsTargetRackController.clear();
    derivedSourceWarehouse.value = null;
    derivedTargetWarehouse.value = null;
    bsMaxQty.value = 0.0;
    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;
    isSourceRackValid.value = false;
    isTargetRackValid.value = false;
    isSheetValid.value = false;
    rackError.value = null;
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

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StockEntryItemFormSheet(
              controller: this,
              scrollController: scrollController
          );
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      rackError.value = null;
    });
  }

  void editItem(StockEntryItem item) {
    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) return;

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
    _initialQty = qtyStr;
    _initialBatch = item.batchNo ?? '';
    _initialSourceRack = item.rack ?? '';
    _initialTargetRack = item.toRack ?? '';
    derivedSourceWarehouse.value = item.sWarehouse;
    derivedTargetWarehouse.value = item.tWarehouse;
    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;
    if (item.rack != null && item.rack!.isNotEmpty) isSourceRackValid.value = true;
    if (item.toRack != null && item.toRack!.isNotEmpty) isTargetRackValid.value = true;
    _updateAvailableStock();
    validateSheet();

    isItemSheetOpen.value = true;
    rackError.value = null;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StockEntryItemFormSheet(
              controller: this,
              scrollController: scrollController
          );
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      currentItemNameKey.value = null;
      rackError.value = null;
    });
  }

  Future<void> addItem() async {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch = bsBatchController.text;
    final sourceRack = bsSourceRackController.text;
    final targetRack = bsTargetRackController.text;

    final sWh = derivedSourceWarehouse.value ?? selectedFromWarehouse.value;
    final tWh = derivedTargetWarehouse.value ?? selectedToWarehouse.value;

    final String uniqueId = currentItemNameKey.value ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
    final currentItems = stockEntry.value?.items.toList() ?? [];

    final existingIndex = currentItems.indexWhere((i) => i.name == uniqueId);

    if (existingIndex != -1) {
      final existing = currentItems[existingIndex];
      currentItems[existingIndex] = StockEntryItem(
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
        owner: existing.owner,
        creation: existing.creation,
        modified: existing.modified,
        modifiedBy: existing.modifiedBy,
      );
    } else {
      final duplicateIndex = currentItems.indexWhere((i) =>
      i.itemCode == currentItemCode &&
          (i.batchNo ?? '') == batch &&
          (i.rack ?? '') == sourceRack &&
          (i.toRack ?? '') == targetRack &&
          (i.sWarehouse ?? '') == sWh &&
          (i.tWarehouse ?? '') == tWh &&
          (i.customInvoiceSerialNumber ?? '') == (selectedSerial.value ?? '')
      );

      if (duplicateIndex != -1) {
        final existing = currentItems[duplicateIndex];
        currentItems[duplicateIndex] = StockEntryItem(
          name: existing.name,
          itemCode: existing.itemCode,
          qty: existing.qty + qty,
          basicRate: existing.basicRate,
          itemGroup: existing.itemGroup,
          customVariantOf: existing.customVariantOf,
          batchNo: existing.batchNo,
          itemName: existing.itemName,
          rack: existing.rack,
          toRack: existing.toRack,
          sWarehouse: existing.sWarehouse,
          tWarehouse: existing.tWarehouse,
          customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
          owner: existing.owner,
          creation: existing.creation,
          modified: existing.modified,
          modifiedBy: existing.modifiedBy,
        );
        currentItemNameKey.value = existing.name;
      } else {
        final newItem = StockEntryItem(
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
        currentItems.add(newItem);
      }
    }

    stockEntry.update((val) {
      val?.items.assignAll(currentItems);
    });

    barcodeController.clear();
    triggerHighlight(currentItemNameKey.value ?? uniqueId);

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

  void _markDirty() {
    if (!isLoading.value && !isDirty.value) {
      isDirty.value = true;
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

  Future<void> _updateAvailableStock() async {
    final type = selectedStockEntryType.value;
    final isSourceOp = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
    if (!isSourceOp) {
      bsMaxQty.value = 999999.0;
      return;
    }

    String? warehouse = derivedSourceWarehouse.value ?? selectedFromWarehouse.value;
    String batch = bsBatchController.text.trim();
    String rack = bsSourceRackController.text.trim();

    try {
      final response = await _apiProvider.getStockBalance(
          itemCode: currentItemCode,
          warehouse: warehouse,
          batchNo: batch.isNotEmpty ? batch : null
      );

      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        double totalBalance = 0.0;
        for (var row in result) {
          if (row is! Map) continue;
          if (rack.isNotEmpty && row['rack'] != null && row['rack'] != rack) continue;
          totalBalance += (row['bal_qty'] ?? 0 as num?)?.toDouble() ?? 0.0;
        }
        bsMaxQty.value = totalBalance;
        if (rack.isNotEmpty && totalBalance <= 0) {
          GlobalSnackbar.error(message: 'Insufficient stock in Rack: $rack');
          isSourceRackValid.value = false;
        }
      }
    } catch (e) {
      print('Failed to fetch stock balance: $e');
      GlobalSnackbar.error(message: e.toString().contains('Session Defaults')
          ? 'Please set Session Defaults in Dashboard'
          : 'Failed to fetch stock');
    }
  }

  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;
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
        // GlobalSnackbar.success(message: 'Batch validated');
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
      if (isSource) isSourceRackValid.value = false;
      else isTargetRackValid.value = false;
      validateSheet();
      return;
    }
    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        if (isSource) derivedSourceWarehouse.value = wh;
        else derivedTargetWarehouse.value = wh;
      }
    }
    if (isSource) isValidatingSourceRack.value = true;
    else isValidatingTargetRack.value = true;
    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        if (isSource) {
          isSourceRackValid.value = true;
          await _updateAvailableStock();
        } else {
          isTargetRackValid.value = true;
        }
        // GlobalSnackbar.success(message: 'Rack Validated');
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

  void validateSheet() {
    rackError.value = null;
    final qty = double.tryParse(bsQtyController.text) ?? 0;

    // 1. Basic Quantity Validation
    if (qty <= 0) {
      isSheetValid.value = false;
      return;
    }
    if (bsMaxQty.value > 0 && qty > bsMaxQty.value) {
      isSheetValid.value = false;
      return;
    }

    // 2. Batch Validation
    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value) {
      isSheetValid.value = false;
      return;
    }

    final type = selectedStockEntryType.value;
    final requiresSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
    final requiresTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

    // 3. Source Rack Validation (STRICT: Must be present and valid)
    if (requiresSource) {
      if (bsSourceRackController.text.isEmpty) {
        isSheetValid.value = false;
        // Only show error if the user has interacted or other fields are valid to avoid noise
        // rackError.value = "Source Rack is required";
        return;
      }
      if (!isSourceRackValid.value) {
        isSheetValid.value = false;
        return;
      }
    }

    // 4. Target Rack Validation (STRICT: Must be present and valid)
    if (requiresTarget) {
      if (bsTargetRackController.text.isEmpty) {
        isSheetValid.value = false;
        return;
      }
      if (!isTargetRackValid.value) {
        isSheetValid.value = false;
        return;
      }
    }

    // 5. Cross Validation
    if (requiresSource && requiresTarget) {
      final source = bsSourceRackController.text.trim();
      final target = bsTargetRackController.text.trim();

      // Ensure we don't transfer to the same rack
      if (source.isNotEmpty && target.isNotEmpty && source == target) {
        isSheetValid.value = false;
        rackError.value = "Source and Target Racks cannot be the same";
        return;
      }
    }

    // 6. Serial Validation for Issue
    if (type == 'Material Issue') {
      if (selectedSerial.value == null || selectedSerial.value!.isEmpty) {
        isSheetValid.value = false;
        return;
      }
    }

    // 7. Change Detection (Edit Mode)
    if (currentItemNameKey.value != null) {
      bool isChanged = false;
      if (bsQtyController.text != _initialQty) isChanged = true;
      if (bsBatchController.text != _initialBatch) isChanged = true;
      if (bsSourceRackController.text != _initialSourceRack) isChanged = true;
      if (bsTargetRackController.text != _initialTargetRack) isChanged = true;
      if (!isChanged) {
        isSheetValid.value = false;
        return;
      }
    }

    isSheetValid.value = true;
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta);
    final double upperLimit = bsMaxQty.value > 0 ? bsMaxQty.value : 999999.0;
    if (newVal >= 0 && newVal <= upperLimit) {
      bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
      validateSheet();
    }
  }

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
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
    };
    final itemsJson = stockEntry.value?.items.map((i) {
      final json = i.toJson();
      if (json['name'] != null && json['name'].toString().startsWith('local_')) {
        json.remove('name');
      }
      if (json['basic_rate'] == 0.0) {
        json.remove('basic_rate');
      }
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
          GlobalSnackbar.success(message: 'Stock Entry updated');
          await fetchStockEntry();
        } else {
          GlobalSnackbar.error(message: 'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      String errorMessage = 'Save failed';
      if (e.response != null && e.response!.data != null) {
        if (e.response!.data is Map && e.response!.data['exception'] != null) {
          errorMessage = e.response!.data['exception'].toString().split(':').last.trim();
        } else if (e.response!.data is Map && e.response!.data['_server_messages'] != null) {
          errorMessage = 'Validation Error: Check form details';
        }
      }
      GlobalSnackbar.error(message: errorMessage);
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  void _handleSheetRackScan(String code) {
    final type = selectedStockEntryType.value;
    bool handled = false;

    if (type == 'Material Transfer' || type == 'Material Transfer for Manufacture') {
      if (bsSourceRackController.text.isEmpty) {
        bsSourceRackController.text = code;
        validateRack(code, true);
        handled = true;
      } else {
        // PREVENT CONCURRENT SAME VALUE
        if (bsSourceRackController.text == code) {
          GlobalSnackbar.error(message: "Source and Target Racks cannot be the same");
          return;
        }

        // Set Target
        bsTargetRackController.text = code;
        validateRack(code, false);
        handled = true;
      }
    } else if (type == 'Material Issue') {
      bsSourceRackController.text = code;
      validateRack(code, true);
      handled = true;
    } else if (type == 'Material Receipt') {
      bsTargetRackController.text = code;
      validateRack(code, false);
      handled = true;
    }
  }

  Future<void> scanBarcode(String barcode) async {
    // 1. Guard against disposed controller
    if (isClosed) return;
    if (barcode.isEmpty) return;

    // 2. Logic for when the Sheet is ALREADY Open
    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) {
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
      return;
    }

    // 3. Logic to OPEN the Sheet
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);
      if (result.isSuccess && result.itemData != null) {
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
}