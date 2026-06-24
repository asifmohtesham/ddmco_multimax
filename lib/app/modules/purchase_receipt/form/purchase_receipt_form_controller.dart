import 'dart:async';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';

import 'purchase_receipt_item_form_controller.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_po_link_sheet.dart';

class PurchaseReceiptFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
  final PurchaseReceiptProvider _provider       = Get.find<PurchaseReceiptProvider>();
  final PurchaseOrderProvider   _poProvider     = Get.find<PurchaseOrderProvider>();
  final ApiProvider             _apiProvider    = Get.find<ApiProvider>();
  final ScanService             _scanService    = Get.find<ScanService>();
  final StorageService          _storageService = Get.find<StorageService>();
  final DataWedgeService        _dataWedgeService = Get.find<DataWedgeService>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  // ── Document-level state ─────────────────────────────────────────────
  var isLoading       = true.obs;
  @override var isSaving = false.obs;
  @override var isDirty  = false.obs;
  var isScanning      = false.obs;
  var isItemSheetOpen = false.obs;

  var isAddingItem       = false.obs;
  var isLoadingItemEdit  = false.obs;
  var loadingForItemName = RxnString();

  // ── Save result state machine ───────────────────────────────────────────
  var saveResult      = SaveResult.idle.obs;
  Timer? _saveResultTimer;

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }

  var purchaseReceipt = Rx<PurchaseReceipt?>(null);

  // ── Header form controllers ──────────────────────────────────────────────
  final supplierController    = TextEditingController();
  final postingDateController = TextEditingController();
  final postingTimeController = TextEditingController();
  final barcodeController     = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // ── Warehouse ──────────────────────────────────────────────────────────────
  var setWarehouse         = RxnString();
  var warehouses           = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── PO linking cache ────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _cachedPoItems = [];
  var poItemQuantities = <String, double>{}.obs;

  /// Re-entrancy guard so the 417 PO-link recovery re-save runs at most once.
  bool _poLinkRecoveryAttempted = false;

  // ── EAN context for doc-level scan routing ────────────────────────────
  String currentScannedEan = '';

  // ── UI feedback ─────────────────────────────────────────────────────────────
  var recentlyAddedItemName = ''.obs;

  // ── Persistent scan worker ────────────────────────────────────────────────────
  Worker? _scanWorker;
  Timer?  _scanDebounce;

  bool get isEditable => (purchaseReceipt.value?.docstatus ?? 1) == 0;

  @override String get realtimeDoctype => 'Purchase Receipt';
  @override String get realtimeDocname => name;

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
    log('[PR:onInit] _scanWorker registered', name: 'PR');

    if (mode == 'new') {
      _initNewPurchaseReceipt();
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
  }

  void _markDirty() {
    if (!isLoading.value && isEditable) {
      isDirty.value = true;
      scheduleAutoSave();
    }
  }

  @override
  void onClose() {
    disposeRealtimeSync();
    _scanWorker?.dispose();
    _saveResultTimer?.cancel();
    _scanDebounce?.cancel();
    log('[PR:onClose] _scanWorker disposed', name: 'PR');
    supplierController.dispose();
    postingDateController.dispose();
    postingTimeController.dispose();
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
    isStale.value    = false;
    isScanning.value = false;
    AppNotification.success('Document reloaded successfully');
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Raw scan entry point ───────────────────────────────────────────────
  void _onRawScan(String code) {
    log('[PR:_onRawScan] code="$code" route=${Get.currentRoute}', name: 'PR');
    if (code.isEmpty) return;
    final route = Get.currentRoute;
    final isOnForm  = route == AppRoutes.PURCHASE_RECEIPT_FORM;
    final isOnSheet = isItemSheetOpen.value;
    if (!isOnForm && !isOnSheet) return;
    // Debounce: ignore follow-up firings within 300 ms of a valid scan.
    _scanDebounce?.cancel();
    _scanDebounce = Timer(const Duration(milliseconds: 300), () {
      final clean = code.trim();
      barcodeController.text = clean;
      scanBarcode(clean);
    });
  }

  // ── Data fetching ────────────────────────────────────────────────────────────
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

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final receipt = PurchaseReceipt.fromJson(response.data['data']);

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

        // Re-hydrate poQty on each PR item from the cached PO items.
        // purchase_order_qty is not stored on the server — the app derives
        // it by matching purchaseOrderItem (the PO item row name) to the
        // cached PO items fetched above.
        final hydratedItems = receipt.items.map((prItem) {
          if (prItem.purchaseOrderItem == null) return prItem;
          final qty = poItemQuantities[prItem.purchaseOrderItem!];
          if (qty == null || qty <= 0) return prItem;
          return prItem.copyWith(purchaseOrderQty: qty);
        }).toList();

        purchaseReceipt.value = PurchaseReceipt(
          name:         receipt.name,
          postingDate:  receipt.postingDate,
          modified:     receipt.modified,
          creation:     receipt.creation,
          status:       receipt.status,
          docstatus:    receipt.docstatus,
          owner:        receipt.owner,
          postingTime:  receipt.postingTime,
          setWarehouse: receipt.setWarehouse,
          supplier:     receipt.supplier,
          currency:     receipt.currency,
          totalQty:     receipt.totalQty,
          grandTotal:   receipt.grandTotal,
          items:        hydratedItems,
        );
      } else {
        AppNotification.error('Failed to fetch purchase receipt');
      }
    } catch (e) {
      AppNotification.error(e.toString());
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

  // ── PO linking ─────────────────────────────────────────────────────────────

  /// Resolves a valid PO Item row for [itemCode] against the cached PO rows.
  PoLinkResult resolvePoLink(String itemCode,
      {required bool allowOverReceipt}) {
    final cands = _cachedPoItems
        .map((d) =>
            PoLinkCandidate(d['poName'] as String, d['item'] as PurchaseOrderItem))
        .toList();
    return resolvePoLinkFor(cands, itemCode,
        allowOverReceipt: allowOverReceipt);
  }

  /// Writes a resolved PO row onto the item-sheet controller.
  void applyPoLink(
      PurchaseReceiptItemFormController child, PoLinkCandidate c) {
    child.poItemId.value = c.item.name ?? '';
    child.poDocName.value = c.poName;
    child.poQty.value = c.item.qty;
    child.poRate.value = c.item.rate;
  }

  /// Best-effort PO link used when the sheet opens, so the PO Qty chip and
  /// progress bar populate. Final authority is the submit-time resolve in
  /// PurchaseReceiptItemFormController.submit(). Never links a closed row
  /// here (toggle defaults off); blocked items are simply left unlinked.
  void linkToPurchaseOrder(
      String itemCode, PurchaseReceiptItemFormController child) {
    final result =
        resolvePoLink(itemCode, allowOverReceipt: child.allowOverReceipt.value);
    switch (result.outcome) {
      case PoLinkOutcome.autoLinked:
        applyPoLink(child, result.linked!);
      case PoLinkOutcome.needsPicker:
        applyPoLink(child, result.candidates.first);
      case PoLinkOutcome.blocked:
        break;
    }
  }

  /// Opens the link picker and returns the chosen PO row (null if dismissed).
  Future<PoLinkCandidate?> showPoLinkPicker({
    required String itemCode,
    required List<PoLinkCandidate> candidates,
    required bool initialAllowOverReceipt,
  }) {
    return Get.bottomSheet<PoLinkCandidate>(
      PurchaseReceiptPoLinkSheet(
        itemCode: itemCode,
        candidates: candidates,
        initialAllowOverReceipt: initialAllowOverReceipt,
      ),
      isScrollControlled: true,
    );
  }

  double getOrderedQty(String? poItemName) {
    if (poItemName == null) return 0.0;
    return poItemQuantities[poItemName] ?? 0.0;
  }

  void ensureItemKey(PurchaseReceiptItem item) {
    if (item.name != null && !itemKeys.containsKey(item.name)) {
      itemKeys[item.name!] = GlobalKey();
    }
  }

  // ── addItem / updateItem ────────────────────────────────────

  void addItem(
    String itemCode,
    String itemName,
    double qty,
    String batch,
    String rack,
    String warehouse, {
    String uom       = '',
    String variantOf = '',
    String poItemId  = '',
    String poDocName = '',
    double poQty     = 0.0,
    double poRate    = 0.0,
  }) {
    if (!isEditable || qty <= 0) return;

    final currentItems = purchaseReceipt.value?.items.toList() ?? [];

    final dupIdx = currentItems.indexWhere((i) =>
        i.itemCode == itemCode &&
        (i.batchNo  ?? '') == batch &&
        (i.rack     ?? '') == rack &&
        i.warehouse == warehouse);

    if (dupIdx != -1) {
      final existing = currentItems[dupIdx];
      currentItems[dupIdx] = existing.copyWith(qty: existing.qty + qty);
      triggerHighlight(existing.name ?? '');
    } else {
      final uniqueId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      currentItems.add(PurchaseReceiptItem(
        name:              uniqueId,
        owner:             '',
        creation:          DateTime.now().toString(),
        itemCode:          itemCode,
        qty:               qty,
        itemName:          itemName,
        batchNo:           batch.isNotEmpty ? batch : null,
        rack:              rack.isNotEmpty  ? rack  : null,
        warehouse:         warehouse,
        uom:               uom,
        stockUom:          uom,
        customVariantOf:   variantOf,
        purchaseOrderItem: poItemId.isNotEmpty  ? poItemId  : null,
        purchaseOrder:     poDocName.isNotEmpty ? poDocName : null,
        purchaseOrderQty:  poQty > 0           ? poQty     : null,
        rate:              poRate,
        idx:               currentItems.length + 1,
      ));
      triggerHighlight(uniqueId);
    }

    _rebuildReceipt(currentItems);
    isDirty.value = true;
    scheduleAutoSave();
  }

  void updateItem(
    String itemName,
    double qty,
    String batch,
    String rack,
    String warehouse,
  ) {
    if (!isEditable) return;

    final currentItems = purchaseReceipt.value?.items.toList() ?? [];
    final idx = currentItems.indexWhere((i) => i.name == itemName);
    if (idx == -1) return;

    final existing = currentItems[idx];
    currentItems[idx] = existing.copyWith(
      qty:       qty,
      batchNo:   batch,
      rack:      rack,
      warehouse: warehouse.isNotEmpty ? warehouse : existing.warehouse,
    );

    _rebuildReceipt(currentItems);
    triggerHighlight(itemName);
    isDirty.value = true;
    scheduleAutoSave();
  }

  void _rebuildReceipt(List<PurchaseReceiptItem> items) {
    final old = purchaseReceipt.value!;
    purchaseReceipt.value = PurchaseReceipt(
      name:         old.name,
      postingDate:  old.postingDate,
      modified:     old.modified,
      creation:     old.creation,
      status:       old.status,
      docstatus:    old.docstatus,
      owner:        old.owner,
      postingTime:  old.postingTime,
      setWarehouse: old.setWarehouse,
      supplier:     old.supplier,
      currency:     old.currency,
      totalQty:     old.totalQty,
      grandTotal:   old.grandTotal,
      items:        items,
    );
  }

  // ── Item sheet orchestration ────────────────────────────────────────────────

  Future<void> _openItemSheet({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOf,
    String?  itemGroup,
    String?  uom,
    PurchaseReceiptItem? editingItem,
  }) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    final child = Get.put(PurchaseReceiptItemFormController());
    child.initialise(
      parent:          this,
      code:            itemCode,
      name:            itemName,
      batchNo:         batchNo,
      scannedEan:      scannedEan,
      variantOfValue:  variantOf,
      itemGroupValue:  itemGroup,
      uomValue:        uom,
      editingItem:     editingItem,
    );

    // Inject PO qty so the progress bar and PO Qty chip render on the item card.
    // Only for new items — editing items already have purchaseOrderQty from server.
    if (editingItem == null) {
      linkToPurchaseOrder(itemCode, child);
    }

    if (editingItem != null) ensureItemKey(editingItem);

    Future<void> onSubmit() async {
      await child.submit();
      await saveDocument();
    }

    isItemSheetOpen.value = true;
    log('[PR:_openItemSheet] isItemSheetOpen → true', name: 'PR');

    await Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.95,
        expand:           false,
        builder: (ctx, sc) => UniversalItemFormSheet(
          controller:       child,
          scrollController: sc,
          onSubmit: () async {
            final ok = await child.submitWithFeedback();
            if (ok) Get.back();
          },
          onScan: (code) => scanBarcode(code),
          customFields: [
            SharedBatchField(
              c:           child,
              accentColor: Colors.purple,
              editMode:    true,
              fieldKey:    'pr_batch_field',
              showBrowseBatches: true,
            ),
            SharedRackField(
              c:           child,
              accentColor: Colors.green,
              label:       'Target Rack',
              hint:        'Rack',
              editMode:    true,
              balanceOverride: () => null,
            ),
            Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Allow Over-Receipt'),
                  subtitle: const Text(
                      'Receive above ordered qty / against closed PO lines'),
                  value: child.allowOverReceipt.value,
                  onChanged: (v) {
                    child.allowOverReceipt.value = v;
                    child.validateSheet();
                  },
                )),
          ],
        ),
      ),
      isScrollControlled: true,
    );

    isItemSheetOpen.value = false;
    log('[PR:_openItemSheet] isItemSheetOpen → false', name: 'PR');
    barcodeController.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      child.disposeControllers();
      Get.delete<PurchaseReceiptItemFormController>(force: true);
      log('[PR:_openItemSheet] post-frame teardown complete', name: 'PR');
    });

    if (Get.isRegistered<PurchaseReceiptItemFormController>()) {
      Get.delete<PurchaseReceiptItemFormController>();
    }
  }

  // ── Public entry points ───────────────────────────────────────────────────

  void openSheetForNewItem({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOf,
    String?  itemGroup,
    String?  uom,
  }) {
    _openItemSheet(
      itemCode:   itemCode,
      itemName:   itemName,
      batchNo:    batchNo,
      scannedEan: scannedEan,
      variantOf:  variantOf,
      itemGroup:  itemGroup,
      uom:        uom,
    );
  }

  Future<void> editItem(PurchaseReceiptItem item) async {
    if (!isEditable) return;
    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;
    try {
      await _openItemSheet(
        itemCode:    item.itemCode,
        itemName:    item.itemName ?? '',
        variantOf:   item.customVariantOf,
        itemGroup:   item.itemGroup,
        uom:         item.uom,
        editingItem: item,
      );
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }
  }

  void deleteItem(PurchaseReceiptItem item) {
    if (!isEditable) return;

    if (isItemSheetOpen.value) {
      if (Get.isBottomSheetOpen == true) Get.back();
    }

    GlobalDialog.showConfirmation(
      title:   'Remove Item?',
      message: 'Remove ${item.itemCode} from the receipt?',
      onConfirm: () async {
        final currentItems = purchaseReceipt.value?.items.toList() ?? [];
        currentItems.removeWhere((i) => i.name == item.name);
        purchaseReceipt.update((val) => val?.items.assignAll(currentItems));
        isDirty.value = true;
        scheduleAutoSave();
        AppNotification.success('Item removed');
        await saveDocument();
      },
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────────────────
  @override
  Future<void> saveDocument() async {
    if (!isEditable) return;
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    isSaving.value = true;

    final Map<String, dynamic> data = {
      'supplier':      supplierController.text,
      'posting_date':  purchaseReceipt.value?.postingDate,
      'posting_time':  purchaseReceipt.value?.postingTime,
      'set_warehouse': setWarehouse.value,
      'modified':      purchaseReceipt.value?.modified,
    };

    final itemsJson = purchaseReceipt.value?.items.map((i) {
      final json = i.toJson();
      if (json['name']?.toString().startsWith('local_') == true) {
        json.remove('name');
      }
      json.removeWhere((key, value) => value == null);
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
          await startRealtimeSyncAfterCreate();
          await fetchDocument();
          _setSaveResult(SaveResult.success);
          AppNotification.success('Purchase Receipt created: $name');
        } else {
          _setSaveResult(SaveResult.error);
          AppNotification.error('Failed to create: '
                  '${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updatePurchaseReceipt(name, data);
        if (response.statusCode == 200) {
          _setSaveResult(SaveResult.success);
          await fetchDocument();
        } else {
          _setSaveResult(SaveResult.error);
          AppNotification.error('Failed to update: '
                  '${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) {
        // handled by OptimisticLockingMixin
      } else if (await _maybeRecoverInvalidPoRef(e)) {
        // 417 invalid PO ref handled: re-linked + re-saved, or surfaced.
      } else {
        _setSaveResult(SaveResult.error);
        String msg = 'Save failed';
        if (e.response?.data is Map) {
          if (e.response!.data['exception'] != null) {
            msg = e.response!.data['exception']
                .toString().split(':').last.trim();
          } else if (e.response!.data['_server_messages'] != null) {
            msg = 'Validation Error: Check form details';
          }
        }
        AppNotification.error(msg);
      }
    } catch (e) {
      _setSaveResult(SaveResult.error);
      AppNotification.error('Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  /// Reactive safety net for the 417 "Invalid reference Purchase Order Item"
  /// failure (design Section 4). Re-fetches the linked PO(s) fresh, re-links
  /// the offending items via the resolver, then re-saves ONCE. Returns true
  /// when the failure was a PO-ref problem this method handled (re-saved or
  /// surfaced its own message), false to let the caller show the generic error.
  Future<bool> _maybeRecoverInvalidPoRef(DioException e) async {
    if (_poLinkRecoveryAttempted) return false;
    if (e.response?.statusCode != 417) return false;
    final data = e.response?.data;
    final exc = (data is Map ? data['exception']?.toString() : null) ?? '';
    final badRefs = parseInvalidPoItemRefs(exc);
    if (badRefs.isEmpty) return false;

    _poLinkRecoveryAttempted = true;
    isSaving.value = false; // release the save lock before re-entrant save

    try {
      // Re-fetch linked POs fresh to drop stale child-row names.
      final poNames = purchaseReceipt.value?.items
              .map((i) => i.purchaseOrder)
              .whereType<String>()
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList() ??
          <String>[];
      await _fetchLinkedPurchaseOrders(poNames);

      final items = purchaseReceipt.value?.items.toList() ?? [];
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        if (it.purchaseOrderItem == null ||
            !badRefs.contains(it.purchaseOrderItem)) {
          continue;
        }
        final result =
            resolvePoLink(it.itemCode, allowOverReceipt: false);
        PoLinkCandidate? chosen;
        switch (result.outcome) {
          case PoLinkOutcome.autoLinked:
            chosen = result.linked;
          case PoLinkOutcome.needsPicker:
          case PoLinkOutcome.blocked:
            chosen = await showPoLinkPicker(
              itemCode: it.itemCode,
              candidates: result.allForItem,
              initialAllowOverReceipt: false,
            );
        }
        if (chosen == null) {
          AppNotification.error(
              'Could not link ${it.itemCode} to a valid Purchase Order Item.');
          return true; // handled (surfaced message); do not re-save
        }
        items[i] = it.copyWith(
          purchaseOrderItem: chosen.item.name,
          purchaseOrder: chosen.poName,
          purchaseOrderQty: chosen.item.qty,
        );
      }
      _rebuildReceipt(items);

      await saveDocument(); // single re-save
      return true;
    } finally {
      _poLinkRecoveryAttempted = false;
    }
  }

  // ── UX helpers ────────────────────────────────────────────────────────────────────
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

  // ── Scan routing ────────────────────────────────────────────────────────────────

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
      child.applyRackScan(result.rackId!);
    } else if (result.batchNo != null) {
      child.batchController.text = result.batchNo!;
      child.validateBatch(result.batchNo!);
    } else {
      AppNotification.error(
          result.message ?? 'Invalid input for this field');
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (!isEditable) {
      AppNotification.warning('Document is submitted.');
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
            AppNotification.error(
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
          itemGroup:  itemData.itemGroup,
          uom:        itemData.stockUom,
        );
      } else {
        AppNotification.error(result.message ?? 'Item not found');
      }
    } catch (e) {
      AppNotification.error('Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }
}
