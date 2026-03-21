import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/form/controllers/purchase_order_item_form_controller.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_order_item_form_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class PurchaseOrderFormController extends GetxController {
  final PurchaseOrderProvider _provider = Get.find<PurchaseOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();

  // ---------------------------------------------------------------------------
  // Arguments
  // ---------------------------------------------------------------------------

  late final String name;
  late final String mode;

  PurchaseOrderFormController() {
    final args = Get.arguments;
    if (args is Map) {
      name = args['name'] ?? '';
      mode = args['mode'] ?? 'view';
    } else if (args is String) {
      name = args;
      mode = 'view';
    } else {
      name = '';
      mode = 'new';
    }
  }

  // ---------------------------------------------------------------------------
  // Document state
  // ---------------------------------------------------------------------------

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isScanning = false.obs;
  var isDirty = false.obs;

  var purchaseOrder = Rx<PurchaseOrder?>(null);

  String _originalJson = '';
  String _originalStatus = 'Draft';

  bool get isEditable => purchaseOrder.value?.docstatus == 0;

  // ---------------------------------------------------------------------------
  // Header field controllers
  // ---------------------------------------------------------------------------

  final supplierController = TextEditingController();
  final dateController = TextEditingController();
  final barcodeController = TextEditingController();

  var suppliers = <String>[].obs;
  var isFetchingSuppliers = false.obs;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
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
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Pop / discard
  // ---------------------------------------------------------------------------

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Supplier fetch
  // ---------------------------------------------------------------------------

  Future<void> fetchSuppliers() async {
    isFetchingSuppliers.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Supplier', limit: 0, fields: ['name']);
      if (response.statusCode == 200 && response.data['data'] != null) {
        suppliers.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching suppliers: $e');
    } finally {
      isFetchingSuppliers.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Document init / fetch
  // ---------------------------------------------------------------------------

  void _initNewPO() {
    isLoading.value = false;
    final now = DateTime.now();
    purchaseOrder.value = PurchaseOrder(
      name: 'New Purchase Order',
      supplier: '',
      transactionDate: DateFormat('yyyy-MM-dd').format(now),
      grandTotal: 0.0,
      currency: 'AED',
      status: 'Not Saved',
      docstatus: 0,
      modified: '',
      creation: now.toString(),
      items: [],
    );
    dateController.text = DateFormat('yyyy-MM-dd').format(now);
    isDirty.value = true;
    _originalJson = '';
    _originalStatus = 'Draft';
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
    _originalStatus = po.status;
    isDirty.value = false;
  }

  // ---------------------------------------------------------------------------
  // Dirty-check logic
  // ---------------------------------------------------------------------------

  void _checkForChanges() {
    if (purchaseOrder.value == null) return;

    if (mode == 'new') {
      isDirty.value = true;
      if (purchaseOrder.value!.status != 'Not Saved') _updateStatusOnly('Not Saved');
      return;
    }

    final tempPO = PurchaseOrder(
      name: purchaseOrder.value!.name,
      supplier: supplierController.text,
      transactionDate: dateController.text,
      grandTotal: purchaseOrder.value!.grandTotal,
      currency: purchaseOrder.value!.currency,
      status: _originalStatus,
      docstatus: purchaseOrder.value!.docstatus,
      modified: purchaseOrder.value!.modified,
      creation: purchaseOrder.value!.creation,
      items: purchaseOrder.value!.items,
    );

    final currentJson = jsonEncode(tempPO.toJson());
    final dirty = currentJson != _originalJson;
    isDirty.value = dirty;

    if (dirty && purchaseOrder.value!.status != 'Not Saved') {
      _updateStatusOnly('Not Saved');
    } else if (!dirty && purchaseOrder.value!.status == 'Not Saved') {
      _updateStatusOnly(_originalStatus);
    }
  }

  void _updateStatusOnly(String newStatus) {
    if (purchaseOrder.value == null) return;
    final old = purchaseOrder.value!;
    purchaseOrder.value = PurchaseOrder(
      name: old.name,
      supplier: old.supplier,
      transactionDate: old.transactionDate,
      grandTotal: old.grandTotal,
      currency: old.currency,
      status: newStatus,
      docstatus: old.docstatus,
      modified: old.modified,
      creation: old.creation,
      items: old.items,
    );
  }

  // ---------------------------------------------------------------------------
  // Item mutations — called by PurchaseOrderItemFormController
  // ---------------------------------------------------------------------------

  /// Replaces the item list on the current PO and triggers an auto-save.
  void applyItemsAndSave(List<PurchaseOrderItem> updatedItems) {
    final old = purchaseOrder.value!;
    purchaseOrder.value = PurchaseOrder(
      name: old.name,
      supplier: supplierController.text,
      transactionDate: dateController.text,
      grandTotal: updatedItems.fold(0.0, (sum, i) => sum + i.amount),
      currency: old.currency,
      status: old.status,
      docstatus: old.docstatus,
      modified: old.modified,
      creation: old.creation,
      items: updatedItems,
    );
    _checkForChanges();
    savePurchaseOrder();
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  Future<void> scanBarcode(String barcode) async {
    if (!isEditable) {
      GlobalSnackbar.warning(message: 'Document is submitted and cannot be edited.');
      return;
    }
    if (barcode.isEmpty) return;

    // If item sheet is open, ignore outer scan.
    if (Get.isRegistered<PurchaseOrderItemFormController>()) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);

      if (result.isSuccess && result.itemData != null) {
        final item = result.itemData!;
        _openItemSheet(
          code: item.itemCode,
          name: item.itemName,
          uom: item.stockUom ?? 'Nos',
          rate: 0.0,
          qty: 1.0,
        );
      } else if (result.type == ScanType.multiple && result.candidates != null) {
        barcodeController.clear();
        Get.bottomSheet(
          MultiItemSelectionSheet(
            items: result.candidates!,
            onItemSelected: (item) => _openItemSheet(
              code: item.itemCode,
              name: item.itemName,
              uom: item.stockUom ?? 'Nos',
              rate: 0.0,
              qty: 1.0,
            ),
          ),
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
        );
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ---------------------------------------------------------------------------
  // Edit existing item — entry point from item card tap
  // ---------------------------------------------------------------------------

  void editItem(PurchaseOrderItem item) {
    if (!isEditable) return;
    _openItemSheet(
      code: item.itemCode,
      name: item.itemName,
      uom: item.uom ?? '',
      rate: item.rate,
      qty: item.qty,
      rowId: item.name,
      scheduleDate: item.scheduleDate,
      owner: item.owner,
      creation: item.creation,
      modified: item.modified,
      modifiedBy: item.modifiedBy,
    );
  }

  // ---------------------------------------------------------------------------
  // Open item bottom sheet
  // ---------------------------------------------------------------------------

  void _openItemSheet({
    required String code,
    required String name,
    required String uom,
    required double rate,
    required double qty,
    String? rowId,
    String? scheduleDate,
    String? owner,
    String? creation,
    String? modified,
    String? modifiedBy,
  }) {
    // Register a fresh sheet controller each time.
    Get.lazyPut<PurchaseOrderItemFormController>(
      () => PurchaseOrderItemFormController(),
      tag: 'po_item_sheet',
      fenix: true,
    );

    final sheetCtrl = Get.find<PurchaseOrderItemFormController>(tag: 'po_item_sheet');
    sheetCtrl.initialise(
      parentController: this,
      code: code,
      name: name,
      uom: uom,
      qty: qty,
      rate: rate,
      rowId: rowId,
      scheduleDate: scheduleDate,
      owner: owner,
      creation: creation,
      modified: modified,
      modifiedBy: modifiedBy,
    );

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return PurchaseOrderItemFormSheet(scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      Get.delete<PurchaseOrderItemFormController>(tag: 'po_item_sheet');
    });
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

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
