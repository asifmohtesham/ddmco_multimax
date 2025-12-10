import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_order_item_form_sheet.dart';

class PurchaseOrderFormController extends GetxController {
  final PurchaseOrderProvider _provider = Get.find<PurchaseOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isScanning = false.obs;

  // Dirty Check
  var isDirty = false.obs;
  String _originalJson = '';

  var purchaseOrder = Rx<PurchaseOrder?>(null);

  // Form Controllers
  final supplierController = TextEditingController();
  final dateController = TextEditingController();
  final barcodeController = TextEditingController();

  // Suppliers Data
  var suppliers = <String>[].obs;
  var isFetchingSuppliers = false.obs;

  // Sheet State
  var isItemSheetOpen = false.obs;
  final bsQtyController = TextEditingController();
  final bsRateController = TextEditingController();

  // Temp Item State
  String? currentItemCode;
  String? currentItemName;
  String? currentUom;
  String? currentItemNameKey; // Row ID

  // Helper
  bool get isEditable => purchaseOrder.value?.docstatus == 0;

  @override
  void onInit() {
    super.onInit();

    // Fetch Suppliers List
    fetchSuppliers();

    supplierController.addListener(_checkForChanges);
    dateController.addListener(_checkForChanges);

    if (mode == 'new') {
      _initNewPO();
    } else {
      fetchPO();
    }
  }

  @override
  void onClose() {
    supplierController.dispose();
    dateController.dispose();
    barcodeController.dispose();
    bsQtyController.dispose();
    bsRateController.dispose();
    super.onClose();
  }

  Future<void> fetchSuppliers() async {
    isFetchingSuppliers.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Supplier', limit: 0, fields: ['name']); // 0 for all
      if (response.statusCode == 200 && response.data['data'] != null) {
        suppliers.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching suppliers: $e');
    } finally {
      isFetchingSuppliers.value = false;
    }
  }

  void _initNewPO() {
    isLoading.value = false;
    final now = DateTime.now();
    purchaseOrder.value = PurchaseOrder(
      name: 'New Purchase Order',
      supplier: '',
      transactionDate: DateFormat('yyyy-MM-dd').format(now),
      grandTotal: 0.0,
      currency: 'AED',
      status: 'Draft',
      docstatus: 0,
      modified: '',
      creation: now.toString(),
      items: [],
    );
    dateController.text = DateFormat('yyyy-MM-dd').format(now);

    // New doc is dirty by default
    isDirty.value = true;
    _originalJson = '';
  }

  Future<void> fetchPO() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseOrder(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final po = PurchaseOrder.fromJson(response.data['data']);
        purchaseOrder.value = po;

        supplierController.text = po.supplier;
        dateController.text = po.transactionDate;

        _updateOriginalState(po);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load PO: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _updateOriginalState(PurchaseOrder po) {
    _originalJson = jsonEncode(po.toJson());
    isDirty.value = false;
  }

  void _checkForChanges() {
    if (purchaseOrder.value == null) return;
    if (mode == 'new') {
      isDirty.value = true;
      return;
    }

    // Create a temp object with current form values to compare
    final tempPO = PurchaseOrder(
      name: purchaseOrder.value!.name,
      supplier: supplierController.text,
      transactionDate: dateController.text,
      grandTotal: purchaseOrder.value!.grandTotal, // Recalc logic omitted for brevity in dirty check
      currency: purchaseOrder.value!.currency,
      status: purchaseOrder.value!.status,
      docstatus: purchaseOrder.value!.docstatus,
      modified: purchaseOrder.value!.modified,
      creation: purchaseOrder.value!.creation,
      items: purchaseOrder.value!.items,
    );

    final currentJson = jsonEncode(tempPO.toJson());
    isDirty.value = currentJson != _originalJson;
  }

  // --- Item Logic ---

  Future<void> scanBarcode(String barcode) async {
    if (!isEditable) {
      GlobalSnackbar.warning(message: 'Document is submitted and cannot be edited.');
      return;
    }
    if (barcode.isEmpty) return;

    if (isItemSheetOpen.value) {
      // If sheet is open, maybe just update? For now, ignore or warn.
      return;
    }

    isScanning.value = true;

    // Simple EAN check
    String itemCode = barcode; // Assuming barcode is item code for now

    try {
      final response = await _apiProvider.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];

        _openItemSheet(
          code: data['item_code'],
          name: data['item_name'],
          uom: data['stock_uom'] ?? 'Nos',
          rate: 0.0, // Or fetch valuation rate if available
          qty: 1.0,
        );
      } else {
        GlobalSnackbar.error(message: 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void editItem(PurchaseOrderItem item) {
    if (!isEditable) return;

    _openItemSheet(
        code: item.itemCode,
        name: item.itemName,
        uom: item.uom ?? '',
        rate: item.rate,
        qty: item.qty,
        rowId: item.name
    );
  }

  void _openItemSheet({
    required String code,
    required String name,
    required String uom,
    required double rate,
    required double qty,
    String? rowId,
  }) {
    currentItemCode = code;
    currentItemName = name;
    currentUom = uom;
    currentItemNameKey = rowId;

    bsQtyController.text = qty.toStringAsFixed(0); // Assuming integer qty for simplicity, or 2
    bsRateController.text = rate.toStringAsFixed(2);

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return PurchaseOrderItemFormSheet(scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta).clamp(0.0, 999999.0);
    bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
  }

  void submitItem() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    final rate = double.tryParse(bsRateController.text) ?? 0;

    if (qty <= 0) return;

    final currentItems = purchaseOrder.value?.items.toList() ?? [];

    if (currentItemNameKey != null) {
      // Edit Existing
      final index = currentItems.indexWhere((i) => i.name == currentItemNameKey);
      if (index != -1) {
        final existing = currentItems[index];
        currentItems[index] = PurchaseOrderItem(
          name: existing.name,
          itemCode: existing.itemCode,
          itemName: existing.itemName,
          qty: qty,
          receivedQty: existing.receivedQty,
          rate: rate,
          amount: qty * rate,
          uom: existing.uom,
          description: existing.description,
        );
      }
    } else {
      // Add New (Check for duplicates if needed, or just add)
      currentItems.add(PurchaseOrderItem(
        name: null, // New item
        itemCode: currentItemCode!,
        itemName: currentItemName!,
        qty: qty,
        receivedQty: 0.0,
        rate: rate,
        amount: qty * rate,
        uom: currentUom,
      ));
    }

    // Update PO object
    final oldPO = purchaseOrder.value!;
    purchaseOrder.value = PurchaseOrder(
      name: oldPO.name,
      supplier: supplierController.text, // Sync text fields
      transactionDate: dateController.text,
      grandTotal: currentItems.fold(0.0, (sum, i) => sum + i.amount),
      currency: oldPO.currency,
      status: oldPO.status,
      docstatus: oldPO.docstatus,
      modified: oldPO.modified,
      creation: oldPO.creation,
      items: currentItems,
    );

    Get.back(); // Close sheet
    _checkForChanges();
  }

  void deleteItem(PurchaseOrderItem item) {
    if (!isEditable) return;

    final currentItems = purchaseOrder.value?.items.toList() ?? [];
    currentItems.remove(item);

    final oldPO = purchaseOrder.value!;
    purchaseOrder.value = PurchaseOrder(
      name: oldPO.name,
      supplier: supplierController.text,
      transactionDate: dateController.text,
      grandTotal: currentItems.fold(0.0, (sum, i) => sum + i.amount),
      currency: oldPO.currency,
      status: oldPO.status,
      docstatus: oldPO.docstatus,
      modified: oldPO.modified,
      creation: oldPO.creation,
      items: currentItems,
    );

    _checkForChanges();
    GlobalSnackbar.success(message: 'Item removed');
  }

  Future<void> savePurchaseOrder() async {
    if (!isDirty.value && mode != 'new') return;
    if (isSaving.value) return;

    isSaving.value = true;

    final data = {
      'supplier': supplierController.text,
      'transaction_date': dateController.text,
      'items': purchaseOrder.value?.items.map((e) => e.toJson()).toList(),
    };

    try {
      final response = mode == 'new'
          ? await _provider.createPurchaseOrder(data)
          : await _provider.updatePurchaseOrder(name, data);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final saved = PurchaseOrder.fromJson(response.data['data']);
        purchaseOrder.value = saved;
        _updateOriginalState(saved);

        GlobalSnackbar.success(message: 'Purchase Order Saved');
        if (mode == 'new') {
          // Optionally navigate to edit mode or refresh
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to save');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}