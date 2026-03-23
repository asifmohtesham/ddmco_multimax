import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/form/controllers/purchase_order_item_form_controller.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_order_item_form_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class PurchaseOrderFormController extends GetxController {
  final PurchaseOrderProvider _provider       = Get.find<PurchaseOrderProvider>();
  final ApiProvider           _apiProvider    = Get.find<ApiProvider>();
  final ScanService           _scanService    = Get.find<ScanService>();
  final StorageService        _storageService = Get.find<StorageService>();
  final DataWedgeService      _dataWedgeService = Get.find<DataWedgeService>();

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

  var isLoading         = true.obs;
  var isSaving          = false.obs;
  var isScanning        = false.obs;
  var isDirty           = false.obs;
  var isAddingItem      = false.obs;
  var isItemSheetOpen   = false.obs;
  var isLoadingItemEdit = false.obs;
  var loadingForItemName = RxnString();

  var purchaseOrder = Rx<PurchaseOrder?>(null);

  String _originalJson   = '';
  String _originalStatus = 'Draft';

  bool get isEditable => purchaseOrder.value?.docstatus == 0;

  // ---------------------------------------------------------------------------
  // Header field controllers
  // ---------------------------------------------------------------------------

  final supplierController = TextEditingController();
  final dateController     = TextEditingController();
  final barcodeController  = TextEditingController();

  var suppliers           = <String>[].obs;
  var isFetchingSuppliers = false.obs;

  // ---------------------------------------------------------------------------
  // Item feedback / scroll
  // ---------------------------------------------------------------------------

  var recentlyAddedItemName          = ''.obs;
  final Map<String, GlobalKey> itemKeys = {};
  final ScrollController scrollController = ScrollController();

  void ensureItemKey(PurchaseOrderItem item) {
    if (item.name != null && !itemKeys.containsKey(item.name)) {
      itemKeys[item.name!] = GlobalKey();
    }
  }

  void triggerHighlight(String uniqueId) {
    recentlyAddedItemName.value = uniqueId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final key = itemKeys[uniqueId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration:  const Duration(milliseconds: 500),
            curve:     Curves.easeInOut,
            alignment: 0.5,
          );
        }
      });
    });
    Future.delayed(const Duration(seconds: 2), () {
      recentlyAddedItemName.value = '';
    });
  }

  // ---------------------------------------------------------------------------
  // DataWedge scan worker
  // ---------------------------------------------------------------------------

  Worker? _scanWorker;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    fetchSuppliers();
    supplierController.addListener(_checkForChanges);
    dateController.addListener(_checkForChanges);

    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);

    if (mode == 'new') {
      _initNewPurchaseOrder();
    } else {
      fetchPO();
    }
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    supplierController.dispose();
    dateController.dispose();
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // DataWedge raw scan entry point
  // ---------------------------------------------------------------------------

  void _onRawScan(String code) {
    if (code.isEmpty) return;
    // Only process scans when this route is active.
    if (Get.currentRoute != AppRoutes.PURCHASE_ORDER_FORM) return;
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
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
      final response = await _apiProvider.getDocumentList(
          'Supplier', limit: 0, fields: ['name']);
      if (response.statusCode == 200 && response.data['data'] != null) {
        suppliers.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (_) {
      // non-fatal — supplier picker shows empty list
    } finally {
      isFetchingSuppliers.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Document init / fetch
  // ---------------------------------------------------------------------------

  void _initNewPurchaseOrder() {
    isLoading.value = false;
    final now = DateTime.now();
    purchaseOrder.value = PurchaseOrder(
      name:            'New Purchase Order',
      supplier:        '',
      transactionDate: DateFormat('yyyy-MM-dd').format(now),
      grandTotal:      0.0,
      currency:        'AED',
      status:          'Not Saved',
      docstatus:       0,
      modified:        '',
      creation:        now.toString(),
      items:           [],
    );
    dateController.text = DateFormat('yyyy-MM-dd').format(now);
    isDirty.value       = true;
    _originalJson       = '';
    _originalStatus     = 'Draft';
  }

  Future<void> fetchPO() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseOrder(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final po = PurchaseOrder.fromJson(response.data['data']);
        purchaseOrder.value    = po;
        supplierController.text = po.supplier;
        dateController.text    = po.transactionDate;
        _updateOriginalState(po);
      } else {
        GlobalDialog.showError(
          title:   'Could not load Purchase Order',
          message: 'The server returned an unexpected response. '
              'Check your connection and try again.',
          onRetry: fetchPO,
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title:   'Could not load Purchase Order',
        message: e.toString(),
        onRetry: fetchPO,
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// Reload from server — e.g. after an optimistic-lock conflict.
  Future<void> reloadDocument() => fetchPO();

  void _updateOriginalState(PurchaseOrder po) {
    _originalJson   = jsonEncode(po.toJson());
    _originalStatus = po.status;
    isDirty.value   = false;
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
      name:            purchaseOrder.value!.name,
      supplier:        supplierController.text,
      transactionDate: dateController.text,
      grandTotal:      purchaseOrder.value!.grandTotal,
      currency:        purchaseOrder.value!.currency,
      status:          _originalStatus,
      docstatus:       purchaseOrder.value!.docstatus,
      modified:        purchaseOrder.value!.modified,
      creation:        purchaseOrder.value!.creation,
      items:           purchaseOrder.value!.items,
    );

    final currentJson = jsonEncode(tempPO.toJson());
    final dirty       = currentJson != _originalJson;
    isDirty.value     = dirty;

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
      name:            old.name,
      supplier:        old.supplier,
      transactionDate: old.transactionDate,
      grandTotal:      old.grandTotal,
      currency:        old.currency,
      status:          newStatus,
      docstatus:       old.docstatus,
      modified:        old.modified,
      creation:        old.creation,
      items:           old.items,
    );
  }

  // ---------------------------------------------------------------------------
  // Item mutations — called by PurchaseOrderItemFormController
  // ---------------------------------------------------------------------------

  /// Replaces the item list on the current PO and triggers an auto-save.
  /// NOTE: This method is retained for backward compatibility in IT-D.
  ///       IT-F will replace it with granular addItemLocally / updateItemLocally.
  void applyItemsAndSave(List<PurchaseOrderItem> updatedItems) {
    final old = purchaseOrder.value!;
    purchaseOrder.value = PurchaseOrder(
      name:            old.name,
      supplier:        supplierController.text,
      transactionDate: dateController.text,
      grandTotal:      updatedItems.fold(0.0, (sum, i) => sum + i.amount),
      currency:        old.currency,
      status:          old.status,
      docstatus:       old.docstatus,
      modified:        old.modified,
      creation:        old.creation,
      items:           updatedItems,
    );
    _checkForChanges();
    savePurchaseOrder();
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  Future<void> scanBarcode(String barcode) async {
    if (!isEditable) {
      GlobalSnackbar.warning(
          message: 'Document is submitted and cannot be edited.');
      return;
    }
    if (barcode.isEmpty) return;

    // If item sheet is open, ignore outer scan.
    if (isItemSheetOpen.value) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);

      if (result.isSuccess && result.itemData != null) {
        final item = result.itemData!;
        _openItemSheet(
          code: item.itemCode,
          name: item.itemName,
          uom:  item.stockUom ?? 'Nos',
          rate: 0.0,
          qty:  1.0,
        );
      } else if (result.type == ScanType.multiple &&
          result.candidates != null) {
        barcodeController.clear();
        Get.bottomSheet(
          MultiItemSelectionSheet(
            items: result.candidates!,
            onItemSelected: (item) => _openItemSheet(
              code: item.itemCode,
              name: item.itemName,
              uom:  item.stockUom ?? 'Nos',
              rate: 0.0,
              qty:  1.0,
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

  Future<void> editItem(PurchaseOrderItem item) async {
    if (!isEditable) return;
    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;
    try {
      _openItemSheet(
        code:         item.itemCode,
        name:         item.itemName,
        uom:          item.uom ?? '',
        rate:         item.rate,
        qty:          item.qty,
        rowId:        item.name,
        scheduleDate: item.scheduleDate,
        owner:        item.owner,
        creation:     item.creation,
        modified:     item.modified,
        modifiedBy:   item.modifiedBy,
      );
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Delete item — public entry point from item card / IT-F
  // ---------------------------------------------------------------------------

  void confirmAndDeleteItem(PurchaseOrderItem item) {
    GlobalDialog.showConfirmation(
      title:   'Remove Item?',
      message: 'Are you sure you want to remove ${item.itemCode} from this order?',
      onConfirm: () {
        final items = purchaseOrder.value?.items.toList() ?? [];
        items.removeWhere((i) => i.name == item.name);
        applyItemsAndSave(items);
        GlobalSnackbar.success(message: 'Item removed');
      },
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
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    Get.lazyPut<PurchaseOrderItemFormController>(
          () => PurchaseOrderItemFormController(),
      tag:   'po_item_sheet',
      fenix: true,
    );

    final sheetCtrl =
    Get.find<PurchaseOrderItemFormController>(tag: 'po_item_sheet');
    sheetCtrl.initialise(
      parentController: this,
      code:         code,
      name:         name,
      uom:          uom,
      qty:          qty,
      rate:         rate,
      rowId:        rowId,
      scheduleDate: scheduleDate,
      owner:        owner,
      creation:     creation,
      modified:     modified,
      modifiedBy:   modifiedBy,
    );

    isItemSheetOpen.value = true;
    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.9,
        expand:           false,
        builder: (context, scrollController) {
          return PurchaseOrderItemFormSheet(
              scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
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
      'supplier':         supplierController.text,
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
        GlobalDialog.showError(
          title:   'Could not save Purchase Order',
          message: 'The server returned an unexpected response. '
              'Check your connection and try again.',
          onRetry: savePurchaseOrder,
        );
      }
    } catch (e) {
      GlobalDialog.showError(
        title:   'Could not save Purchase Order',
        message: e.toString(),
        onRetry: savePurchaseOrder,
      );
    } finally {
      isSaving.value = false;
    }
  }
}