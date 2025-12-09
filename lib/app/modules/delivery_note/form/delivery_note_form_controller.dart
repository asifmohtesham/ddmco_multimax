import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'dart:developer';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

import 'delivery_note_form_screen.dart';

class DeliveryNoteFormController extends GetxController {
  // ... (Existing variables remain unchanged) ...
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];
  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];
  final String? posUploadNameArg = Get.arguments['posUploadName'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isAddingItem = false.obs;
  var isSaving = false.obs;
  var deliveryNote = Rx<DeliveryNote?>(null);
  var posUpload = Rx<PosUpload?>(null);

  final TextEditingController barcodeController = TextEditingController();
  var expandedItemCode = ''.obs;
  var expandedInvoice = ''.obs;

  var itemFilter = 'All'.obs;

  // New State for UX Feedback
  var recentlyAddedItemCode = ''.obs;
  var recentlyAddedSerial = ''.obs;
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // Bottom Sheet State
  final bsBatchController = TextEditingController();
  final bsRackController = TextEditingController();
  final bsQtyController = TextEditingController(text: '6');
  final bsRackFocusNode = FocusNode();

  var bsIsLoadingBatch = false.obs;
  var bsMaxQty = 0.0.obs;
  var bsBatchError = RxnString();
  var bsIsBatchValid = false.obs;
  var bsIsBatchReadOnly = false.obs;

  var bsInvoiceSerialNo = RxnString();
  var editingItemName = RxnString();
  var isFormDirty = false.obs;

  String _initialBatch = '';
  String _initialRack = '';
  String _initialQty = '';
  String? _initialSerial;

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

  @override
  void onInit() {
    super.onInit();
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

  // ... (Existing init methods: _createNewDeliveryNote, fetchDeliveryNote, fetchPosUpload) ...
  void _createNewDeliveryNote() async {
    isLoading.value = true;
    deliveryNote.value = DeliveryNote(
      name: 'New Delivery Note',
      customer: posUploadCustomer ?? '',
      grandTotal: 0.0,
      postingDate: DateTime.now().toString().split(' ')[0],
      modified: '',
      creation: DateTime.now().toString(),
      status: 'Not Saved',
      currency: 'USD',
      items: [],
      poNo: posUploadNameArg,
      totalQty: 0.0,
      docstatus: 0,
    );
    if (posUploadNameArg != null && posUploadNameArg!.isNotEmpty) {
      await fetchPosUpload(posUploadNameArg!);
    }
    isLoading.value = false;
  }

  Future<void> fetchDeliveryNote() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final note = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = note;
        if (note.poNo != null && note.poNo!.isNotEmpty) {
          await fetchPosUpload(note.poNo!);
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch delivery note');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load initial data: ${e.toString()}');
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
      GlobalSnackbar.error(message: 'Failed to fetch linked POS Upload: $e');
    }
  }

  // ... (Toggle methods) ...
  void toggleExpand(String itemCode) {
    expandedItemCode.value = expandedItemCode.value == itemCode ? '' : itemCode;
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }

  // ... (Bottom Sheet Logic: bsAvailableInvoiceSerialNos, initBottomSheet, checkForChanges, getRelativeTime) ...
  List<String> get bsAvailableInvoiceSerialNos {
    if (posUpload.value == null) return [];
    return posUpload.value!.items
        .map((item) => item.idx.toString())
        .toList();
  }

  void initBottomSheet(String itemCode, String itemName, String? batchNo, double maxQty, {DeliveryNoteItem? editingItem}) {
    // ... Implementation identical to original, just ensuring cleaner context ...
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

      bsItemOwner.value = editingItem.owner;
      bsItemCreation.value = editingItem.creation;
      bsItemModifiedBy.value = editingItem.modifiedBy;
      bsItemModified.value = editingItem.modified;
      bsItemIdx.value = editingItem.idx;
      bsItemCustomVariantOf.value = editingItem.customVariantOf;
      bsItemGroup.value = editingItem.itemGroup;
      bsItemImage.value = editingItem.image;
      bsItemPackedQty.value = editingItem.packedQty;
      bsItemCompanyTotalStock.value = editingItem.companyTotalStock;

      bsIsBatchValid.value = true;
      bsIsBatchReadOnly.value = true;
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

      final availableSerials = bsAvailableInvoiceSerialNos;
      if (availableSerials.isNotEmpty) {
        bsInvoiceSerialNo.value = availableSerials.first;
        _initialSerial = availableSerials.first;
      } else {
        bsInvoiceSerialNo.value = null;
        _initialSerial = null;
      }

      if (batchNo != null && maxQty > 0) {
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
        Future.delayed(const Duration(milliseconds: 100), () {
          bsRackFocusNode.requestFocus();
        });
      } else {
        bsIsBatchValid.value = false;
        bsIsBatchReadOnly.value = false;
      }
    }
    bsIsLoadingBatch.value = false;
  }

  void checkForChanges() {
    bool dirty = false;
    if (bsBatchController.text != _initialBatch) dirty = true;
    if (bsRackController.text != _initialRack) dirty = true;
    if (bsQtyController.text != _initialQty) dirty = true;
    if (bsInvoiceSerialNo.value != _initialSerial) dirty = true;
    isFormDirty.value = dirty;
  }

  String getRelativeTime(String? dateString) {
    // ... Same implementation ...
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      if (difference.inDays > 365) return '${(difference.inDays / 365).floor()}y ago';
      if (difference.inDays > 30) return '${(difference.inDays / 30).floor()}mo ago';
      if (difference.inDays > 0) return '${difference.inDays}d ago';
      if (difference.inHours > 0) return '${difference.inHours}h ago';
      if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
      return 'Just now';
    } catch (e) {
      return dateString.split(' ')[0];
    }
  }

  // ... (Methods using apiProvider need to be careful to not break) ...

  Future<void> validateAndFetchBatch(String batchNo) async {
    if (batchNo.isEmpty) return;

    bsIsLoadingBatch.value = true;
    bsBatchError.value = null;

    try {
      try {
        await _apiProvider.getDocument('Batch', batchNo);
      } catch (e) {
        final batchResponse = await _apiProvider.getDocumentList('Batch', filters: {'batch_id': batchNo, 'item': currentItemCode});
        if (batchResponse.data['data'] == null || (batchResponse.data['data'] as List).isEmpty) {
          throw Exception('Batch not found');
        }
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
    }
  }

  void adjustSheetQty(double amount) {
    double currentQty = double.tryParse(bsQtyController.text) ?? 0;
    double newQty = currentQty + amount;
    if (newQty < 0) newQty = 0;
    if (newQty > bsMaxQty.value && bsMaxQty.value > 0) newQty = bsMaxQty.value;
    bsQtyController.text = newQty.toStringAsFixed(0);
    checkForChanges();
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
      isAddingItem.value = false;
      editingItemName.value = null;
    });
  }

  Future<void> addItemFromBarcode(String barcode) async {
    final RegExp eanRegex = RegExp(r'^\d{8,13}$');
    final RegExp batchRegex = RegExp(r'^(\d{8,13})-([a-zA-Z0-9]{3,6})$');

    String itemCode = '';
    String? batchNo;

    if (eanRegex.hasMatch(barcode)) {
      itemCode = barcode;
      itemCode = itemCode.length == 8 ? itemCode.substring(0,7) : itemCode.substring(0,12);
    } else if (batchRegex.hasMatch(barcode)) {
      final match = batchRegex.firstMatch(barcode);
      itemCode = match!.group(1)!;
      itemCode = itemCode.length == 8 ? itemCode.substring(0,7) : itemCode.substring(0,12);
      batchNo = barcode;
    } else {
      GlobalSnackbar.error(message: 'Invalid barcode format. Expected EAN (8-13 digits) or EAN-BATCH (3-6 chars)');
      barcodeController.clear();
      return;
    }

    isScanning.value = true;

    try {
      final itemResponse = await _apiProvider.getDocument('Item', itemCode);
      if (itemResponse.statusCode != 200 || itemResponse.data['data'] == null) {
        throw Exception('Item not found');
      }
      final String itemName = itemResponse.data['data']['item_name'] ?? '';

      double maxQty = 0.0;

      if (batchNo != null) {
        try {
          await _apiProvider.getDocument('Batch', batchNo);
        } catch (e) {
          final batchResponse = await _apiProvider.getDocumentList('Batch', filters: {'batch_id': batchNo, 'item': itemCode});
          if (batchResponse.data['data'] == null || (batchResponse.data['data'] as List).isEmpty) {
            throw Exception('Batch not found');
          }
        }

        try {
          final balanceResponse = await _apiProvider.getBatchWiseBalance(itemCode, batchNo);
          if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
            final result = balanceResponse.data['message']['result'];
            if (result is List && result.isNotEmpty) {
              final row = result.first;
              maxQty = (row['balance_qty'] as num?)?.toDouble() ?? 0.0;
            }
          }
        } catch (e) {
          maxQty = 6.0;
        }
      }

      isScanning.value = false;
      isAddingItem.value = true;

      initBottomSheet(itemCode, itemName, batchNo, maxQty);

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

    } catch (e) {
      final errorMessage = 'Validation failed: ${e.toString().contains('404') ? 'Item or Batch not found' : e.toString()}';
      GlobalSnackbar.error(message: errorMessage);
    } finally {
      isScanning.value = false;
      isAddingItem.value = false;
      barcodeController.clear();
    }
  }

  Future<void> submitSheet() async {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    final rack = bsRackController.text;
    final batch = bsBatchController.text;
    final invoiceSerial = bsInvoiceSerialNo.value;

    if (editingItemName.value != null && editingItemName.value!.isNotEmpty) {
      await _updateExistingItem(editingItemName.value!, qty, rack, batch, invoiceSerial);
    } else {
      await _addItemToDeliveryNote(currentItemCode, qty, rack, batch, invoiceSerial);
    }
  }

  Future<void> _updateExistingItem(String itemNameID, double qty, String rack, String? batchNo, String? invoiceSerial) async {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    final index = currentItems.indexWhere((item) => item.name == itemNameID);

    if (index != -1) {
      final existingItem = currentItems[index];
      final updatedItem = existingItem.copyWith(
          qty: qty,
          rack: rack,
          batchNo: batchNo,
          customInvoiceSerialNumber: invoiceSerial
      );
      currentItems[index] = updatedItem;
      await _saveDocumentAndReflect(currentItems, updatedItem.itemCode, updatedItem.customInvoiceSerialNumber ?? '0');
    } else {
      GlobalSnackbar.error(message: 'Item to update not found');
    }
  }

  Future<void> _addItemToDeliveryNote(String itemCode, double qty, String rack, String? batchNo, String? invoiceSerial) async {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    final serial = invoiceSerial ?? '0';

    final existingItemIndex = currentItems.indexWhere((item) =>
    item.itemCode == itemCode &&
        item.batchNo == batchNo &&
        item.rack == rack &&
        item.customInvoiceSerialNumber == serial);

    if (existingItemIndex != -1) {
      final existingItem = currentItems[existingItemIndex];
      final updatedItem = existingItem.copyWith(qty: existingItem.qty + qty);
      currentItems[existingItemIndex] = updatedItem;
    } else {
      final newItem = DeliveryNoteItem(
        itemCode: itemCode,
        qty: qty,
        rate: 0.0,
        rack: rack,
        batchNo: batchNo,
        customInvoiceSerialNumber: serial,
        itemName: currentItemName,
      );
      currentItems.add(newItem);
    }
    await _saveDocumentAndReflect(currentItems, itemCode, serial);
  }

  Future<void> confirmAndDeleteItem(DeliveryNoteItem item) async {
    Get.dialog(
      AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete ${item.itemCode}?'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Get.back();
              _deleteItem(item);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(DeliveryNoteItem item) async {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    currentItems.remove(item);
    await _saveDocumentAndReflect(currentItems, item.itemCode, item.customInvoiceSerialNumber ?? '0');
  }

  Future<void> _saveDocumentAndReflect(List<DeliveryNoteItem> updatedItems, String itemCode, String serial) async {
    isSaving.value = true;
    try {
      final String docName = deliveryNote.value?.name ?? '';
      final bool isNew = docName == 'New Delivery Note' || docName.isEmpty;

      final Map<String, dynamic> data = {
        'items': updatedItems.map((e) => e.toJson()).toList(),
      };

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
        deliveryNote.value = DeliveryNote.fromJson(response.data['data']);
        if (Get.isBottomSheetOpen == true) Get.back();
        GlobalSnackbar.success(message: 'Document saved');
        _triggerItemFeedback(itemCode, serial);
      } else {
        throw Exception('Failed to save document. Status: ${response.statusCode}');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to save: $e');
    } finally {
      isSaving.value = false;
    }
  }

  void _triggerItemFeedback(String itemCode, String serial) {
    recentlyAddedItemCode.value = itemCode;
    recentlyAddedSerial.value = serial;
    expandedInvoice.value = serial;

    Future.delayed(const Duration(milliseconds: 300), () {
      final contextKey = itemKeys[serial];
      if (contextKey?.currentContext != null) {
        Scrollable.ensureVisible(
          contextKey!.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      recentlyAddedItemCode.value = '';
      recentlyAddedSerial.value = '';
    });
  }

  // ... (groupedItems, counts, setFilter) ...
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
}