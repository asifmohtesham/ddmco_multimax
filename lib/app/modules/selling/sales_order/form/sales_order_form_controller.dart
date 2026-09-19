import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/utils/app_constants.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/form/sales_order_item_form_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/form/widgets/hold_reason_sheet.dart';
import 'package:multimax/app/modules/selling/sales_order/form/widgets/sales_order_item_form_sheet.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

/// Sales Order form controller. Mirrors PurchaseOrderFormController's
/// structure (args parsing, optimistic locking + realtime sync, save-result
/// timer, highlight/scroll keys, dirty-guard) with SO-specific perms/actions.
///
/// Rx reads that feed `headerSliverBuilder` (so, isDirty, isSaving,
/// saveResult, isLoading, actions, canSubmit, canSaveNow, banner) MUST be
/// hoisted into the outer `Obx` builder body in the screen — see
/// gotcha-nestedscrollview-form-header.md.
class SalesOrderFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
  final SalesOrderProvider _provider = Get.find<SalesOrderProvider>();
  final StorageService _storage = Get.find<StorageService>();
  final PermissionService _perm = Get.find<PermissionService>();
  final ScanService _scanService = Get.find<ScanService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();

  // ---------------------------------------------------------------------------
  // Arguments
  // ---------------------------------------------------------------------------

  // Mutable: after the first POST the controller adopts the saved name and
  // flips to 'edit' in place (Get.offNamed to the SAME route is dropped by
  // GetX's preventDuplicates, so we don't navigate).
  late String name;
  late String mode;
  SalesOrderFormController() {
    final a = Get.arguments;
    name = a is Map ? (a['name'] ?? '') : (a is String ? a : '');
    mode = a is Map ? (a['mode'] ?? 'view') : (a is String ? 'view' : 'new');
  }

  // ---------------------------------------------------------------------------
  // Document state
  // ---------------------------------------------------------------------------

  final isLoading = true.obs;
  @override final isSaving = false.obs;
  @override final isDirty = false.obs;
  final isSubmitting = false.obs;
  final isActing = RxnString(); // SoAction.name in flight
  final isItemSheetOpen = false.obs;
  final isScanning = false.obs;
  final banner = RxnString(); // server error text, cleared on next action
  final so = Rx<SalesOrder?>(null);
  SalesOrder? _original;

  // Per-doc perms for submitted actions; null = unresolved (fail closed).
  final canSubmitPerm = RxnBool();
  final canCancelPerm = RxnBool();

  @override String get realtimeDoctype => 'Sales Order';
  @override String get realtimeDocname => name;

  final saveResult = SaveResult.idle.obs;
  Timer? _saveResultTimer;

  /// Fail-closed: a document is only editable when it's a draft AND the
  /// write (or, for a not-yet-created doc, create) permission has resolved
  /// to exactly `true`. `null` (still loading) or `false` reads as not
  /// editable. This reads `PermissionService`'s permission cache (an
  /// `RxMap`), so every call site that feeds a widget build must be a
  /// hoisted read inside an `Obx` — see the single hoisted read in the
  /// screen's outer `Obx` (never re-read `isEditable` deeper in the tree).
  bool get isEditable =>
      (so.value?.docstatus ?? 1) == 0 &&
      (mode == 'new'
              ? _perm.hasAccess('Sales Order', permType: 'create')
              : _perm.hasAccess('Sales Order', permType: 'write')) ==
          true;

  SoPerms get perms => SoPerms(
        write: mode == 'new'
            ? _perm.hasAccess('Sales Order', permType: 'create')
            : _perm.hasAccess('Sales Order', permType: 'write'),
        submit: canSubmitPerm.value,
        cancel: canCancelPerm.value,
        createDn: _perm.hasAccess('Delivery Note', permType: 'create'),
      );

  Set<SoAction> get actions {
    final s = so.value;
    return s == null ? const {} : allowedActions(s, perms);
  }

  /// Header Save is enabled only when a save could succeed server-side.
  bool get canSaveNow {
    final s = so.value;
    return s != null && s.customer.isNotEmpty && s.items.isNotEmpty;
  }

  /// Draft may be submitted only when saved and clean (SE computeCanSubmit).
  bool get canSubmit =>
      actions.contains(SoAction.submit) &&
      mode != 'new' && !isDirty.value && !isSaving.value && !isSubmitting.value;

  // ---------------------------------------------------------------------------
  // Item feedback / scroll (mirrors PO — driven once the item sheet, Task 5,
  // calls addItem/updateItem/deleteItem below)
  // ---------------------------------------------------------------------------

  // No stored ScrollController: the Items tab's CustomScrollView must inherit
  // NestedScrollView's PrimaryScrollController (an explicit one here would
  // desync it from the pinned-header collapse/injector coordination).
  // Scrollable.ensureVisible below walks up from the item's own context and
  // needs no controller reference.
  final recentlyAddedItemName = ''.obs;
  final Map<String, GlobalKey> itemKeys = {};
  final barcodeController = TextEditingController();

  /// Customer's PO No text field — seeded once per document load (here, not
  /// re-set on every keystroke's rebuild) so the cursor/focus survive the
  /// `_apply`-driven Obx rebuild that follows each `onChanged`.
  final poNoController = TextEditingController();

  void ensureItemKey(SalesOrderItem item) {
    final key = item.name;
    if (key != null && !itemKeys.containsKey(key)) {
      itemKeys[key] = GlobalKey();
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
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
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

  void _onRawScan(String code) {
    if (code.isEmpty) return;
    if (Get.currentRoute != AppRoutes.SALES_ORDER_FORM) return;
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    _loadReservationSetting();
    if (mode == 'new') {
      final today = FormattingHelper.formatDate(DateTime.now());
      so.value = SalesOrder.blank(
          transactionDate: today, company: _storage.getCompany())
          .copyWith(
              sellingPriceList: resolveDefaultPriceList(
                  partyPriceList: null,
                  lastUsed: _storage.getSoLastSellingPriceList(_email)));
      _original = null;
      isDirty.value = true;
      isLoading.value = false;
      poNoController.text = '';
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
  }

  @override
  void onClose() {
    disposeRealtimeSync();
    _scanWorker?.dispose();
    _saveResultTimer?.cancel();
    poNoController.dispose();
    // barcodeController not disposed: see HomeController.onClose (use-after-dispose on logout).
    super.onClose();
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getSalesOrder(name);
      final data = (res.data is Map) ? res.data['data'] : null;
      if (res.statusCode == 200 && data is Map) {
        _setLoaded(SalesOrder.fromJson(Map<String, dynamic>.from(data)));
        await _refreshDocPerms();
      } else {
        GlobalDialog.showError(
            title: 'Could not load Sales Order',
            message: 'The server returned an unexpected response.',
            onRetry: fetchDocument);
      }
    } catch (e) {
      GlobalDialog.showError(
          title: 'Could not load Sales Order',
          message: e.toString(),
          onRetry: fetchDocument);
    } finally {
      isLoading.value = false;
    }
  }

  void _setLoaded(SalesOrder s) {
    so.value = s;
    _original = s;
    isDirty.value = false;
    poNoController.text = s.poNo ?? '';
  }

  /// Applies a successful save's response, reconciling any header edit made
  /// locally while the request was in flight instead of letting it clobber
  /// [so.value] outright (the bug: `addItem(A)` … `addItem(B)` during A's
  /// POST used to silently lose B; the header analogue is typing PO No
  /// during an autosave).
  ///
  /// [saved] is the server's response; [sent] is the exact snapshot that was
  /// POSTed/PUT. Item edits can't have happened meanwhile (addItem/
  /// updateItem/deleteItem all block while isSaving), so only header fields
  /// need reconciling.
  void _applyPostSave(SalesOrder saved, SalesOrder sent) {
    final current = so.value;
    if (current == null ||
        !isSoDirty(sent, current,
            reservationEnabled: reservationEnabled.value)) {
      // Nothing changed locally while this request was in flight (or the
      // document was cleared out from under us) — the server copy stands.
      _setLoaded(saved);
      return;
    }
    // Re-apply the header fields the user changed after `sent` was captured
    // onto the freshly-saved copy (which carries server-computed totals,
    // real item names, etc.), then keep the doc dirty so the next autosave
    // (already scheduled by `_apply` under setHeader/setCustomer) persists
    // them. poNoController is deliberately left untouched here — it already
    // shows what the user typed, which is `current.poNo`, never `saved.poNo`.
    final reapplied = saved.copyWith(
      customer: current.customer != sent.customer ? current.customer : null,
      customerName: current.customerName != sent.customerName
          ? current.customerName
          : null,
      transactionDate: current.transactionDate != sent.transactionDate
          ? current.transactionDate
          : null,
      deliveryDate: current.deliveryDate != sent.deliveryDate
          ? current.deliveryDate
          : null,
      orderType: current.orderType != sent.orderType ? current.orderType : null,
      company: current.company != sent.company ? current.company : null,
      currency: current.currency != sent.currency ? current.currency : null,
      sellingPriceList: current.sellingPriceList != sent.sellingPriceList
          ? current.sellingPriceList
          : null,
      setWarehouse: current.setWarehouse != sent.setWarehouse
          ? current.setWarehouse
          : null,
      poNo: current.poNo != sent.poNo ? current.poNo : null,
    );
    so.value = reapplied;
    _original = saved;
    isDirty.value = true;
    scheduleAutoSave();
  }

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }

  /// Submit (draft) or submit+cancel (submitted) per document; fail-closed.
  Future<void> _refreshDocPerms() async {
    final s = so.value;
    if (s == null || s.name.isEmpty || s.docstatus == 2) {
      canSubmitPerm.value = false;
      canCancelPerm.value = false;
      return;
    }
    final r = await Future.wait([
      _provider.hasDocPerm(s.name, 'submit'),
      s.docstatus == 1 ? _provider.hasDocPerm(s.name, 'cancel') : Future.value(false),
    ]);
    canSubmitPerm.value = r[0];
    canCancelPerm.value = r[1];
  }

  @override
  Future<void> reloadDocument() async {
    // RealtimeSyncMixin._onRemoteUpdate can call this before our own save's
    // HTTP response lands (the doc_update event races the response).
    // Reloading then would call fetchDocument -> _setLoaded, which wipes
    // so.value, poNoController and isDirty out from under the in-flight
    // save — e.g. a PO No typed while the request is in flight. Wait for
    // the save to finish first (bounded, so a wedged save can't hang this
    // reload forever).
    var waited = 0;
    const step = Duration(milliseconds: 200);
    const cap = Duration(seconds: 15);
    while (isSaving.value && waited < cap.inMilliseconds) {
      await Future.delayed(step);
      if (isClosed) return;
      waited += step.inMilliseconds;
    }
    if (isClosed) return;
    // _applyPostSave already reconciled any header edit made during the
    // save and left the doc dirty with another autosave scheduled — that
    // state is newer than whatever the server just told us about, so skip
    // this reload rather than clobber it.
    if (isDirty.value) return;
    isStale.value = false;
    await fetchDocument();
  }

  // ── Mutations ──────────────────────────────────────────────────────────
  void _apply(SalesOrder next) {
    so.value = next;
    isDirty.value = mode == 'new' ||
        _original == null ||
        isSoDirty(_original!, next,
            reservationEnabled: reservationEnabled.value);
    if (isDirty.value) scheduleAutoSave();
  }

  Future<void> setCustomer(String customer) async {
    final s = so.value;
    if (s == null || !isEditable) return;
    _apply(s.copyWith(customer: customer, customerName: customer));
    // Desk's customer trigger: pull price list + currency from the party.
    try {
      final p = await _provider.getPartyDetails(
          customer: customer, company: s.company ?? _storage.getCompany());
      // Stale-response guard: if the user picked a different customer while
      // this lookup was in flight, so.value.customer has moved on — applying
      // this response now would overwrite the newer pick with the old one's
      // price list / currency.
      if (so.value?.customer != customer) return;
      final cur = so.value!;
      _apply(cur.copyWith(
        customerName: (p['customer_name'] ?? customer).toString(),
        sellingPriceList: resolveDefaultPriceList(
            partyPriceList: p['selling_price_list']?.toString(),
            lastUsed: cur.sellingPriceList),
        currency: p['currency']?.toString(),
      ));
    } catch (_) {
      // Fail-open: the server fills the price list on save.
    }
  }

  /// User-picked Price List (smoke-fix-1, Ruling 9). Never re-prices existing
  /// rows — desk doesn't either; the user can edit each row's rate.
  void setPriceList(String pl) {
    final s = so.value;
    if (s == null || !isEditable) return;
    _apply(s.copyWith(sellingPriceList: pl));
  }

  Future<void> _loadReservationSetting() async {
    final on = await _provider.stockReservationEnabled();
    if (isClosed) return;
    reservationEnabled.value = on;
  }

  /// Header "Reserve Stock": the server creates the Stock Reservation Entries
  /// itself on submit (SalesOrder.on_submit), so this only sets the flag.
  void setReserveStock(bool value) {
    final s = so.value;
    if (s == null || !isEditable || !reservationEnabled.value) return;
    _apply(s.copyWith(reserveStock: value));
  }

  void setHeader({
    String? transactionDate,
    String? deliveryDate,
    String? orderType,
    String? setWarehouse,
    String? poNo,
  }) {
    final s = so.value;
    if (s == null || !isEditable) return;
    _apply(s.copyWith(
      transactionDate: transactionDate,
      deliveryDate: deliveryDate,
      orderType: orderType,
      setWarehouse: setWarehouse,
      poNo: poNo,
    ));
  }

  /// Shown when an item mutation is attempted while a save is already in
  /// flight — see saveDocument's in-flight-edit note. Mutating `so.value.items`
  /// then would race the request currently building its payload from the
  /// pre-mutation snapshot, either losing the new row or duplicating it once
  /// the response reloads.
  bool _blockIfSaving() {
    if (!isSaving.value) return false;
    GlobalSnackbar.warning(message: 'Saving… try again in a moment.');
    return true;
  }

  /// Returns true when the row was applied, false when refused (a save was
  /// in flight) — the item sheet's submit() only closes on true so a refused
  /// add/update doesn't silently drop the user's input.
  bool addItem(SalesOrderItem row) {
    if (_blockIfSaving()) return false;
    // Every row needs a non-null unique id: updateItem/deleteItem and the
    // Items tab's Dismissible/highlight keys all match by `name`, and two
    // null-named rows would be indistinguishable to them. Server rows always
    // carry a name; only a freshly-added local row can arrive with none.
    final named = row.name == null
        ? row.withName('local_${DateTime.now().microsecondsSinceEpoch}')
        : row;
    final s = so.value!;
    _apply(s.copyWith(items: [...s.items, named]));
    ensureItemKey(named);
    triggerHighlight(named.name!);
    saveDocument();
    return true;
  }

  bool updateItem(SalesOrderItem row) {
    if (_blockIfSaving()) return false;
    final s = so.value!;
    _apply(s.copyWith(
        items: s.items.map((i) => i.name == row.name ? row : i).toList()));
    saveDocument();
    return true;
  }

  void deleteItem(SalesOrderItem row) {
    if (_blockIfSaving()) return;
    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Remove ${row.itemCode} from this order?',
      onConfirm: () {
        if (_blockIfSaving()) return; // a save may have started while confirming
        final s = so.value!;
        _apply(s.copyWith(
            items: s.items.where((i) => i.name != row.name).toList()));
        saveDocument();
      },
    );
  }

  // ── Scan ───────────────────────────────────────────────────────────────
  /// Resolves a scanned/typed barcode to an item and opens the item sheet.
  /// The sheet itself (add/edit qty, rate, warehouse) is built in Task 5;
  /// today this only resolves the item code and hands off to the stub.
  Future<void> scanBarcode(String barcode) async {
    if (!isEditable) {
      GlobalSnackbar.warning(
          message: 'Document is submitted and cannot be edited.');
      return;
    }
    if (barcode.isEmpty) return;
    if (isItemSheetOpen.value) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);
      if (result.isSuccess && result.itemData != null) {
        openItemSheet(itemCode: result.itemData!.itemCode);
      } else if (result.type == ScanType.multiple && result.candidates != null) {
        barcodeController.clear();
        Get.bottomSheet(
          MultiItemSelectionSheet(
            items: result.candidates!,
            onItemSelected: (item) => openItemSheet(itemCode: item.itemCode),
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

  // ── Item sheet ─────────────────────────────────────────────────────────
  /// Opens the add/edit item sheet. Item prices depend on the customer
  /// (get_item_details needs `customer` + `selling_price_list`), so this
  /// refuses to open until one is set.
  Future<void> openItemSheet({SalesOrderItem? row, String? itemCode}) async {
    if (!isEditable || isItemSheetOpen.value || Get.isBottomSheetOpen == true) {
      return;
    }
    if (so.value!.customer.isEmpty) {
      const msg = 'Select a customer first — item prices depend on it.';
      banner.value = msg;
      GlobalSnackbar.error(message: msg);
      return;
    }
    if ((so.value!.sellingPriceList ?? '').isEmpty) {
      const msg = 'Select a price list first — item rates come from it.';
      banner.value = msg;
      GlobalSnackbar.error(message: msg);
      return;
    }
    Get.lazyPut<SalesOrderItemFormController>(
        () => SalesOrderItemFormController(),
        tag: kSoItemSheetTag, fenix: true);
    final ctrl = Get.find<SalesOrderItemFormController>(tag: kSoItemSheetTag);
    isItemSheetOpen.value = true;
    unawaited(ctrl.initialise(parent: this, row: row, itemCode: itemCode));
    await Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => SalesOrderItemFormSheet(scrollController: sc),
      ),
      isScrollControlled: true,
    );
    isItemSheetOpen.value = false;
    Get.delete<SalesOrderItemFormController>(tag: kSoItemSheetTag);
  }

  // ── Save ───────────────────────────────────────────────────────────────
  @override
  Future<void> saveDocument() async {
    final s = so.value;
    if (s == null || !isEditable) return;
    if (checkStaleAndBlock()) return;
    if (!isDirty.value && mode != 'new') return;
    if (isSaving.value) return;
    // `items` is reqd in the live meta, so a header-only draft can never save;
    // skip silently (autosave fires while the header is still being filled).
    if (!canSaveNow) return;

    final errors = validateOrder(s);
    if (errors.isNotEmpty) {
      final msg = errors.values.join('\n');
      banner.value = msg;
      _setSaveResult(SaveResult.error);
      GlobalSnackbar.error(message: msg);
      return;
    }
    banner.value = null;
    isSaving.value = true;
    // The exact document this request is sending. Header edits made via
    // setCustomer/setHeader while the request is in flight land in
    // `so.value` but must not be discarded when the response lands — see
    // `_applyPostSave`. Item mutations can't happen meanwhile: addItem/
    // updateItem/deleteItem all block while isSaving is true.
    final sent = s;
    try {
      final isNew = mode == 'new';
      final res = isNew
          ? await _provider.create(buildPayload(sent,
              reservationEnabled: reservationEnabled.value))
          : await _provider.update(
              sent.name,
              buildPayload(sent,
                  reservationEnabled: reservationEnabled.value));
      final data = (res.data is Map) ? res.data['data'] : null;
      if (res.statusCode == 200 && data is Map) {
        final saved = SalesOrder.fromJson(Map<String, dynamic>.from(data));
        if (isNew) {
          name = saved.name;
          mode = 'edit';
        }
        _applyPostSave(saved, sent);
        if (isNew) await startRealtimeSyncAfterCreate();
        await _refreshDocPerms();
        if ((saved.sellingPriceList ?? '').isNotEmpty) {
          unawaited(
              _storage.saveSoLastSellingPriceList(_email, saved.sellingPriceList!));
        }
        GlobalSnackbar.success(message: 'Sales Order saved');
        _setSaveResult(SaveResult.success);
      } else {
        _setSaveResult(SaveResult.error);
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      banner.value = ItemFormController.parseServerMessage(e.response?.data);
      _setSaveResult(SaveResult.error);
    } catch (e) {
      banner.value = e.toString();
      _setSaveResult(SaveResult.error);
    } finally {
      isSaving.value = false;
    }
  }

  // ── Submit / Cancel ─────────────────────────────────────────────────────
  Future<void> submitDocument() async {
    if (!canSubmit) return;
    final errors = validateOrder(so.value!);
    if (errors.isNotEmpty) {
      banner.value = errors.values.join('\n');
      return;
    }
    final ok = await GlobalDialog.confirm(
        title: 'Confirm',
        message: 'Permanently Submit $name?',
        confirmText: 'Yes',
        confirmColor: AppColors.blue600);
    if (ok != true) return;
    isSubmitting.value = true;
    banner.value = null;
    try {
      await _provider.submit(name);
      await fetchDocument();
      GlobalSnackbar.success(message: 'Sales Order $name submitted');
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      banner.value = ItemFormController.parseServerMessage(e.response?.data);
    } finally {
      isSubmitting.value = false;
    }
  }

  Future<void> cancelDocument() => _runAction(SoAction.cancel,
      confirm: 'Permanently Cancel $name?',
      call: () => _provider.cancel(name),
      done: 'Sales Order $name cancelled');

  /// Shared runner for cancel + lifecycle actions (Task 6 adds the others).
  Future<void> _runAction(
    SoAction a, {
    String? confirm,
    required Future<dynamic> Function() call,
    required String done,
  }) async {
    if (!actions.contains(a) || isActing.value != null) return;
    if (confirm != null) {
      final ok = await GlobalDialog.confirm(
          title: 'Confirm', message: confirm, confirmText: 'Yes',
          confirmColor: AppColors.red500);
      if (ok != true) return;
    }
    isActing.value = a.name;
    banner.value = null;
    try {
      await call();
      await fetchDocument();
      GlobalSnackbar.success(message: done);
    } on DioException catch (e) {
      final msg = ItemFormController.parseServerMessage(e.response?.data);
      // Best-effort: a partial failure (e.g. hold's reason posted but the
      // status update threw) must still surface the true server state, not
      // whatever `so.value` held before this action ran. fetchDocument
      // never rethrows (it shows its own error dialog on failure), but the
      // wrap is defensive — either way the banner is set AFTER, so a
      // refetch can't clobber it.
      await _refetchBestEffort();
      banner.value = msg;
    } catch (e) {
      final msg = e.toString();
      await _refetchBestEffort();
      banner.value = msg;
    } finally {
      isActing.value = null;
    }
  }

  Future<void> _refetchBestEffort() async {
    try {
      await fetchDocument();
    } catch (_) {
      // Keep showing the previous document state; the banner set by the
      // caller right after this still reports the original failure.
    }
  }

  // ── Hold / Resume / Close / Re-open / Make Delivery Note ─────────────────
  String get _email =>
      Get.find<AuthenticationController>().currentUser.value?.email ?? '';

  /// Doc name whose "Reason for hold" comment has already been posted this
  /// session — set right after `addHoldReason` succeeds, cleared once the
  /// follow-up `updateStatus` also succeeds. Desk posts the comment before
  /// the status change, so if `updateStatus` throws the comment is already
  /// on the server; without this guard a retry would post it a second time.
  String? _holdReasonPostedFor;

  Future<void> hold() async {
    if (!actions.contains(SoAction.hold)) return;
    final reason = await showHoldReasonSheet();
    if (reason == null || reason.isEmpty) return;
    await _runAction(SoAction.hold,
        call: () async {
          if (_holdReasonPostedFor != name) {
            await _provider.addHoldReason(name, reason, _email);
            _holdReasonPostedFor = name;
          }
          await _provider.updateStatus(name, 'On Hold');
          _holdReasonPostedFor = null;
        },
        done: 'Sales Order $name put on hold');
  }

  Future<void> resume() => _runAction(SoAction.resume,
      call: () => _provider.updateStatus(name, 'Draft'),
      done: 'Sales Order $name resumed');

  Future<void> close() => _runAction(SoAction.close,
      confirm: 'Close $name? It will stop counting as pending delivery.',
      call: () => _provider.updateStatus(name, 'Closed'),
      done: 'Sales Order $name closed');

  Future<void> reopen() => _runAction(SoAction.reopen,
      call: () => _provider.updateStatus(name, 'Draft'),
      done: 'Sales Order $name re-opened');

  /// Stock Settings' enable_stock_reservation, resolved once per form.
  /// False until the probe answers, so the control stays hidden (desk hides
  /// it too when the setting is off).
  final reservationEnabled = false.obs;

  final isMakingDn = false.obs;

  Future<void> makeDeliveryNote() async {
    if (!actions.contains(SoAction.makeDn) || isActing.value != null) return;
    isActing.value = SoAction.makeDn.name;
    isMakingDn.value = true;
    banner.value = null;
    try {
      final dn = await _provider.makeDeliveryNote(name);
      Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
          arguments: {'name': dn, 'mode': 'edit'});
    } on DioException catch (e) {
      banner.value = ItemFormController.parseServerMessage(e.response?.data);
    } catch (e) {
      banner.value = e.toString();
    } finally {
      isActing.value = null;
      isMakingDn.value = false;
    }
  }

  Future<void> confirmDiscard() async => GlobalDialog.showUnsavedChanges(
        onDiscard: () {
          isDirty.value = false;
          Get.back();
        },
      );
}
