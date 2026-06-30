import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_balance.dart';

/// Item-level sheet controller for Packing Slip.
///
/// Extends [ItemSheetControllerBase] for the full animated item-sheet
/// infrastructure (save-button state, auto-submit worker, dirty tracking, etc.).
///
/// Commit 6 (serial refactor):
///   • Adopts [SerialFieldMixin] — full [SerialNumberFieldDelegate] compliance.
///   • [availableSerialNos] returns a single-element list seeded from
///     [PackingSlipFormController.currentSerial] when a POS Upload is loaded,
///     otherwise [] (widget hidden).
///   • [posItemQtyForSerial] delegates to [PackingSlipFormController.posQtyCapForSerial].
///   • [sumQtyUsedForSerial] sums qty for the serial across the current slip's
///     in-memory items list.
///   • [selectedSerial] is seeded in [initialise] so the dropdown is
///     pre-selected (read-only) on sheet open.
///   • [computeLiveRemaining] wired into [validateSheet] — cap badge reacts
///     to every qty keystroke.
class PackingSlipItemFormController extends ItemSheetControllerBase
    with SerialFieldMixin {
  // ── Parent reference ───────────────────────────────────────────────────────
  late PackingSlipFormController _parent;

  /// PS hard-disables Full serials — see SerialFieldMixin.supportsAllowFullToggle.
  @override
  bool get supportsAllowFullToggle => false;

  /// Retargets the parent sheet session when the user picks another serial.
  /// Stored so it can be cancelled in [onClose] (project Worker rule).
  Worker? _serialRetargetWorker;

  // ── ItemSheetControllerBase abstract overrides ─────────────────────────────

  @override
  String? get resolvedWarehouse => null;

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  @override
  Color get accentColor => Colors.teal;

  @override
  bool get isAddMode => editingItemName.value == null;

  @override
  String get qtyInfoText {
    final max = _parent.bsMaxQty.value;
    if (max > 0) return 'Remaining: ${max.toStringAsFixed(2)}';
    return '';
  }

  @override
  RxnString get qtyInfoTooltip => RxnString(null);

  @override
  void adjustQty(int delta) {
    final current = _parseCurrentQty();
    final ceiling = _resolveQtyCeiling();
    final next    = _clampNextQty(current + delta, ceiling);
    _applyQty(next);
    validateSheet();
  }

  // ── Private SRP helpers ────────────────────────────────────────────────────

  /// (1) Parses the current raw text in [qtyController], defaulting to 0.0
  /// when the field is empty or contains a non-numeric value.
  double _parseCurrentQty() =>
      double.tryParse(qtyController.text) ?? 0.0;

  /// (2) Resolves the effective upper bound for qty stepper adjustments.
  ///
  /// [bsMaxQty] > 0 means a DN item is linked and imposes a hard cap.
  /// A zero value means uncapped → [double.infinity] so [clamp] is a no-op
  /// on the upper bound.
  double _resolveQtyCeiling() {
    final cap = _parent.bsMaxQty.value;
    return cap > 0 ? cap : double.infinity;
  }

  /// (3) Clamps [rawNext] into the valid range [0.0, ceiling].
  double _clampNextQty(double rawNext, double ceiling) =>
      rawNext.clamp(0.0, ceiling);

  /// (4) Formats [qty] as a whole-number string when it has no fractional
  /// part, otherwise as a two-decimal string, then writes it to [qtyController].
  void _applyQty(double qty) {
    qtyController.text = qty.truncateToDouble() == qty
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
  }

  @override
  Future<void> deleteCurrentItem() => _parent.deleteCurrentItem();

  // ── SerialFieldMixin: availableSerialNos ────────────────────────────────────
  //
  // Add mode: all serials whose DN rows match the current item (and scanned
  // batch) — the user can re-target the sheet to any non-Full serial.
  // Edit mode: locked to the existing row's serial (single-element list).
  // Return [] when no POS Upload is loaded → widget hidden entirely.
  @override
  List<String> get availableSerialNos {
    if (_parent.posUpload.value == null) return [];
    if (editingItemName.value != null) {
      final serial = _parent.currentSerial;
      if (serial == null || serial.isEmpty || serial == '0') return [];
      return [serial];
    }
    return _parent.serialOptionsForSheet().map((o) => o.serial).toList();
  }

  // ── SerialFieldMixin: rich dropdown row metadata ───────────────────────────
  //
  // qty/remaining describe the serial's DN row (not the POS cap): a serial is
  // "Full" when its DN row is fully packed across current + related slips.
  @override
  SerialDropdownItem? posDropdownItemFor(String serial) {
    final option = _parent
        .serialOptionsForSheet()
        .firstWhereOrNull((o) => o.serial == serial);
    if (option == null) return null;

    final posName = _parent.getPosItemName(serial);
    final dnItems = _parent.linkedDeliveryNote.value?.items ?? const [];
    final blocked = isPairedItemGroup(itemGroup.value) &&
            isSerialStrapBuckleUnbalanced(dnItems, serial)
        ? 'Strap ≠ Buckle'
        : null;
    return SerialDropdownItem(
      serial:       serial,
      itemName:     posName.isNotEmpty ? posName : option.dnRow.itemName,
      qty:          option.qty,
      remaining:    option.remaining,
      used:         option.qty - option.remaining,
      blockedReason: blocked,
    );
  }

  // ── Serial retarget wiring ─────────────────────────────────────────────────

  /// Add-mode only: when the user selects a different serial, re-seed the
  /// parent session to that serial's DN row and re-prefill qty with the new
  /// remaining. Safe against auto-submit: programmatic qty writes reset
  /// saveButtonState to idle via _resetSaveStateOnEdit.
  void _wireSerialRetarget() {
    _serialRetargetWorker = ever(selectedSerial, (String? serial) {
      if (serial == null || serial.isEmpty) return;
      if (serial == _parent.currentSerial) return;
      _parent.retargetSheetToSerial(serial);
      _prefillQtyFromRemaining();
      notifySerialItemsChanged();
      validateSheet();
    });
  }

  /// Pre-fills qty with the parent's current remaining cap (same formatting
  /// as _populateAddFields).
  void _prefillQtyFromRemaining() {
    final remaining = _parent.bsMaxQty.value;
    qtyController.text = remaining > 0
        ? (remaining % 1 == 0
            ? remaining.toInt().toString()
            : remaining.toString())
        : '0';
  }

  @override
  void onClose() {
    _serialRetargetWorker?.dispose();
    super.onClose();
  }

  // ── SerialFieldMixin: POS qty cap for a given serial ───────────────────────
  //
  // Delegates to PackingSlipFormController.posQtyCapForSerial(serial) which
  // resolves serial → idx → PosUploadItem.quantity.
  @override
  double posItemQtyForSerial(String serial) =>
      _parent.posQtyCapForSerial(serial);

  // ── SerialFieldMixin: sum of all committed rows for this serial ────────────
  //
  // Walks the current slip's in-memory items list — no API call.
  // PS items carry customInvoiceSerialNumber so we match on that field.
  @override
  double sumQtyUsedForSerial(String serial, {String? excludeRowId}) {
    return _parent.packingSlip.value?.items
        .where((i) =>
          i.customInvoiceSerialNumber == serial &&
          i.name != excludeRowId)
        .fold(0.0, (sum, i) => sum! + i.qty) ??
        0.0;
  }

  // ── Sheet validation ───────────────────────────────────────────────────────

  @override
  void validateSheet() {
    final qty = double.tryParse(qtyController.text);

    if (!_isQtyPresent(qty) ||
        !_isQtyWithinCap(qty!) ||
        !_isEditDirtyWhenRequired()) {
      isSheetValid.value = false;
      return;
    }

    _updateLiveRemaining(qty);
    isSheetValid.value = true;
  }

  // ── Private SRP helpers ────────────────────────────────────────────────────

  /// (1) True when [qty] was successfully parsed and is strictly positive.
  bool _isQtyPresent(double? qty) => qty != null && qty > 0;

  /// (2) True when the parent's balance cap is not exceeded.
  ///
  /// The cap is only active when [bsMaxQty] > 0; a zero value means
  /// "uncapped" (no DN item linked), so the check is unconditionally
  /// satisfied in that case.
  bool _isQtyWithinCap(double qty) {
    final cap = _parent.bsMaxQty.value;
    return cap <= 0 || qty <= cap;
  }

  /// (3) True when the edit-mode dirty requirement is satisfied.
  ///
  /// In add mode ([editingItemName] == null) the check is always satisfied.
  /// In edit mode the sheet must be dirty before the save button is enabled —
  /// submitting an unchanged item is a no-op and therefore invalid.
  bool _isEditDirtyWhenRequired() {
    if (editingItemName.value == null) return true;
    return isDirty;
  }

  /// (4) Recomputes the live remaining badge via [SerialFieldMixin].
  ///
  /// Called only after all guards pass so [computeLiveRemaining] always
  /// receives a valid, in-range [qty].
  void _updateLiveRemaining(double qty) {
    computeLiveRemaining(
      currentTypedQty: qty,
      editingRowId:    editingItemName.value,
    );
  }

  @override
  Future<void> submit() async {
    final qty = _parseQty();
    if (qty == null) return;

    await _dismissKeyboardAndClose();
    await _parent.addItemWithQty(qty);
  }

  // ── Private SRP helpers ────────────────────────────────────────────────────

  /// (1) Parses and validates the qty field.
  /// Returns null (caller must return early) when the value is absent or ≤ 0.
  double? _parseQty() {
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    return qty > 0 ? qty : null;
  }

  /// (2) Dismisses the software keyboard through both APIs, then pops the sheet.
  ///
  /// Two unfocus calls are required:
  /// • [FocusManager.instance.primaryFocus?.unfocus()] — severs the IME
  ///   connection immediately, preventing the TEC from receiving further
  ///   events while the sheet animates out.
  /// • [FocusScope.of(context).unfocus()] — propagates the unfocus through
  ///   the widget-tree focus scope so no descendant can reclaim focus during
  ///   the dispose cycle.
  /// Both must precede [Get.back()] to avoid the race between
  /// _AnimatedState.didUpdateWidget and disposeControllers().
  Future<void> _dismissKeyboardAndClose() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final context = Get.context;
    if (context != null) FocusScope.of(context).unfocus();

    Get.back();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  void initialise({
    required PackingSlipFormController parent,
    required String itemCode,
    required String itemName,
    String itemGroup = '',
    String variantOf = '',
    PackingSlipItem? editingItem,
  }) {
    _bindParent(parent);
    _seedItemIdentity(
      itemCode:  itemCode,
      itemName:  itemName,
      itemGroup: itemGroup,
      variantOf: variantOf,
    );
    _seedSerial(parent);
    _populateFields(editingItem: editingItem, parent: parent);
    // After the serial seed so the initial value never fires a retarget.
    if (editingItem == null) _wireSerialRetarget();
    _finaliseInit();
  }

  // ── Private SRP helpers ────────────────────────────────────────────────────

  /// (1) Binds the parent controller reference and propagates its current
  /// isAddingItem flag into the base layer.
  void _bindParent(PackingSlipFormController parent) {
    _parent = parent;
    isAddingItemFlag = parent.isAddingItem.value;
  }

  /// (2) Seeds the read-only item identity fields exposed to the sheet widget.
  void _seedItemIdentity({
    required String itemCode,
    required String itemName,
    String itemGroup = '',
    String variantOf = '',
  }) {
    this.itemCode.value    = itemCode;
    this.itemName.value    = itemName;
    this.itemGroup.value   = itemGroup;
    this.variantOf.value   = variantOf;
  }

  /// (3) Pre-selects the serial from [parent.currentSerial].
  ///
  /// PS serials are fixed by the linked DN item; the dropdown is read-only.
  /// A null / empty / sentinel ('0') serial clears the selection so the
  /// widget is hidden entirely by [availableSerialNos].
  void _seedSerial(PackingSlipFormController parent) {
    final serial = parent.currentSerial;
    selectedSerial.value =
    (serial != null && serial.isNotEmpty && serial != '0') ? serial : null;
    // Baseline for isSerialDirty — must follow the seed above.
    captureSerialSnapshot();
  }

  /// (4a) Populates sheet fields for **edit** mode from [editingItem].
  void _populateEditFields(PackingSlipItem editingItem) {
    editingItemName.value = editingItem.name;
    itemOwner.value       = editingItem.owner;
    itemCreation.value    = editingItem.creation;
    itemModified.value    = editingItem.modified;
    itemModifiedBy.value  = editingItem.modifiedBy;

    final qty = editingItem.qty;
    qtyController.text =
    qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
  }

  /// (4b) Clears sheet fields for **add** mode and pre-fills qty from the
  /// parent's remaining balance ([bsMaxQty]).
  void _populateAddFields(PackingSlipFormController parent) {
    editingItemName.value = null;
    itemOwner.value       = null;
    itemCreation.value    = null;
    itemModified.value    = null;
    itemModifiedBy.value  = null;
    _prefillQtyFromRemaining();
  }

  /// (4) Dispatch to the correct field-population helper based on mode.
  void _populateFields({
    required PackingSlipItem? editingItem,
    required PackingSlipFormController parent,
  }) {
    if (editingItem != null) {
      _populateEditFields(editingItem);
    } else {
      _populateAddFields(parent);
    }
  }

  /// (5) Runs the lifecycle finalisers that must always execute last.
  void _finaliseInit() {
    initBaseListeners();
    captureSnapshot();
    validateSheet();
  }
}
