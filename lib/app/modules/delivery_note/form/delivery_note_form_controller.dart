
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'dart:developer';
import 'package:ddmco_multimax/app/data/models/delivery_note_model.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';
import 'package:ddmco_multimax/app/data/models/pos_upload_model.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

import 'delivery_note_form_screen.dart'; // Import to access AddItemBottomSheet

class DeliveryNoteFormController extends GetxController {
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
  var deliveryNote = Rx<DeliveryNote?>(null);
  var posUpload = Rx<PosUpload?>(null);

  final TextEditingController barcodeController = TextEditingController();
  var expandedItemCode = ''.obs;
  var expandedInvoice = ''.obs;

  var itemFilter = 'All'.obs;

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
  
  // New Field State
  var bsInvoiceSerialNo = RxnString();
  
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
    super.onClose();
  }

  void _createNewDeliveryNote() async {
    isLoading.value = true;
    deliveryNote.value = DeliveryNote(
      name: 'New Delivery Note',
      customer: posUploadCustomer ?? '',
      grandTotal: 0.0,
      postingDate: DateTime.now().toString().split(' ')[0],
      modified: '',
      status: 'Draft',
      currency: 'USD',
      items: [],
      poNo: posUploadNameArg,
    );
    log('[CONTROLLER] New DN created with poNo: ${deliveryNote.value?.poNo}');

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
        log('[CONTROLLER] Fetched DN. poNo from JSON: ${note.poNo}');
        
        if (note.poNo != null && note.poNo!.isNotEmpty) {
          await fetchPosUpload(note.poNo!);
        }
      } else {
        Get.snackbar('Error', 'Failed to fetch delivery note');
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load initial data: ${e.toString()}');
      log('Error loading initial data: $e');
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
      Get.snackbar('Error', 'Failed to fetch linked POS Upload: $e');
    }
  }

  void toggleExpand(String itemCode) {
    expandedItemCode.value = expandedItemCode.value == itemCode ? '' : itemCode;
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }

  // --- Bottom Sheet Logic ---

  List<String> get bsAvailableInvoiceSerialNos {
    if (posUpload.value == null) return [];
    return posUpload.value!.items
        // .where((item) => item.itemName == currentItemName) // Using itemName as a proxy for itemCode
        .map((item) => item.idx.toString())
        .toList();
  }

  void initBottomSheet(String itemCode, String itemName, String? batchNo, double maxQty) {
    currentItemCode = itemCode;
    currentItemName = itemName;
    
    bsBatchController.text = batchNo ?? '';
    bsRackController.clear();
    bsQtyController.text = '6';
    
    bsMaxQty.value = maxQty;
    bsBatchError.value = null;
    
    // Initialize Invoice Serial No
    final availableSerials = bsAvailableInvoiceSerialNos;
    if (availableSerials.isNotEmpty) {
      bsInvoiceSerialNo.value = availableSerials.first;
    } else {
      bsInvoiceSerialNo.value = null;
    }
    
    if (batchNo != null && maxQty > 0) {
      bsIsBatchValid.value = true;
      bsIsBatchReadOnly.value = true;
      // Focus rack slightly after build to ensure visibility
      Future.delayed(const Duration(milliseconds: 100), () {
        bsRackFocusNode.requestFocus();
      });
    } else {
      bsIsBatchValid.value = false;
      bsIsBatchReadOnly.value = false;
    }
    
    bsIsLoadingBatch.value = false;
  }

  Future<void> validateAndFetchBatch(String batchNo) async {
    if (batchNo.isEmpty) return;

    bsIsLoadingBatch.value = true;
    bsBatchError.value = null;

    try {
      // 1. Check if batch exists
      try {
         await _apiProvider.getDocument('Batch', batchNo);
      } catch (e) {
         // Fallback search
         final batchResponse = await _apiProvider.getDocumentList('Batch', filters: {'batch_id': batchNo, 'item': currentItemCode});
         if (batchResponse.data['data'] == null || (batchResponse.data['data'] as List).isEmpty) {
           throw Exception('Batch not found');
         }
      }

      // 2. Fetch Balance
      final balanceResponse = await _apiProvider.getBatchWiseBalance(currentItemCode, batchNo);
      double fetchedQty = 0.0;
      if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
         final result = balanceResponse.data['message']['result'];
         if (result is List && result.isNotEmpty) {
            final row = result.first;
            log(jsonEncode(row));
            fetchedQty = (row['balance_qty'] as num?)?.toDouble() ?? 0.0;
         }
      }

      bsMaxQty.value = fetchedQty;
      bsIsLoadingBatch.value = false;

      if (fetchedQty > 0) {
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true; // Lock the field
        bsBatchError.value = null;
        bsRackFocusNode.requestFocus();
      } else {
        bsIsBatchValid.value = false;
        bsBatchError.value = 'Batch has no stock';
      }

    } catch (e, stackTrace) {
      final errorMessage = 'Failed to validate batch: ${e.toString()}';
      log(errorMessage, error: e, stackTrace: stackTrace);
      
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
      Get.snackbar('Error', 'Invalid barcode format. Expected EAN (8-13 digits) or EAN-BATCH (3-6 chars)');
      barcodeController.clear();
      return;
    }

    isScanning.value = true;

    try {
      // 1. Validate Item and get details (Name)
      final itemResponse = await _apiProvider.getDocument('Item', itemCode);
      if (itemResponse.statusCode != 200 || itemResponse.data['data'] == null) {
         throw Exception('Item not found');
      }
      final String itemName = itemResponse.data['data']['item_name'] ?? '';

      double maxQty = 0.0;

      // 2. If Batch is present, Validate and Fetch Balance
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
        } catch (e, stackTrace) {
          log('Failed to fetch balance', error: e, stackTrace: stackTrace);
          maxQty = 6.0; // Fail safe
        }
      }

      isScanning.value = false;
      isAddingItem.value = true;
      
      // Initialize Sheet State
      initBottomSheet(itemCode, itemName, batchNo, maxQty);

      // 3. Show Bottom Sheet
      await Get.bottomSheet(
        const AddItemBottomSheet(),
        isScrollControlled: true,
      );

    } catch (e, stackTrace) {
      final errorMessage = 'Validation failed: ${e.toString().contains('404') ? 'Item or Batch not found' : e.toString()}';
      Get.snackbar('Error', errorMessage);
      log(errorMessage, error: e, stackTrace: stackTrace);
    } finally {
      isScanning.value = false;
      isAddingItem.value = false;
      barcodeController.clear();
    }
  }

  void submitSheet() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    final rack = bsRackController.text;
    final batch = bsBatchController.text;
    final invoiceSerial = bsInvoiceSerialNo.value; // Get the selected serial
    
    _addItemToDeliveryNote(currentItemCode, qty, rack, batch, invoiceSerial);
    Get.back();
  }

  void _addItemToDeliveryNote(String itemCode, double qty, String rack, String? batchNo, String? invoiceSerial) {
    final newItem = DeliveryNoteItem(
      itemCode: itemCode,
      qty: qty,
      rate: 0.0,
      rack: rack,
      batchNo: batchNo,
      customInvoiceSerialNumber: invoiceSerial ?? '0', // Use the selected serial
    );
    
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    currentItems.add(newItem);
    
    deliveryNote.value = deliveryNote.value?.copyWith(items: currentItems);
    Get.snackbar('Success', 'Item added');
  }

  Map<String, List<DeliveryNoteItem>> get groupedItems {
    if (deliveryNote.value == null || deliveryNote.value!.items.isEmpty) {
      return {};
    }
    return groupBy(deliveryNote.value!.items, (DeliveryNoteItem item) {
      return item.customInvoiceSerialNumber ?? '0'; 
    });
  }

  // --- Counts for Filtering ---

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
