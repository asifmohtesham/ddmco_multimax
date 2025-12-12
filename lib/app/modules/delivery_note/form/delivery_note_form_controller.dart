import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'delivery_note_form_screen.dart';
import 'widgets/delivery_note_item_form_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';

class DeliveryNoteFormController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();

  var itemFormKey = GlobalKey<FormState>();
  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];
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
  var bsMaxQty = 0.0.obs;
  var bsBatchError = RxnString();
  var bsIsBatchValid = false.obs;
  var bsIsBatchReadOnly = false.obs;

  // Rack Validation State
  var bsIsRackValid = false.obs;
  var isValidatingRack = false.obs;

  var bsInvoiceSerialNo = RxnString();
  var editingItemName = RxnString();
  var isFormDirty = false.obs;
  // Added Validation Observable
  var isSheetValid = false.obs;

  String _initialBatch = '';
  String _initialRack = '';
  String _initialQty = '';
  String? _initialSerial;

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

  final ScrollController highlightScrollController = ScrollController();
  final Map<String, GlobalKey> highlightItemKeys = {};

  @override
  void onInit() {
    super.onInit();

    // Add Listeners for Validation
    bsQtyController.addListener(validateSheet);
    bsBatchController.addListener(validateSheet);
    bsRackController.addListener(validateSheet);
    ever(bsInvoiceSerialNo, (_) => validateSheet());

    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDeliveryNote();
    }
  }

  @override
  void onClose() {
    barcodeController.dispose();
    bsBatchController.dispose();
    bsRackController.dispose();
    bsQtyController.dispose();
    bsRackFocusNode.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ... [Existing Methods: _markDirty, _createNewDeliveryNote, fetchDeliveryNote, fetchPosUpload] ...

  void _markDirty() {
    if (!isLoading.value && !isDirty.value && deliveryNote.value?.docstatus == 0) {
      isDirty.value = true;
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
    );
    if (posUploadNameArg != null && posUploadNameArg!.isNotEmpty) {
      await fetchPosUpload(posUploadNameArg!);
    }
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
        _originalJson = jsonEncode(note.toJson());
        isDirty.value = false;
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
    _markDirty();

    await saveDeliveryNote();

    if(editingItemName.value == null) {
      GlobalSnackbar.success(message: 'Item added to list. Remember to Save.');
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
      // ADDED: Trigger feedback on update
      _triggerItemFeedback(existingItem.itemCode, invoiceSerial ?? '0');
    }
  }

  void _addItemLocally(String itemCode, String itemName, double qty, String rack, String? batchNo, String? invoiceSerial) {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    final serial = invoiceSerial ?? '0';
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

  // ... [Existing Methods: confirmAndDeleteItem, _deleteItemLocally, saveDeliveryNote, _triggerItemFeedback, toggleExpand, etc.] ...

  Future<void> confirmAndDeleteItem(DeliveryNoteItem item) async {
    Get.dialog(
      AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Remove ${item.itemCode} from this note?'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Get.back();
              _deleteItemLocally(item);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteItemLocally(DeliveryNoteItem item) {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    currentItems.remove(item);
    deliveryNote.update((val) {
      val?.items.assignAll(currentItems);
    });
    _markDirty();
    GlobalSnackbar.success(message: 'Item removed');
  }

  Future<void> saveDeliveryNote() async {
    if (isSaving.value) return;
    isSaving.value = true;
    try {
      final String docName = deliveryNote.value?.name ?? '';
      final bool isNew = docName == 'New Delivery Note' || docName.isEmpty;
      final Map<String, dynamic> data = deliveryNote.value!.toJson();
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
        _originalJson = jsonEncode(savedNote.toJson());
        isDirty.value = false;
        GlobalSnackbar.success(message: 'Delivery Note Saved');
      } else {
        GlobalSnackbar.error(message: 'Failed to save: ${response.data['exception'] ?? 'Unknown error'}');
      }
    } on DioException catch (e) {
      GlobalSnackbar.error(message: 'Save failed: ${e.message}');
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  void _triggerItemFeedback(String itemCode, String serial) {
    recentlyAddedItemCode.value = itemCode;
    recentlyAddedSerial.value = serial;

    // If using grouping, expand the group
    if (serial != '0' && serial.isNotEmpty) {
      expandedInvoice.value = serial;
    }

    // Scroll Logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Small delay to ensure list rebuilds with the new item/key
      Future.delayed(const Duration(milliseconds: 100), () {
        // We need to find the unique ID of the item that matches this code and serial
        // For simplicity, we iterate visible items or rely on the UI having registered the key via the item.name

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
              alignment: 0.5, // Center the item
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

  // --- UPDATED: Validations ---

  void validateSheet() {
    bool valid = true;
    final qty = double.tryParse(bsQtyController.text) ?? 0;

    // Qty Check
    if (qty <= 0) valid = false;
    if (bsMaxQty.value > 0 && qty > bsMaxQty.value) valid = false;

    // Batch Check
    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value) valid = false;

    // Rack Check (if logic requires it, assuming just needs to be non-empty or valid if entered)
    // if (bsRackController.text.isNotEmpty && !bsIsRackValid.value) valid = false;

    // Invoice Serial Check (Critical Requirement)
    if (bsInvoiceSerialNo.value == null || bsInvoiceSerialNo.value!.isEmpty) {
      if (bsAvailableInvoiceSerialNos.isNotEmpty) {
        valid = false;
      }
    }

    // Change Detection
    bool dirty = false;
    if (bsBatchController.text != _initialBatch) dirty = true;
    if (bsRackController.text != _initialRack) dirty = true;
    if (bsQtyController.text != _initialQty) dirty = true;
    if (bsInvoiceSerialNo.value != _initialSerial) dirty = true;
    isFormDirty.value = dirty;

    if (editingItemName.value != null && !dirty) valid = false;

    isSheetValid.value = valid;
  }

  // --- Sheet Init ---

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

    if (editingItem != null) {
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
      bsIsBatchReadOnly.value = bsIsBatchValid.value;
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

      final availableSerials = bsAvailableInvoiceSerialNos;
      if (availableSerials.isNotEmpty) {
        // Auto-select first if available
        bsInvoiceSerialNo.value = availableSerials.first;
        _initialSerial = availableSerials.first;
      } else {
        bsInvoiceSerialNo.value = null;
        _initialSerial = null;
      }

      if (batchNo != null && maxQty > 0) {
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
      } else {
        bsIsBatchValid.value = false;
        bsIsBatchReadOnly.value = false;
      }
    }

    // Initial validation
    validateSheet();

    bsIsLoadingBatch.value = false;
    isValidatingRack.value = false;
    isItemSheetOpen.value = true;
  }

  // ... [Existing Methods: validateAndFetchBatch, validateRack, resetRackValidation, adjustSheetQty, editItem, addItemFromBarcode] ...

  void checkForChanges() {
    // Replaced by validateSheet logic, keeping for backward compat if called elsewhere
    validateSheet();
  }

  Future<void> validateAndFetchBatch(String batchNo) async {
    if (batchNo.isEmpty) return;
    bsIsLoadingBatch.value = true;
    bsBatchError.value = null;
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

      final balanceResponse = await _apiProvider.getBatchWiseBalance(currentItemCode, batchNo);
      double fetchedQty = 0.0;
      if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
        final result = balanceResponse.data['message']['result'];
        if (result is List && result.isNotEmpty) {
          final row = result.first;
          fetchedQty = (row['balance_qty'] as num?)?.toDouble() ?? 0.0;
        }
      }

      bsMaxQty.value = fetchedQty;
      bsIsLoadingBatch.value = false;

      if (fetchedQty > 0) {
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
        bsBatchError.value = null;
        bsRackFocusNode.requestFocus();
      } else {
        bsIsBatchValid.value = false;
        bsBatchError.value = 'Batch has no stock';
      }
    } catch (e) {
      bsIsLoadingBatch.value = false;
      bsBatchError.value = 'Invalid Batch';
      bsMaxQty.value = 0.0;
      bsIsBatchValid.value = false;
    } finally {
      validateSheet();
    }
  }

  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) return;
    isValidatingRack.value = true;
    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        bsIsRackValid.value = true;
        GlobalSnackbar.success(message: 'Rack validated');
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
    isAddingItem.value = true;
    double fetchedQty = 0.0;
    bsIsLoadingBatch.value = true;
    try {
      if (item.batchNo != null) {
        final balanceResponse = await _apiProvider.getBatchWiseBalance(item.itemCode, item.batchNo!);
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
      isAddingItem.value = false;
      editingItemName.value = null;
    });
  }

  Future<void> addItemFromBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    if (isItemSheetOpen.value) {
      barcodeController.clear();
      final result = await _scanService.processScan(barcode, contextItemCode: currentItemCode);

      if (result.type == ScanType.rack && result.rackId != null) {
        bsRackController.text = result.rackId!;
        validateRack(result.rackId!);
      } else if (result.batchNo != null) {
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
            final balanceResponse = await _apiProvider.getBatchWiseBalance(itemData.itemCode, result.batchNo!);
            if (balanceResponse.statusCode == 200 && balanceResponse.data['message']?['result'] != null) {
              final list = balanceResponse.data['message']['result'] as List;
              if(list.isNotEmpty) maxQty = (list[0]['balance_qty'] as num).toDouble();
            }
          } catch (_) { maxQty = 6.0; }
        }

        isScanning.value = false;
        isAddingItem.value = true;
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
        isAddingItem.value = false;

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