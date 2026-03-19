import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

// Step 3.2: UniversalItemFormSheet used directly in _openItemSheet.
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_batch_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_rack_field.dart';

import 'controllers/purchase_receipt_item_form_controller.dart';

class PurchaseReceiptFormController extends GetxController {
  final PurchaseReceiptProvider _provider       = Get.find<PurchaseReceiptProvider>();
  final PurchaseOrderProvider   _poProvider     = Get.find<PurchaseOrderProvider>();
  final ApiProvider             _apiProvider    = Get.find<ApiProvider>();
  final ScanService             _scanService    = Get.find<ScanService>();
  final StorageService          _storageService = Get.find<StorageService>();
  final DataWedgeService        _dataWedgeService = Get.find<DataWedgeService>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  // ── Document-level state ────────────────────────────────────────────────
  var isLoading       = true.obs;
  var isSaving        = false.obs;
  var isDirty         = false.obs;
  var isScanning      = false.obs;
  var isItemSheetOpen = false.obs;

  var purchaseReceipt = Rx<PurchaseReceipt?>(null);

  // ── Header form controllers ─────────────────────────────────────────────
  final supplierController    = TextEditingController();
  final postingDateController = TextEditingController();
  final postingTimeController = TextEditingController();
  final barcodeController     = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // ── Warehouse ─────────────────────────────────────────────────────────────
  var setWarehouse         = RxnString();
  var warehouses           = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── PO linking cache ───────────────────────────────────────────────────
  final List<Map<String, dynamic>> _cachedPoItems = [];
  var poItemQuantities = <String, double>{}.obs;

  // ── EAN context for inside-sheet scan routing ───────────────────────────
  String currentScannedEan = '';

  // ── UI feedback ──────────────────────────────────────────────────────────
  var recentlyAddedItemName = ''.obs;

  // ── Persistent scan worker ──────────────────────────────────────────────
  Worker? _scanWorker;

  bool get isEditable => purchaseReceipt.value?.docstatus == 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    supplierController.addListener(_markDirty);
    postingDateController.addListener(_markDirty);
    postingTimeController.addListener(_markDirty);
    ever(setWarehouse, (_) => _markDirty());

    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    log('[PR:onInit] _scanWorker registered on DataWedgeService.scannedCode',
        name: 'PR');

    if (mode == 'new') {
      _initNewPurchaseReceipt();
    } else {
      fetchPurchaseReceipt();
    }
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value && isEditable) isDirty.value = true;
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    log('[PR:onClose] _scanWorker disposed', name: 'PR');
    supplierController.dispose();
    postingDateController.dispose();
    postingTimeController.dispose();
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ── PopScope ────────────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Step 2.2: reloadDocument ──────────────────────────────────────────────
  /// Reloads the document from the server and resets dirty state.
  /// Mirrors [DeliveryNoteFormController.reloadDocument].
  /// Called by OptimisticLockingMixin (Phase 5.1) and pull-to-refresh.
  Future<void> reloadDocument() => fetchPurchaseReceipt();

  // ── Raw scan entry point ───────────────────────────────────────────────
  void _onRawScan(String code) {
    log('[PR:_onRawScan] code="$code" route=${Get.currentRoute}', name: 'PR');
    if (code.isEmpty) return;
    if (Get.currentRoute != AppRoutes.PURCHASE_RECEIPT_FORM) return;
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
  }

  // ── Data fetching ─────────────────────────────────────────────────────────
  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList(
          'Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      log('[PR:fetchWarehouses] error: $e', name: 'PR');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  Future<void> _initNewPurchaseReceipt() async {
    isLoading.value = true;
    final now      = DateTime.now();
    final supplier = Get.arguments['supplier'] ?? '';
    final poName   = Get.arguments['purchaseOrder'];

    purchaseReceipt.value = PurchaseReceipt(
      name:         'New Purchase Receipt',
      owner:        '',
      creation:     now.toString(),
      modified:     '',
      docstatus:    0,
      status:       'Draft',
      supplier:     supplier,
      postingDate:  DateFormat('yyyy-MM-dd').format(now),
      postingTime:  DateFormat('HH:mm:ss').format(now),
      setWarehouse: '',
      currency:     'AED',
      totalQty:     0,
      grandTotal:   0.0,
      items:        [],
    );

    supplierController.text    = supplier;
    postingDateController.text = DateFormat('yyyy-MM-dd').format(now);
    postingTimeController.text = DateFormat('HH:mm:ss').format(now);

    if (poName != null && poName.isNotEmpty) {
      await _fetchLinkedPurchaseOrders([poName]);
    }

    isLoading.value = false;
    isDirty.value   = true;
  }

  Future<void> fetchPurchaseReceipt() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final receipt = PurchaseReceipt.fromJson(response.data['data']);
        purchaseReceipt.value = receipt;

        supplierController.text    = receipt.supplier;
        postingDateController.text = receipt.postingDate;
        postingTimeController.text = receipt.postingTime;
        setWarehouse.value         = receipt.setWarehouse;

        final poNames = receipt.items
            .map((i) => i.purchaseOrder)
            .where((n) => n != null && n.isNotEmpty)
            .whereType<String>()
            .toSet()
            .toList();

        if (poNames.isNotEmpty) await _fetchLinkedPurchaseOrders(poNames);
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch purchase receipt');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    } finally {
      isLoading.value = false;
      isDirty.value   = false;
    }
  }

  Future<void> _fetchLinkedPurchaseOrders(List<String> poNames) async {
    _cachedPoItems.clear();
    poItemQuantities.clear();
    for (final poName in poNames) {
      try {
        final response = await _poProvider.getPurchaseOrder(poName);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final po = PurchaseOrder.fromJson(response.data['data']);
          for (final item in po.items) {
            if (item.name != null) {
              poItemQuantities[item.name!] = item.qty;
              _cachedPoItems.add({'poName': po.name, 'item': item});
            }
          }
        }
      } catch (e) {
        log('[PR:fetchLinkedPO] error for $poName: $e', name: 'PR');
      }
    }
  }

  // ── PO linking (called by child controller) ────────────────────────────────

  void linkToPurchaseOrder(
      String itemCode, PurchaseReceiptItemFormController child) {
    var match = _cachedPoItems.firstWhereOrNull((d) {
      final PurchaseOrderItem item = d['item'];
      return item.itemCode == itemCode && item.receivedQty < item.qty;
    });
    match ??= _cachedPoItems.firstWhereOrNull((d) {
      final PurchaseOrderItem item = d['item'];
      return item.itemCode == itemCode;
    });

    if (match != null) {
      final PurchaseOrderItem item = match['item'];
      child.poItemId.value  = item.name  ?? '';
      child.poDocName.value = match['poName'];
      child.poQty.value     = item.qty;
      child.poRate.value    = item.rate;
    }
  }

  double getOrderedQty(String? poItemName) {
    if (poItemName == null) return 0.0;
    return poItemQuantities[poItemName] ?? 0.0;
  }

  // ── Item sheet orchestration ──────────────────────────────────────────────
  //
  // Step 3.2: Mirrors DN’s _openItemSheet structure (P1-B pattern).
  //   • onSubmit lambda declared locally, passed to both the sheet widget
  //     AND setupAutoSubmit.onAutoSubmit — single coordinator path.
  //   • UniversalItemFormSheet used directly.
  //   • await on Get.bottomSheet so isItemSheetOpen resets after dismiss.

  Future<void> _openItemSheet({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOf,
    String?  uom,
    PurchaseReceiptItem? editingItem,
  }) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    final child = Get.put(PurchaseReceiptItemFormController());
    child.initialise(
      parent:         this,
      code:           itemCode,
      name:           itemName,
      batchNo:        batchNo,
      scannedEan:     scannedEan,
      variantOfValue: variantOf,
      uomValue:       uom,
      editingItem:    editingItem,
    );

    // ── P1-B: onSubmit coordinator ─────────────────────────────────────────
    // child.submit() performs the local mutation + ERPNext save.
    // Sheet closure is exclusively the caller’s responsibility.
    Future<void> onSubmit() async {
      await child.submit();
    }

    child.setupAutoSubmit(
      enabled:       _storageService.getAutoSubmitEnabled(),
      delaySeconds:  _storageService.getAutoSubmitDelay(),
      isSheetOpen:   isItemSheetOpen,
      isSubmittable: () => purchaseReceipt.value?.docstatus == 0,
      onAutoSubmit: () async {
        await onSubmit();
        if (Get.isBottomSheetOpen == true) Get.back();
      },
    );

    isItemSheetOpen.value = true;
    log('[PR:_openItemSheet] isItemSheetOpen → true', name: 'PR');

    await Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.95,
        builder: (ctx, sc) => UniversalItemFormSheet(
          controller:       child,
          scrollController: sc,
          onSubmit:         () async {
            await onSubmit();
            Get.back();
          },
          onScan: (code) => scanBarcode(code),
          customFields: [
            // 1. Batch No — editMode (purple, readOnly-when-valid + Edit btn)
            SharedBatchField(
              c:           child,
              accentColor: Colors.purple,
              editMode:    true,
              fieldKey:    'pr_batch_field',
            ),
            // 2. Target Rack — required (green)
            SharedRackField(
              c:           child,
              accentColor: Colors.green,
              label:       'Target Rack',
              hint:        'Rack',
              editMode:    true,
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );

    isItemSheetOpen.value = false;
    log('[PR:_openItemSheet] isItemSheetOpen → false', name: 'PR');
    barcodeController.clear();
    if (Get.isRegistered<PurchaseReceiptItemFormController>()) {
      Get.delete<PurchaseReceiptItemFormController>();
    }
  }

  // ── Public entry points ────────────────────────────────────────────────

  void openSheetForNewItem({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOf,
    String?  uom,
  }) {
    _openItemSheet(
      itemCode:   itemCode,
      itemName:   itemName,
      batchNo:    batchNo,
      scannedEan: scannedEan,
      variantOf:  variantOf,
      uom:        uom,
    );
  }

  void editItem(PurchaseReceiptItem item) {
    _openItemSheet(
      itemCode:    item.itemCode,
      itemName:    item.itemName ?? '',
      variantOf:   item.customVariantOf,
      uom:         item.uom,
      editingItem: item,
    );
  }

  void confirmAndDeleteItem(PurchaseReceiptItem item) {
    if (!isEditable) return;

    if (isItemSheetOpen.value) {
      if (Get.isBottomSheetOpen == true) Get.back();
    }

    GlobalDialog.showConfirmation(
      title:   'Remove Item?',
      message: 'Remove ${item.itemCode} from the receipt?',
      onConfirm: () {
        final currentItems = purchaseReceipt.value?.items.toList() ?? [];
        currentItems.removeWhere((i) => i.name == item.name);
        purchaseReceipt.update((val) => val?.items.assignAll(currentItems));
        isDirty.value = true;
        GlobalSnackbar.success(message: 'Item removed');
      },
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────
  Future<void> savePurchaseReceipt() async {
    if (!isEditable) return;
    if (isSaving.value) return;
    isSaving.value = true;

    final Map<String, dynamic> data = {
      'supplier':     supplierController.text,
      'posting_date': purchaseReceipt.value?.postingDate,
      'posting_time': purchaseReceipt.value?.postingTime,
      'set_warehouse': setWarehouse.value,
    };

    final itemsJson = purchaseReceipt.value?.items.map((i) {
      final json = i.toJson();
      if (json['name']?.toString().startsWith('local_') == true) {
        json.remove('name');
      }
      return json;
    }).toList() ?? [];
    data['items'] = itemsJson;

    try {
      if (mode == 'new') {
        final response = await _provider.createPurchaseReceipt(data);
        if (response.statusCode == 200) {
          final created = response.data['data'];
          name = created['name'];
          mode = 'edit';
          await fetchPurchaseReceipt();
          GlobalSnackbar.success(message: 'Purchase Receipt created: $name');
        } else {
          GlobalSnackbar.error(message:
              'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updatePurchaseReceipt(name, data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Purchase Receipt updated');
          await fetchPurchaseReceipt();
        } else {
          GlobalSnackbar.error(message:
              'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      String msg = 'Save failed';
      if (e.response?.data is Map) {
        msg = e.response!.data['exception']?.toString().split(':').last.trim()
            ?? 'Validation Error: Check form details';
      }
      GlobalSnackbar.error(message: msg);
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── UX helpers ─────────────────────────────────────────────────────────────
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
    Future.delayed(
        const Duration(seconds: 2), () => recentlyAddedItemName.value = '');
  }

  // ── Scan routing ────────────────────────────────────────────────────────────

  void _handleSheetScan(String barcode) async {
    barcodeController.clear();
    if (!Get.isRegistered<PurchaseReceiptItemFormController>()) {
      log('[PR:_handleSheetScan] child not registered — scan dropped', name: 'PR');
      return;
    }

    final child = Get.find<PurchaseReceiptItemFormController>();
    final contextEan = child.currentScannedEan.isNotEmpty
        ? child.currentScannedEan
        : child.itemCode.value;

    final result =
        await _scanService.processScan(barcode, contextItemCode: contextEan);

    if (result.type == ScanType.rack && result.rackId != null) {
      child.rackController.text = result.rackId!;
      child.validateRack(result.rackId!);
    } else if (result.batchNo != null) {
      child.batchController.text = result.batchNo!;
      child.validateBatch(result.batchNo!);
    } else {
      GlobalSnackbar.error(
          message: result.message ?? 'Invalid input for this field');
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (!isEditable) {
      GlobalSnackbar.warning(message: 'Document is submitted.');
      return;
    }
    if (barcode.isEmpty) return;

    log('[PR:scanBarcode] barcode="$barcode" isItemSheetOpen=${isItemSheetOpen.value}',
        name: 'PR');

    if (isItemSheetOpen.value) {
      _handleSheetScan(barcode);
      return;
    }

    if (isScanning.value) return;
    isScanning.value = true;

    try {
      final result = await _scanService.processScan(barcode);
      if (isItemSheetOpen.value) return;

      if (result.isSuccess && result.itemData != null) {
        if (result.rawCode.contains('-') &&
            !result.rawCode.startsWith('SHIPMENT')) {
          currentScannedEan = result.rawCode.split('-').first;
        } else {
          currentScannedEan = result.rawCode;
        }

        final itemData = result.itemData!;

        if (_cachedPoItems.isNotEmpty) {
          final found = _cachedPoItems.any((d) {
            final PurchaseOrderItem pi = d['item'];
            return pi.itemCode == itemData.itemCode;
          });
          if (!found) {
            GlobalSnackbar.error(message:
                'Item ${itemData.itemCode} is not in the linked Purchase Order');
            return;
          }
        }

        isScanning.value = false;
        barcodeController.clear();

        openSheetForNewItem(
          itemCode:   itemData.itemCode,
          itemName:   itemData.itemName,
          batchNo:    result.batchNo,
          scannedEan: currentScannedEan,
          variantOf:  itemData.variantOf,
          uom:        itemData.stockUom,
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
}
