import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/stock_entry_model.dart';
import 'package:ddmco_multimax/app/data/providers/stock_entry_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';
import 'package:ddmco_multimax/app/data/models/pos_upload_model.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_screen.dart'; 
import 'package:intl/intl.dart';

class StockEntryFormController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs; 
  var stockEntry = Rx<StockEntry?>(null);

  // Form Fields
  var selectedFromWarehouse = RxnString();
  var selectedToWarehouse = RxnString();
  final customReferenceNoController = TextEditingController();
  var selectedStockEntryType = 'Material Transfer'.obs; 

  final TextEditingController barcodeController = TextEditingController();
  
  // Data Sources
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var posUploadSerialOptions = <String>[].obs;

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsSourceRackController = TextEditingController(); // Added for rack
  final bsTargetRackController = TextEditingController(); // Added for rack
  
  final sourceRackFocusNode = FocusNode(); // Focus Node
  final targetRackFocusNode = FocusNode(); // Focus Node

  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs; 
  var isValidatingBatch = false.obs; // Loading state
  
  var currentItemCode = '';
  var currentItemName = '';
  var currentUom = '';
  
  // Selected Serial from Dropdown in Sheet
  var selectedSerial = RxnString();

  final List<String> stockEntryTypes = [
    'Material Issue',
    'Material Receipt',
    'Material Transfer',
    'Material Transfer for Manufacture'
  ];

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    customReferenceNoController.addListener(_onReferenceNoChanged);

    if (mode == 'new') {
      _initNewStockEntry();
    } else {
      fetchStockEntry();
    }
  }

  @override
  void onClose() {
    barcodeController.dispose();
    bsQtyController.dispose();
    bsBatchController.dispose();
    bsSourceRackController.dispose();
    bsTargetRackController.dispose();
    sourceRackFocusNode.dispose();
    targetRackFocusNode.dispose();
    customReferenceNoController.dispose();
    super.onClose();
  }

  void _onReferenceNoChanged() {
    final ref = customReferenceNoController.text;
    if (ref.isNotEmpty) {
      _fetchPosUploadDetails(ref);
    } else {
      posUploadSerialOptions.clear();
    }
  }

  Future<void> _fetchPosUploadDetails(String posId) async {
    try {
      final response = await _posProvider.getPosUpload(posId);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final pos = PosUpload.fromJson(response.data['data']);
        final count = pos.items.length;
        posUploadSerialOptions.value = List.generate(count, (index) => (index + 1).toString());
      }
    } catch (e) {
      print('Error fetching POS Upload: $e');
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

  void _initNewStockEntry() {
    isLoading.value = true;
    final now = DateTime.now();
    stockEntry.value = StockEntry(
      name: 'New Stock Entry',
      purpose: 'Material Transfer',
      totalAmount: 0.0,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      postingTime: DateFormat('HH:mm:ss').format(now),
      modified: '',
      creation: now.toString(),
      status: 'Draft',
      docstatus: 0,
      items: [],
      stockEntryType: 'Material Transfer',
      fromWarehouse: '',
      toWarehouse: '',
      customReferenceNo: '',
    );
    selectedStockEntryType.value = 'Material Transfer';
    isLoading.value = false;
  }

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = StockEntry.fromJson(response.data['data']);
        stockEntry.value = entry;
        
        selectedFromWarehouse.value = entry.fromWarehouse;
        selectedToWarehouse.value = entry.toWarehouse;
        customReferenceNoController.text = entry.customReferenceNo ?? '';
        selectedStockEntryType.value = entry.stockEntryType ?? 'Material Transfer';
        
        if (entry.customReferenceNo != null && entry.customReferenceNo!.isNotEmpty) {
          _fetchPosUploadDetails(entry.customReferenceNo!);
        }
      } else {
        Get.snackbar('Error', 'Failed to fetch stock entry');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> saveStockEntry() async {
    if (isSaving.value) return;
    isSaving.value = true;

    final Map<String, dynamic> data = {
      'stock_entry_type': selectedStockEntryType.value,
      'posting_date': stockEntry.value?.postingDate,
      'posting_time': stockEntry.value?.postingTime,
      'from_warehouse': selectedFromWarehouse.value,
      'to_warehouse': selectedToWarehouse.value,
      'custom_reference_no': customReferenceNoController.text,
    };
    
    final itemsJson = stockEntry.value?.items.map((i) => i.toJson()).toList() ?? [];
    data['items'] = itemsJson;

    try {
      if (mode == 'new') {
        final response = await _provider.createStockEntry(data);
        if (response.statusCode == 200) {
          Get.back();
          Get.snackbar('Success', 'Stock Entry created');
        } else {
          Get.snackbar('Error', 'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updateStockEntry(name, data);
        if (response.statusCode == 200) {
          Get.snackbar('Success', 'Stock Entry updated');
          fetchStockEntry();
        } else {
          Get.snackbar('Error', 'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } catch (e) {
      Get.snackbar('Error', 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    isScanning.value = true;
    
    String itemCode;
    String? batchNo;

    if (barcode.contains('-')) {
      final parts = barcode.split('-');
      final ean = parts.first;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = parts.sublist(1).join('-'); 
    } else {
      final ean = barcode;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = null;
    }
    
    try {
      final response = await _apiProvider.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        currentItemCode = itemData['item_code'];
        currentItemName = itemData['item_name'];
        currentUom = itemData['stock_uom'] ?? 'Nos';
        
        _openQtySheet(scannedBatch: batchNo);
      } else {
        Get.snackbar('Error', 'Item not found');
      }
    } catch (e) {
      Get.snackbar('Error', 'Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void _openQtySheet({String? scannedBatch}) {
    bsQtyController.clear();
    bsBatchController.clear();
    bsSourceRackController.clear();
    bsTargetRackController.clear();
    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;
    selectedSerial.value = null;

    if (scannedBatch != null) {
      bsBatchController.text = scannedBatch;
      // Auto validate if scanned? Yes, usually implied.
      // Or we call the API to confirm it exists.
      validateBatch(scannedBatch); 
    }

    Get.bottomSheet(
      const StockEntryItemQtySheet(),
      isScrollControlled: true,
    );
  }

  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;
    
    isValidatingBatch.value = true;
    
    // Simple check first: if batch is provided, verify with API
    try {
      // Assuming standard filter: batch_id or name.
      final response = await _apiProvider.getDocumentList('Batch', filters: {
        'item': currentItemCode,
        'name': batch 
      });
      
      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true; 
        Get.snackbar('Success', 'Batch validated', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
        
        // Determine which rack field to focus
        _focusNextField();
      } else {
        bsIsBatchValid.value = false;
        Get.snackbar('Error', 'Batch not found for this item');
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to validate batch: $e');
      bsIsBatchValid.value = false;
    } finally {
      isValidatingBatch.value = false;
    }
  }

  void _focusNextField() {
    final type = selectedStockEntryType.value;
    final isMaterialIssue = type == 'Material Issue';
    final isMaterialReceipt = type == 'Material Receipt';
    final isMaterialTransfer = type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

    if (isMaterialIssue || isMaterialTransfer) {
      sourceRackFocusNode.requestFocus();
    } else if (isMaterialReceipt) {
      targetRackFocusNode.requestFocus();
    }
  }

  void addItem() {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    // if (qty <= 0) return; // Allow 0? Probably not.
    
    final batch = bsBatchController.text;
    // if (!bsIsBatchValid.value) return; // Enforced by button state in UI

    final currentItems = stockEntry.value?.items.toList() ?? [];
    
    final index = currentItems.indexWhere((i) => i.itemCode == currentItemCode && i.batchNo == batch);
    
    if (index != -1) {
      final existing = currentItems[index];
      currentItems[index] = StockEntryItem(
        itemCode: existing.itemCode,
        qty: existing.qty + qty,
        basicRate: existing.basicRate,
        itemGroup: existing.itemGroup,
        customVariantOf: existing.customVariantOf,
        batchNo: batch,
        itemName: existing.itemName,
        rack: bsSourceRackController.text.isNotEmpty ? bsSourceRackController.text : existing.rack,
        toRack: bsTargetRackController.text.isNotEmpty ? bsTargetRackController.text : existing.toRack,
        sWarehouse: selectedFromWarehouse.value,
        tWarehouse: selectedToWarehouse.value,
      );
    } else {
      currentItems.add(StockEntryItem(
        itemCode: currentItemCode,
        qty: qty,
        basicRate: 0.0,
        itemName: currentItemName,
        batchNo: batch,
        rack: bsSourceRackController.text,
        toRack: bsTargetRackController.text,
        sWarehouse: selectedFromWarehouse.value,
        tWarehouse: selectedToWarehouse.value,
      ));
    }
    
    final old = stockEntry.value!;
    stockEntry.value = StockEntry(
      name: old.name,
      purpose: old.purpose,
      totalAmount: old.totalAmount,
      postingDate: old.postingDate,
      modified: old.modified,
      creation: old.creation,
      status: old.status,
      docstatus: old.docstatus,
      owner: old.owner,
      stockEntryType: selectedStockEntryType.value,
      postingTime: old.postingTime,
      fromWarehouse: selectedFromWarehouse.value,
      toWarehouse: selectedToWarehouse.value,
      customTotalQty: old.customTotalQty,
      customReferenceNo: customReferenceNoController.text,
      items: currentItems,
    );
    
    Get.back();
    Get.snackbar('Success', 'Item added');
  }
}
