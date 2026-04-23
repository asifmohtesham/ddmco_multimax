import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';
import 'package:multimax/app/shared/item_sheet/dual_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';
// docs only — tree-shaken at compile time; surfaces TEC rules in IDE hover
import 'package:multimax/app/shared/item_sheet/tec_lifecycle_rules.dart'
    show TecLifecycleRules; // ignore: unused_import

/// Item-level sheet controller for Stock Entry.
///
/// Commit 4 (compiler fix):
///   • resolvedWarehouse now reads selectedFromWarehouse.value.
///   • POS wiring re-done: availableSerialNos derives from
///     _parent.posUploadSerialOptions; serial ceiling reads
///     _parent.remainingQtyForSerial(selectedSerial.value).
///   • deleteCurrentItem delegates to _parent.confirmAndDeleteItem().
///   • submit() delegates to _parent.updateItemLocally() / addItemLocally()
///     with the correct signatures.
///   • autoFillRackController / onAutoFillRackSelected wired to the
///     dual-rack sourceRackController / validateDualRack per mixin docs.
///
/// Commit 5 (compiler fix):
///   • Add currentScannedEan String field (used by initialise() and
///     _openNewItemSheet in parent; not on base or any mixin).
///   • Remove redundant qtyInfoTooltip getter override — base RxnString is
///     the single source of truth; validateSheet() writes it correctly via
///     super.qtyInfoTooltip.value and SharedBatchField observes the same ref.
///   • Fix showError / showSuccess: use named `message:` param as required
///     by GlobalSnackbar.
///
/// Commit 7:
///   • validateSheet() now gates on isSourceRackValid for SE types that
///     require a source rack (Material Issue / Transfer / Transfer for Mfg).
///   • validateDualRack() clears rackError on success for both sides.
///
/// Commit 8:
///   • Implements [DualRackDelegate] — additive; no members change.
///     SharedDualRackSection now depends on the narrow interface rather than
///     this concrete class.
///
/// Commit 9 (build-2):
///   • Wires [RackFieldWithBrowseDelegate] picker flow: overrides
///     [canBrowseRacks], [browseRacks], and [handleRackPicked] with the
///     full SE-flavoured rack picker implementation so the shelves-icon
///     button in SharedRackField(editMode:true) becomes live for SE.
///   • fix: RackPickerResult now requires `availableQty`; pass 0.0 in the
///     onSelected callback — handleRackPicked calls validateRack() which
///     overwrites rackBalance with the live authoritative value before it
///     is ever read, so the 0.0 snapshot is never consumed.
///
/// Commit 6 (QtyFieldWithPlusMinusDelegate wiring):
///   • effectiveMaxQty overrides base default (double.infinity) with
///     min(batchBalance, rackBalance, posSerialCeiling, mrQty) — the same
///     multi-factor formula used in qtyInfoText/validateSheet, now surfaced
///     as the single authoritative ceiling.
///   • adjustQty clamps to effectiveMaxQty (was double.infinity).
///   • validateSheet writes isQtyValid.value and qtyError.value so
///     SharedQtyField can show an inline error beneath the field.
///   • docStatus seeded in _loadExistingItem (edit mode) and reset to 0
///     in initForNewItem so the ever() worker in
///     ItemSheetControllerBase.onInit correctly locks / unlocks isQtyReadOnly.
///
/// fix(docstatus): read from parent document, not item row.
///   StockEntryItem does not carry a docstatus field — docstatus belongs
///   to the parent StockEntry only.  _loadExistingItem now reads
///   _parent.stockEntry.value?.docstatus ?? 0.
///
/// Commit 5 (serial refactor):
///   • `with PosSerialMixin` replaced by `with SerialFieldMixin`.
///   • import of item_sheet_mixin_pos_serial.dart removed; serial_field_mixin
///     imported instead.
///   • posItemQtyForSerial() delegates to _parent.posQtyCapForSerial().
///   • sumQtyUsedForSerial() walks _parent.stockEntry.items to sum qty
///     for the given serial (all rows, including the row being edited —
///     savedQtyForRow() subtracts the edit-row's saved qty to avoid
///     double-counting).
///   • savedQtyForRow() returns the committed qty of the row being edited.
///   • validateSheet() calls computeLiveRemaining() from SerialFieldMixin
///     instead of the old hand-rolled liveRemaining assignment.
///
/// fix(se-item-form): defer dual-rack TEC disposal; remove stale listeners
///   on session reset.
///   • prepareForItem() now calls removeSheetListeners() before
///     addSheetListeners() (Rule 3 — tec_lifecycle_rules.dart) to prevent
///     listener accumulation across reused controller sessions.
///
/// fix(se-item-form): extend removeSheetListeners to cover dual-rack TECs
///   • Overrides removeSheetListeners() to also remove validateSheet
///     listeners from sourceRackController and targetRackController before
///     delegating to super.
///   • Ensures Rule 3 (tec_lifecycle_rules.dart) teardown in prepareForItem()
///     is complete for all TECs owned by this controller, not just the
///     base-class trio (batch/rack/qty).
///
/// fix(se-item-form): guard initForNewItem against post-disposal writes
///   • initForNewItem() now returns immediately when isClosed is true.
///   • Prevents "Cannot use a disposed controller" / "Cannot write to a
///     closed observable" crashes on racing async paths where the sheet
///     is dismissed before prepareForItem() completes.
///
/// fix(se-item-form): guard _loadExistingItem against post-disposal writes
///   • _loadExistingItem() now returns immediately when isClosed is true.
///   • Consistent with the initForNewItem guard (Commit B) and the
///     existing `if (!isClosed)` pattern in the postFrameCallbacks already
///     present in this same method.
///
/// refactor(se-item-form): override disposeControllers() + simplify onClose()
///   • disposeControllers() override disposes sourceRackController and
///     targetRackController via try/catch, then delegates to
///     super.disposeControllers() for the base-class trio.
///   • onClose() simplified to `super.onClose()` — the base class already
///     defers disposeControllers() to addPostFrameCallback (Rule 1), so all
///     five TECs share a single deferred + idempotent disposal path.
///
/// fix(se-item-form): drop inaccessible _resetSaveStateOnEdit refs
///   • _resetSaveStateOnEdit is file-private to item_sheet_controller_base.dart.
///     Dart file-privacy means it cannot be referenced by name from this file,
///     causing a compile error. Removed the two removeListener calls that
///     referenced it — they were no-ops anyway since addSheetListeners() never
///     wires _resetSaveStateOnEdit to sourceRackController / targetRackController.
class StockEntryItemFormController extends ItemSheetControllerBase
    with SerialFieldMixin, AutoFillRackMixin, BarcodeListenerMixin, BarcodeAwareMixin
    implements DualRackDelegate {

  // ── Parent back-reference ──────────────────────────────────────────────────────
  late StockEntryFormController _parent;

  StockEntryFormController get parent => _parent;

  // ── In-sheet scan context ───────────────────────────────────────────────
  String currentScannedEan = '';

  // ── BarcodeAwareMixin: handleScan override for deprecated batch labels ────
  /// Mirrors DeliveryNoteItemFormController.handleScan exactly.
  ///
  /// Routing priority:
  ///   1. Rack barcode   → applyRackScan (unchanged from mixin)
  ///   2. Current EAN-8 format ("{EAN}-{BatchID}") → raw is the full Batch No ✔
  ///   3. Deprecated SHIPMENT-* format / plain Batch ID → extract batch ID,
  ///      prepend currentScannedEan to form the full Batch No
  @override
  Future<void> handleScan(String raw) async {
    // ── Rack-first gate ────────────────────────────────────────────────────
    // If first token is not an 8-digit EAN-8 and not "SHIPMENT", it is a rack
    // asset code. Route immediately — bypass all batch reconstruction.
    final firstToken = raw.split('-').first;
    final isEan8     = firstToken.length == 8 && int.tryParse(firstToken) != null;
    final isShipment = firstToken.toUpperCase() == 'SHIPMENT';

    if (!isEan8 && !isShipment && raw.contains('-')) {
      applyRackScan(raw);
      return;
    }

    // ── Batch paths ────────────────────────────────────────────────────────
    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);

    if (ean.isNotEmpty) {
      // Current format: raw IS the full Batch No (e.g. "20003609-ESU").
      batchController.text = raw;
      await validateBatch(raw);
      return;
    }

    // Deprecated SHIPMENT-* or plain Batch ID: extract ID and prepend item EAN-8.
    final extractedId = _extractBatchId(raw);
    final fullBatchNo = currentScannedEan.isNotEmpty
        ? '$currentScannedEan-$extractedId'
        : extractedId;

    batchController.text = fullBatchNo;
    await validateBatch(fullBatchNo);
  }

  /// Splits [raw] on '-', discards the literal token 'SHIPMENT' (any case),
  /// and discards tokens shorter than 3 characters.
  /// Returns the first surviving token, or [raw] unchanged when none survive.
  ///
  /// Examples:
  ///   'SHIPMENT-ESU'      → 'ESU'
  ///   'SHIPMENT-24-ESU'   → 'ESU'
  ///   'ESU'               → 'ESU'
  String _extractBatchId(String raw) {
    final candidates = raw
        .split('-')
        .where((p) => p.toUpperCase() != 'SHIPMENT' && p.length >= 3)
        .toList();
    return candidates.isNotEmpty ? candidates.first : raw;
  }

  // ── Abstract overrides ─────────────────────────────────────────────────
  @override
  String? get resolvedWarehouse => _parent.fromWarehouse.value;

  @override bool get requiresBatch => true;
  @override bool get requiresRack  => false;
  @override Color get accentColor  => Colors.purple;

  @override
  bool get isAddMode => editingItemName.value == null;

  @override
  MobileScannerController? get sheetScanController => null;

  // ── RackFieldWithBrowseDelegate: picker flow (Commit 9) ──────────────────

  /// Returns true when the picker preconditions are satisfied:
  ///   • itemCode is non-empty (item has been selected)
  ///   • resolvedWarehouse is non-null (source warehouse is known)
  @override
  bool get canBrowseRacks =>
      itemCode.value.isNotEmpty && resolvedWarehouse != null;

  // ── SourceRackDelegate: warehouse + change hook ────────────────────────────

  /// Resolved warehouse for the source-rack picker scope.
  ///
  /// Returns the parent SE's "from" warehouse so the [RackPickerController]
  /// is seeded with the correct warehouse filter on open.
  @override
  RxnString get sourceRackWarehouse => _parent.fromWarehouse;

  /// Called by [SharedSourceRackField] when the user edits the source-rack
  /// field directly (typed input).  Delegates to [validateDualRack] which
  /// handles balance fetch + [isSourceRackValid] state.
  @override
  Future<void> onSourceRackChanged(String rack) async =>
      validateDualRack(rack, true);

  // ── TargetRackDelegate: warehouse + change hook ────────────────────────────

  /// Resolved warehouse for the target-rack picker scope.
  ///
  /// Returns the parent SE's "to" warehouse so the [RackPickerController]
  /// for the target side is scoped to the correct destination warehouse.
  @override
  RxnString get targetRackWarehouse => _parent.toWarehouse;

  /// Called by [SharedTargetRackField] when the user edits the target-rack
  /// field directly (typed input).  Delegates to [validateDualRack] on the
  /// target side (isSource = false).
  @override
  Future<void> onTargetRackChanged(String rack) async =>
      validateDualRack(rack, false);

  /// Opens the rack picker sheet for the single-rack (non-dual) flow.
  ///
  /// Lifecycle mirrors [SharedDualRackSection._openRackPicker]:
  ///   1. Register a scoped [RackPickerController] with a timestamped tag.
  ///   2. Fire [RackPickerController.load] (non-blocking) with a snapshot
  ///      of [_rackStockMap] as fallbackMap.
  ///   3. Present [RackPickerSheet] via Get.bottomSheet.
  ///   4. Deferred-delete the controller in a post-frame callback.
  ///   5. Return [RackPickerResult] from the selected entry, or null.
  @override
  Future<RackPickerResult?> browseRacks() async {
    final tag = 'rack_picker_se_single_'
        '${DateTime.now().microsecondsSinceEpoch}';

    final ctrl = Get.put(RackPickerController(), tag: tag);

    unawaited(ctrl.load(
      itemCode:     itemCode.value,
      batchNo:      batchController.text.trim(),
      warehouse:    resolvedWarehouse ?? '',
      requestedQty: double.tryParse(qtyController.text) ?? 0.0,
      currentRack:  rackController.text.trim(),
      fallbackMap:  Map<String, double>.from(_rackStockMap),
    ));

    RackPickerResult? result;

    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          result = RackPickerResult(rackId: rack, availableQty: 0.0);
        },
      ),
      isScrollControlled: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });

    return result;
  }

  /// SE post-pick hook: writes the selected rack into [rackController] and
  /// fires [validateRack]. Declared explicitly so the @override annotation
  /// documents the intentional standard behaviour and future SE-specific
  /// post-pick logic can be added here without touching the base class.
  @override
  Future<void> handleRackPicked(RackPickerResult result) async {
    rackController.text = result.rackId;
    await validateRack(result.rackId);
  }

  // ── Batch-wise history (for BatchPickerSheet) ──────────────────────────────
  final RxList<BatchWiseBalanceRow> _batchWiseHistory = <BatchWiseBalanceRow>[].obs;
  @override List<BatchWiseBalanceRow> get batchWiseHistory => _batchWiseHistory;

  final RxBool _isLoadingBatchHistory = false.obs;
  @override RxBool get isLoadingBatchHistory => _isLoadingBatchHistory;

  @override
  Future<void> fetchBatchWiseHistory() async {
    if (_isLoadingBatchHistory.value) return;
    _isLoadingBatchHistory.value = true;
    try {
      final rows = await ApiProvider().getBatchWiseBalance(
        itemCode:  itemCode.value,
        warehouse: resolvedWarehouse,
      );
      _batchWiseHistory.assignAll(
        rows.map((r) => BatchWiseBalanceRow.fromMap(r)).toList(),
      );
    } catch (e) {
      log('[SE-Item] fetchBatchWiseHistory error: $e', name: 'SE-Item');
    } finally {
      _isLoadingBatchHistory.value = false;
    }
  }

  // ── openBatchPicker override ───────────────────────────────────────────────
  @override
  Future<void> openBatchPicker() async {
    if (batchWiseHistory.isEmpty && !isLoadingBatchHistory.value) {
      unawaited(fetchBatchWiseHistory());
    }
    await super.openBatchPicker();
  }

  // ── SerialFieldMixin: availableSerialNos ───────────────────────────────────
  @override
  List<String> get availableSerialNos => _parent.posUploadSerialOptions;

  // ── SerialFieldMixin: rich dropdown row metadata ──────────────────────────
  /// Resolves serial → PosUploadItem and returns the full tile metadata.
  /// Falls back to null (index-badge only) when no POS Upload is loaded or
  /// when the serial has no matching item.
  @override
  SerialDropdownItem? posDropdownItemFor(String serial) {
    final upload = _parent.posUpload.value;
    if (upload == null) return null;

    final idx = int.tryParse(serial);
    if (idx == null) return null;

    final posItem = upload.items.firstWhereOrNull((i) => i.idx == idx);
    if (posItem == null) return null;

    return SerialDropdownItem(
      serial:    serial,
      itemName:  posItem.itemName,
      qty:       posItem.quantity.toDouble(),
      remaining: liveRemaining.value,
    );
  }

  // ── SerialFieldMixin: POS qty cap for a given serial ──────────────────────
  //
  // Delegates to _parent.posQtyCapForSerial(serial), which resolves
  // serial → idx → PosUploadItem.quantity.  Returns double.infinity when
  // no POS Upload is loaded (badge hidden by the widget).
  @override
  double posItemQtyForSerial(String serial) =>
      _parent.posQtyCapForSerial(serial);

  // ── SerialFieldMixin: sum of all committed rows for this serial ────────────
  //
  // Walks the parent SE's in-memory items list synchronously — no API call.
  // Includes the row currently being edited (savedQtyForRow subtracts it
  // back out in computeLiveRemaining to avoid double-counting).
  @override
  double sumQtyUsedForSerial(String serial) {
    return (_parent.stockEntry.value?.items ?? [])
        .where((i) => (i.customInvoiceSerialNumber ?? '0') == serial)
        .fold(0.0, (sum, i) => sum + i.qty);
  }

  // ── SerialFieldMixin: saved qty of the row being edited ───────────────────
  //
  // In edit mode, computeLiveRemaining adds this value back so the live
  // remaining reacts correctly to the user's current input rather than
  // double-counting the saved row qty that sumQtyUsedForSerial already
  // includes.
  @override
  double savedQtyForRow(String rowId) {
    return _parent.stockEntry.value?.items
            .firstWhereOrNull((i) => i.name == rowId)
            ?.qty ??
        0.0;
  }

  // ── AutoFillRackMixin hooks ────────────────────────────────────────────────
  @override
  TextEditingController get autoFillRackController => sourceRackController;

  @override
  void onAutoFillRackSelected(String rack) => validateDualRack(rack, true);

  @override
  Map<String, double> get rackStockMap => _rackStockMap;

  // ── Dual-rack state ──────────────────────────────────────────────────────────
  //
  // Rule 1 (tec_lifecycle_rules.dart): These TECs are disposed via
  // disposeControllers() which is called inside addPostFrameCallback
  // in the base onClose() — never synchronously.
  @override final TextEditingController sourceRackController = TextEditingController();
  @override final RxBool isSourceRackValid       = false.obs;
  @override final RxBool isValidatingSourceRack  = false.obs;

  @override final TextEditingController targetRackController = TextEditingController();
  @override final RxBool isTargetRackValid       = false.obs;
  @override final RxBool isValidatingTargetRack  = false.obs;

  @override final RxBool isLoadingRackBalance    = false.obs;

  @override final RxnString itemSourceWarehouse    = RxnString(null);
  @override final RxnString derivedSourceWarehouse = RxnString(null);
  @override final RxnString itemTargetWarehouse    = RxnString(null);
  @override final RxnString derivedTargetWarehouse = RxnString(null);

  final Map<String, double> _rackStockMap = {};

  // ── DualRackDelegate: parent warehouse accessors ─────────────────────────
  @override
  RxnString get selectedFromWarehouse => _parent.fromWarehouse;

  @override
  RxnString get selectedToWarehouse => _parent.toWarehouse;

  @override
  RxString get selectedStockEntryType => _parent.stockEntryType;

  // ── Dual-rack actions ──────────────────────────────────────────────────────
  @override
  void resetSourceRackValidation() {
    sourceRackController.clear();
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
  }

  @override
  void resetTargetRackValidation() {
    targetRackController.clear();
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
  }

  @override
  Future<void> validateDualRack(String rack, bool isSource) async {
    if (rack.isEmpty) {
      if (isSource) { resetSourceRackValidation(); } else { resetTargetRackValidation(); }
      return;
    }
    if (isSource) {
      isValidatingSourceRack.value = true;
      isSourceRackValid.value      = false;
    } else {
      isValidatingTargetRack.value = true;
      isTargetRackValid.value      = false;
    }
    try {
      if (isSource) {
        isLoadingRackBalance.value = true;
        if (_rackStockMap.containsKey(rack)) {
          rackBalance.value = _rackStockMap[rack]!;
        } else {
          await fetchRackBalance(rack);
        }
        isLoadingRackBalance.value = false;
        isSourceRackValid.value    = true;
      } else {
        isTargetRackValid.value = true;
      }
      rackError.value = '';
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
      log('[SE-Item] validateDualRack error: $e', name: 'SE-Item');
      isLoadingRackBalance.value = false;
    } finally {
      if (isSource) { isValidatingSourceRack.value = false; }
      else          { isValidatingTargetRack.value = false; }
    }
  }

  /// Overrides [ItemSheetControllerBase.disposeControllers] to include
  /// the dual-rack TECs owned by this subclass.
  ///
  /// ## Rule 1 — tec_lifecycle_rules.dart
  ///
  /// This method is called by the base [onClose] from inside an
  /// `addPostFrameCallback`, so disposal is always deferred past the
  /// exit-animation frame — identical to the previous two-callback
  /// approach but expressed as a single override point.
  ///
  /// [super.disposeControllers] handles the base-class trio
  /// (`batchController`, `rackController`, `qtyController`) through
  /// its own idempotent + guarded try/catch blocks (Rule 2).
  @override
  void disposeControllers() {
    // Rule 1 (tec_lifecycle_rules.dart): capture TECs into locals BEFORE
    // calling super — super sets _controllersDisposed and removes listeners.
    // Disposal is deferred to the next frame so the exit animation
    // completes before _AnimatedState.didUpdateWidget fires addListener().
    // Capture local references — the controller fields may be nulled
    // or garbage-collected before the callback fires.
    final tecs = <TextEditingController>[
      batchController,
      qtyController,
      rackController,
      // add any others here
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final tec in tecs) {
        tec.dispose();
      }
    });
    super.disposeControllers();
  }

  /// Overrides [ItemSheetControllerBase.removeSheetListeners] to also remove
  /// [validateSheet] listeners from the dual-rack TECs owned by this subclass.
  ///
  /// ## Rule 3 — tec_lifecycle_rules.dart
  ///
  /// The base implementation only knows about [batchController],
  /// [rackController], and [qtyController].  [sourceRackController] and
  /// [targetRackController] are declared here and are invisible to the base,
  /// so their listeners would otherwise survive across [prepareForItem] calls,
  /// stacking duplicate [validateSheet] invocations on every keystroke.
  ///
  /// Note: _resetSaveStateOnEdit is file-private to
  /// item_sheet_controller_base.dart and is never wired to sourceRackController
  /// or targetRackController by addSheetListeners(), so no removeListener call
  /// for it is needed or possible here.
  @override
  void removeSheetListeners() {
    try { sourceRackController.removeListener(validateSheet); } catch (_) {}
    try { targetRackController.removeListener(validateSheet); } catch (_) {}
    super.removeSheetListeners();
  }

  // ── Derived / computed ────────────────────────────────────────────────────────
  double? get _posSerialCeiling {
    final serial = selectedSerial.value;
    if (serial == null || serial.isEmpty) return null;
    if (_parent.posUpload.value == null) return null;
    final remaining = _parent.remainingQtyForSerial(serial);
    return remaining == double.infinity ? null : remaining;
  }

  @override
  String? get qtyInfoText {
    final eff = effectiveMaxQty;
    if (eff == double.infinity) return null;
    return 'Max: ${eff.toStringAsFixed(eff.truncateToDouble() == eff ? 0 : 2)}';
  }

  /// Effective qty ceiling for SE: min(batchBalance, rackBalance,
  /// posSerialCeiling, mrQty) — whichever positive value is lowest.
  ///
  /// Returns [double.infinity] when no positive balance is available
  /// (open-ended entry; balances may still be loading).
  ///
  /// Overrides [ItemSheetControllerBase.effectiveMaxQty].
  @override
  double get effectiveMaxQty {
    double? ceil;

    final serial = _posSerialCeiling;
    if (serial != null && serial > 0) {
      ceil = serial;
    }

    final batch = batchBalance.value;
    if (batch > 0) {
      ceil = (ceil == null) ? batch : (batch < ceil ? batch : ceil);
    }

    final rack = rackBalance.value;
    if (rack > 0) {
      ceil = (ceil == null) ? rack : (rack < ceil ? rack : ceil);
    }

    final mr = _mrQty;
    if (mr != null && mr > 0) {
      ceil = (ceil == null) ? mr : (mr < ceil ? mr : ceil);
    }

    return ceil ?? double.infinity;
  }

  @override
  double get maxQty {
    final eff = effectiveMaxQty;
    return eff == double.infinity ? 0.0 : eff;
  }

  // ── State ──────────────────────────────────────────────────────────────────
  var uom              = ''.obs;
  var itemGroup        = ''.obs;
  var isBatchedItem    = false.obs;
  var isSerialisedItem = false.obs;
  var isEditingExisting = false.obs;

  /// Whether the item being edited/added is the finished-good row of a
  /// Manufacture Stock Entry ([StockEntryItem.isFinishedItem] == 1).
  ///
  /// When `true`, batch-balance validation is **relaxed**: a batch that
  /// exists but has a zero balance is accepted because the finished good
  /// is being *produced* (output row) — its balance starts at 0.
  ///
  /// This flag is seeded inside [_loadExistingItem] for edit mode and
  /// inside [initForNewItem] (reset to `false`) for add mode.
  var isFinishedItem = false.obs;

  String? editingOriginalBatch;

  // MR-link state
  String? _mrName;
  String? _mrItemName;
  double? _mrQty;
  String? _mrUom;
  String? _mrBatch;

  // ── Whether this SE type requires a source rack ──────────────────────────
  bool get _requiresSourceRack {
    final t = _parent.stockEntryType.value;
    return t == 'Material Issue' ||
        t == 'Material Transfer' ||
        t == 'Material Transfer for Manufacture';
  }

  @override
  bool get showSourceRack {
    if (selectedStockEntryType.value == 'Manufacture' && isFinishedItem.value) {
      return false;
    }
    return ['Material Issue', 'Material Transfer',
      'Material Transfer for Manufacture']
        .contains(selectedStockEntryType.value);
  }

  @override
  bool get showTargetRack {
    if (selectedStockEntryType.value == 'Manufacture' && isFinishedItem.value) {
      return true; // FG row always needs a target rack
    }
    return ['Material Receipt', 'Material Transfer',
      'Material Transfer for Manufacture']
        .contains(selectedStockEntryType.value);
  }

  // ── Sheet-valid gate ────────────────────────────────────────────────────────
  /// Recomputes [isSheetValid] based on the current field state.
  ///
  /// ## Batch gate relaxation for Manufacture finished-good rows
  ///
  /// For [StockEntrySource.manufacture] entries, the item with
  /// [isFinishedItem] == 1 is the *output* of the production run.
  /// Its batch balance is 0 by definition (it has not yet been
  /// manufactured), so the normal [isBatchValid] gate would permanently
  /// block the save button.  When [isFinishedItem] is `true` **and**
  /// [batchController] is non-empty **and** the parent SE type is
  /// `'Manufacture'`, the batch gate is treated as satisfied regardless
  /// of the balance returned by ERP.
  ///
  /// All other validation axes (qty > 0, qty ≤ ceiling, source-rack for
  /// transfer/issue types) remain unchanged.
  @override
  void validateSheet() {
    final qty  = double.tryParse(qtyController.text);
    final ceil = effectiveMaxQty;

    // rackOk: only enforce source-rack if the current item/context requires it.
    final rackOk = !showSourceRack || isSourceRackValid.value;
    final ceilOk   = ceil == double.infinity || (qty != null && qty <= ceil);
    final qtyOk    = qty != null && qty > 0;

    // ── isQtyValid / qtyError (Commit 6) ─────────────────────────────────
    if (!qtyOk) {
      isQtyValid.value = false;
      qtyError.value   = qty == null ? '' : 'Enter a quantity greater than 0';
    } else if (!ceilOk) {
      isQtyValid.value = false;
      final ceilStr = ceil.toStringAsFixed(
          ceil.truncateToDouble() == ceil ? 0 : 2);
      qtyError.value = 'Qty cannot exceed $ceilStr';
    } else {
      isQtyValid.value = true;
      qtyError.value   = '';
    }

    // Manufacture finished-good rows are outputs, not consumed stock.
    // Their batch may validly have a zero on-hand balance (it is being
    // produced right now), so we allow isBatchValid == false provided the
    // batch text is non-empty and the parent is a Manufacture SE.
    final batchOk = isBatchValid.value ||
        (_parent.stockEntryType.value == 'Manufacture' &&
            isFinishedItem.value &&
            batchController.text.isNotEmpty);

    final valid = batchOk && qtyOk && ceilOk && rackOk;

    isSheetValid.value = valid;

    // ── Live remaining via SerialFieldMixin ───────────────────────────────
    // computeLiveRemaining handles: no serial selected, no POS Upload loaded,
    // infinity cap (badge hidden), edit-mode double-count prevention via
    // savedQtyForRow(), and negative over-allocation values.
    computeLiveRemaining(
      currentTypedQty: qty ?? 0.0,
      editingRowId:    editingItemName.value,
    );

    final parts = <String>[];
    final serial = _posSerialCeiling;
    if (serial != null) parts.add('Serial: ${serial.toStringAsFixed(0)}');
    final batchBal = batchBalance.value;
    if (batchBal > 0) parts.add('Batch: ${batchBal.toStringAsFixed(0)}');
    final rackBal = rackBalance.value;
    if (rackBal > 0) parts.add('Rack: ${rackBal.toStringAsFixed(0)}');
    final mr = _mrQty;
    if (mr != null && mr > 0) parts.add('MR: ${mr.toStringAsFixed(0)}');
    qtyInfoTooltip.value = parts.isEmpty ? null : parts.join('  \u00b7  ');
  }

  // ── adjustQty ───────────────────────────────────────────────────────────────────
  /// Increments or decrements qty by [delta], clamped to
  /// [0.0, effectiveMaxQty] (Commit 6: was clamped to double.infinity).
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, effectiveMaxQty);
    qtyController.text = next.toStringAsFixed(
        next.truncateToDouble() == next ? 0 : 2);
    validateSheet();
  }

  // ── deleteCurrentItem ───────────────────────────────────────────────────────────
  @override
  void deleteCurrentItem() {
    final rowId = editingItemName.value;
    if (rowId == null) return;
    final item = _parent.stockEntry.value?.items
        .firstWhereOrNull((i) => i.name == rowId);
    if (item == null) return;
    _parent.confirmAndDeleteItem(item);
  }

  // ── MR link ───────────────────────────────────────────────────────────────────
  void linkMrItem({
    required String mrName,
    required String itemName,
    required String uom,
    required double qty,
    String? batchNo,
  }) {
    _mrName     = mrName;
    _mrItemName = itemName;
    _mrQty      = qty;
    _mrUom      = uom;
    _mrBatch    = batchNo;
  }

  void clearMrLink() {
    _mrName = _mrItemName = _mrUom = _mrBatch = null;
    _mrQty  = null;
  }

  String? get mrName     => _mrName;
  String? get mrItemName => _mrItemName;
  double? get mrQty      => _mrQty;
  String? get mrUom      => _mrUom;
  String? get mrBatch    => _mrBatch;

  // ── Init helpers ──────────────────────────────────────────────────────────────
  void initForItem({
    required String code,
    required String name,
    required String uomValue,
    required String group,
    required bool   hasBatch,
    required bool   hasSerial,
  }) {
    itemCode.value         = code;
    itemName.value         = name;
    uom.value              = uomValue;
    itemGroup.value        = group;
    isBatchedItem.value    = hasBatch;
    isSerialisedItem.value = hasSerial;
  }

  /// Resets all sheet state for a new (add-mode) item session.
  ///
  /// ## isClosed guard
  ///
  /// Returns immediately when [isClosed] is true.  This prevents
  /// "Cannot use a disposed controller" and "Cannot write to a closed
  /// observable" exceptions on racing async paths where [prepareForItem]
  /// is still executing after the sheet has been dismissed and GetX has
  /// already called [onClose] on this controller.
  void initForNewItem() {
    if (isClosed) return;
    editingItemName.value    = null;
    isEditingExisting.value  = false;
    isFinishedItem.value = false; // reset; seeded later by _loadExistingItem
    editingOriginalBatch     = null;
    // Commit 6: reset docStatus → unlocks isQtyReadOnly via ever() worker.
    docStatus.value          = 0;
    clearMrLink();
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    sourceRackController.clear();
    targetRackController.clear();
    isBatchValid.value    = false;
    isBatchReadOnly.value = false;
    batchError.value      = '';
    batchInfoTooltip.value = null;
    isRackValid.value     = false;
    rackError.value       = '';
    batchBalance.value    = 0.0;
    rackBalance.value     = 0.0;
    liveRemaining.value   = 0.0;
    isSheetValid.value    = false;
    isQtyValid.value      = false;
    qtyError.value        = '';
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
    isLoadingRackBalance.value   = false;
    _batchWiseHistory.clear();
    // Reset serial selection so a freshly opened sheet never inherits the
    // serial from a previous sheet session.
    selectedSerial.value = null;
  }

  /// Populates sheet state from an existing [StockEntryItem] (edit mode).
  ///
  /// ## isClosed guard
  ///
  /// Returns immediately when [isClosed] is true.  Without this guard,
  /// a racing dismiss between the `await ApiProvider().getDocument()`
  /// call in [initialise] and this method's synchronous TEC/Rx writes
  /// would throw "Cannot use a disposed controller".  The
  /// `addPostFrameCallback` closures below already carry `if (!isClosed)`
  /// individually; this top-level guard makes the entire method safe.
  void _loadExistingItem(
    StockEntryItem item,
    List<Map<String, dynamic>> mrReferenceItems,
  ) {
    if (isClosed) return;
    isEditingExisting.value = true;
    editingOriginalBatch    = item.batchNo;
    editingItemName.value   = item.name;

    // fix(docstatus): docstatus belongs to the parent document, not the item
    // row. Read from parent StockEntry to drive the isQtyReadOnly lock.
    docStatus.value = _parent.stockEntry.value?.docstatus ?? 0;

    // Seed finished-item flag so validateSheet() can relax the
    // batch-balance gate for the Manufacture FG row.
    isFinishedItem.value = item.isFinishedItem == 1;

    batchController.text        = item.batchNo ?? '';
    rackController.text         = item.rack    ?? '';
    sourceRackController.text   = item.rack    ?? '';
    targetRackController.text   = item.toRack  ?? '';
    qtyController.text          = item.qty.toString();

    if (item.customInvoiceSerialNumber != null &&
        item.customInvoiceSerialNumber != '0') {
      selectedSerial.value = item.customInvoiceSerialNumber;
    }

    final mrMatch = mrReferenceItems.firstWhereOrNull(
      (r) => r['item_code'] == item.itemCode,
    );
    if (mrMatch != null) {
      linkMrItem(
        mrName:   mrMatch['parent']    as String? ?? '',
        itemName: mrMatch['item_name'] as String? ?? '',
        qty:      (mrMatch['qty'] as num?)?.toDouble() ?? 0.0,
        uom:      mrMatch['uom']       as String? ?? '',
        batchNo:  mrMatch['batch_no']  as String?,
      );
    }

    if (item.batchNo != null && item.batchNo!.isNotEmpty) {
      validateBatchOnInit(item.batchNo!);
    }
    if (item.rack != null && item.rack!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateDualRack(item.rack!, true);
      });
    }
    if (item.toRack != null && item.toRack!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) validateDualRack(item.toRack!, false);
      });
    }
  }

  /// Prepares this controller for a new or existing item sheet session.
  ///
  /// ## Rule 3 — tec_lifecycle_rules.dart
  ///
  /// [removeSheetListeners] is called **before** [addSheetListeners] so
  /// that any listeners wired in a previous session are removed before the
  /// new session registers its own copies.  Without this, each successive
  /// call to `prepareForItem` on a reused controller instance stacks
  /// another duplicate of every listener onto the same TECs, causing:
  ///   • Redundant `validateSheet()` calls on every keystroke.
  ///   • Stale listeners that fire after the controller is disposed,
  ///     potentially crashing in a future session.
  Future<void> prepareForItem({
    required String itemCode,
    required String itemName,
    required String uom,
    required String itemGroup,
    required bool   hasBatch,
    required bool   hasSerial,
    StockEntryItem? existingItem,
    List<Map<String, dynamic>> mrReferenceItems = const [],
    String? scannedBatch,
  }) async {
    initForItem(
      code:      itemCode,
      name:      itemName,
      uomValue:  uom,
      group:     itemGroup,
      hasBatch:  hasBatch,
      hasSerial: hasSerial,
    );

    if (existingItem != null) {
      _loadExistingItem(existingItem, mrReferenceItems);
    } else {
      initForNewItem();
      if (scannedBatch != null && scannedBatch.isNotEmpty) {
        batchController.text = scannedBatch;
        validateBatchOnInit(scannedBatch);
      }
    }

    // Rule 3 (tec_lifecycle_rules.dart): remove prior-session listeners
    // before registering new ones to prevent accumulation.
    removeSheetListeners();
    addSheetListeners();
    snapshotState();
    // captureSerialSnapshot() is called inside snapshotState() via the
    // SerialFieldMixin hook — baseline for isSerialDirty dirty-detection.
    captureSerialSnapshot();
  }

  Future<void> initialise({
    required StockEntryFormController parent,
    required String code,
    required String name,
    String variantOf          = '',
    String itemName           = '',
    String? batchNo,
    StockEntryItem? editingItem,
    List<Map<String, dynamic>> mrReferenceItems = const [],
    String scannedEan8        = '',
  }) async {
    _parent = parent;

    String uomValue   = 'Nos';
    String group      = '';
    bool   hasBatch   = false;
    bool   hasSerial  = false;

    try {
      final meta = await ApiProvider().getDocument('Item', code);
      if (meta.statusCode == 200 && meta.data['data'] != null) {
        final d  = meta.data['data'] as Map<String, dynamic>;
        uomValue  = d['stock_uom']       as String? ?? 'Nos';
        group     = d['item_group']      as String? ?? '';
        hasBatch  = (d['has_batch_no']   as int?)    == 1;
        hasSerial = (d['has_serial_no']  as int?)    == 1;
      }
    } catch (e) {
      log('[SE-Item] initialise: failed to fetch item meta: $e', name: 'SE-Item');
    }

    await prepareForItem(
      itemCode:         code,
      itemName:         itemName,
      uom:              uomValue,
      itemGroup:        group,
      hasBatch:         hasBatch,
      hasSerial:        hasSerial,
      existingItem:     editingItem,
      mrReferenceItems: mrReferenceItems,
      scannedBatch:     batchNo,
    );

    if (scannedEan8.isNotEmpty) currentScannedEan = scannedEan8;

    unawaited(_preloadRackStockMap());
  }

  Future<void> _preloadRackStockMap() async {
    try {
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: resolvedWarehouse,
      );
      final map = <String, double>{};
      for (final r in rows) {
        final rack = r['rack'] as String?;
        final qty  = (r['qty'] as num?)?.toDouble() ?? 0.0;
        if (rack != null && rack.isNotEmpty) map[rack] = qty;
      }
      seedRackStockMap(map);
    } catch (e) {
      log('[SE-Item] _preloadRackStockMap error: $e', name: 'SE-Item');
    }
  }

  // ── submit ────────────────────────────────────────────────────────────────────
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Invalid quantity');

    final batch      = isBatchValid.value ? batchController.text : null;
    final srcRack    = isSourceRackValid.value ? sourceRackController.text : null;
    final tgtRack    = isTargetRackValid.value ? targetRackController.text : null;
    final serial     = selectedSerial.value;

    final sWh = itemSourceWarehouse.value ?? _parent.fromWarehouse.value;
    final tWh = itemTargetWarehouse.value ?? _parent.toWarehouse.value;

    final rowId = editingItemName.value;
    if (rowId != null) {
      _parent.updateItemLocally(
        rowId, qty, batch, srcRack, tgtRack, sWh, tWh, serial,
      );
    } else {
      _parent.addItemLocally(
        qty, batch, srcRack, tgtRack, sWh, tWh, serial,
      );
    }
  }

  @override
  void onClose() {
    disposeBarcodeListener();   // BarcodeAwareMixin: safety-net disposal
    disposeAutoFillListener();
    super.onClose();
  }

  // ── validateRack override (uses rackStockMap cache) ──────────────────────
  @override
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) { resetRack(); return; }
    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;
    try {
      if (_rackStockMap.containsKey(rack)) {
        rackBalance.value = _rackStockMap[rack]!;
      } else {
        await fetchRackBalance(rack);
      }
      isRackValid.value = true;
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
    } finally {
      isValidatingRack.value = false;
    }
  }

  void seedRackStockMap(Map<String, double> map) {
    _rackStockMap
      ..clear()
      ..addAll(map);
  }

  @override
  void applyRackScan(String rackId) {
    // Route the scanned rack to the correct side based on what is visible
    // (and therefore applicable) for the current SE type.
    //
    // For SE types where source rack is not shown (e.g. Material Receipt),
    // the very first scan must go directly to the target rack controller.
    // The old logic checked sourceRackController.text.isEmpty, which is always
    // true on a fresh form and caused Material Receipt scans to silently set
    // the hidden source rack instead of the visible target rack.
    //
    // Priority:
    //   1. If showSourceRack and sourceRackController is empty → fill source.
    //   2. If showTargetRack and targetRackController is empty → fill target.
    //   3. Otherwise fall back to source (handles single-rack SE types like
    //      Material Issue where only source is shown).
    if (showSourceRack && sourceRackController.text.isEmpty) {
      sourceRackController.text = rackId;
      validateDualRack(rackId, true);
    } else if (showTargetRack && targetRackController.text.isEmpty) {
      targetRackController.text = rackId;
      validateDualRack(rackId, false);
    } else if (showSourceRack) {
      // Both racks already filled or second scan on a source-only type:
      // overwrite source (original fallback behaviour).
      sourceRackController.text = rackId;
      validateDualRack(rackId, true);
    } else {
      // showTargetRack only (e.g. Material Receipt with target already set):
      // overwrite target.
      targetRackController.text = rackId;
      validateDualRack(rackId, false);
    }
  }

  bool get needsRackScanFallback =>
      (showSourceRack && sourceRackController.text.isEmpty) ||
          (showTargetRack && targetRackController.text.isEmpty);

  // ── Snackbar helpers ──────────────────────────────────────────────────────────
  void showError(String msg)   => GlobalSnackbar.error(message: msg);
  void showSuccess(String msg) => GlobalSnackbar.success(message: msg);
}
