import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';

// Shared base + mixins
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';

// Picker
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';

// Data layer
import 'package:multimax/app/data/providers/api_provider.dart';

// Domain model
import 'package:multimax/app/data/models/delivery_note_model.dart';

// Parent controller
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';

/// Item-level sheet controller for Delivery Note.
///
/// Commit 4 (SerialFieldMixin adoption):
///   - Replaced `with PosSerialMixin` with `with SerialFieldMixin`.
///   - Removed private _seedLiveRemaining() and _updateLiveRemaining();
///     both delegated to SerialFieldMixin.computeLiveRemaining().
///   - posItemQtyForSerial(String serial) replaces posItemQty getter;
///     delegates to _parent.posQtyCapForSerial(serial).
///   - sumQtyUsedForSerial(String serial) added; delegates to
///     _parent.scannedQtyForSerial() which walks items in-memory.
///   - savedQtyForRow(String rowId) added; looks up the item's saved qty
///     from _parent.items by name for edit-mode double-count prevention.
///   - effectiveMaxQty: replaced posItemQty with
///     posItemQtyForSerial(selectedSerial.value ?? '').
///
/// Group B fixes (on top of Commit 7):
///   B3 — deleteCurrentItem() called _parent.items.refresh() on a plain
///        List<DeliveryNoteItem>.  .refresh() does not exist on List;
///        replaced with _parent.deliveryNote.refresh() (the Rx wrapper).
///   B4 — submit() passed posQtyCap: _posQtyCap to the DeliveryNoteItem
///        constructor.  DeliveryNoteItem has no such field; argument removed.
///
/// Error E2 fix:
///   maybeAutoFillRack() overrides the AutoFillRackMixin method to inject
///   a preloadRackStockMap() step before autofill runs.
///
/// Commit 1 fix:
///   initForEdit() now seeds selectedSerial and preserves rackController
///   text so the sheet opens with the item's existing serial and rack
///   values pre-populated (Bugs 1 & 3 from the DN item-form discrepancy
///   report).
///
/// DN-6:
///   - initForEdit() serial seed guard relaxed.
///   - captureSerialSnapshot() called after selectedSerial is seeded.
///   - initForNewItem() also calls captureSerialSnapshot() for symmetry.
///
/// Commit 7 (SharedRackField universal refactor):
///   - canBrowseRacks overridden: returns true when itemCode is non-empty.
///   - browseRacks() overridden with the full RackPickerController lifecycle.
///
/// Commit 6 (QtyFieldWithPlusMinusDelegate wiring):
///   - effectiveMaxQty overrides base: min(batchBalance, rackBalance,
///     liveRemaining) — three-way minimum per Q4 spec.
///   - adjustQty clamps to effectiveMaxQty.
///   - validateSheet writes isQtyValid.value and qtyError.value.
///   - docStatus seeded in initForEdit / reset in initForNewItem.
///
/// fix(docstatus): read from parent document, not item row.
class DeliveryNoteItemFormController extends ItemSheetControllerBase
    with SerialFieldMixin, AutoFillRackMixin, BarcodeListenerMixin, BarcodeAwareMixin {

  // ── Parent back-reference ──────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  DeliveryNoteFormController get parent => _parent;

  // ── Local reactive state ───────────────────────────────────────────────────
  final RxString itemCodeRx       = ''.obs;
  final RxString itemNameRx       = ''.obs;
  final RxString itemUomRx        = ''.obs;
  final RxString itemGroupRx      = ''.obs;
  final RxString currentVariantOf = ''.obs;

  final RxBool isExistingItem = false.obs;
  final RxInt  editingIndex   = (-1).obs;

  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;

  // ── EAN-8 barcode context (for deprecated batch label reassembly) ──────────
  /// Stores the 8-digit EAN8 barcode of the current item, set at sheet-open
  /// time by initialise(). Used by handleScan to reassemble Batch No from
  /// deprecated SHIPMENT-* label formats.
  String _itemEan8 = '';
  String get itemEan8 => _itemEan8;

  // Also pass into initForNewItem and reset in initForEdit:
  // initForNewItem: _itemEan8 already set above, no param needed
  // initForEdit: _itemEan8 = item.batchNo?.split('-').first ?? '' (or keep from initialise)

  // ── Base abstract overrides ────────────────────────────────────────────────
  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;

  @override bool  get requiresBatch => true;
  @override bool  get requiresRack  => false;
  @override Color get accentColor   => Colors.blueGrey;

  @override
  bool get isAddMode => !isExistingItem.value;

  @override
  MobileScannerController? get sheetScanController => null;

  // ── qtyInfoText / qtyInfoTooltip ───────────────────────────────────────────
  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == double.infinity) return null;
    return 'Max: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── QtyFieldWithPlusMinusDelegate: effectiveMaxQty ────────────────────────
  // ── Private helper ────────────────────────────────────────────────────────
  /// Responsibility: apply a positive-only candidate to the running minimum.
  /// Returns [candidate] when [current] is null, the smaller value otherwise.
  /// Non-positive candidates are ignored (treated as "no constraint").
  double? _applyConstraint(double? current, double candidate) =>
      candidate > 0
          ? (current == null ? candidate : candidate.clamp(0, current))
          : current;

  // ── QtyFieldWithPlusMinusDelegate: effectiveMaxQty ────────────────────────
  @override
  double get effectiveMaxQty {
    double? ceil;
    ceil = _applyConstraint(ceil, batchBalance.value);
    ceil = _applyConstraint(ceil, rackBalance.value);
    if ((selectedSerial.value ?? '').isNotEmpty) {
      ceil = _applyConstraint(ceil, liveRemaining.value);
    }
    return ceil ?? double.infinity;
  }

  /// Returns true when:
  /// - No rack has been entered yet (permissive)
  /// - Rack validation is still in progress (don't block while fetching)
  /// - Rack has been validated and balance > 0
  /// Returns false only when rack validation is COMPLETE and balance ≤ 0.
  bool get _rackBalanceOk {
    final rack = rackController.text.trim();
    if (rack.isEmpty) return true;              // no rack entered
    if (isValidatingRack.value) return true;    // still fetching — don't block yet
    if (!isRackValid.value) return false;       // validation done, failed
    return rackBalance.value > 0;              // validation done, check balance
  }

  /// Returns true when:
  /// - No batch has been entered yet (permissive)
  /// - Batch validation is still in progress (don't block while fetching)
  /// - Batch has been validated and balance > 0
  /// Returns false only when batch validation is COMPLETE and balance ≤ 0.
  bool get _batchBalanceOk {
    final batch = batchController.text.trim();
    if (batch.isEmpty) return true;              // no batch entered
    if (isValidatingBatch.value) return true;    // still fetching — don't block yet
    if (!isBatchValid.value) return false;       // validation done, failed
    return batchBalance.value > 0;              // validation done, check balance
  }

  // ── SerialFieldMixin: posItemQtyForSerial override ────────────────────────
  /// Delegates to the parent controller's POS qty-cap lookup.
  /// The parent resolves serial (= idx string) → PosUploadItem.quantity.
  @override
  double posItemQtyForSerial(String serial) =>
      _parent.posQtyCapForSerial(serial);

  // ── SerialFieldMixin: sumQtyUsedForSerial override ────────────────────────
  /// Walks the parent document's in-memory items list synchronously.
  /// Excludes the row currently being edited to avoid double-counting
  /// (savedQtyForRow adds it back with the correct value).
  @override
  double sumQtyUsedForSerial(String serial, {String? excludeRowId}) {
    return _parent.deliveryNote.value?.items
        .where((i) =>
          i.customInvoiceSerialNumber == serial &&
          i.name != excludeRowId)
        .fold(0.0, (sum, i) => sum! + i.qty) ??
        0.0;
  }

  // ── SerialFieldMixin: savedQtyForRow override ─────────────────────────────
  /// Returns the already-saved qty of the row being edited.
  /// Used by computeLiveRemaining to undo the double-count exclusion
  /// performed by sumQtyUsedForSerial above, then subtract the live
  /// typed qty instead.
  @override
  double savedQtyForRow(String rowId) {
    final item = _parent.items.firstWhere(
      (i) => i.name == rowId,
      orElse: () => DeliveryNoteItem(
        itemCode: '', qty: 0.0, rate: 0.0,
      ),
    );
    return item.qty;
  }

  // ── adjustQty ──────────────────────────────────────────────────────────────
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, effectiveMaxQty);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem ──────────────────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    if (!isExistingItem.value || editingIndex.value < 0) return;
    _parent.deliveryNote.value?.items.removeAt(editingIndex.value);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_parent.isClosed) return;
      _parent.deliveryNote.refresh();
      _parent.checkForChanges();           // Mark document dirty
      if (_parent.mode == 'edit') {
        _parent.saveDeliveryNote();        // Execute PUT request
      }
    });
  }

  // ── SerialFieldMixin wiring ────────────────────────────────────────────────
  @override
  List<String> get availableSerialNos {
    final upload = _parent.posUpload.value;
    if (upload == null) return const [];
    return upload.items
        .map((e) => e.idx.toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── SerialFieldMixin: rich dropdown row metadata ──────────────────────────
  /// Resolves serial (= idx string) → PosUploadItem → SerialDropdownItem so
  /// the dropdown shows a two-line tile: item name + ×qty.
  ///
  /// Returns null when the parent has no POS Upload loaded or when the
  /// serial does not map to a known POS item — the widget falls back to the
  /// plain index badge in those cases.
  @override
  SerialDropdownItem? posDropdownItemFor(String serial) {
    final upload = _parent.posUpload.value;
    if (upload == null) return null;

    final idx = int.tryParse(serial);
    if (idx == null) return null;

    final posItem = upload.items.firstWhereOrNull((i) => i.idx == idx);
    if (posItem == null) return null;

    // Qty: POS Upload Item (1-based idx) quantity field.
    final cap = posItem.quantity.toDouble();

    // Used: sum of DN item qtys where custom_invoice_serial_number == serial.
    // sumQtyUsedForSerial already excludes the row being edited via
    // excludeItemName, so each dropdown row reflects committed-only used.
    // Used =
    final used = _parent.scannedQtyForSerial(
      serial,
      excludeItemName: editingItemName.value,  // exclude self when in edit mode
    );

    // Remaining (for isFull per-row): Qty − Used, independently per serial.
    // Do NOT add back editingQty here — that compensation is only needed
    // for liveRemaining (the badge on the selected serial), handled in
    // computeLiveRemaining via savedQtyForRow. Each dropdown row must show
    // its true remaining so isFull is correct for all rows, not just the
    // currently selected one.
    final remaining = cap - used;
    debugPrint('_parent.scannedQtyForSerial: $serial, $used / $cap, $remaining');

    return SerialDropdownItem(
      serial:   serial,
      itemName: posItem.itemName,
      qty:      cap,
      remaining: remaining,
      used:     used,
    );
  }

  // ── Legacy name aliases ────────────────────────────────────────────────────
  RxString get itemCodeValue  => itemCodeRx;
  RxString get itemNameValue  => itemNameRx;
  RxString get itemUomValue   => itemUomRx;
  RxString get itemGroupValue => itemGroupRx;

  // ── AutoFillRackMixin wiring ───────────────────────────────────────────────
  String  get mixinItemCode  => itemCode.value;
  String? get mixinWarehouse => resolvedWarehouse;
  String  get mixinBatch     => batchController.text;
  double  get mixinQty       => double.tryParse(qtyController.text) ?? 0.0;
  @override Map<String, double> get rackStockMap => Map<String, double>.from(rackStockMapRx);

  void onRackAutoFilled(String rackId) {
    rackController.text = rackId;
    validateRack(rackId);
  }

  // ── RackBrowseDelegate ─────────────────────────────────────────────────────
  @override
  bool get canBrowseRacks => itemCode.value.isNotEmpty;

  static const _kPickerTag = 'dn_rack_picker';

  @override
  Future<RackPickerResult?> browseRacks() async {
    if (!canBrowseRacks || isValidatingRack.value) return null;
    final ctx = Get.context;
    if (ctx == null) return null;

    final pickerCtrl = Get.put(RackPickerController(), tag: _kPickerTag);
    try {
      _triggerRackPickerLoad(pickerCtrl);
      final selectedRackId = await _presentRackSheet(ctx);
      if (selectedRackId == null || selectedRackId.isEmpty) return null;
      return _rackPickerResultFor(pickerCtrl, selectedRackId);
    } catch (e) {
      log('[DN-Item] browseRacks error: $e', name: 'DN-Item');
      return null;
    } finally {
      if (Get.isRegistered<RackPickerController>(tag: _kPickerTag)) {
        Get.delete<RackPickerController>(tag: _kPickerTag);
      }
    }
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: start the async rack-stock load on [pickerCtrl]
  /// without awaiting it — the sheet observes the reactive state directly.
  void _triggerRackPickerLoad(RackPickerController pickerCtrl) {
    unawaited(pickerCtrl.load(
      itemCode:     itemCode.value,
      batchNo:      batchController.text.trim(),
      warehouse:    resolvedWarehouse ?? '',
      requestedQty: double.tryParse(qtyController.text) ?? 0.0,
      currentRack:  rackController.text.trim(),
      fallbackMap:  Map<String, double>.from(rackStockMapRx),
    ));
  }

  /// Responsibility: show the [RackPickerSheet] modal and return the
  /// rack ID selected by the user, or null if dismissed.
  Future<String?> _presentRackSheet(BuildContext ctx) async {
    String? selectedRackId;
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RackPickerSheet(
        pickerTag: _kPickerTag,
        onSelected: (rack) => selectedRackId = rack,
      ),
    );
    return selectedRackId;
  }

  /// Responsibility: map [selectedRackId] to a [RackPickerResult] using
  /// the entry already loaded in [pickerCtrl], falling back to a zero-
  /// balance sentinel when no matching entry exists.
  RackPickerResult _rackPickerResultFor(
      RackPickerController pickerCtrl,
      String selectedRackId,
      ) {
    final entry = pickerCtrl.entries.firstWhere(
          (e) => e.rackName == selectedRackId,
      orElse: () => RackPickerEntry(
        rackName:     selectedRackId,
        location:     null,
        availableQty: 0.0,
        requestedQty: double.tryParse(qtyController.text) ?? 0.0,
      ),
    );
    return RackPickerResult(
      rackId:       entry.rackName,
      availableQty: entry.availableQty,
      warehouse:    entry.warehouseName,
      raw:          const {},
    );
  }


  // ── initialise() entry point ───────────────────────────────────────────────
  void initialise({
    required DeliveryNoteFormController parent,
    required String code,
    required String name,
    String?  batchNo,
    String?  scannedEan8,
    String?  variantOf,
    DeliveryNoteItem? editingItem,
  }) {
    _seedContext(parent: parent, scannedEan8: scannedEan8);

    if (editingItem != null) {
      _initEdit(item: editingItem, variantOf: variantOf);
    } else {
      _initNew(
        code:      code,
        name:      name,
        batchNo:   batchNo,
        variantOf: variantOf,
      );
    }
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: bind the parent back-reference and seed the EAN-8
  /// barcode context used by deprecated batch-label reassembly.
  void _seedContext({
    required DeliveryNoteFormController parent,
    String? scannedEan8,
  }) {
    _parent   = parent;
    _itemEan8 = scannedEan8 ?? '';
  }

  /// Responsibility: resolve the editing index from the parent's items list
  /// and route to [initForEdit].
  void _initEdit({
    required DeliveryNoteItem item,
    String? variantOf,
  }) {
    final items = _parent.deliveryNote.value?.items ?? [];
    final idx   = items.indexWhere((i) => i.name == item.name);
    initForEdit(
      index:     idx >= 0 ? idx : 0,
      item:      item,
      variantOf: variantOf ?? item.customVariantOf ?? '',
    );
  }

  /// Responsibility: build the new-item arguments and route to [initForNewItem].
  void _initNew({
    required String  code,
    required String  name,
    String?  batchNo,
    String?  variantOf,
  }) {
    initForNewItem(
      itemCode:  code,
      itemName:  name,
      uom:       'Nos',
      itemGroup: '',
      variantOf: variantOf ?? '',
      batchNo:   batchNo,
    );
  }

  // ── Lifecycle / init ───────────────────────────────────────────────────────
  void initForNewItem({
    required String itemCode,
    required String itemName,
    required String uom,
    required String itemGroup,
    String  variantOf = '',
    String? batchNo,
  }) {
    _seedNewItemModeFlags();
    _seedItemIdentity(
      itemCode:  itemCode,
      itemName:  itemName,
      uom:       uom,
      itemGroup: itemGroup,
      variantOf: variantOf,
    );
    _seedFieldControllers(batchNo: batchNo);
    _resetValidationState();
    _wireListenersAndSnapshot();

    if ((batchNo ?? '').isNotEmpty) {
      validateBatchOnInit(batchNo!);
    }
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: mark this sheet as an add-mode (non-editing) session
  /// and seed the doc-status from the live parent document.
  void _seedNewItemModeFlags() {
    isExistingItem.value  = false;
    editingIndex.value    = -1;
    editingItemName.value = null;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
  }

  /// Responsibility: write all item-identity reactive variables so the
  /// sheet widgets observe the correct item from the moment they build.
  void _seedItemIdentity({
    required String itemCode,
    required String itemName,
    required String uom,
    required String itemGroup,
    required String variantOf,
  }) {
    this.itemCode.value    = itemCode;
    itemCodeRx.value       = itemCode;
    itemNameRx.value       = itemName;
    itemUomRx.value        = uom;
    itemGroupRx.value      = itemGroup;
    currentVariantOf.value = variantOf;
  }

  /// Responsibility: pre-populate (or clear) the three text-field controllers
  /// so the user sees the correct starting values on sheet open.
  void _seedFieldControllers({String? batchNo}) {
    batchController.text = batchNo ?? '';
    rackController.clear();
    qtyController.clear();
  }

  /// Responsibility: reset every piece of validation state to a clean
  /// baseline — batch, rack, serial, live-remaining, qty error, and the
  /// transient rack-stock map.
  void _resetValidationState() {
    resetBatch();
    resetRack();
    // selectedSerial is intentionally NOT reset here.
    // - initForNewItem: serial is cleared in _seedFieldControllers() below.
    // - initForEdit:    serial is seeded in _resolveAndSeedSerial() AFTER
    //                   this method runs, so it must not be clobbered here.
    liveRemaining.value   = 0.0;
    rackStockMapRx.clear();
    isSheetValid.value = false;
    isQtyValid.value   = false;
    qtyError.value     = '';
  }

  /// Responsibility: tear down any stale listeners, attach fresh ones,
  /// then capture the baseline state snapshots that change-detection
  /// and serial-remaining logic depend on.
  void _wireListenersAndSnapshot() {
    removeSheetListeners();
    addSheetListeners();
    snapshotState();
    captureSerialSnapshot();
    // Seed the chip immediately with the correct remaining value so the
    // badge is accurate the moment the sheet opens — without waiting for
    // the user to change the qty field.
    _refreshLiveRemaining(qty: double.tryParse(qtyController.text));
  }

  void initForEdit({
    required int index,
    required DeliveryNoteItem item,
    String variantOf = '',
  }) {
    _seedEditModeFlags(index: index, item: item);
    _seedItemIdentityFromItem(item: item, variantOf: variantOf);

    final existingBatch = item.batchNo ?? '';
    final existingRack  = item.rack    ?? '';
    _seedEditFieldControllers(item: item);

    _seedLiveRemainingFromItem(item: item);
    _resetValidationState();
    // Re-seed rack text after _resetValidationState() which calls resetRack()
    // and clears rackController. The validation round-trip happens later in
    // _triggerEditValidations(), so the text must survive until then.
    rackController.text = existingRack;

    _resolveAndSeedSerial(item: item);
    _wireListenersAndSnapshot();

    _triggerEditValidations(
      existingBatch: existingBatch,
      existingRack:  existingRack,
    );
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: mark this sheet as an edit-mode session, record which
  /// index is being edited, and seed doc-status from the live parent document.
  void _seedEditModeFlags({
    required int index,
    required DeliveryNoteItem item,
  }) {
    isExistingItem.value  = true;
    editingIndex.value    = index;
    editingItemName.value = item.name;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
  }

  /// Responsibility: write all item-identity reactive variables from the
  /// existing [item] row so sheet widgets observe the correct values on open.
  void _seedItemIdentityFromItem({
    required DeliveryNoteItem item,
    required String variantOf,
  }) {
    this.itemCode.value    = item.itemCode;
    itemCodeRx.value       = item.itemCode;
    itemNameRx.value       = item.itemName  ?? '';
    itemUomRx.value        = item.uom       ?? '';
    itemGroupRx.value      = item.itemGroup ?? '';
    currentVariantOf.value = variantOf;
  }

  /// Responsibility: reset batch/rack validation state, then pre-populate
  /// the three text-field controllers with the item's persisted values.
  void _seedEditFieldControllers({required DeliveryNoteItem item}) {
    resetBatch();
    resetRack();
    batchController.text = item.batchNo ?? '';
    rackController.text  = item.rack    ?? '';
    qtyController.text   = item.qty.toString();
  }

  /// Responsibility: determine which serial number (if any) to pre-select
  /// in the dropdown — validating the persisted serial against the live
  /// availableSerialNos list and logging on mismatch.
  void _resolveAndSeedSerial({required DeliveryNoteItem item}) {
    final persistedSerial = item.customInvoiceSerialNumber;
    final serials         = availableSerialNos;

    // ── Primary path: persisted serial field is populated ────────────────────
    if (persistedSerial != null && persistedSerial.isNotEmpty) {
      if (serials.isEmpty || serials.contains(persistedSerial)) {
        selectedSerial.value = persistedSerial;
      } else {
        log(
          '[DN-Item] initForEdit: persisted serial "$persistedSerial" '
              'is not in availableSerialNos $serials — dropdown left unset.',
          name: 'DN-Item',
        );
        selectedSerial.value = null;
      }
      return;
    }

    // ── Fallback path: no persisted serial — leave unset ─────────────────────
    // Do NOT infer serial from editingIndex. The DN item list is NOT
    // guaranteed to be parallel to availableSerialNos: multiple items can
    // share the same idx position if serials were not persisted, and inferring
    // by position silently assigns the wrong serial (e.g. serial "7" to all
    // items), causing scannedQtyForSerial to sum all their qtys and report
    // Used: 372 instead of 12.
    selectedSerial.value = null;
    log(
      '[DN-Item] initForEdit: no persisted serial and no safe inference — '
          'serial left unset. User must select manually.',
      name: 'DN-Item',
    );

    selectedSerial.value = null;
  }

  /// Responsibility: seed liveRemaining at open time using the mixin formula
  /// so the remaining-qty badge is correct before the user types anything.
  void _seedLiveRemainingFromItem({required DeliveryNoteItem item}) {
    computeLiveRemaining(
      currentTypedQty: item.qty,
      editingRowId:    item.name,
    );
  }

  /// Responsibility: trigger batch and rack background-validation after the
  /// sheet is fully assembled. Rack validation is deferred to the next frame
  /// so the widget tree is mounted before the round-trip begins.
  void _triggerEditValidations({
    required String existingBatch,
    required String existingRack,
  }) {
    if (existingBatch.isNotEmpty) {
      validateBatchOnInit(existingBatch);
    }
    if (existingRack.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateRack(existingRack);
      });
    }
  }

  // ── Sheet validity ─────────────────────────────────────────────────────────
  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text);
    final ceil = effectiveMaxQty;

    _evaluateQtyValidity(qty: qty, ceil: ceil);
    _evaluateSheetValidity(
      qtyOk:  qty != null && qty > 0,
      ceilOk: ceil == double.infinity || (qty != null && qty <= ceil),
    );
    _refreshLiveRemaining(qty: qty);
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: determine whether the typed quantity is positive and
  /// within the effective ceiling, then write [isQtyValid] and [qtyError]
  /// with an appropriate message for each failure case.
  void _evaluateQtyValidity({required double? qty, required double ceil}) {
    // Gate on batch balance first — mirrors _rackBalanceOk pattern.
    if (!_batchBalanceOk) {
      isQtyValid.value = false;
      qtyError.value   = 'Batch has no available stock (balance: 0)';
      return;
    }

    // FIX: gate on rack balance first
    if (!_rackBalanceOk) {
      isQtyValid.value = false;
      qtyError.value   = 'No stock available in selected rack';
      return;
    }

    final qtyOk  = qty != null && qty > 0;
    final ceilOk = ceil == double.infinity || (qty != null && qty <= ceil);

    if (!qtyOk) {
      isQtyValid.value = false;
      qtyError.value   = qty == null ? '' : 'Enter a quantity greater than 0';
      return;
    }

    if (!ceilOk) {
      isQtyValid.value = false;
      qtyError.value   = 'Qty cannot exceed ${_formatQty(ceil)}';
      return;
    }

    isQtyValid.value = true;
    qtyError.value   = '';
  }

  /// Responsibility: combine batch validity with the qty flags to decide
  /// whether the sheet as a whole may be submitted.
  void _evaluateSheetValidity({required bool qtyOk, required bool ceilOk}) {
    // Added _batchBalanceOk alongside existing _rackBalanceOk gate.
    isSheetValid.value =
        isBatchValid.value && _batchBalanceOk && _rackBalanceOk && qtyOk && ceilOk;
  }

  /// Responsibility: recompute and publish the live-remaining badge so the
  /// UI reflects the current typed quantity without waiting for a rebuild.
  void _refreshLiveRemaining({required double? qty}) {
    computeLiveRemaining(
      currentTypedQty: qty ?? 0.0,
      editingRowId:    editingItemName.value,
    );
  }

  /// Formats a qty ceiling for display — no decimal places when the value
  /// is a whole number, two decimal places otherwise.
  String _formatQty(double value) =>
      value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);

  // ── submit ─────────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = _assertSubmitPreconditions();
    final item = _buildItem(qty: qty);
    _commitToParent(item: item);
    _scheduleParentRefresh();
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: assert that the sheet is in a submittable state.
  /// Throws a descriptive [Exception] on the first failing precondition.
  /// Returns the parsed qty so callers do not re-parse.
  double _assertSubmitPreconditions() {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Enter a valid quantity');
    if (!isBatchValid.value)     throw Exception('Batch validation required');
    return qty;
  }

  /// Responsibility: construct a [DeliveryNoteItem] from the current
  /// reactive field state. Normalises optional fields (rack, variantOf)
  /// to null when blank.
  DeliveryNoteItem _buildItem({required double qty}) {
    final rack      = rackController.text.trim();
    final variantOf = currentVariantOf.value.trim();

    return DeliveryNoteItem(
      itemCode:                  itemCode.value,
      itemName:                  itemNameRx.value,
      uom:                       itemUomRx.value,
      qty:                       qty,
      rate:                      0.0,
      batchNo:                   batchController.text.trim(),
      rack:                      rack.isEmpty      ? null : rack,
      itemGroup:                 itemGroupRx.value,
      customVariantOf:           variantOf.isEmpty ? null : variantOf,
      customInvoiceSerialNumber: selectedSerial.value,
    );
  }

  /// Responsibility: write [item] into the parent document's items list —
  /// replacing the row at [editingIndex] for edits, appending for new items.
  void _commitToParent({required DeliveryNoteItem item}) {
    final items = _parent.deliveryNote.value?.items;
    if (items == null) return;

    if (isExistingItem.value && editingIndex.value >= 0) {
      items[editingIndex.value] = item;
    } else {
      items.add(item);
    }
  }

  /// Responsibility: defer the Rx rebuild to the next frame so the sheet's
  /// exit animation completes before the parent list re-renders.
  void _scheduleParentRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_parent.isClosed) return;
      if (isClosed) return;   // ← ADD THIS
      _parent.deliveryNote.refresh();
      _parent.checkForChanges();
      debugPrint('_scheduleParentRefresh');
      notifySerialItemsChanged();
      if (_parent.mode == 'edit') {
        _parent.saveDeliveryNote();
      }
    });
  }

  // ── Rack-map preload for AutoFillRack / RackPicker ─────────────────────────
  Future<void> preloadRackStockMap() async {
    final wh    = resolvedWarehouse;
    final batch = batchController.text.trim();
    if (itemCode.value.isEmpty || wh == null || wh.isEmpty || batch.isEmpty) return;

    try {
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: wh,
        batchNo:   batch,
      );
      final map = <String, double>{};
      for (final raw in rows) {
        final rack = (raw['rack'] ?? '').toString().trim();
        if (rack.isEmpty) continue;
        final qty = (raw['qty'] as num?)?.toDouble() ?? 0.0;
        map[rack] = (map[rack] ?? 0) + qty;
      }
      rackStockMapRx.assignAll(map);
    } catch (e) {
      log('[DN-Item] preloadRackStockMap error: $e', name: 'DN-Item');
      rackStockMapRx.clear();
    }
  }

  Future<void> maybeAutoFillRack() async {
    await preloadRackStockMap();
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty > 0) autoFillRackForQty(qty);
  }

  @override
  Future<void> validateBatch(String batch) async {
    await super.validateBatch(batch);
    if (!isBatchValid.value) return;
    unawaited(maybeAutoFillRack());
  }

  @override
  Future<void> validateRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) { resetRack(); return; }

    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;

    try {
      double balance;
      final mapQty = rackStockMapRx[trimmed];
      debugPrint('mapQty: $mapQty');
      if (mapQty != null) {
        balance = mapQty;
      } else {
        await fetchRackBalance(trimmed);
        // ✅ Re-read from the map AFTER the await instead of trusting rackBalance.value
        balance = rackStockMapRx[trimmed] ?? 0.0;
      }
      rackBalance.value = balance; // sync the observable last

      debugPrint('trimmed: $trimmed');
      debugPrint('rackBalance: $balance');
      _applyRackValidationResult(rackName: trimmed, balance: balance);
    } catch (e) {
      rackError.value = 'Error validating rack: $e';
      log('[DN-Item] validateRack error: $e', name: 'DN-Item');
    } finally {
      isValidatingRack.value = false;
      validateSheet();
    }
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: evaluate the fetched [balance] for [rackName] and
  /// write [isRackValid] / [rackError] accordingly.
  /// Single definition of the "no stock" error template (DRY).
  void _applyRackValidationResult({
    required String rackName,
    required double balance,
  }) {
    if (balance > 0) {
      isRackValid.value = true;
      rackError.value   = '';
    } else {
      isRackValid.value = false;
      rackError.value   =
      'No stock available in rack "$rackName" '
          '(balance: ${balance.toStringAsFixed(2)})';
    }
  }

  // ── BarcodeAwareMixin: handleScan override for deprecated batch labels ──────
  /// The base BarcodeAwareMixin.handleScan handles current-format scans
  /// ('20003609-ESU') correctly — ean is non-empty so raw is used as-is.
  ///
  /// This override adds handling for deprecated SHIPMENT-* formats and plain
  /// Batch ID scans where no EAN8 prefix is present in the scanned string.
  /// The Batch ID is extracted and prepended with the stored _itemEan8 to
  /// form the correct Batch No ('20003609-ESU').
  @override
  @override
  Future<void> handleScan(String raw) async {
    // Priority 1 — strict rack pattern (same gate as SE via isRackBarcode).
    if (BarcodeAwareMixin.isRackBarcode(raw)) {
      applyRackScan(raw);
      return;
    }

    // Priority 2 — SE fallback: when batch is already valid any unrecognised
    // scan is treated as a rack scan.  Mirrors BarcodeAwareMixin._routeScan's
    // else-branch so rack names whose format doesn't satisfy the isRackBarcode
    // regex (e.g. KA-WH-DUBAI-SHELF1) still reach validateRack().
    if (isBatchValid.value) {
      applyRackScan(raw);
      return;
    }

    // Priority 3 — batch not yet set: assemble and validate batch.
    final batchNo = _assembleBatchNo(raw);
    batchController.text = batchNo;
    await validateBatch(batchNo);
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: resolve the correct Batch No string from [raw].
  ///
  /// - Current format (`EAN8-BatchId`): the raw string already is the
  ///   full Batch No — return it unchanged.
  /// - Deprecated SHIPMENT-* format: extract the Batch ID token and
  ///   prepend the stored [_itemEan8] to reconstruct the Batch No.
  String _assembleBatchNo(String raw) {
    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);
    if (ean.isNotEmpty) return raw;

    final extractedId = _extractBatchId(raw);
    return _itemEan8.isNotEmpty ? '$_itemEan8-$extractedId' : extractedId;
  }

  /// Splits [raw] on '-', discards the literal token 'SHIPMENT' (any case),
  /// and discards any token shorter than 3 characters.
  /// Returns the first surviving token, or [raw] unchanged if none survive.
  ///
  /// Examples:
  ///   'SHIPMENT-ESU'       → 'ESU'
  ///   'SHIPMENT-24-ESU'    → 'ESU'  (discards '24' — length < 3)
  ///   'SHIPMENT-24-ESU-1'  → 'ESU'  (discards '24' and '1')
  ///   'ESU'                → 'ESU'  (no hyphens, passes through as-is via
  ///                                   the ean.isNotEmpty guard above, so
  ///                                   this method is only called for
  ///                                   hyphenated SHIPMENT-* strings in
  ///                                   practice — but handles plain too)
  String _extractBatchId(String raw) {
    final candidates = raw.split('-').where((p) =>
    p.toUpperCase() != 'SHIPMENT' &&
        p.length >= 3
    ).toList();
    return candidates.isNotEmpty ? candidates.first : raw;
  }

  // BarcodeAwareMixin: applyRackScan
  /// Called by BarcodeAwareMixin._routeScan when the scan pattern matches a
  /// rack barcode (KA-WH-DXB1-101A), either after batch is valid or before.
  ///
  /// Resets rack validity flags BEFORE writing to [rackController] so the
  /// TextEditingController listener's [validateSheet] call sees a clean state
  /// (isRackValid = false) rather than stale state from a prior autofill.
  /// [validateRack] then confirms the balance and calls [validateSheet] again
  /// with the authoritative result.
  @override
  void applyRackScan(String code) {
    softResetRack();      // zero isRackValid before listener fires
    rackController.text = code;
    unawaited(validateRack(code)); // API round-trip — sets isRackValid + rackBalance
  }

  void clearAll() {
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    resetBatch();
    resetRack();
    selectedSerial.value  = null;
    liveRemaining.value   = 0.0;
    rackStockMapRx.clear();
  }

  String get currentItemDisplay =>
      [itemCode.value, itemNameRx.value]
          .where((e) => e.trim().isNotEmpty)
          .join(' - ');

  bool get hasExistingRackMap => rackStockMapRx.isNotEmpty;

  Future<void> ensureReadyForOpen() async {}

  @override
  void onClose() {
    removeSheetListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      super.onClose();
    });
  }
}
