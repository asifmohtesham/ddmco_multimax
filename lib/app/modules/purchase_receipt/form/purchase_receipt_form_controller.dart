import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/purchase_receipt_model.dart';
import 'package:ddmco_multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/purchase_receipt_form_screen.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:intl/intl.dart';

class PurchaseReceiptFormController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs;
  var purchaseReceipt = Rx<PurchaseReceipt?>(null);

  // Form Fields
  final supplierController = TextEditingController();
  final postingDateController = TextEditingController();
  final postingTimeController = TextEditingController();
  var setWarehouse = RxnString();

  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  final TextEditingController barcodeController = TextEditingController();

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsRackController = TextEditingController();

  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs;
  var isValidatingBatch = false.obs;

  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var isValidatingSourceRack = false.obs;
  var isValidatingTargetRack = false.obs;

  var currentOwner = '';
  var currentCreation = '';
  var currentModifiedBy = '';
  var currentModified = '';
  var currentItemCode = '';
  var currentVariantOf = '';
  var currentItemName = '';
  var currentUom = '';
  var currentItemIdx = 0.obs;
  var currentPurchaseOrderQty = 0.0.obs;

  // Dirty Check State
  var isFormDirty = false.obs;
  String _initialBatch = '';
  String _initialRack = '';
  String _initialQty = '';

  // Add this to store the unique row ID (name field in Purchase Receipt Item)
  String? currentItemNameKey;
  var warehouse = RxnString(); // Stores item-level warehouse

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    if (mode == 'new') {
      _initNewPurchaseReceipt();
    } else {
      fetchPurchaseReceipt();
    }
  }

  @override
  void onClose() {
    supplierController.dispose();
    postingDateController.dispose();
    postingTimeController.dispose();
    bsQtyController.dispose();
    bsBatchController.dispose();
    bsRackController.dispose();
    super.onClose();
  }

  final targetRackFocusNode = FocusNode();

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

  void _initNewPurchaseReceipt() {
    isLoading.value = true;
    final now = DateTime.now();
    final purchaseOrder = Get.arguments['purchaseOrder'] ?? '';
    final supplier = Get.arguments['supplier'] ?? '';

    purchaseReceipt.value = PurchaseReceipt(
      name: 'New Purchase Receipt',
      owner: '',
      creation: now.toString(),
      modified: '',
      docstatus: 0,
      status: 'Draft',
      supplier: supplier,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      postingTime: DateFormat('HH:mm:ss').format(now),
      setWarehouse: '',
      currency: 'AED', // Default or from settings
      totalQty: 0,
      grandTotal: 0.0,
      items: [],
    );

    supplierController.text = supplier;
    postingDateController.text = DateFormat('yyyy-MM-dd').format(now);
    postingTimeController.text = DateFormat('HH:mm:ss').format(now);

    isLoading.value = false;
  }

  Future<void> fetchPurchaseReceipt() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final receipt = PurchaseReceipt.fromJson(response.data['data']);
        purchaseReceipt.value = receipt;

        supplierController.text = receipt.supplier;
        postingDateController.text = receipt.postingDate;
        // time?
      } else {
        Get.snackbar('Error', 'Failed to fetch purchase receipt');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> savePurchaseReceipt() async {
    if (isSaving.value) return;
    isSaving.value = true;

    final Map<String, dynamic> data = {
      'supplier': supplierController.text, // Added supplier
      'posting_date': purchaseReceipt.value?.postingDate,
      'posting_time': purchaseReceipt.value?.postingTime,
      'set_warehouse': setWarehouse.value,
    };

    final itemsJson = purchaseReceipt.value?.items.map((i) => i.toJson()).toList() ?? [];
    data['items'] = itemsJson;

    try {
      if (mode == 'new') {
        final response = await _provider.createPurchaseReceipt(data);
        if (response.statusCode == 200) {
          final createdDoc = response.data['data'];
          name = createdDoc['name'];
          mode = 'edit';

          final old = purchaseReceipt.value!;
          purchaseReceipt.value = PurchaseReceipt(
            name: name,
            supplier: old.supplier,
            postingDate: old.postingDate,
            modified: old.modified,
            creation: old.creation,
            status: old.status,
            docstatus: old.docstatus,
            owner: old.owner,
            postingTime: old.postingTime,
            setWarehouse: old.setWarehouse,
            currency: old.currency,
            totalQty: old.totalQty,
            grandTotal: old.grandTotal,
            items: old.items,
          );

          Get.snackbar('Success', 'Purchase Receipt created: $name');
        } else {
          Get.snackbar('Error', 'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updatePurchaseReceipt(name, data);
        if (response.statusCode == 200) {
          Get.snackbar('Success', 'Purchase Receipt updated');
          fetchPurchaseReceipt();
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
      batchNo = parts.join('-');
    } else {
      final ean = barcode;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = null;
    }

    try {
      final response = await _apiProvider.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        currentItemNameKey = null; // New Item
        currentOwner = itemData['owner'];
        currentItemCode = itemData['item_code'];
        currentVariantOf = itemData['variant_of'] ?? '';
        currentItemName = itemData['item_name'];
        currentUom = itemData['stock_uom'] ?? 'Nos';
        currentItemIdx.value = 0;
        currentPurchaseOrderQty.value = 0.0;

        _openBottomSheet(scannedBatch: batchNo);
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

  String getRelativeTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 365) {
        return '${(difference.inDays / 365).floor()}y ago';
      } else if (difference.inDays > 30) {
        return '${(difference.inDays / 30).floor()}mo ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return dateString.split(' ')[0]; // Fallback to date part
    }
  }

  void _openBottomSheet({String? scannedBatch}) {
    bsQtyController.clear();
    bsBatchController.clear();
    bsRackController.clear();

    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;

    isTargetRackValid.value = false;

    currentItemNameKey = null; // Reset key for new item
    warehouse.value = null; // Reset item warehouse
    isFormDirty.value = false;

    _initialBatch = '';
    _initialRack = '';
    _initialQty = '';

    if (scannedBatch != null) {
      bsBatchController.text = scannedBatch;
      validateBatch(scannedBatch);
    }

    Get.bottomSheet(
      const PurchaseReceiptItemFormSheet(),
      isScrollControlled: true,
    );
  }

  void checkForChanges() {
    bool dirty = false;
    if (bsBatchController.text != _initialBatch) dirty = true;
    if (bsRackController.text != _initialRack) dirty = true;
    if (bsQtyController.text != _initialQty) dirty = true;

    // If adding new item, form is valid if fields are filled (dirty logic mainly for update)
    if (currentItemNameKey == null) dirty = true;

    isFormDirty.value = dirty;
  }

  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;

    isValidatingBatch.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Batch', filters: {
        'item': currentItemCode,
        'name': batch
      });

      // For Purchase Receipt, accept any batch (existing or new)
      bsIsBatchValid.value = true;
      bsIsBatchReadOnly.value = true;

      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        Get.snackbar('Success', 'Existing Batch found', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
      } else {
        Get.snackbar('Info', 'New Batch will be created', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 1));
      }
      checkForChanges();
      _focusNextField();
    } catch (e) {
      Get.snackbar('Error', 'Failed to check batch: $e');
      bsIsBatchValid.value = false;
    } finally {
      isValidatingBatch.value = false;
    }
  }

  Future<void> validateRack(String rack, bool isSource) async {
    if (rack.isEmpty) return;

    // Auto-parse Warehouse from Rack Pattern
    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        if (parts.length >= 3) {
          final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
          warehouse.value = wh;
        }
      }
    }

    if (isSource) isValidatingSourceRack.value = true;
    else isValidatingTargetRack.value = true;

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        if (isSource) isSourceRackValid.value = true;
        else isTargetRackValid.value = true;
      } else {
        if (isSource) isSourceRackValid.value = false;
        else isTargetRackValid.value = false;
        Get.snackbar('Error', 'Rack not found');
      }
    } catch (e) {
      if (isSource) isSourceRackValid.value = false;
      else isTargetRackValid.value = false;
    } finally {
      if (isSource) isValidatingSourceRack.value = false;
      else isValidatingTargetRack.value = false;
      checkForChanges();
    }
  }

  void _focusNextField() {
    targetRackFocusNode.requestFocus();
  }

  // New method to edit existing item
  void editItem(PurchaseReceiptItem item) {
    currentItemNameKey = item.name;
    currentOwner = item.owner;
    currentCreation = item.creation;
    currentModified = item.modified ?? '';
    currentModifiedBy = item.modifiedBy ?? '';
    currentItemCode = item.itemCode;
    currentItemName = item.itemName ?? '';
    currentVariantOf = item.customVariantOf ?? '';
    currentItemIdx.value = item.idx;
    currentPurchaseOrderQty.value = item.purchaseOrderQty ?? 0.0;

    _initialQty = item.qty.toString();
    _initialBatch = item.batchNo ?? '';
    _initialRack = item.rack ?? '';

    bsQtyController.text = _initialQty;
    bsBatchController.text = _initialBatch;
    bsRackController.text = _initialRack;

    // Restore warehouse
    if (item.warehouse.isNotEmpty) {
      warehouse.value = item.warehouse;
    }

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;
    isFormDirty.value = false;

    // Fix: Update Target Rack valid state instead of Source
    if (item.rack != null && item.rack!.isNotEmpty) isTargetRackValid.value = true;
    else isTargetRackValid.value = false;

    Get.bottomSheet(
      const PurchaseReceiptItemFormSheet(),
      isScrollControlled: true,
    );
  }

  void addItem() {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch = bsBatchController.text;
    if (!bsIsBatchValid.value && batch.isNotEmpty) return;

    final currentItems = purchaseReceipt.value?.items.toList() ?? [];

    final index = currentItems.indexWhere((i) => i.itemCode == currentItemCode && i.batchNo == batch);

    if (index != -1 && currentItemNameKey == null) {
      // Merging existing item if adding new
      final existing = currentItems[index];
      currentItems[index] = existing.copyWith(
        qty: existing.qty + qty,
        rack: bsRackController.text.isNotEmpty ? bsRackController.text : existing.rack,
        warehouse: warehouse.value!.isNotEmpty ? warehouse.value! : existing.warehouse,
      );
    } else if (currentItemNameKey != null) {
      // Updating specific item
      final editIndex = currentItems.indexWhere((i) => i.name == currentItemNameKey);
      if (editIndex != -1) {
        final existing = currentItems[editIndex];
        currentItems[editIndex] = existing.copyWith(
          qty: qty,
          batchNo: batch,
          rack: bsRackController.text,
          warehouse: warehouse.value!.isNotEmpty ? warehouse.value! : existing.warehouse,
        );
      }
    } else {
      // Add New
      currentItems.add(PurchaseReceiptItem(
        owner: currentOwner,
        creation: DateTime.now().toString(),
        itemCode: currentItemCode,
        qty: qty,
        itemName: currentItemName,
        batchNo: batch,
        rack: bsRackController.text,
        warehouse: warehouse.value ?? '',
        customVariantOf: currentVariantOf,
        purchaseOrderQty: currentPurchaseOrderQty.value,
        idx: currentItems.length + 1,
      ));
    }

    final old = purchaseReceipt.value!;
    purchaseReceipt.value = PurchaseReceipt(
      name: old.name,
      postingDate: old.postingDate,
      modified: old.modified,
      creation: old.creation,
      status: old.status,
      docstatus: old.docstatus,
      owner: old.owner,
      postingTime: old.postingTime,
      setWarehouse: old.setWarehouse,
      supplier: old.supplier,
      currency: old.currency,
      totalQty: old.totalQty,
      grandTotal: old.grandTotal,
      items: currentItems,
    );

    Get.back();

    // Auto-Save logic for new draft
    if (mode == 'new') {
      savePurchaseReceipt();
    } else {
      Get.snackbar('Success', 'Item list updated');
    }
  }
}