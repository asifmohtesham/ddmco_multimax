import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/core/widgets/sheet_status_bar_gap.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/controller_feedback_mixin.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_checker.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';
import 'package:multimax/app/shared/item_sheet/rack_warehouse_resolver.dart';
import 'package:multimax/app/shared/item_sheet/rack_warehouse_rule.dart';
import 'package:multimax/app/shared/item_sheet/widgets/rack_warehouse_controls.dart';

// Child sheet controller
import 'delivery_note_item_form_controller.dart';
import 'so_pick.dart';
import 'widgets/voucher_assignment_sheet.dart';

class DeliveryNoteFormController extends GetxController
    with OptimisticLockingMixin, ControllerFeedbackMixin, RealtimeSyncMixin {
  final DeliveryNoteProvider  _provider          = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider     _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider           _apiProvider       = Get.find<ApiProvider>();
  final WorkOrderProvider     _woProvider        = Get.find<WorkOrderProvider>();
  final ScanService           _scanService       = Get.find<ScanService>();
  final DataWedgeService      _dataWedgeService  = Get.find<DataWedgeService>();

  final String  name = Get.arguments['name'];
  String        mode = Get.arguments['mode'];

  @override String get realtimeDoctype => 'Delivery Note';
  @override String get realtimeDocname => name;

  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];
  final String? posUploadNameArg  = Get.arguments['posUploadName'];

  /// Set when the DN is started from a Sales Order (Dashboard → Sales Order).
  final String? salesOrderNameArg = Get.arguments['salesOrderName'];

  // ── Document-level state ──────────────────────────────────────────────────
  var isLoading    = true.obs;
  var isScanning   = false.obs;
  var isAddingItem = false.obs;
  @override var isSaving = false.obs;
  @override var isDirty  = false.obs;
  String _originalJson = '';

  // ── Save result state machine ─────────────────────────────────────────────
  var saveResult     = SaveResult.idle.obs;
  Timer? _saveResultTimer;

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }

  var deliveryNote = Rx<DeliveryNote?>(null);
  var posUpload    = Rx<PosUpload?>(null);

  /// The Sales Order this DN is picked against. While set, only items on the
  /// order can be scanned and each row is capped at its line's open qty.
  var salesOrder   = Rx<SoPickContext?>(null);
  bool get isSoMode => salesOrder.value != null;

  /// Header from `make_delivery_note`, sent once when the new DN is created.
  Map<String, dynamic> _soHeader = const {};

  /// How this SO-bound DN relates to the order's POS Upload (Sales Voucher).
  /// See [SoUploadLink] for the po_no ⇔ voucher-serial invariant.
  final uploadLink = SoUploadLink.none.obs;
  final isAssigningVoucher = false.obs;

  /// The POS Upload the order points at (SO po_no), ML/KA only.
  String? get orderUploadName => SoPick.dnFamilyUpload(salesOrder.value?.poNo);

  final TextEditingController barcodeController = TextEditingController();
  var expandedItemCode = ''.obs;
  var expandedInvoice  = ''.obs;
  var itemFilter       = 'All'.obs;

  var recentlyAddedItemCode = ''.obs;
  var recentlyAddedSerial   = ''.obs;
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // ── Sheet-open + item-edit loading flags ──────────────────────────────────
  var isItemSheetOpen    = false.obs;
  var isLoadingItemEdit  = false.obs;
  var loadingForItemName = RxnString();

  // ── Warehouse ─────────────────────────────────────────────────────────────
  var warehouses           = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var setWarehouse         = RxnString();
  final warehouseWarning = ''.obs;
  final savedRackWarning = ''.obs;
  final warehouseConfirmation = WarehouseDivergenceConfirmation();
  final _savedRows = <String, DeliveryNoteItem>{};
  late final rackWarehouseResolver = RackWarehouseResolver(_apiProvider);

  String get company {
    final saved = deliveryNote.value?.company?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return Get.find<StorageService>().getCompany();
  }

  // ── Customer-level error ──────────────────────────────────────────────────
  var customerError = RxnString();

  // ── EAN scan context ──────────────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Persistent scan worker ────────────────────────────────────────────────
  Worker? _scanWorker;
  Worker? _warehouseWorker;

  // ── items convenience getter ──────────────────────────────────────────────
  List<DeliveryNoteItem> get items => deliveryNote.value?.items ?? [];

  @override
  bool get canAutoSave =>
      !warehouseConfirmation.isPending.value &&
      (mode != 'new' || items.isNotEmpty);

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    _warehouseWorker = ever(setWarehouse, (_) => checkForChanges());
    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    log('[DN:onInit] _scanWorker registered on DataWedgeService.scannedCode',
        name: 'DN');

    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
  }

  @override
  void onClose() {
    disposeRealtimeSync();
    _scanWorker?.dispose();
    _warehouseWorker?.dispose();
    _saveResultTimer?.cancel();
    disposeFeedback();
    log('[DN:onClose] _scanWorker disposed', name: 'DN');
    // barcodeController not disposed: see HomeController.onClose (use-after-dispose on logout).
    scrollController.dispose();
    super.onClose();
  }

  // ── Raw scan entry point ──────────────────────────────────────────────────
  void _onRawScan(String code) {
    if (code.isEmpty) return;
    if (Get.currentRoute != AppRoutes.DELIVERY_NOTE_FORM) return;
    if (isItemSheetOpen.value) return;
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
  }


  // ── PopScope ──────────────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Dirty tracking ────────────────────────────────────────────────────────
  void checkForChanges() {
    if (deliveryNote.value == null) return;
    if (mode == 'new') {
      isDirty.value = !(isSoMode && items.isEmpty);
      if (canAutoSave) scheduleAutoSave();
      return;
    }
    if (deliveryNote.value?.docstatus != 0) { isDirty.value = false; return; }
    final tempNote = DeliveryNote(
      name:         deliveryNote.value!.name,
      customer:     deliveryNote.value!.customer,
      grandTotal:   deliveryNote.value!.grandTotal,
      postingDate:  deliveryNote.value!.postingDate,
      modified:     deliveryNote.value!.modified,
      creation:     deliveryNote.value!.creation,
      status:       deliveryNote.value!.status,
      currency:     deliveryNote.value!.currency,
      items:        deliveryNote.value!.items,
      poNo:         deliveryNote.value!.poNo,
      totalQty:     deliveryNote.value!.totalQty,
      docstatus:    deliveryNote.value!.docstatus,
      setWarehouse: setWarehouse.value,
      setTargetWarehouse: deliveryNote.value!.setTargetWarehouse,
      company: deliveryNote.value!.company,
    );
    isDirty.value = jsonEncode(tempNote.toJson()) != _originalJson;
    if (isDirty.value) scheduleAutoSave();
  }

  void _updateOriginalState(DeliveryNote note) {
    _originalJson = jsonEncode(note.toJson());
    _savedRows
      ..clear()
      ..addEntries(note.items.where((row) => row.name != null).map(
        (row) => MapEntry(row.name!, row),
      ));
    isDirty.value = false;
  }

  // ── Data fetching ─────────────────────────────────────────────────────────
  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList(
          'Warehouse', filters: {'is_group': 0, 'disabled': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      log('[DN:fetchWarehouses] error: $e', name: 'DN');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  void _createNewDeliveryNote() async {
    isLoading.value = true;
    final now = DateTime.now();
    deliveryNote.value = DeliveryNote(
      name:        'New Delivery Note',
      customer:    posUploadCustomer ?? '',
      grandTotal:  0.0,
      postingDate: now.toString().split(' ')[0],
      modified:    '',
      creation:    now.toString(),
      status:      'Draft',
      currency:    'AED',
      items:       [],
      poNo:        posUploadNameArg,
      totalQty:    0.0,
      docstatus:   0,
      setWarehouse: '',
    );
    if (posUploadNameArg != null && posUploadNameArg!.isNotEmpty) {
      await fetchPosUpload(posUploadNameArg!);
    }
    if (salesOrderNameArg != null && salesOrderNameArg!.isNotEmpty) {
      await _startFromSalesOrder(salesOrderNameArg!);
    }
    await _validateCustomerOnOpen();
    // An untouched SO-bound DN has nothing to lose; leaving it is not
    // "discarding changes".
    isDirty.value   = !(isSoMode && items.isEmpty);
    _originalJson   = '';
    isLoading.value = false;
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final note = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value  = note;
        setWarehouse.value  = note.setWarehouse;
        _updateOriginalState(note);
        warehouseWarning.value = '';
        savedRackWarning.value = '';
        final soName = note.items
            .map((i) => i.againstSalesOrder)
            .firstWhereOrNull((s) => s != null && s.isNotEmpty);
        if (soName != null) {
          await fetchSalesOrder(soName);
          await _resolveUploadLink();
        } else if (note.poNo != null && note.poNo!.isNotEmpty) {
          await fetchPosUpload(note.poNo!);
        }
        await _validateCustomerOnOpen();
        if (note.docstatus == 0) unawaited(_inspectSavedWarehouses(note));
      } else {
        showBanner('Failed to fetch delivery note', type: BannerType.error);
      }
    } catch (e) {
      showBanner('Failed to load data: $e', type: BannerType.error);
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
    isStale.value = false;
    showBanner('Document reloaded successfully', type: BannerType.success);
  }

  Future<void> fetchPosUpload(String posName) async {
    try {
      final response = await _posUploadProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
      }
    } catch (e) {
      log('[DN:fetchPosUpload] error: $e', name: 'DN');
    }
  }

  // ── Sales Order context ───────────────────────────────────────────────────
  Future<void> fetchSalesOrder(String soName) async {
    try {
      final res = await _apiProvider.getDocument('Sales Order', soName);
      if (res.statusCode == 200 && res.data['data'] != null) {
        // Rows without a header warehouse ship from their SO line's.
        salesOrder.value = SoPickContext.fromSalesOrder(
            Map<String, dynamic>.from(res.data['data']));
      }
    } catch (e) {
      log('[DN:fetchSalesOrder] error: $e', name: 'DN');
      showBanner('Could not load Sales Order $soName', type: BannerType.error);
    }
  }

  /// New DN from a Sales Order: header from ERPNext's own mapper (company,
  /// price list, taxes, addresses), items left empty so only what is
  /// actually scanned gets delivered.
  Future<void> _startFromSalesOrder(String soName) async {
    await fetchSalesOrder(soName);
    final so = salesOrder.value;
    if (so == null) return;
    try {
      final mapped = await _apiProvider.callMethodPost(
          'erpnext.selling.doctype.sales_order.sales_order.make_delivery_note',
          params: {'source_name': soName});
      final doc = (mapped.data as Map?)?['message'];
      if (doc is Map) {
        _soHeader = SoPick.headerFromMappedDn(Map<String, dynamic>.from(doc))
          // po_no is set by _resolveUploadLink only when it names a usable
          // upload — never copied blindly from the order.
          ..remove('po_no');
      }
    } catch (e) {
      log('[DN:_startFromSalesOrder] mapper error: $e', name: 'DN');
    }
    final wh = (_soHeader['set_warehouse'] as String?)?.isNotEmpty == true
        ? _soHeader['set_warehouse'] as String
        : so.commonWarehouse;
    setWarehouse.value = wh;
    deliveryNote.value = deliveryNote.value?.copyWith(
      customer: so.customer,
      currency: (_soHeader['currency'] as String?) ?? deliveryNote.value?.currency,
      setWarehouse: wh,
      company: _soHeader['company'] as String?,
    );
    await _resolveUploadLink();
  }

  // ── POS Upload (Sales Voucher) link ───────────────────────────────────────
  /// Works out how the DN relates to the order's POS Upload and loads it.
  /// An upload linked before any pick is adopted straight away; one linked
  /// after picking began needs every row assigned to a voucher line first.
  Future<void> _resolveUploadLink() async {
    final so = salesOrder.value;
    if (so == null) return;
    final dnPo = deliveryNote.value?.poNo?.trim() ?? '';
    final state = SoPick.uploadLink(
        soPoNo: so.poNo, dnPoNo: dnPo, hasRows: items.isNotEmpty);
    final upload = dnPo.isNotEmpty ? dnPo : orderUploadName;
    uploadLink.value = state;

    switch (state) {
      case SoUploadLink.none:
        posUpload.value = null;
      case SoUploadLink.wrongFamily:
        posUpload.value = null;
        showBanner(
            '${so.poNo} is a Stock Entry upload (MX/KX), so it cannot be '
            "delivered on a Delivery Note. Correct the Sales Order's "
            "Customer's PO.",
            type: BannerType.error);
      case SoUploadLink.linked:
        await fetchPosUpload(upload!);
        if (dnPo.isEmpty) {
          // Nothing picked yet: adopt the upload now (saved with row one).
          deliveryNote.value = deliveryNote.value?.copyWith(poNo: upload);
        }
      case SoUploadLink.pendingAssignment:
        await fetchPosUpload(upload!);
        final lines = posUpload.value?.items ?? const [];
        if (lines.length == 1) {
          // One voucher line: every row can only belong to it.
          await applyVoucherAssignment(
              {for (var i = 0; i < items.length; i++) i: lines.single.idx});
        }
    }
  }

  /// True (after telling the operator) while rows still need voucher lines.
  bool _blockedByPendingAssignment() {
    if (uploadLink.value != SoUploadLink.pendingAssignment) return false;
    HapticFeedback.mediumImpact();
    GlobalSnackbar.warning(
        title: 'Assign voucher lines first',
        message: 'POS Upload ${orderUploadName ?? ''} is now linked to this '
            'order. Assign each picked row to its voucher line.');
    return true;
  }

  /// Voucher line qty by line number (POS Upload Item idx).
  Map<int, double> get voucherLineQty => {
        for (final l in posUpload.value?.items ?? const <PosUploadItem>[])
          l.idx: l.quantity.toDouble(),
      };

  /// Sets each row's invoice serial to its voucher line ([assignment]: row
  /// index → line idx), then links the upload by writing the DN's po_no and
  /// saves. Returns an error message instead when lines would be overfilled.
  Future<String?> applyVoucherAssignment(Map<int, int> assignment) async {
    if (isAssigningVoucher.value) return null;
    if (isSaving.value) return 'Wait for the delivery note to finish saving.';
    final upload = orderUploadName;
    final note = deliveryNote.value;
    if (upload == null || note == null) return 'No POS Upload to link.';
    if (assignment.length != note.items.length) {
      return 'Assign every row to a voucher line.';
    }
    final over = SoPick.overAllocatedLines(
      [
        for (final e in assignment.entries)
          (serial: e.value, qty: note.items[e.key].qty),
      ],
      voucherLineQty,
    );
    if (over.isNotEmpty) {
      final lines = over.entries
          .map((e) => '#${e.key} by ${_fmtQty(e.value)}')
          .join(', ');
      return 'Voucher line over-filled: $lines. Reduce or reassign rows.';
    }
    isAssigningVoucher.value = true;
    try {
      final rows = [
        for (var i = 0; i < note.items.length; i++)
          note.items[i].copyWith(
              customInvoiceSerialNumber: assignment[i].toString()),
      ];
      deliveryNote.value = note.copyWith(poNo: upload, items: rows);
      uploadLink.value = SoUploadLink.linked;
      isDirty.value = true;
      await saveDocument();
      return null;
    } finally {
      isAssigningVoucher.value = false;
    }
  }

  Future<void> openVoucherAssignment() async {
    final upload = orderUploadName;
    final lines = posUpload.value?.items ?? const <PosUploadItem>[];
    if (upload == null || lines.isEmpty) {
      GlobalSnackbar.error(message: 'POS Upload has no lines to assign to.');
      return;
    }
    await Get.bottomSheet(
      VoucherAssignmentSheet(
        uploadName: upload,
        rows: List.of(items),
        lines: lines,
        busy: isAssigningVoucher,
        onConfirm: applyVoucherAssignment,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  static String _fmtQty(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  /// Open qty left on [line] given the rows already in this DN.
  double soRemainingFor(SoPickLine line, {String? excludeRowName}) =>
      SoPick.remainingFor(line, items, excludeRowName: excludeRowName);

  SoPickProgress get soProgress =>
      SoPick.progress(salesOrder.value?.lines ?? const [], items);

  /// SO line the scanned item goes to, or null after telling the operator
  /// why it can't be picked.
  SoPickLine? _resolveSoLineOrWarn(String itemCode, String itemName) {
    final so = salesOrder.value;
    if (so == null) return null;
    final r = SoPick.resolveLine(so.lines, itemCode, items);
    switch (r.outcome) {
      case SoPickOutcome.ok:
        return r.line;
      case SoPickOutcome.notOnOrder:
        HapticFeedback.heavyImpact();
        GlobalSnackbar.error(
            title: 'Not on this order',
            message: '$itemName ($itemCode) is not on ${so.name}.');
        return null;
      case SoPickOutcome.fullyPicked:
        HapticFeedback.mediumImpact();
        GlobalSnackbar.warning(
            title: 'Already picked',
            message: 'All of $itemCode on ${so.name} is already picked.');
        return null;
    }
  }

  /// The SO line that a new item sheet for [itemCode] binds to.
  SoPickLine? pendingSoLine;

  // ── POS qty-cap helpers ───────────────────────────────────────────────────
  double posQtyCapForSerial(String serial) {
    final idx = int.tryParse(serial);
    if (idx == null || posUpload.value == null) return double.infinity;
    return posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == idx)
            ?.quantity ??
        double.infinity;
  }

  double scannedQtyForSerial(String serial, {String? excludeItemName}) {
    return (deliveryNote.value?.items ?? [])
        .where((i) {
          return (i.customInvoiceSerialNumber) == serial &&
              (excludeItemName == null || i.name != excludeItemName);
        })
        .fold(0.0, (sum, i) {
          debugPrint('i.qty: ${i.qty}');
          return sum + i.qty;
        });
  }

  double remainingQtyForSerial(String serial) {
    final cap = posQtyCapForSerial(serial);
    if (cap == double.infinity) return double.infinity;
    final used = scannedQtyForSerial(serial);
    return (cap - used).clamp(0.0, cap);
  }

  // ── Item sheet orchestration ──────────────────────────────────────────────
  Future<void> _openItemSheet({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  variantOf,
    DeliveryNoteItem? editingItem,
  }) async {
    if (isSaving.value || checkStaleAndBlock()) return;
    if (editingItem != null) {
      if (editingItem.batchNo != null && editingItem.batchNo!.contains('-')) {
        currentScannedEan = editingItem.batchNo!.split('-').first;
      } else {
        currentScannedEan = '';
      }
    }

    final child = Get.put(
      DeliveryNoteItemFormController(),
      permanent: true,
    );
    child.initialise(
      parent:      this,
      code:        itemCode,
      name:        itemName,
      batchNo:     batchNo,
      variantOf:   variantOf ?? editingItem?.customVariantOf,
      scannedEan8: currentScannedEan,
      editingItem: editingItem,
    );

    isItemSheetOpen.value = true;
    child.initBarcodeListener();
    await Get.bottomSheet(
      UniversalItemFormSheet(
        controller:       child,
        scrollController: child.sheetScrollController,
        customFields: [
          _CheckWoButton(
            itemCode: itemCode,
            fetchWorkOrders: () => fetchWorkOrdersForItem(itemCode),
          ),
          // Commit 4: migrated from SharedSerialField to
          // SharedInvoiceSerialNumberField (delegate-driven, zero coupling).
          SharedInvoiceSerialNumberField(c: child),
          SharedBatchField(
            c:               child,
            editMode:        true,
            onPickerTap:     child.openBatchPicker,
            balanceOverride: () => child.batchBalance.value,
          ),
          Obx(() => RowWarehouseField(
                label: 'Warehouse',
                value: child.resolvedWarehouse,
                company: company,
                onChanged: child.selectWarehouse,
              )),
          SharedRackField(
            c: child,
            label: 'Source Rack',
            editMode: true,
            balanceOverride: () => child.rackBalance.value,
            checkingWarehouse: () => child.isCheckingRackWarehouse.value,
            onPickerTap: child.pickRack,
          ),
          Obx(() => RackWarehouseActions(
                verdict: child.rackWarehouseVerdict.value,
                onChooseRack: child.pickRack,
                onUseRackWarehouse: child.useRackWarehouse,
                onRetry: child.retryRack,
              )),
          if (child.hasTargetSide) ..._targetRackFields(child),
        ],
        onSubmit: () async {
          final ok = await child.submitWithFeedback();
          if (ok) Get.back();
        },
      ),
      isScrollControlled: true,
      enableDrag:         false,
      isDismissible:      false,
      backgroundColor:    Colors.transparent,
    );
    child.disposeBarcodeListener();
    child.endValidationSession();
    isItemSheetOpen.value = false;
    pendingSoLine = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      child.disposeControllers();
      Get.delete<DeliveryNoteItemFormController>(force: true);
      log('[DN:_openItemSheet] post-frame teardown complete', name: 'DN');
    });
  }

  List<Widget> _targetRackFields(DeliveryNoteItemFormController child) => [
    if (child.targetRackApplicable)
      Obx(() => RowWarehouseField(
            label: 'Target Warehouse',
            value: child.targetWarehouse.value,
            company: company,
            onChanged: child.selectTargetWarehouse,
          )),
    Builder(
      builder: (context) => Obx(() {
        final message = child.targetRackMessage;
        final checking = child.isCheckingTargetRack.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Focus(
              onFocusChange: (focused) => child.targetRackHasFocus = focused,
              child: ValidatedRackField(
                textController: child.targetRackController,
                isValid: child.targetRackValid,
                isValidating: checking,
                labelText: 'Target Rack',
                hintText: 'Enter target rack ID',
                color: Theme.of(context).colorScheme.primary,
                onEdit: child.unlockTargetRack,
                onReset: child.clearTargetRack,
                onValidate: () => child.validateTargetRack(
                  child.targetRackController.text,
                ),
                onSubmitted: child.validateTargetRack,
                onPickerTap:
                    child.targetRackApplicable ? child.pickTargetRack : null,
              ),
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  message,
                  style: TextStyle(
                    color: checking
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (child.targetRackVerdict.value?.issue == RackPairIssue.inapplicable)
              TextButton(
                onPressed: child.clearTargetRack,
                child: const Text('Clear rack'),
              ),
            RackWarehouseActions(
              verdict: child.targetRackVerdict.value,
              onChooseRack: child.targetRackApplicable ? child.pickTargetRack : null,
              onUseRackWarehouse:
                  child.targetRackApplicable ? child.useTargetRackWarehouse : null,
              onRetry: () => child.validateTargetRack(child.targetRackController.text),
            ),
          ],
        );
      }),
    ),
  ];

  void _handleCustomerNotFound(String customer) {
    customerError.value = 'Customer not found in the system';
    GlobalDialog.showCustomerNotFound(customer: customer);
  }

  Future<void> _validateCustomerOnOpen() async {
    final customer = deliveryNote.value?.customer ?? '';
    if (customer.isEmpty) return;
    try {
      final response = await _apiProvider.getDocument('Customer', customer);
      if (response.statusCode != 200 || response.data['data'] == null) {
        _handleCustomerNotFound(customer);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _handleCustomerNotFound(customer);
      }
      // Network/other errors: don't block the form; save will surface them.
    }
  }

  // ── Work Order lookup for item (Item #7A) ─────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchWorkOrdersForItem(String itemCode) async {
    try {
      final res = await _woProvider.getWorkOrders(
        filters: {
          'production_item': itemCode,
          'status': ['in', 'Not Started,In Process'],
        },
        limit: 5,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        return (res.data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  @override
  Future<void> saveDocument() async {
    if (isSaving.value ||
        warehouseConfirmation.isPending.value ||
        checkStaleAndBlock()) {
      return;
    }
    final note = deliveryNote.value;
    if (note == null || note.docstatus != 0) return;
    if (!canAutoSave) {
      showBanner('Add an item before saving.', type: BannerType.error);
      return;
    }

    final rows = List<DeliveryNoteItem>.of(note.items);
    final header = setWarehouse.value;
    isSaving.value = true;
    try {
      final checkedRows = await _validateDocumentRows(note, rows, header);
      if (isClosed) return;
      if (!identical(deliveryNote.value, note) ||
          setWarehouse.value != header ||
          !const ListEquality<DeliveryNoteItem>().equals(note.items, rows)) {
        _setSaveResult(SaveResult.error);
        showBanner(
          'The delivery note changed during validation. Save again.',
          type: BannerType.error,
        );
        return;
      }
      final payload = note.copyWith(items: checkedRows).toJson();
      if (mode == 'new' && _soHeader.isNotEmpty) {
        payload.addAll(_soHeader);
        payload['customer'] = note.customer;
      }
      payload['set_warehouse'] = header ?? '';
      if (mode == 'new') payload['company'] = company;

      Response response;
      if (mode == 'new') {
        response = await _apiProvider.createDocument('Delivery Note', payload);
      } else {
        response = await _apiProvider.updateDocument('Delivery Note', note.name, payload);
      }

      if (isClosed) return;
      if (response.statusCode == 200 && response.data['data'] != null) {
        final saved = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = saved;
        setWarehouse.value = saved.setWarehouse;
        _updateOriginalState(saved);
        unawaited(_inspectSavedWarehouses(saved, includeMixed: false));
        customerError.value = null;
        if (mode == 'new') {
          mode = 'edit';
          Get.parameters['mode'] = 'edit';
        }
        _setSaveResult(SaveResult.success);
      } else {
        _setSaveResult(SaveResult.error);
        showBanner('Failed to save delivery note', type: BannerType.error);
      }
    } on DioException catch (e) {
      if (isClosed) return;
      _setSaveResult(SaveResult.error);
      if (handleVersionConflict(e)) return;
      final int? statusCode = e.response?.statusCode;
      final String rawError = (() {
        final data = e.response?.data;
        if (data is Map) return data.toString();
        return data?.toString() ?? '';
      })();

      final bool isCustomerNotFound =
          (statusCode == 417 || statusCode == 400) &&
          (rawError.toLowerCase().contains('customer') ||
          rawError.toLowerCase().contains('does not exist') ||
          rawError.toLowerCase().contains('link validation'));

      if (isCustomerNotFound) {
        _handleCustomerNotFound(
            deliveryNote.value?.customer ?? posUploadCustomer ?? '');
      } else {
        final message = e.response?.data is Map
            ? (e.response!.data['exception'] ??
               e.response!.data['message'] ??
               'An unexpected error occurred.')
            : 'An unexpected error occurred.';
        showBanner(message.toString(), type: BannerType.error);
      }
    } on FormatException catch (e) {
      if (isClosed) return;
      _setSaveResult(SaveResult.error);
      showBanner(e.message, type: BannerType.error);
    } catch (e) {
      if (isClosed) return;
      _setSaveResult(SaveResult.error);
      showBanner('An unexpected error occurred: $e', type: BannerType.error);
    } finally {
      if (!isClosed) isSaving.value = false;
    }
  }

  static String? _warehouse(String? value) {
    final cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? effectiveWarehouse({
    String? row,
    String? salesOrder,
    String? header,
  }) => _warehouse(row) ?? _warehouse(salesOrder) ?? _warehouse(header);

  String? outboundWarehouse(DeliveryNoteItem row, {required String? header}) =>
      effectiveWarehouse(
        row: row.warehouse,
        salesOrder: salesOrder.value?.lineByDetail(row.soDetail)?.warehouse,
        header: header,
      );

  String? targetWarehouseFor(DeliveryNoteItem row) => effectiveWarehouse(
        row: row.targetWarehouse,
        header: deliveryNote.value?.setTargetWarehouse,
      );

  void changeHeaderWarehouse(String? warehouse) {
    final note = deliveryNote.value;
    final previous = setWarehouse.value;
    if (note == null || previous == warehouse || isSaving.value) return;
    final keptRows = [
      for (final row in note.items)
        row.copyWith(warehouse: outboundWarehouse(row, header: previous)),
    ];
    deliveryNote.value = note.copyWith(items: keptRows);
    setWarehouse.value = warehouse;
    final differences = keptRows.where(
      (row) => _warehouse(row.warehouse) != null && row.warehouse != warehouse,
    ).length;
    warehouseWarning.value = warehouse == null || warehouse.isEmpty
        ? (keptRows.isEmpty
            ? ''
            : 'Default warehouse cleared. Existing item rows keep their warehouses.')
        : (differences > 0
            ? 'Default warehouse changed to $warehouse. $differences existing rows use a different warehouse.'
            : '');
  }

  List<WarehouseDivergence> warehouseDifferences(
    DeliveryNoteItem row, {
    required int editingIndex,
  }) {
    final soLine = salesOrder.value?.lineByDetail(row.soDetail);
    final peers = [
      for (var i = 0; i < items.length; i++)
        if (i != editingIndex && items[i].itemCode.trim().isNotEmpty) items[i],
    ];
    return [
      WarehouseDivergence(
        side: RackSide.outbound,
        warehouse: outboundWarehouse(row, header: setWarehouse.value),
        header: setWarehouse.value,
        peers: peers.map((peer) => outboundWarehouse(peer, header: setWarehouse.value)),
        soWarehouse: soLine?.warehouse,
        soLine: soLine?.idx.toString(),
      ),
      if (targetWarehouseFor(row) != null)
        WarehouseDivergence(
          side: RackSide.target,
          warehouse: targetWarehouseFor(row),
          header: deliveryNote.value?.setTargetWarehouse,
          peers: peers.map(targetWarehouseFor),
        ),
    ];
  }

  bool canRetainSavedPair(DeliveryNoteItem row, RackSide side) {
    final saved = _savedRows[row.name];
    if (saved == null) return false;
    return _rackSnapshot(saved, side).canRetain(_rackSnapshot(row, side));
  }

  RackRowSnapshot _rackSnapshot(DeliveryNoteItem row, RackSide side) {
    final target = side == RackSide.target;
    return RackRowSnapshot(
      item: row.itemCode,
      batch: row.batchNo,
      rack: target ? row.toRack : row.rack,
      warehouse: target ? row.targetWarehouse : row.warehouse,
      applies: !target || targetWarehouseFor(row) != null,
      quantity: row.qty * ((row.conversionFactor ?? 0) > 0 ? row.conversionFactor! : 1),
    );
  }

  Future<RackPairVerdict> checkPair(
    RackSide side, {
    required String rack,
    required String? warehouse,
    bool applicable = true,
    bool initializeWarehouse = false,
  }) => rackWarehouseResolver.check(
        rack: rack,
        rowWarehouse: warehouse,
        company: company,
        side: side,
        applicable: applicable,
        initializeWarehouse: initializeWarehouse,
      );

  Future<List<DeliveryNoteItem>> _validateDocumentRows(
    DeliveryNote note,
    List<DeliveryNoteItem> rows,
    String? header,
  ) => Future.wait([
    for (var i = 0; i < rows.length; i++)
      _validateDocumentRow(rows[i], i + 1, header, note.setTargetWarehouse),
  ]);

  Future<DeliveryNoteItem> _validateDocumentRow(
    DeliveryNoteItem row,
    int index,
    String? header,
    String? targetHeader,
  ) async {
    final warehouse = outboundWarehouse(row, header: header);
    final target = effectiveWarehouse(row: row.targetWarehouse, header: targetHeader);
    final rack = row.rack?.trim() ?? '';
    final toRack = row.toRack?.trim() ?? '';
    if (rack.isEmpty && !canRetainSavedPair(row, RackSide.outbound)) {
      throw FormatException('Row $index: Scan or choose a rack');
    }
    final checks = await Future.wait([
      if (rack.isNotEmpty)
        checkPair(RackSide.outbound, rack: rack, warehouse: warehouse),
      if (toRack.isNotEmpty)
        checkPair(RackSide.target, rack: toRack, warehouse: target, applicable: target != null),
    ]);
    for (final verdict in checks) {
      if (!verdict.isValid && !canRetainSavedPair(row, verdict.side)) {
        final reason = _savedRows.containsKey(row.name) &&
                _rackSnapshot(_savedRows[row.name]!, verdict.side)
                    .canRetain(_rackSnapshot(row.copyWith(qty: 0), verdict.side))
            ? verdict.savedMessage
            : verdict.message;
        throw FormatException('Row $index: $reason');
      }
    }
    final outboundVerdict = rack.isEmpty ? null : checks.first;
    final targetVerdict = toRack.isEmpty ? null : checks.last;
    return row.copyWith(
      warehouse: outboundVerdict?.isValid == false ? null : warehouse,
      rack: outboundVerdict?.isValid == true ? outboundVerdict!.rack : null,
      targetWarehouse: targetVerdict?.isValid == false ? null : target,
      toRack: targetVerdict?.isValid == true ? targetVerdict!.rack : null,
    );
  }

  Future<void> _inspectSavedWarehouses(
    DeliveryNote note, {
    bool includeMixed = true,
  }) async {
    final warnings = <String>[];
    for (final side in includeMixed ? [RackSide.outbound, RackSide.target] : <RackSide>[]) {
      final target = side == RackSide.target;
      final header = target ? note.setTargetWarehouse : note.setWarehouse;
      if (_warehouse(header) != null) continue;
      final warehouses = {
        for (final row in note.items)
          target ? targetWarehouseFor(row) : outboundWarehouse(row, header: header),
      }.whereType<String>().toList()..sort();
      if (warehouses.length > 1) {
        warnings.add('Item rows use more than one ${side.label}. Review ${warehouses.join(', ')}.');
      }
    }
    final exceptions = await Future.wait([
      for (var i = 0; i < note.items.length; i++)
        for (final side in [RackSide.outbound, RackSide.target])
          _inspectSavedRack(note.items[i], i + 1, side),
    ]);
    if (isClosed || !identical(deliveryNote.value, note)) return;
    if (includeMixed) warehouseWarning.value = warnings.join('\n');
    savedRackWarning.value = exceptions.whereType<String>().join('\n');
  }

  Future<String?> _inspectSavedRack(
    DeliveryNoteItem row,
    int index,
    RackSide side,
  ) async {
    final target = side == RackSide.target;
    final rack = (target ? row.toRack : row.rack)?.trim() ?? '';
    if (rack.isEmpty) return null;
    final warehouse = target
        ? targetWarehouseFor(row)
        : outboundWarehouse(row, header: setWarehouse.value);
    final verdict = await checkPair(
      side,
      rack: rack,
      warehouse: warehouse,
      applicable: !target || warehouse != null,
    );
    return verdict.isValid ? null : 'Row $index: ${verdict.savedMessage}';
  }

  bool _validateHeaderBeforeScan() {
    final note = deliveryNote.value;
    if (note == null) {
      GlobalSnackbar.error(message: 'Delivery note not loaded yet.');
      return false;
    }
    if (note.customer.isEmpty) {
      customerError.value = 'Customer is required before scanning.';
      GlobalSnackbar.error(
          message: 'Please set a customer before scanning items.');
      return false;
    }
    customerError.value = null;
    return true;
  }

  Future<void> scanBarcode(String barcode) async {
    if (!_validateHeaderBeforeScan()) return;
    if (_blockedByPendingAssignment()) return;
    if (isScanning.value || isAddingItem.value) return;
    if (barcode.isEmpty) return;

    final cleanBarcode = barcode.trim();
    isScanning.value = true;

    try {
      final result = await _scanService.processScan(cleanBarcode);

      switch (result.type) {
        case ScanType.item:
          currentScannedEan = result.rawCode;
          await _handleScanResult(result);
          break;
        case ScanType.batch:
          currentScannedEan = '';
          await _handleScanResult(result);
          break;
        case ScanType.multiple:
          isScanning.value = false;
          await _showMultipleMatchSheet(result.candidates ?? []);
          break;
        case ScanType.rack:
        case ScanType.variant_of:
        case ScanType.unknown:
        case ScanType.error:
          GlobalSnackbar.error(
            message: 'Item not found for barcode: $cleanBarcode',
          );
          break;
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan error: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  Future<void> _handleScanResult(ScanResult result) async {
    isScanning.value = false;
    if (isSoMode) {
      final line = _resolveSoLineOrWarn(result.itemCode!,
          result.itemData?.itemName ?? result.itemCode!);
      if (line == null) return;
      pendingSoLine = line;
    }
    await _openItemSheet(
      itemCode:  result.itemCode!,
      itemName:  result.itemData?.itemName ?? result.itemCode!,
      batchNo:   result.batchNo,
      variantOf: result.itemData?.variantOf,
    );
  }

  Future<void> _showMultipleMatchSheet(List<Item> candidates) async {
    if (isSoMode) {
      final codes = salesOrder.value!.lines
          .map((l) => l.itemCode.trim().toLowerCase())
          .toSet();
      final onOrder = candidates
          .where((c) => codes.contains(c.itemCode.trim().toLowerCase()))
          .toList();
      if (onOrder.isEmpty) {
        GlobalSnackbar.error(
            title: 'Not on this order',
            message: 'None of the matching items are on ${salesOrder.value!.name}.');
        return;
      }
      if (onOrder.length == 1) {
        final item = onOrder.single;
        final line = _resolveSoLineOrWarn(item.itemCode, item.itemName);
        if (line == null) return;
        pendingSoLine = line;
        await _openItemSheet(
          itemCode:  item.itemCode,
          itemName:  item.itemName,
          variantOf: item.variantOf,
        );
        return;
      }
      candidates = onOrder;
    }
    await Get.bottomSheet(
      _MultipleMatchSheet(candidates: candidates, parent: this),
      isScrollControlled: true,
    );
  }

  // ── Item CRUD ─────────────────────────────────────────────────────────────
  Future<void> addItem(DeliveryNoteItem newItem) async {
    deliveryNote.value?.items.add(newItem);
    deliveryNote.refresh();
    checkForChanges();
    recentlyAddedItemCode.value = newItem.itemCode;
    recentlyAddedSerial.value   = newItem.customInvoiceSerialNumber ?? '';
    Future.delayed(const Duration(seconds: 2), () {
      if (recentlyAddedItemCode.value == newItem.itemCode) {
        recentlyAddedItemCode.value = '';
      }
    });
    _scrollToItem(newItem.name ?? newItem.itemCode);
    if (mode == 'edit') await saveDocument();
  }

  Future<void> updateItem(DeliveryNoteItem updatedItem) async {
    final items = deliveryNote.value?.items ?? [];
    final idx   = items.indexWhere((i) => i.name == updatedItem.name);
    if (idx != -1) {
      items[idx] = updatedItem;
      deliveryNote.refresh();
      checkForChanges();
    }
    if (mode == 'edit') await saveDocument();
  }

  Future<void> deleteItem(DeliveryNoteItem item) async {
    if (isSaving.value || checkStaleAndBlock()) return;
    final confirmed = await GlobalDialog.confirm(
      title:        'Remove Item',
      message:      'Remove "${item.itemName}" from this delivery note?',
      confirmText:  'Remove',
      confirmColor: AppColors.red700,
      icon:         Icons.delete_outline,
    );
    if (confirmed != true || isSaving.value) return;
    final remaining = items.where((i) => i.name != item.name).toList();
    final reason = await batchOrderBreak(
      itemCode:     item.itemCode,
      rowWarehouse: item.warehouse,
      after:        remaining,
    );
    if (reason != null) {
      GlobalSnackbar.error(message: reason);
      return;
    }
    if (isClosed || isSaving.value || !items.contains(item)) return;
    deliveryNote.value?.items.remove(item);
    deliveryNote.refresh();
    checkForChanges();
    if (mode == 'edit') await saveDocument();
  }

  // ── Oldest stock first (docs/batch_age_validation.md) ─────────────────────

  /// The saved document's name, once it exists on the server. Its saved rows
  /// are then left out of the draft lookup in favour of the rows in memory.
  String? get batchAgeDocName =>
      mode == 'new' ? null : deliveryNote.value?.name;

  /// [rows] (default: this note's rows) for [itemCode], as the quantities the
  /// oldest-stock-first rule takes off the batch balances.
  List<BatchDraftLine> batchAgeLines(
    String itemCode, {
    Iterable<DeliveryNoteItem>? rows,
  }) {
    final code   = itemCode.trim().toLowerCase();
    final header = setWarehouse.value ?? '';
    return [
      for (final r in rows ?? items)
        if (r.itemCode.trim().toLowerCase() == code &&
            (r.batchNo ?? '').trim().isNotEmpty)
          BatchDraftLine(
            batchNo:   r.batchNo!.trim(),
            warehouse: outboundWarehouse(r, header: header) ?? '',
            qty: r.qty *
                ((r.conversionFactor ?? 0) > 0 ? r.conversionFactor! : 1),
          ),
    ];
  }

  /// Why this note's rows may not become [after], or null when they may.
  ///
  /// Reducing or removing an older-batch row frees that stock again, which
  /// would leave a newer batch of the same item on the note out of order.
  /// Skipped (no network) unless the note holds two batches of [itemCode].
  Future<String?> batchOrderBreak({
    required String itemCode,
    required String? rowWarehouse,
    required List<DeliveryNoteItem> after,
  }) async {
    final before = batchAgeLines(itemCode);
    if ({for (final l in before) l.batchNo}.length < 2) return null;

    final header = setWarehouse.value;
    final pickWarehouse = effectiveWarehouse(row: rowWarehouse, header: header);
    try {
      return await BatchAgeChecker.create().orderBreakReason(
        itemCode:      itemCode,
        pickWarehouse: pickWarehouse,
        linesBefore:   before,
        linesAfter:    batchAgeLines(itemCode, rows: after),
        ownDoctype:    'Delivery Note',
        ownDocName:    batchAgeDocName,
      );
    } catch (e) {
      log('[DN] batch order check failed: $e', name: 'DN');
      return 'Could not check for older stock. '
          'Check the connection and try again.';
    }
  }

  Future<void> editItem(DeliveryNoteItem item) async {
    if (isLoadingItemEdit.value) return;
    if (_blockedByPendingAssignment()) return;
    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;

    await _openItemSheet(
      itemCode:    item.itemCode,
      itemName:    item.itemName ?? item.itemCode,
      batchNo:     item.batchNo,
      editingItem: item,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    });
  }

  void _scrollToItem(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final globalKey = itemKeys[key];
      if (globalKey?.currentContext != null) {
        Scrollable.ensureVisible(
          globalKey!.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve:    Curves.easeInOut,
        );
      }
    });
  }

  void setFilter(String filter) => itemFilter.value = filter;

  int get allCount {
    if (isSoMode) return soProgress.totalLines;
    return posUpload.value?.items.length ??
        (deliveryNote.value?.items.length ?? 0);
  }

  int get pendingCount {
    if (isSoMode) {
      final p = soProgress;
      return p.totalLines - p.completeLines;
    }
    if (posUpload.value == null) return 0;
    return posUpload.value!.items.where((posItem) {
      final serial = posItem.idx.toString();
      final used   = groupedItems[serial]
              ?.fold(0.0, (s, i) => s + i.qty) ?? 0.0;
      return used < posItem.quantity;
    }).length;
  }

  int get completedCount {
    if (isSoMode) return soProgress.completeLines;
    if (posUpload.value == null) return 0;
    return posUpload.value!.items.where((posItem) {
      final serial = posItem.idx.toString();
      final used   = groupedItems[serial]
              ?.fold(0.0, (s, i) => s + i.qty) ?? 0.0;
      return used >= posItem.quantity;
    }).length;
  }

  Map<String, List<DeliveryNoteItem>> get groupedItems {
    final map = <String, List<DeliveryNoteItem>>{};
    for (final item in deliveryNote.value?.items ?? []) {
      final serial = item.customInvoiceSerialNumber ?? '0';
      map.putIfAbsent(serial, () => []).add(item);
    }
    return map;
  }

  void toggleExpand(String itemCode) {
    expandedItemCode.value =
        expandedItemCode.value == itemCode ? '' : itemCode;
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }
}

// ── Multiple-match sheet (private widget) ─────────────────────────────────────

class _MultipleMatchSheet extends StatelessWidget {
  const _MultipleMatchSheet({
    required this.candidates,
    required this.parent,
  });

  final List<Item> candidates;
  final DeliveryNoteFormController parent;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      margin: EdgeInsets.only(top: sheetStatusBarInset(context)),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Multiple Items Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Select the item you want to add:',
              style: TextStyle(color: scheme.textMuted),
            ),
            const SizedBox(height: 16),
            ...candidates.map((item) => ListTile(
                  title: Text(item.itemName),
                  subtitle: Text(item.itemCode),
                  onTap: () async {
                    Get.back();
                    if (parent.isSoMode) {
                      final line = parent._resolveSoLineOrWarn(
                          item.itemCode, item.itemName);
                      if (line == null) return;
                      parent.pendingSoLine = line;
                    }
                    await parent._openItemSheet(
                      itemCode:  item.itemCode,
                      itemName:  item.itemName,
                      variantOf: item.variantOf,
                    );
                  },
                )),
          ],
        ),
      ),
    );
  }
}

// ── Check WO button widget ─────────────────────────────────────────────────────
// Shows active Work Orders for the item directly in the DN item sheet.

class _CheckWoButton extends StatefulWidget {
  final String itemCode;
  final Future<List<Map<String, dynamic>>> Function() fetchWorkOrders;
  const _CheckWoButton({required this.itemCode, required this.fetchWorkOrders});

  @override
  State<_CheckWoButton> createState() => _CheckWoButtonState();
}

class _CheckWoButtonState extends State<_CheckWoButton> {
  bool _loading   = false;
  bool _expanded  = false;
  List<Map<String, dynamic>> _wos = [];

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final results = await widget.fetchWorkOrders();
    if (!mounted) return;
    setState(() {
      _loading  = false;
      _expanded = true;
      _wos      = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _expanded ? () => setState(() => _expanded = false) : _load,
          icon: _loading
              ? SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                )
              : Icon(_expanded ? Icons.expand_less : Icons.precision_manufacturing_outlined, size: 18),
          label: Text(_expanded ? 'Hide Work Orders' : 'Check Work Orders'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.accentText,
            side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
            visualDensity: VisualDensity.compact,
            textStyle: text.labelMedium,
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          if (_wos.isEmpty)
            Text('No active Work Orders for this item.',
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant))
          else
            ..._wos.map((wo) => _WoInfoTile(wo: wo, cs: cs, text: text)),
        ],
      ],
    );
  }
}

class _WoInfoTile extends StatelessWidget {
  final Map<String, dynamic> wo;
  final ColorScheme cs;
  final TextTheme text;
  const _WoInfoTile({required this.wo, required this.cs, required this.text});

  @override
  Widget build(BuildContext context) {
    final name   = wo['name']   as String? ?? '';
    final status = wo['status'] as String? ?? '';
    final qty    = (wo['qty']   as num?)?.toStringAsFixed(0) ?? '0';
    final done   = (wo['produced_qty'] as num?)?.toStringAsFixed(0) ?? '0';

    return InkWell(
      onTap: () => Get.toNamed(
        AppRoutes.WORK_ORDER_FORM,
        arguments: {'name': name, 'mode': 'view'},
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('$done / $qty  ·  $status',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
