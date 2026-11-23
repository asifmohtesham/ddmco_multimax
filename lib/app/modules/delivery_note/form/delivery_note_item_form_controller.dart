import 'dart:async';
import 'dart:developer';
// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';

// Shared base + mixins
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';

// Picker
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/rack_warehouse_rule.dart';

// Data layer
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

// Domain model
import 'package:multimax/app/data/models/delivery_note_model.dart';

// Parent controller
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/delivery_note/form/so_pick.dart';
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
///        `List<DeliveryNoteItem>`.  .refresh() does not exist on List;
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

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  /// Choosing an invoice serial changes the qty ceiling (voucher line cap),
  /// so the sheet must re-validate — otherwise a qty typed under a looser
  /// ceiling stays "valid" and over-fills the newly chosen line.
  Worker? _serialWorker;

  @override
  void onInit() {
    super.onInit();
    _serialWorker = ever(selectedSerial, (_) {
      submitError.value = '';
      validateSheet();
    });
  }

  @override
  void onClose() {
    _serialWorker?.dispose();
    disposeAutoFillListener();
    endValidationSession();
    Future.delayed(const Duration(milliseconds: 400), targetRackController.dispose);
    super.onClose();
  }

  // ── Parent back-reference ──────────────────────────────────────────────────
  late DeliveryNoteFormController _parent;

  DeliveryNoteFormController get parent => _parent;

  // ── Local reactive state ───────────────────────────────────────────────────
  final RxString itemCodeRx       = ''.obs;
  final RxString itemNameRx       = ''.obs;
  final RxString itemUomRx        = ''.obs;

  final RxBool isExistingItem = false.obs;
  final RxInt  editingIndex   = (-1).obs;

  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;
  final RxnString itemWarehouse = RxnString();
  final rackWarehouseVerdict = Rxn<RackPairVerdict>();
  final isCheckingRackWarehouse = false.obs;
  final targetRackController = TextEditingController();
  final targetWarehouse = RxnString();
  bool targetRackHasFocus = false;
  final targetRackVerdict = Rxn<RackPairVerdict>();
  final isCheckingTargetRack = false.obs;

  DeliveryNoteItem? _editedRow;
  bool _warehousePinned = false;
  bool _validationSessionClosed = false;
  int _rackGeneration = 0;
  int _targetRackGeneration = 0;
  String _rackRequest = '';
  String _targetRackRequest = '';
  String _batchInput = '';
  String? _batchCheckWarehouse;
  ({String? warehouse, String batch})? _rackStockScope;

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
  String? get resolvedWarehouse => DeliveryNoteFormController.effectiveWarehouse(
        row: itemWarehouse.value,
        salesOrder: soLine?.warehouse,
        header: _parent.setWarehouse.value,
      );

  bool get hasTargetSide => _editedRow != null &&
      (targetWarehouse.value != null || (_editedRow?.toRack ?? '').isNotEmpty);

  bool get targetRackApplicable => targetWarehouse.value != null;

  bool get targetRackValid => targetRackVerdict.value?.isValid == true;

  String get targetRackMessage {
    if (isCheckingTargetRack.value) return 'Checking rack warehouse…';
    final verdict = targetRackVerdict.value;
    if (verdict == null) return '';
    return _savedTargetException(verdict) ? verdict.savedMessage : verdict.message;
  }

  bool _savedTargetException(RackPairVerdict verdict) =>
      !verdict.isValid &&
      _editedRow?.toRack == targetRackController.text.trim() &&
      _editedRow?.targetWarehouse == targetWarehouse.value;

  void endValidationSession() {
    if (_validationSessionClosed) return;
    _validationSessionClosed = true;
    _rackGeneration++;
    _targetRackGeneration++;
    invalidateBatchValidation();
    rackController.removeListener(_rackInputChanged);
    targetRackController.removeListener(_targetRackInputChanged);
    batchController.removeListener(_batchInputChanged);
  }

  /// Sales Order line this row is picked against (SO mode only): the edited
  /// row's own `so_detail`, else the line the parent resolved at scan time.
  SoPickLine? soLine;

  bool get _soVoucherLinked =>
      soLine != null && _parent.uploadLink.value == SoUploadLink.linked;

  /// Open qty on [soLine] excluding the row being edited.
  double get soRemaining => soLine == null
      ? double.infinity
      : _parent.soRemainingFor(soLine!, excludeRowName: editingItemName.value);

  @override bool  get requiresBatch => true;
  /// Mirrors Desk's Property Setter on Delivery Note Item.rack
  /// (`mandatory_depends_on: eval:doc.item_code`), which the server does not
  /// enforce for API saves. Read by [_assertSubmitPreconditions].
  @override bool  get requiresRack  => true;
  @override Color get accentColor   => AppColors.gray700;

  @override
  bool get isAddMode => !isExistingItem.value;

  // ── Oldest stock first (docs/batch_age_validation.md) ─────────────────────
  /// A Delivery Note ships stock out, so a batch is refused while an older
  /// batch of the item is still available.
  @override
  bool get enforcesBatchAge => true;

  /// The Delivery Note sheet keeps the item name in [itemNameRx].
  @override
  String get batchAgeItemName => itemNameRx.value;

  @override
  String? get batchAgeOwnDoctype => 'Delivery Note';

  @override
  String? get batchAgeOwnDocName => _parent.batchAgeDocName;

  /// The batch this row was opened with; never refused on re-open.
  String? _savedBatch;
  String? _openedWarehouse;

  @override
  String? get batchAgeExemptBatch =>
      _savedBatch != null && _openedWarehouse == resolvedWarehouse ? _savedBatch : null;

  /// This note's other rows for the item (the row being edited is left out).
  @override
  List<BatchDraftLine> get batchAgeOwnLines {
    final rows = _parent.items;
    final skip = isExistingItem.value ? editingIndex.value : -1;
    return _parent.batchAgeLines(
      itemCode.value,
      rows: [
        for (var i = 0; i < rows.length; i++)
          if (i != skip) rows[i],
      ],
    );
  }

  // ── qtyInfoText / qtyInfoTooltip ───────────────────────────────────────────
  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == double.infinity) return null;
    return 'Max: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

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
    final serial = selectedSerial.value ?? '';
    if (serial.isNotEmpty && !allowFullSerials.value) {
      // Apply the raw POS Item Qty as a hard cap — independently of how
      // much the user has already typed (liveRemaining shifts as they type
      // so it must NOT be used as the cap source here).
      final posQty = posItemQtyForSerial(serial);
      if (posQty != double.infinity) {
        // Remaining already-used slots for this serial (excluding self in edit).
        final used = sumQtyUsedForSerial(serial, excludeRowId: editingItemName.value);
        final allowedByPos = (posQty - used).clamp(0.0, posQty);
        ceil = _applyConstraint(ceil, allowedByPos);
      }
    }
    if (soLine != null) {
      // Hard cap even at 0 (_applyConstraint ignores non-positive values).
      final rem = soRemaining;
      ceil = ceil == null ? rem : (rem < ceil ? rem : ceil);
    }
    return ceil ?? double.infinity;
  }

  bool get _rackBalanceOk =>
      !isValidatingRack.value &&
      (isRackValid.value && rackBalance.value > 0 || _canRetainOutbound());

  bool get _batchBalanceOk =>
      !isValidatingBatch.value && isBatchValid.value && batchBalance.value > 0;

  bool get _isSavedOutboundPair =>
      rackWarehouseVerdict.value?.isValid == false &&
      _editedRow?.rack == rackController.text.trim() &&
      _openedWarehouse == resolvedWarehouse;

  bool _canRetainOutbound() {
    if (!_isSavedOutboundPair) return false;
    return _parent.canRetainSavedPair(
      _buildItem(qty: double.tryParse(qtyController.text) ?? double.infinity),
      RackSide.outbound,
    );
  }

  bool get _targetPairOk {
    if (isCheckingTargetRack.value) return false;
    final rack = targetRackController.text.trim();
    if (rack.isEmpty || targetRackValid) return true;
    return targetRackVerdict.value != null &&
        _parent.canRetainSavedPair(
          _buildItem(qty: double.tryParse(qtyController.text) ?? double.infinity),
          RackSide.target,
        );
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
    final items = _parent.deliveryNote.value?.items;
    if (items == null || editingIndex.value >= items.length) return;
    // The sheet closes (and this controller is deleted) right after this
    // call, so the parent is captured and the removal completes on it.
    unawaited(_removeRow(_parent, items[editingIndex.value]));
  }

  /// Removes [row] from [parent] unless that would free older stock while a
  /// newer batch of the item stays on the note (oldest stock first).
  static Future<void> _removeRow(
      DeliveryNoteFormController parent, DeliveryNoteItem row) async {
    final items = parent.deliveryNote.value?.items;
    if (items == null) return;
    final reason = await parent.batchOrderBreak(
      itemCode:     row.itemCode,
      rowWarehouse: row.warehouse,
      after:        [for (final r in items) if (!identical(r, row)) r],
    );
    if (parent.isClosed) return;
    if (reason != null) {
      GlobalSnackbar.error(message: reason);
      return;
    }
    items.removeWhere((r) => identical(r, row));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (parent.isClosed) return;
      parent.deliveryNote.refresh();
      parent.checkForChanges();           // Mark document dirty
      if (parent.mode == 'edit') {
        parent.saveDocument();        // Execute PUT request
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

  // ── AutoFillRackMixin wiring ───────────────────────────────────────────────
  String  get mixinItemCode  => itemCode.value;
  String? get mixinWarehouse => resolvedWarehouse;
  String  get mixinBatch     => batchController.text;
  double  get mixinQty       => double.tryParse(qtyController.text) ?? 0.0;
  @override Map<String, double> get rackStockMap => Map<String, double>.from(rackStockMapRx);

  Future<void> pickRack() async {
    final selected = await browseRacks();
    if (selected != null && !_validationSessionClosed) {
      _applySourceRackScan(selected.rackId);
    }
  }

  Future<void> pickTargetRack() async {
    final context = Get.context;
    final warehouse = targetWarehouse.value;
    if (context == null || warehouse == null || isCheckingTargetRack.value) {
      return;
    }
    final tag = 'dn_target_rack_picker';
    final picker = Get.put(RackPickerController(), tag: tag);
    try {
      unawaited(picker.loadForTarget(
        warehouse: warehouse,
        currentRack: targetRackController.text.trim(),
      ));
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => RackPickerSheet(
          pickerTag: tag,
          onSelected: (rack) {
            _applyTargetRackScan(rack);
          },
        ),
      );
    } finally {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    }
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
    _editedRow = editingItem;
    _warehousePinned = editingItem != null;
    targetWarehouse.value = editingItem == null
        ? null
        : parent.targetWarehouseFor(editingItem);
    targetRackController.text = editingItem?.toRack ?? '';
    _targetRackRequest = targetRackController.text.trim();
    soLine = editingItem != null
        ? parent.salesOrder.value?.lineByDetail(editingItem.soDetail)
        : parent.pendingSoLine;

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
    final idx   = items.indexWhere(
      (i) => identical(i, item) || (item.name != null && i.name == item.name),
    );
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
    _savedBatch           = null;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
    allowFullSerials.value = false;
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
    this.itemCode.value  = itemCode;
    itemCodeRx.value     = itemCode;
    itemNameRx.value     = itemName;
    itemUomRx.value      = uom;
    this.itemGroup.value = itemGroup;
    this.variantOf.value = variantOf;
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
    itemWarehouse.value   = null;
    // selectedSerial is intentionally NOT reset here.
    // - initForNewItem: serial is cleared in _seedFieldControllers() below.
    // - initForEdit:    serial is seeded in _resolveAndSeedSerial() AFTER
    //                   this method runs, so it must not be clobbered here.
    liveRemaining.value   = 0.0;
    rackStockMapRx.clear();
    isSheetValid.value = false;
    isQtyValid.value   = false;
    qtyError.value     = '';
    _batchCheckWarehouse = null;
    _rackStockScope = null;
  }

  /// Responsibility: tear down any stale listeners, attach fresh ones,
  /// then capture the baseline state snapshots that change-detection
  /// and serial-remaining logic depend on.
  void _wireListenersAndSnapshot() {
    removeSheetListeners();
    addSheetListeners();
    snapshotState();
    captureSerialSnapshot();
    rackController.addListener(_rackInputChanged);
    targetRackController.addListener(_targetRackInputChanged);
    _batchInput = batchController.text.trim();
    batchController.addListener(_batchInputChanged);
    initAutoFillListener();
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
    // Re-seed rack text and itemWarehouse after _resetValidationState() which
    // calls resetRack() and clears both rackController and itemWarehouse.
    rackController.text = existingRack;
    itemWarehouse.value =
        _parent.outboundWarehouse(item, header: _parent.setWarehouse.value);
    _openedWarehouse = itemWarehouse.value;

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
    _savedBatch           = item.batchNo;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
    allowFullSerials.value = false;
  }

  /// Responsibility: write all item-identity reactive variables from the
  /// existing [item] row so sheet widgets observe the correct values on open.
  void _seedItemIdentityFromItem({
    required DeliveryNoteItem item,
    required String variantOf,
  }) {
    itemCode.value = item.itemCode;
    itemCodeRx.value     = item.itemCode;
    itemNameRx.value     = item.itemName  ?? '';
    itemUomRx.value      = item.uom       ?? '';
    itemGroup.value = item.itemGroup ?? '';
    this.variantOf.value = variantOf;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_validationSessionClosed) return;
      if (existingRack.isNotEmpty && existingBatch.isEmpty) {
        unawaited(validateRack(existingRack));
      }
      if (targetRackController.text.trim().isNotEmpty) {
        unawaited(validateTargetRack(targetRackController.text));
      }
    });
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
    // Batch refused because older stock must ship first: the batch field
    // carries the reason, so no "no available stock" message here.
    if (olderBatches.isNotEmpty) {
      isQtyValid.value = false;
      qtyError.value   = '';
      return;
    }

    // Gate on batch balance first — mirrors _rackBalanceOk pattern.
    if (!_batchBalanceOk) {
      isQtyValid.value = false;
      qtyError.value   = 'Batch has no available stock (balance: 0)';
      return;
    }

    if (!_rackBalanceOk || !_targetPairOk) {
      isQtyValid.value = false;
      qtyError.value = '';
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
    isSheetValid.value = _batchBalanceOk &&
        _rackBalanceOk &&
        _targetPairOk &&
        qtyOk &&
        ceilOk &&
        !_parent.isSaving.value;
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
    final before = List<DeliveryNoteItem>.of(_parent.items);
    final header = _parent.setWarehouse.value;
    final generation = _rackGeneration;
    final targetGeneration = _targetRackGeneration;
    bool rowChanged() =>
        _validationSessionClosed ||
        generation != _rackGeneration ||
        targetGeneration != _targetRackGeneration ||
        _parent.setWarehouse.value != header ||
        _parent.items.length != before.length ||
        !_parent.items.asMap().entries.every((e) => identical(e.value, before[e.key]));

    await _assertBatchOrderKept(item);
    if (rowChanged() ||
        !await _parent.warehouseConfirmation.confirm(
          _parent.warehouseDifferences(item, editingIndex: editingIndex.value),
        )) {
      throw const ItemSheetSubmissionCancelled();
    }
    if (rowChanged() ||
        item.qty != _assertSubmitPreconditions() ||
        item.customInvoiceSerialNumber !=
            _buildItem(qty: qty).customInvoiceSerialNumber) {
      throw const ItemSheetSubmissionCancelled();
    }
    _commitToParent(item: item);
    _scheduleParentRefresh();
  }

  /// Oldest stock first: an edit that reduces an older-batch row (or moves it
  /// to another batch) frees that stock again. Refused while a newer batch of
  /// the item is on the note. Throws the reason for the sheet to show.
  Future<void> _assertBatchOrderKept(DeliveryNoteItem edited) async {
    if (!isExistingItem.value || editingIndex.value < 0) return;
    final rows = _parent.items;
    if (editingIndex.value >= rows.length) return;

    final saved = rows[editingIndex.value];
    final freesStock = edited.qty < saved.qty ||
        (edited.batchNo ?? '') != (saved.batchNo ?? '') ||
        (edited.warehouse ?? '') != (saved.warehouse ?? '');
    if (!freesStock) return;

    final reason = await _parent.batchOrderBreak(
      itemCode:     saved.itemCode,
      rowWarehouse: saved.warehouse,
      after: [
        for (var i = 0; i < rows.length; i++)
          i == editingIndex.value ? edited : rows[i],
      ],
    );
    if (reason != null) throw Exception(reason);
  }

  // ── SRP helpers ────────────────────────────────────────────────────────────

  /// Responsibility: assert that the sheet is in a submittable state.
  /// Throws a descriptive [Exception] on the first failing precondition.
  /// Returns the parsed qty so callers do not re-parse.
  double _assertSubmitPreconditions() {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Enter a valid quantity');
    if (_parent.isSaving.value) {
      throw Exception('The delivery note is saving.');
    }
    if (requiresRack && rackController.text.trim().isEmpty) {
      throw Exception('Scan or choose a rack');
    }
    if (!_batchBalanceOk) throw Exception('Batch validation required');
    if (!_rackBalanceOk) {
      throw Exception(rackError.value.isEmpty ? 'Validate the source rack' : rackError.value);
    }
    if (!_targetPairOk) {
      throw Exception(targetRackMessage.isEmpty ? 'Validate the target rack' : targetRackMessage);
    }
    // Hard ceiling (batch/rack/voucher line/SO line) — never trust a stale
    // isSheetValid alone.
    final ceil = effectiveMaxQty;
    if (ceil != double.infinity && qty > ceil + 1e-9) {
      throw Exception('Qty cannot exceed ${_formatQty(ceil)}');
    }
    // SO linked to its POS Upload: the row must name its voucher line, or a
    // provisional SO idx would sit on a DN whose po_no claims otherwise.
    if (_soVoucherLinked && (selectedSerial.value ?? '').isEmpty) {
      throw Exception('Choose the invoice serial (voucher line)');
    }
    return qty;
  }

  /// Responsibility: construct a [DeliveryNoteItem] from the current
  /// reactive field state. Normalises optional fields (rack, variantOf)
  /// to null when blank.
  DeliveryNoteItem _buildItem({required double qty}) {
    final rack         = rackController.text.trim();
    final variantOfStr = variantOf.value.trim();

    final saved = _editedRow;
    return DeliveryNoteItem(
      name: saved?.name,
      itemCode:                  itemCode.value,
      itemName:                  itemNameRx.value,
      uom:                       itemUomRx.value,
      qty:                       qty,
      rate:                      saved?.rate ?? 0.0,
      batchNo:                   batchController.text.trim(),
      rack:                      rack.isEmpty            ? null : rack,
      warehouse: _isSavedOutboundPair
          ? saved?.warehouse
          : resolvedWarehouse,
      targetWarehouse: targetRackVerdict.value != null &&
              _savedTargetException(targetRackVerdict.value!)
          ? saved?.targetWarehouse
          : targetWarehouse.value,
      toRack:                    hasTargetSide ? targetRackController.text.trim() : null,
      againstSalesOrder:         saved?.againstSalesOrder,
      soDetail:                  saved?.soDetail,
      conversionFactor:          saved?.conversionFactor,
      itemGroup:                 itemGroup.value,
      customVariantOf:           variantOfStr.isEmpty    ? null : variantOfStr,
      customInvoiceSerialNumber: selectedSerial.value,
    ).withSoLine(soLine, _parent.salesOrder.value?.name,
        serial: _soVoucherLinked ? selectedSerial.value : null);
  }

  /// Responsibility: write [item] into the parent document's items list —
  /// replacing the row at [editingIndex] for edits; for new items, merging
  /// the qty into an existing row with the same item/batch/rack/serial
  /// (a rescanned duplicate) instead of appending a second line.
  void _commitToParent({required DeliveryNoteItem item}) {
    final items = _parent.deliveryNote.value?.items;
    if (items == null) return;

    if (isExistingItem.value && editingIndex.value >= 0) {
      items[editingIndex.value] = item;
      return;
    }

    final dupIndex = items
        .indexWhere((existing) => isDuplicateLine(existing, item));
    if (dupIndex >= 0) {
      items[dupIndex] =
          items[dupIndex].copyWith(qty: items[dupIndex].qty + item.qty);
    } else {
      final localName = 'local_${DateTime.now().microsecondsSinceEpoch}';
      items.add(item.copyWith(name: localName));
    }
  }

  /// Responsibility: identify a rescanned duplicate line — same item, batch,
  /// and rack, within the same POS invoice-serial context (so distinct POS
  /// invoice lines are never merged into one another). Pure/static so it is
  /// unit-testable without constructing the full sheet controller.
  static bool isDuplicateLine(
      DeliveryNoteItem existing, DeliveryNoteItem incoming) {
    return existing.itemCode.trim().toLowerCase() ==
            incoming.itemCode.trim().toLowerCase() &&
        (existing.batchNo ?? '') == (incoming.batchNo ?? '') &&
        (existing.rack ?? '').trim() == (incoming.rack ?? '').trim() &&
        (existing.warehouse ?? '').trim() == (incoming.warehouse ?? '').trim() &&
        (existing.targetWarehouse ?? '').trim() == (incoming.targetWarehouse ?? '').trim() &&
        (existing.toRack ?? '').trim() == (incoming.toRack ?? '').trim() &&
        (existing.customInvoiceSerialNumber ?? '') ==
            (incoming.customInvoiceSerialNumber ?? '') &&
        (existing.soDetail ?? '') == (incoming.soDetail ?? '');
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
        _parent.saveDocument();
      }
    });
  }

  // ── Rack-map preload for AutoFillRack / RackPicker ─────────────────────────
  ({String? warehouse, String batch}) get _currentRackStockScope =>
      (warehouse: resolvedWarehouse, batch: batchController.text.trim());

  Future<void> preloadRackStockMap() async {
    final scope = _currentRackStockScope;
    final code = itemCode.value;
    final warehouse = scope.warehouse;
    if (code.isEmpty || warehouse == null) return;
    try {
      final rows = await Get.find<ApiProvider>().getStockBalanceWithDimension(
        itemCode: code,
        warehouse: warehouse,
        batchNo: scope.batch.isEmpty ? null : scope.batch,
      );
      if (_validationSessionClosed || scope != _currentRackStockScope) return;
      final balances = <String, double>{};
      for (final row in rows) {
        final reportedWarehouse = warehouseValue(row['warehouse'] as String?);
        if (reportedWarehouse != null && reportedWarehouse != warehouse) continue;
        final rack = (row['rack'] ?? '').toString().trim();
        if (rack.isEmpty) continue;
        final qty = ((row['bal_qty'] ?? row['qty']) as num?)?.toDouble() ?? 0;
        balances[rack] = (balances[rack] ?? 0) + qty;
      }
      _rackStockScope = scope;
      rackStockMapRx.assignAll(balances);
    } catch (e) {
      if (_validationSessionClosed || scope != _currentRackStockScope) return;
      log('[DN-Item] preloadRackStockMap error: $e', name: 'DN-Item');
      _rackStockScope = null;
      rackStockMapRx.clear();
    }
  }

  Future<void> maybeAutoFillRack() async {
    await preloadRackStockMap();
    if (_validationSessionClosed) return;
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty > 0) await autoFillRackForQty(qty);
  }

  Future<void> _checkBatch(String batch) async {
    _batchCheckWarehouse = resolvedWarehouse;
    await super.validateBatch(batch);
    if (!_validationSessionClosed) validateSheet();
  }

  @override
  Future<void> validateBatch(String batch) async {
    if (_validationSessionClosed) return;
    await _checkBatch(batch);
    if (_validationSessionClosed || batchController.text.trim() != batch.trim()) return;
    if (rackController.text.trim().isNotEmpty &&
        !isValidatingRack.value &&
        rackWarehouseVerdict.value == null) {
      await _validateRack(
        rackController.text,
        allowInitialization: _rackMayInitialize,
      );
    }
    if (!_validationSessionClosed && isBatchValid.value && rackController.text.isEmpty) {
      unawaited(maybeAutoFillRack());
    }
  }

  void _batchInputChanged() {
    final batch = batchController.text.trim();
    if (_batchInput == batch) return;
    _batchInput = batch;
    invalidateBatchValidation();
    _rackGeneration++;
    isCheckingRackWarehouse.value = false;
    isValidatingRack.value = false;
    isRackValid.value = false;
    rackWarehouseVerdict.value = null;
    rackError.value = '';
    rackBalance.value = 0;
    _rackStockScope = null;
    rackStockMapRx.clear();
    validateSheet();
  }

  void _rackInputChanged() {
    if (rackController.text.trim() == _rackRequest) return;
    _rackMayInitialize = false;
    softResetRack();
    validateSheet();
  }

  @override
  void softResetRack() {
    _rackGeneration++;
    _rackRequest = rackController.text.trim();
    isCheckingRackWarehouse.value = false;
    isValidatingRack.value = false;
    rackWarehouseVerdict.value = null;
    rackBalance.value = 0;
    super.softResetRack();
  }

  @override
  void resetRack() {
    softResetRack();
    super.resetRack();
  }

  bool _rackMayInitialize = false;

  void retryRack() =>
      unawaited(_validateRack(rackController.text, allowInitialization: _rackMayInitialize));

  void useRackWarehouse() {
    final warehouse = rackWarehouseVerdict.value?.warehouse;
    if (warehouse != null) selectWarehouse(warehouse);
  }

  void selectWarehouse(String warehouse) {
    _warehousePinned = true;
    if (resolvedWarehouse == warehouse) {
      itemWarehouse.value = warehouse;
      return;
    }
    itemWarehouse.value = warehouse;
    softResetBatch();
    _batchCheckWarehouse = null;
    _rackStockScope = null;
    rackStockMapRx.clear();
    final rack = rackController.text.trim();
    final batch = batchController.text.trim();
    if (rack.isNotEmpty) {
      unawaited(validateRack(rack));
    } else if (batch.isNotEmpty) {
      unawaited(validateBatch(batch));
    }
    validateSheet();
  }

  @override
  Future<void> validateRack(String rack) => _validateRack(rack);

  Future<void> _validateRack(String rack, {bool allowInitialization = false}) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) {
      resetRack();
      validateSheet();
      return;
    }
    if (_validationSessionClosed || rackController.text.trim() != trimmed) return;

    final generation = ++_rackGeneration;
    final batch = batchController.text.trim();
    final code = itemCode.value;
    var expectedWarehouse = resolvedWarehouse;
    var expectedRack = trimmed;
    bool current() =>
        !_validationSessionClosed &&
        generation == _rackGeneration &&
        itemCode.value == code &&
        rackController.text.trim() == expectedRack &&
        batchController.text.trim() == batch &&
        resolvedWarehouse == expectedWarehouse;

    _rackRequest = trimmed;
    _rackMayInitialize = allowInitialization;
    isValidatingRack.value = true;
    isCheckingRackWarehouse.value = true;
    isRackValid.value = false;
    rackWarehouseVerdict.value = null;
    rackError.value = '';
    rackBalance.value = 0;
    validateSheet();
    try {
      final verdict = await _parent.checkPair(
        RackSide.outbound,
        rack: trimmed,
        warehouse: expectedWarehouse,
        initializeWarehouse: !_warehousePinned &&
            (allowInitialization || expectedWarehouse == null),
      );
      if (!current()) return;
      rackWarehouseVerdict.value = verdict;
      isCheckingRackWarehouse.value = false;
      if (!verdict.isValid) {
        rackError.value = _isSavedOutboundPair ? verdict.savedMessage : verdict.message;
        return;
      }
      if (expectedWarehouse != verdict.warehouse) {
        expectedWarehouse = verdict.warehouse;
        itemWarehouse.value = verdict.warehouse;
      }
      expectedRack = verdict.rack;
      _rackRequest = verdict.rack;
      if (rackController.text.trim() != verdict.rack) rackController.text = verdict.rack;

      if (batch.isNotEmpty && _batchCheckWarehouse != expectedWarehouse) {
        await _checkBatch(batch);
        if (!current()) return;
      }
      if (_rackStockScope != _currentRackStockScope) {
        await preloadRackStockMap();
        if (!current()) return;
      }
      final balance = rackStockMapRx[verdict.rack] ?? 0;
      rackBalance.value = balance;
      _applyRackValidationResult(rackName: verdict.rack, balance: balance);
    } catch (e) {
      if (!current()) return;
      rackError.value = 'Error validating rack: $e';
      log('[DN-Item] validateRack error: $e', name: 'DN-Item');
    } finally {
      if (current()) {
        isCheckingRackWarehouse.value = false;
        isValidatingRack.value = false;
        validateSheet();
      }
    }
  }

  void _targetRackInputChanged() {
    if (targetRackController.text.trim() == _targetRackRequest) return;
    unlockTargetRack();
  }

  void unlockTargetRack() {
    _targetRackGeneration++;
    _targetRackRequest = targetRackController.text.trim();
    targetRackVerdict.value = null;
    isCheckingTargetRack.value = false;
    validateSheet();
  }

  void clearTargetRack() {
    targetRackController.clear();
    unlockTargetRack();
  }

  void selectTargetWarehouse(String warehouse) {
    if (!targetRackApplicable || targetWarehouse.value == warehouse) return;
    targetWarehouse.value = warehouse;
    final rack = targetRackController.text.trim();
    unlockTargetRack();
    if (rack.isNotEmpty) unawaited(validateTargetRack(rack));
  }

  void useTargetRackWarehouse() {
    final warehouse = targetRackVerdict.value?.warehouse;
    if (warehouse != null) selectTargetWarehouse(warehouse);
  }

  Future<void> validateTargetRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty ||
        _validationSessionClosed ||
        targetRackController.text.trim() != trimmed) {
      return;
    }
    final generation = ++_targetRackGeneration;
    final warehouse = targetWarehouse.value;
    _targetRackRequest = trimmed;
    targetRackVerdict.value = null;
    isCheckingTargetRack.value = true;
    validateSheet();
    final verdict = await _parent.checkPair(
      RackSide.target,
      rack: trimmed,
      warehouse: warehouse,
      applicable: targetRackApplicable,
    );
    if (_validationSessionClosed ||
        generation != _targetRackGeneration ||
        targetRackController.text.trim() != trimmed) {
      return;
    }
    targetRackVerdict.value = verdict;
    if (verdict.isValid && trimmed != verdict.rack) {
      _targetRackRequest = verdict.rack;
      targetRackController.text = verdict.rack;
    }
    isCheckingTargetRack.value = false;
    validateSheet();
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
    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);
    final isExplicitBatch = (ean.isNotEmpty && batchId.isNotEmpty) ||
        raw.toUpperCase().startsWith('SHIPMENT-');
    if (isBatchValid.value && !isExplicitBatch) {
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
    if (!_canApplyRackScan) return;
    if (targetRackApplicable &&
        (targetRackHasFocus ||
            (rackController.text.trim().isNotEmpty &&
                targetRackController.text.trim().isEmpty))) {
      _applyTargetRackScan(code);
      return;
    }
    _applySourceRackScan(code);
  }

  bool get _canApplyRackScan =>
      !_validationSessionClosed && !_parent.warehouseConfirmation.isPending.value;

  void _applySourceRackScan(String code) {
    if (!_canApplyRackScan) return;
    rackController.text = code;
    unawaited(_validateRack(code, allowInitialization: true));
  }

  void _applyTargetRackScan(String code) {
    if (!_canApplyRackScan) return;
    targetRackController.text = code;
    unawaited(validateTargetRack(code));
  }

  void clearAll() {
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    resetBatch();
    resetRack();
    itemWarehouse.value   = null;
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

}
