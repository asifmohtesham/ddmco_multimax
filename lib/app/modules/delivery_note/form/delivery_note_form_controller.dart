import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'widgets/delivery_note_item_form_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class DeliveryNoteFormController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final StorageService _storageService = Get.find<StorageService>();

  var itemFormKey = GlobalKey<FormState>();
  final String name = Get.arguments['name'];

  // CHANGED: Removed 'final' so we can update mode to 'edit' after saving a new doc
  String mode = Get.arguments['mode'];

  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];
  final String? posUploadNameArg = Get.arguments['posUploadName'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isAddingItem = false.obs;
  var isSaving = false.obs;

  var isDirty = false.obs;
  String _originalJson = '';

  var deliveryNote = Rx<DeliveryNote?>(null);
  var posUpload = Rx<PosUpload?>(null);

  final TextEditingController barcodeController = TextEditingController();
  var expandedItemCode = ''.obs;
  var expandedInvoice = ''.obs;

  var itemFilter = 'All'.obs;

  var recentlyAddedItemCode = ''.obs;
  var recentlyAddedSerial = ''.obs;
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // Bottom Sheet State
  final bsBatchController = TextEditingController();
  final bsRackController = TextEditingController();
  final bsQtyController = TextEditingController(text: '6');
  final bsRackFocusNode = FocusNode();

  var isItemSheetOpen = false.obs;
  var bsIsLoadingBatch = false.obs;
  var isValidatingBatch = false.obs;
  var bsMaxQty = 0.0.obs;
  var customerError = RxnString();
  var bsBatchError = RxnString();
  var bsIsBatchValid = false.obs;
  var batchInfoTooltip = RxnString();

  // Rack Validation State
  var bsIsRackValid = false.obs;
  var isValidatingRack = false.obs;
  var rackStockTooltip = RxnString();
  var rackStockMap = <String, double>{}.obs;
  var rackError = RxnString();

  var bsInvoiceSerialNo = RxnString();
  var editingItemName = RxnString();
  var isFormDirty = false.obs;
  var isSheetValid = false.obs;

  String _initialBatch = '';
  String _initialRack = '';
  String _initialQty = '';
  String? _initialSerial;

  // Warehouse State
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var setWarehouse = RxnString();

  // Temp Item Data
  var bsItemOwner = RxnString();
  var bsItemCreation = RxnString();
  var bsItemModifiedBy = RxnString();
  var bsItemModified = RxnString();
  var bsItemIdx = RxnInt();
  var bsItemCustomVariantOf = RxnString();
  var bsItemGroup = RxnString();
  var bsItemImage = RxnString();
  var bsItemPackedQty = RxnDouble();
  var bsItemCompanyTotalStock = RxnDouble();

  String currentItemCode = '';
  String currentItemName = '';
  String currentScannedEan = '';

  Timer? _autoSubmitTimer;

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();

    // Add Listeners for Validation
    bsQtyController.addListener(validateSheet);
    bsBatchController.addListener(validateSheet);
    bsRackController.addListener(validateSheet);
    ever(bsInvoiceSerialNo, (_) => validateSheet());
    ever(setWarehouse, (_) => _checkForChanges());

    _setupAutoSubmit();

    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDeliveryNote();
    }
  }

  @override
  void onClose() {
    _autoSubmitTimer?.cancel();
    barcodeController.dispose();
    bsBatchController.dispose();
    bsRackController.dispose();
    bsQtyController.dispose();
    bsRackFocusNode.dispose();
    scrollController.dispose();
    super.onClose();
  }

  void _setupAutoSubmit() {
    ever(isSheetValid, (bool valid) {
      _autoSubmitTimer?.cancel();
      // Check if valid, sheet is open, and document is editable (docstatus == 0)
      if (valid && isItemSheetOpen.value && deliveryNote.value?.docstatus == 0) {
        if (_storageService.getAutoSubmitEnabled()) {
          final int delay = _storageService.getAutoSubmitDelay();
          _autoSubmitTimer = Timer(Duration(seconds: delay), () async {
            if (isSheetValid.value && isItemSheetOpen.value) {
              // Trigger loading state only during auto-submit
              isAddingItem.value = true;
              await Future.delayed(const Duration(milliseconds: 500));
              await submitSheet();
              isAddingItem.value = false;
            }
          });
        }
      }
    });
  }

  // --- PopScope Logic ---
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false; // Reset dirty flag
        Get.back(); // Pop the screen (Navigation)
      },
    );
  }

  void _checkForChanges() {
    if (deliveryNote.value == null) return;

    // Explicitly mark new documents as dirty
    if (mode == 'new') {
      isDirty.value = true;
      return;
    }
    // Prevent dirty check if document is not editable (submitted/cancelled)
    if (deliveryNote.value?.docstatus != 0) {
      isDirty.value = false;
      return;
    }

    final tempNote = DeliveryNote(
      name: deliveryNote.value!.name,
      customer: deliveryNote.value!.customer,
      grandTotal: deliveryNote.value!.grandTotal,
      postingDate: deliveryNote.value!.postingDate,
      modified: deliveryNote.value!.modified,
      creation: deliveryNote.value!.creation,
      status: deliveryNote.value!.status,
      currency: deliveryNote.value!.currency,
      items: deliveryNote.value!.items,
      poNo: deliveryNote.value!.poNo,
      totalQty: deliveryNote.value!.totalQty,
      docstatus: deliveryNote.value!.docstatus,
      setWarehouse: setWarehouse.value,
    );

    final currentJson = jsonEncode(tempNote.toJson());
    isDirty.value = currentJson != _originalJson;
  }

  void _updateOriginalState(DeliveryNote note) {
    _originalJson = jsonEncode(note.toJson());
    isDirty.value = false;
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

  void _createNewDeliveryNote() async {
    isLoading.value = true;
    final now = DateTime.now();
    deliveryNote.value = DeliveryNote(
      name: 'New Delivery Note',
      customer: posUploadCustomer ?? '',
      grandTotal: 0.0,
      postingDate: now.toString().split(' ')[0],
      modified: '',
      creation: now.toString(),
      status: 'Draft',
      currency: 'AED',
      items: [],
      poNo: posUploadNameArg,
      totalQty: 0.0,
      docstatus: 0,
      setWarehouse: '',
    );
    if (posUploadNameArg != null && posUploadNameArg!.isNotEmpty) {
      await fetchPosUpload(posUploadNameArg!);
    }

    // CHANGED: Explicitly set dirty for new doc
    isDirty.value = true;
    _originalJson = '';
    isLoading.value = false;
  }

  Future<void> fetchDeliveryNote() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final note = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = note;
        setWarehouse.value = note.setWarehouse;
        _updateOriginalState(note);
        if (note.poNo != null && note.poNo!.isNotEmpty) {
          await fetchPosUpload(note.poNo!);
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch delivery note');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load data: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchPosUpload(String posName) async {
    try {
      final response = await _posUploadProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
      }
    } catch (e) {
      print('Failed to fetch linked POS Upload: $e');
    }
  }

  Future<void> submitSheet() async {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    final rack = bsRackController.text;
    final batch = bsBatchController.text;
    final invoiceSerial = bsInvoiceSerialNo.value;

    if (editingItemName.value != null && editingItemName.value!.isNotEmpty) {
      _updateItemLocally(editingItemName.value!, qty, rack, batch, invoiceSerial);
    } else {
      _addItemLocally(currentItemCode, currentItemName, qty, rack, batch, invoiceSerial);
    }

    Get.back();
    barcodeController.clear();
    _checkForChanges();

    await saveDeliveryNote();

    if(editingItemName.value == null) {
      GlobalSnackbar.success(message: 'Item added/updated.');
    }
  }

  void _updateItemLocally(String itemNameID, double qty, String rack, String? batchNo, String? invoiceSerial) {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    final index = currentItems.indexWhere((item) => item.name == itemNameID);
    if (index != -1) {
      final existingItem = currentItems[index];
      currentItems[index] = existingItem.copyWith(
          qty: qty,
          rack: rack,
          batchNo: batchNo,
          customInvoiceSerialNumber: invoiceSerial
      );
      deliveryNote.update((val) {
        val?.items.assignAll(currentItems);
      });
      _triggerItemFeedback(existingItem.itemCode, invoiceSerial ?? '0');
    }
  }

  void _addItemLocally(String itemCode, String itemName, double qty, String rack, String? batchNo, String? invoiceSerial) {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    final serial = invoiceSerial ?? '0';

    final existingIndex = currentItems.indexWhere((item) =>
    item.itemCode == itemCode &&
        (item.batchNo ?? '') == (batchNo ?? '') &&
        (item.rack ?? '') == rack &&
        (item.customInvoiceSerialNumber ?? '0') == serial
    );

    if (existingIndex != -1) {
      final existing = currentItems[existingIndex];
      final newQty = existing.qty + qty;
      currentItems[existingIndex] = existing.copyWith(qty: newQty);

      deliveryNote.update((val) {
        val?.items.assignAll(currentItems);
      });
      _triggerItemFeedback(itemCode, serial);

    } else {
      final tempId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      final newItem = DeliveryNoteItem(
        name: tempId,
        itemCode: itemCode,
        qty: qty,
        rate: 0.0,
        rack: rack,
        batchNo: batchNo,
        customInvoiceSerialNumber: serial,
        itemName: itemName,
        creation: DateTime.now().toString(),
      );
      currentItems.add(newItem);
      deliveryNote.update((val) {
        val?.items.assignAll(currentItems);
      });
      _triggerItemFeedback(itemCode, serial);
    }
  }

  Future<void> confirmAndDeleteItem(DeliveryNoteItem item) async {
    GlobalDialog.showConfirmation(
      title: 'Delete Item?',
      message: 'Are you sure you want to remove ${item.itemCode} from this note?',
      onConfirm: () => _deleteItemLocally(item),
    );
  }

  void _deleteItemLocally(DeliveryNoteItem item) {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    currentItems.remove(item);
    deliveryNote.update((val) {
      val?.items.assignAll(currentItems);
    });
    _checkForChanges();
    GlobalSnackbar.success(message: 'Item removed');
  }

  Future<void> saveDeliveryNote() async {
    if (isSaving.value) return;
    isSaving.value = true;
    customerError.value = null; // Clear previous error

    try {
      final String docName = deliveryNote.value?.name ?? '';
      final bool isNew = docName == 'New Delivery Note' || docName.isEmpty;
      final Map<String, dynamic> data = deliveryNote.value!.toJson();

      data['set_warehouse'] = setWarehouse.value;

      if (isNew) {
        data['customer'] = deliveryNote.value!.customer;
        data['posting_date'] = deliveryNote.value!.postingDate;
        if (deliveryNote.value!.poNo != null) data['po_no'] = deliveryNote.value!.poNo;
        data['docstatus'] = 0;
      }
      final response = isNew
          ? await _apiProvider.createDocument('Delivery Note', data)
          : await _apiProvider.updateDocument('Delivery Note', docName, data);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final savedNote = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = savedNote;
        _updateOriginalState(savedNote);

        // CHANGED: Update mode to 'edit' so _checkForChanges logic works correctly for subsequent edits
        if (isNew) {
          mode = 'edit';
        }

        GlobalSnackbar.success(message: 'Delivery Note Saved');
      } else {
        GlobalSnackbar.error(message: 'Failed to save: ${response.data['exception'] ?? 'Unknown error'}');
      }
    } on DioException catch (e) {
      // Check response data for specific Frappe/ERPNext error messages
      final errorMsg = e.response?.data.toString() ?? e.message ?? '';
      if (errorMsg.contains('Customer') && errorMsg.contains('not found')) {
        customerError.value = 'Customer not found in the system';
      }
      GlobalSnackbar.error(message: 'Save failed: ${e.message}');
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('Customer') && errorMsg.contains('not found')) {
        customerError.value = 'Customer not found in the system';
      }
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  void _triggerItemFeedback(String itemCode, String serial) {
    recentlyAddedItemCode.value = itemCode;
    recentlyAddedSerial.value = serial;

    if (serial != '0' && serial.isNotEmpty) {
      expandedInvoice.value = serial;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final item = deliveryNote.value?.items.firstWhereOrNull(
                (i) => i.itemCode == itemCode && (i.customInvoiceSerialNumber ?? '0') == serial
        );

        if (item != null && item.name != null) {
          final key = itemKeys[item.name];
          if (key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
          }
        }
      });
    });

    Future.delayed(const Duration(seconds: 2), () {
      recentlyAddedItemCode.value = '';
      recentlyAddedSerial.value = '';
    });
  }

  void toggleExpand(String itemCode) {
    expandedItemCode.value = expandedItemCode.value == itemCode ? '' : itemCode;
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }

  Map<String, List<DeliveryNoteItem>> get groupedItems {
    if (deliveryNote.value == null || deliveryNote.value!.items.isEmpty) {
      return {};
    }
    return groupBy(deliveryNote.value!.items, (DeliveryNoteItem item) {
      return item.customInvoiceSerialNumber ?? '0';
    });
  }

  int get allCount => posUpload.value?.items.length ?? 0;
  int get completedCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serialNumber = (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final dnItems = groups[serialNumber] ?? [];
      final cumulativeQty = dnItems.fold(0.0, (sum, item) => sum + item.qty);
      return cumulativeQty >= posItem.quantity;
    }).length;
  }
  int get pendingCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serialNumber = (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final dnItems = groups[serialNumber] ?? [];
      final cumulativeQty = dnItems.fold(0.0, (sum, item) => sum + item.qty);
      return cumulativeQty < posItem.quantity;
    }).length;
  }
  void setFilter(String filter) {
    itemFilter.value = filter;
  }
  List<String> get bsAvailableInvoiceSerialNos {
    if (posUpload.value == null) return [];
    return posUpload.value!.items
        .map((item) => item.idx.toString())
        .toList();
  }

  void validateSheet() {
    bool valid = true;
    rackError.value = null;

    final qty = double.tryParse(bsQtyController.text) ?? 0;

    if (qty <= 0) valid = false;
    if (bsMaxQty.value > 0 && qty > bsMaxQty.value) valid = false;

    // Strict Validation Check
    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value) valid = false;

    // RACK-WISE VALIDATION LOGIC
    final selectedRack = bsRackController.text;
    if (selectedRack.isNotEmpty && rackStockMap.isNotEmpty) {
      final availableInRack = rackStockMap[selectedRack] ?? 0.0;
      if (qty > availableInRack) {
        valid = false;
        rackError.value = 'Only $availableInRack available in $selectedRack';
      }
    }

    if (bsInvoiceSerialNo.value == null || bsInvoiceSerialNo.value!.isEmpty) {
      if (bsAvailableInvoiceSerialNos.isNotEmpty) {
        valid = false;
      }
    }

    bool dirty = false;
    if (bsBatchController.text != _initialBatch) dirty = true;
    if (bsRackController.text != _initialRack) dirty = true;
    if (bsQtyController.text != _initialQty) dirty = true;
    if (bsInvoiceSerialNo.value != _initialSerial) dirty = true;
    isFormDirty.value = dirty;

    if (editingItemName.value != null && !dirty) valid = false;

    isSheetValid.value = valid;
  }

  void initBottomSheet(String itemCode, String itemName, String? batchNo, double maxQty, {DeliveryNoteItem? editingItem}) {
    itemFormKey = GlobalKey<FormState>();
    currentItemCode = itemCode;
    currentItemName = itemName;
    bsItemOwner.value = null;
    bsItemCreation.value = null;
    bsItemModifiedBy.value = null;
    bsItemModified.value = null;
    bsItemIdx.value = null;
    bsItemCustomVariantOf.value = null;
    bsItemGroup.value = null;
    bsItemImage.value = null;
    bsItemPackedQty.value = null;
    bsItemCompanyTotalStock.value = null;
    isFormDirty.value = false;
    rackStockTooltip.value = null;
    rackStockMap.clear();
    rackError.value = null;

    if (editingItem != null) {
      bsItemOwner.value = editingItem.owner;
      bsItemCreation.value = editingItem.creation;
      bsItemModified.value = editingItem.modified;
      bsItemModifiedBy.value = editingItem.modifiedBy;

      editingItemName.value = editingItem.name;
      bsBatchController.text = editingItem.batchNo ?? '';
      bsRackController.text = editingItem.rack ?? '';
      bsQtyController.text = editingItem.qty.toStringAsFixed(0);
      bsInvoiceSerialNo.value = editingItem.customInvoiceSerialNumber;

      _initialBatch = editingItem.batchNo ?? '';
      _initialRack = editingItem.rack ?? '';
      _initialQty = editingItem.qty.toStringAsFixed(0);
      _initialSerial = editingItem.customInvoiceSerialNumber;

      bsIsBatchValid.value = (editingItem.batchNo != null && editingItem.batchNo!.isNotEmpty);
      bsIsRackValid.value = (editingItem.rack != null && editingItem.rack!.isNotEmpty);

      bsMaxQty.value = maxQty;
      bsBatchError.value = null;
    } else {
      editingItemName.value = null;
      bsBatchController.text = batchNo ?? '';
      bsRackController.clear();
      bsQtyController.text = '6';

      _initialBatch = batchNo ?? '';
      _initialRack = '';
      _initialQty = '6';

      bsMaxQty.value = maxQty;
      bsBatchError.value = null;
      bsIsRackValid.value = false;

      bsInvoiceSerialNo.value = null;
      _initialSerial = null;

      if (batchNo != null && maxQty > 0) {
        bsIsBatchValid.value = true;
      } else {
        bsIsBatchValid.value = false;
      }
    }

    validateSheet();
    _fetchAllRackStocks();

    bsIsLoadingBatch.value = false;
    isValidatingRack.value = false;
    isValidatingBatch.value = false;
    isItemSheetOpen.value = true;
  }

  Future<void> _fetchAllRackStocks() async {
    final warehouse = setWarehouse.value;
    if (warehouse == null || warehouse.isEmpty) return;

    try {
      final response = await _apiProvider.getStockBalance(
        itemCode: currentItemCode,
        warehouse: warehouse,
        batchNo: bsBatchController.text.isNotEmpty ? bsBatchController.text : null,
        // No rack filter = get all racks
      );

      if (response.statusCode == 200 && response.data['message'] != null) {
        final result = response.data['message']['result'];
        log(name: 'Fetch Rack Stocks', result is List ? result.slice(0,result.length-1).toString() : '');
        if (result is List && result.isNotEmpty) {
          final Map<String, double> tempMap = {};
          final List<String> tooltipLines = [];

          // The last item is the total row, discard it.
          for (int i = 0; i < result.length - 1; i++) {
            final row = result[i];
            final String? r = row['rack'];
            final double qty = (row['bal_qty'] as num?)?.toDouble() ?? 0.0;

            if (r != null && r.isNotEmpty && qty > 0) {
              tempMap[r] = qty;
              tooltipLines.add('$r: $qty');
            }
          }

          rackStockMap.assignAll(tempMap);
          if (tooltipLines.isNotEmpty) {
            rackStockTooltip.value = tooltipLines.join('\n');
          } else {
            rackStockTooltip.value = "No stock in racks";
          }
        }
      }
    } catch (e) {
      print('Error fetching rack stocks: $e');
    }
  }

  Future<void> validateAndFetchBatch(String batchNo) async {
    if (batchNo.isEmpty) return;
    isValidatingBatch.value = true;
    bsBatchError.value = null;
    batchInfoTooltip.value = null;

    try {
      final batchResponse = await _apiProvider.getDocumentList('Batch',
          filters: {'name': batchNo, 'item': currentItemCode},
          fields: ['name', 'custom_packaging_qty']
      );

      if (batchResponse.data['data'] == null || (batchResponse.data['data'] as List).isEmpty) {
        throw Exception('Batch not found');
      }

      final batchData = batchResponse.data['data'][0];
      final double pkgQty = (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
      if (pkgQty > 0) {
        bsQtyController.text = pkgQty % 1 == 0 ? pkgQty.toInt().toString() : pkgQty.toString();
      }

      // Refresh Rack Stocks whenever Batch changes
      await _fetchAllRackStocks();

      // --- Determine Warehouse ---
      String? determinedWarehouse = setWarehouse.value;
      if (bsRackController.text.isNotEmpty) {
        try {
          final rackRes = await _apiProvider.getDocument('Rack', bsRackController.text);
          if (rackRes.statusCode == 200 && rackRes.data['data'] != null) {
            determinedWarehouse = rackRes.data['data']['warehouse'] ?? determinedWarehouse;
          }
        } catch (_) {}
      }

      // 1. Get Batch-Wise Balance History (General Stock)
      final balanceResponse = await _apiProvider.getBatchWiseBalance(
          currentItemCode,
          batchNo,
          warehouse: determinedWarehouse
      );

      double fetchedBatchQty = 0.0;
      if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
        final result = balanceResponse.data['message']['result'];
        if (result is List && result.isNotEmpty) {
          final row = result.first;
          fetchedBatchQty = (row['balance_qty'] as num?)?.toDouble() ?? 0.0;
        }
      }

      bsMaxQty.value = fetchedBatchQty;

      // Construct Batch Tooltip
      final sb = StringBuffer();
      sb.writeln('Batch Stock: $fetchedBatchQty');
      // Add Rack Info to this tooltip if available
      if (rackStockTooltip.value != null) {
        sb.writeln('\nRack Availability:');
        sb.write(rackStockTooltip.value);
      }
      batchInfoTooltip.value = sb.toString().trim();

      if (fetchedBatchQty > 0) {
        bsIsBatchValid.value = true;
        bsBatchError.value = null;
        // GlobalSnackbar.success(message: 'Batch Validated');
        bsRackFocusNode.requestFocus();
      } else {
        bsIsBatchValid.value = false;
        bsBatchError.value = 'Batch has no stock';
        GlobalSnackbar.error(message: 'Batch has 0 stock');
      }
    } catch (e) {
      bsBatchError.value = 'Invalid Batch';
      bsMaxQty.value = 0.0;
      bsIsBatchValid.value = false;
      GlobalSnackbar.error(message: 'Batch validation failed');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  void resetBatchValidation() {
    bsIsBatchValid.value = false;
    validateSheet();
  }

  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) return;
    isValidatingRack.value = true;
    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        bsIsRackValid.value = true;
        // GlobalSnackbar.success(message: 'Rack validated');

        // Re-run validation to check stock quantities against this new rack
        validateSheet();
      } else {
        bsIsRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      bsIsRackValid.value = false;
      GlobalSnackbar.error(message: 'Validation failed: $e');
    } finally {
      isValidatingRack.value = false;
      validateSheet();
    }
  }

  void resetRackValidation() {
    bsIsRackValid.value = false;
    validateSheet();
  }

  void adjustSheetQty(double amount) {
    double currentQty = double.tryParse(bsQtyController.text) ?? 0;
    double newQty = currentQty + amount;
    if (newQty < 0) newQty = 0;
    if (newQty > bsMaxQty.value && bsMaxQty.value > 0) newQty = bsMaxQty.value;
    bsQtyController.text = newQty.toStringAsFixed(0);
    validateSheet();
  }

  Future<void> editItem(DeliveryNoteItem item) async {
    // REMOVED: isAddingItem.value = true;
    double fetchedQty = 0.0;
    bsIsLoadingBatch.value = true;
    try {
      if (item.batchNo != null) {
        // Logic for edit mode: Use item.rack if available, else fallback to setWarehouse
        String? targetWh = setWarehouse.value;
        if (item.rack != null && item.rack!.isNotEmpty) {
          try {
            final rackRes = await _apiProvider.getDocument('Rack', item.rack!);
            if (rackRes.statusCode == 200 && rackRes.data['data'] != null) {
              targetWh = rackRes.data['data']['warehouse'];
            }
          } catch (_) {}
        }

        final balanceResponse = await _apiProvider.getBatchWiseBalance(
            item.itemCode,
            item.batchNo!,
            warehouse: targetWh
        );

        if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
          final result = balanceResponse.data['message']['result'];
          if (result is List && result.isNotEmpty) {
            final row = result.first;
            fetchedQty = (row['balance_qty'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (e) {
      fetchedQty = 999;
    }

    initBottomSheet(item.itemCode, item.itemName ?? '', item.batchNo, fetchedQty, editingItem: item);

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return DeliveryNoteItemBottomSheet(scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).then((_) {
      isItemSheetOpen.value = false;
      // REMOVED: isAddingItem.value = false;
      editingItemName.value = null;
    });
  }

  /// UX Validation Helper to prevent scanning if document cannot be saved
  bool _validateHeaderBeforeScan() {
    if (deliveryNote.value == null) return false;

    // 1. Check Mandatory Fields (e.g. Customer)
    if (deliveryNote.value!.customer.isEmpty) {
      GlobalSnackbar.error(message: 'Missing Customer: Please select a customer before scanning.');
      return false;
    }

    // 2. Check for unresolved errors (e.g. from previous failed save)
    if (customerError.value != null) {
      GlobalSnackbar.error(message: 'Invalid Customer: ${customerError.value}');
      return false;
    }

    // 3. Optional: PO No Check (if required by business logic)
    // if (deliveryNote.value!.poNo == null) ...

    return true;
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    // [UX] Rigid Validation: Prevent scanning if header is invalid
    // This blocks the user from adding items if the document is currently in an unsavable state.
    if (!_validateHeaderBeforeScan()) return;

    if (isItemSheetOpen.value) {
      barcodeController.clear();
      final String? contextItem = currentScannedEan.isNotEmpty ? currentScannedEan : currentItemCode;

      final result = await _scanService.processScan(barcode, contextItemCode: contextItem);

      if (result.type == ScanType.rack && result.rackId != null) {
        bsRackController.text = result.rackId!;
        validateRack(result.rackId!);
      } else if ((result.type == ScanType.batch || result.type == ScanType.item) && result.batchNo != null) {
        bsBatchController.text = result.batchNo!;
        validateAndFetchBatch(result.batchNo!);
      } else if (result.type == ScanType.error) {
        GlobalSnackbar.error(message: result.message ?? 'Invalid Scan');
      }
      return;
    }

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
        double maxQty = 0.0;

        if (result.batchNo != null) {
          try {
            final balanceResponse = await _apiProvider.getBatchWiseBalance(
                itemData.itemCode,
                result.batchNo!,
                warehouse: setWarehouse.value
            );

            if (balanceResponse.statusCode == 200 && balanceResponse.data['message']?['result'] != null) {
              final list = balanceResponse.data['message']['result'] as List;
              if(list.isNotEmpty) maxQty = (list[0]['balance_qty'] as num).toDouble();
            }
          } catch (_) { maxQty = 6.0; }
        }

        isScanning.value = false;
        // REMOVED: isAddingItem.value = true;
        barcodeController.clear();

        initBottomSheet(itemData.itemCode, itemData.itemName, result.batchNo, maxQty);

        await Get.bottomSheet(
          DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return DeliveryNoteItemBottomSheet(scrollController: scrollController);
            },
          ),
          isScrollControlled: true,
        );

        isItemSheetOpen.value = false;
        // REMOVED: isAddingItem.value = false;

      } else if (result.type == ScanType.multiple && result.candidates != null) {
        GlobalSnackbar.warning(message: 'Multiple items found. Please search manually.');
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan processing failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }
}