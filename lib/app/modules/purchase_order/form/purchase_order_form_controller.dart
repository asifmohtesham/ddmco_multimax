import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_order_item_form_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';

class PurchaseOrderFormController extends GetxController
    with OptimisticLockingMixin {
  final PurchaseOrderProvider _provider = Get.find<PurchaseOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final StorageService _storageService = Get.find<StorageService>();

  var itemFormKey = GlobalKey<FormState>();

  // Robust Argument Handling
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

  var isLoading = true.obs;
  var isSaving  = false.obs;
  var isScanning = false.obs;

  var isDirty = false.obs;

  // Track original state for dirty checks
  String _originalJson   = '';
  String _originalStatus = 'Draft';

  var purchaseOrder = Rx<PurchaseOrder?>(null);

  final supplierController       = TextEditingController();
  final dateController           = TextEditingController();
  final barcodeController        = TextEditingController();

  var suppliers          = <String>[].obs;
  var isFetchingSuppliers = false.obs;

  // Item Sheet State
  var isItemSheetOpen = false.obs;
  var isSheetValid    = false.obs;

  final bsQtyController          = TextEditingController();
  final bsRateController         = TextEditingController();
  final bsScheduleDateController = TextEditingController();

  // Metadata Observables
  var bsItemOwner      = RxnString();
  var bsItemCreation   = RxnString();
  var bsItemModified   = RxnString();
  var bsItemModifiedBy = RxnString();

  var sheetQty  = 0.0.obs;
  var sheetRate = 0.0.obs;

  double get sheetAmount => sheetQty.value * sheetRate.value;

  String? currentItemCode;
  String? currentItemName;
  String? currentUom;
  String? currentItemNameKey;

  // Validation State Tracking
  double _initialQty  = 0.0;
  double _initialRate = 0.0;
  String _initialDate = '';

  bool get isEditable => purchaseOrder.value?.docstatus == 0;

  Timer? _autoSubmitTimer;

  @override
  void onInit() {
    super.onInit();
    fetchSuppliers();

    // Item sheet field listeners — always safe to attach immediately.
    bsQtyController.addListener(() {
      sheetQty.value = double.tryParse(bsQtyController.text) ?? 0.0;
      validateSheet();
    });
    bsRateController.addListener(() {
      sheetRate.value = double.tryParse(bsRateController.text) ?? 0.0;
      validateSheet();
    });
    bsScheduleDateController.addListener(validateSheet);

    // Auto-Submit Logic
    ever(isSheetValid, (bool valid) {
      _autoSubmitTimer?.cancel();
      if (valid && isItemSheetOpen.value && isEditable) {
        if (_storageService.getAutoSubmitEnabled()) {
          final int delay = _storageService.getAutoSubmitDelay();
          _autoSubmitTimer = Timer(Duration(seconds: delay), () {
            if (isSheetValid.value && isItemSheetOpen.value) submitItem();
          });
        }
      }
    });

    // NOTE: supplierController and dateController listeners are NOT
    // attached here.  Each path (_initNewPO / fetchPO) attaches them
    // only after the baseline (_originalJson) has been established,
    // preventing a false dirty-check during initial population.
    if (mode == 'new') {
      _initNewPO();
    } else {
      fetchPO();
    }
  }

  @override
  void onClose() {
    _autoSubmitTimer?.cancel();
    supplierController.dispose();
    dateController.dispose();
    barcodeController.dispose();
    bsQtyController.dispose();
    bsRateController.dispose();
    bsScheduleDateController.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // PopScope
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
  // Sheet validation
  // ---------------------------------------------------------------------------

  void validateSheet() {
    if (!isEditable) {
      isSheetValid.value = false;
      return;
    }

    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) {
      isSheetValid.value = false;
      return;
    }

    if (bsScheduleDateController.text.isEmpty) {
      isSheetValid.value = false;
      return;
    }

    bool isDirtySheet = false;
    if (currentItemNameKey != null) {
      final currentRate = double.tryParse(bsRateController.text) ?? 0;
      if (qty != _initialQty)                        isDirtySheet = true;
      if (currentRate != _initialRate)               isDirtySheet = true;
      if (bsScheduleDateController.text != _initialDate) isDirtySheet = true;
    } else {
      isDirtySheet = true; // new items are always dirty
    }

    isSheetValid.value = isDirtySheet;
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
    } catch (e) {
      print('Error fetching suppliers: $e');
    } finally {
      isFetchingSuppliers.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Initialisation helpers
  // ---------------------------------------------------------------------------

  /// Called for mode == 'new'.  Builds a blank PO, locks in the baseline,
  /// then attaches the form-field listeners so any subsequent user edit
  /// is correctly detected as dirty.
  void _initNewPO() {
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

    // Baseline for a new doc: empty original so any change stays dirty.
    _originalJson   = '';
    _originalStatus = 'Draft';
    isDirty.value   = true;

    // Attach listeners AFTER baseline is set — changes from here are real.
    supplierController.addListener(_checkForChanges);
    dateController.addListener(_checkForChanges);
  }

  /// Called for mode == 'view' / 'edit'.  Detaches listeners while
  /// populating controllers from server data so the assignments do NOT
  /// trigger _checkForChanges.  Re-attaches in finally{} after the
  /// baseline has been locked in via _updateOriginalState().
  Future<void> fetchPO() async {
    isLoading.value = true;

    // Detach before touching controllers — prevents false dirty signal
    // while we write server values into the form fields.
    supplierController.removeListener(_checkForChanges);
    dateController.removeListener(_checkForChanges);

    try {
      final response = await _provider.getPurchaseOrder(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final po = PurchaseOrder.fromJson(response.data['data']);
        purchaseOrder.value = po;

        // Silent population — listeners are detached.
        supplierController.text = po.supplier;
        dateController.text     = po.transactionDate;

        // Lock in baseline BEFORE listeners are re-attached.
        _updateOriginalState(po);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load PO: $e');
    } finally {
      // Always re-attach so subsequent user edits are tracked correctly.
      supplierController.addListener(_checkForChanges);
      dateController.addListener(_checkForChanges);
      isLoading.value = false;
    }
  }

  void _updateOriginalState(PurchaseOrder po) {
    _originalJson   = jsonEncode(po.toJson());
    _originalStatus = po.status;
    isDirty.value   = false;
  }

  // ---------------------------------------------------------------------------
  // Dirty / status tracking
  // ---------------------------------------------------------------------------

  void _checkForChanges() {
    if (purchaseOrder.value == null) return;

    // New docs are always dirty; keep status as 'Not Saved'.
    if (mode == 'new') {
      isDirty.value = true;
      if (purchaseOrder.value!.status != 'Not Saved') {
        _updateStatusOnly('Not Saved');
      }
      return;
    }

    // Build a temp object using _originalStatus so data changes are
    // isolated from status changes in the JSON comparison.
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
  // OptimisticLockingMixin
  // ---------------------------------------------------------------------------

  @override
  Future<void> reloadDocument() async {
    await fetchPO();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
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
    if (checkStaleAndBlock()) return;
    if (barcode.isEmpty) return;
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
        GlobalSnackbar.error(
            message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ---------------------------------------------------------------------------
  // Item sheet
  // ---------------------------------------------------------------------------

  void editItem(PurchaseOrderItem item) {
    if (!isEditable) return;
    _openItemSheet(
      code:         item.itemCode,
      name:         item.itemName,
      uom:          item.uom ?? '',
      rate:         item.rate,
      qty:          item.qty,
      rowId:        item.name,
      scheduleDate: item.scheduleDate,
    );
    bsItemOwner.value      = item.owner;
    bsItemCreation.value   = item.creation;
    bsItemModified.value   = item.modified;
    bsItemModifiedBy.value = item.modifiedBy;
  }

  void _openItemSheet({
    required String code,
    required String name,
    required String uom,
    required double rate,
    required double qty,
    String? rowId,
    String? scheduleDate,
  }) {
    itemFormKey        = GlobalKey<FormState>();
    currentItemCode    = code;
    currentItemName    = name;
    currentUom         = uom;
    currentItemNameKey = rowId;
    bsItemOwner.value      = null;
    bsItemCreation.value   = null;
    bsItemModified.value   = null;
    bsItemModifiedBy.value = null;

    bsQtyController.text          = qty.toStringAsFixed(0);
    bsRateController.text         = rate.toStringAsFixed(2);
    bsScheduleDateController.text =
        scheduleDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    sheetQty.value  = qty;
    sheetRate.value = rate;

    _initialQty  = qty;
    _initialRate = rate;
    _initialDate = bsScheduleDateController.text;

    isItemSheetOpen.value = true;
    validateSheet();

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.9,
        builder: (context, scrollController) {
          return PurchaseOrderItemFormSheet(
              scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal  = (current + delta).clamp(0.0, 999999.0);
    bsQtyController.text =
        newVal == 0 ? '' : newVal.toStringAsFixed(0);
  }

  void submitItem() async {
    final qty  = double.tryParse(bsQtyController.text) ?? 0;
    final rate = double.tryParse(bsRateController.text) ?? 0;
    if (qty <= 0) return;

    final currentItems = purchaseOrder.value?.items.toList() ?? [];

    final newItem = PurchaseOrderItem(
      name:         currentItemNameKey,
      itemCode:     currentItemCode!,
      itemName:     currentItemName!,
      qty:          qty,
      receivedQty:  0.0,
      rate:         rate,
      amount:       qty * rate,
      uom:          currentUom,
      scheduleDate: bsScheduleDateController.text,
    );

    if (currentItemNameKey != null) {
      final index =
          currentItems.indexWhere((i) => i.name == currentItemNameKey);
      if (index != -1) {
        final existing = currentItems[index];
        currentItems[index] = PurchaseOrderItem(
          name:         existing.name,
          itemCode:     existing.itemCode,
          itemName:     existing.itemName,
          qty:          qty,
          receivedQty:  existing.receivedQty,
          rate:         rate,
          amount:       qty * rate,
          uom:          existing.uom,
          description:  existing.description,
          scheduleDate: bsScheduleDateController.text,
        );
      }
    } else {
      currentItems.add(newItem);
    }

    final oldPO = purchaseOrder.value!;
    purchaseOrder.value = PurchaseOrder(
      name:            oldPO.name,
      supplier:        supplierController.text,
      transactionDate: dateController.text,
      grandTotal:
          currentItems.fold(0.0, (sum, i) => sum + i.amount),
      currency:  oldPO.currency,
      status:    oldPO.status,
      docstatus: oldPO.docstatus,
      modified:  oldPO.modified,
      creation:  oldPO.creation,
      items:     currentItems,
    );

    Get.back();
    _checkForChanges();
    await savePurchaseOrder();
  }

  void deleteItem(PurchaseOrderItem item) {
    if (!isEditable) return;
    GlobalDialog.showConfirmation(
      title:   'Remove Item?',
      message: 'Remove ${item.itemCode} from the order?',
      onConfirm: () {
        final currentItems = purchaseOrder.value?.items.toList() ?? [];
        currentItems.remove(item);

        final oldPO = purchaseOrder.value!;
        purchaseOrder.value = PurchaseOrder(
          name:            oldPO.name,
          supplier:        supplierController.text,
          transactionDate: dateController.text,
          grandTotal:
              currentItems.fold(0.0, (sum, i) => sum + i.amount),
          currency:  oldPO.currency,
          status:    oldPO.status,
          docstatus: oldPO.docstatus,
          modified:  oldPO.modified,
          creation:  oldPO.creation,
          items:     currentItems,
        );
        _checkForChanges();
        GlobalSnackbar.success(message: 'Item removed');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> savePurchaseOrder() async {
    if (!isDirty.value && mode != 'new') return;
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    isSaving.value = true;

    final data = {
      'supplier':         supplierController.text,
      'transaction_date': dateController.text,
      'modified':         purchaseOrder.value?.modified,
      'items': purchaseOrder.value?.items
          .map((e) => e.toJson())
          .toList(),
    };

    try {
      final response = mode == 'new'
          ? await _provider.createPurchaseOrder(data)
          : await _provider.updatePurchaseOrder(name, data);

      if (response.statusCode == 200 &&
          response.data['data'] != null) {
        final saved = PurchaseOrder.fromJson(response.data['data']);
        purchaseOrder.value = saved;
        _updateOriginalState(saved);
        GlobalSnackbar.success(message: 'Purchase Order Saved');
      } else {
        GlobalSnackbar.error(message: 'Failed to save');
      }
    } catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}
