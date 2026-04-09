import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/models/batch_wise_balance_row.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_autofill_rack.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';
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
///
/// feat(barcode): wire BarcodeAwareMixin — hardware + camera scan routing
///   • `with BarcodeAwareMixin` added to the mixin chain.
///   • onInit() calls initBarcodeListeners() after super.onInit() so both
///     DataWedgeService and ScanService streams are subscribed.
///   • _targetRackController / _targetRackFocusNode getters route targetRack
///     scans to targetRackController / targetRackFocusNode.
///   • onTargetRackScanned delegates to validateDualRack(barcode, false).
///   • activeScanScopes keeps all four scopes (itemBarcode, batchNo,
///     sourceRack, targetRack) — the full SE routing chain.
///
/// feat(barcode): implement onItemBarcodeScanned — SE item lookup on scan
///   • Overrides BarcodeAwareMixin.onItemBarcodeScanned(String barcode) to
///     store the raw EAN in currentScannedEan and delegate item lookup to
///     _parent.onItemBarcodeScanned(barcode), which is the existing parent-
///     level handler responsible for resolving the barcode to an itemCode
///     and calling prepareForItem() on this controller.
///   • currentScannedEan is set before the parent call so that any sync
///     path inside the parent that reads currentScannedEan (e.g. to open a
///     variant picker) sees the correct value immediately.
class StockEntryItemFormController extends ItemSheetControllerBase
    with SerialFieldMixin, AutoFillRackMixin, BarcodeAwareMixin
    implements DualRackDelegate {

  // ── Parent back-reference ──────────────────────────────────────────────────────
  late StockEntryFormController _parent;

  StockEntryFormController get parent => _parent;

  // ── In-sheet scan context ───────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Abstract overrides ─────────────────────────────────────────────────
  @override
  String? get resolvedWarehouse => _parent.selectedFromWarehouse.value;

  @override bool get requiresBatch => true;
  @override bool get requiresRack  => false;
  @override Color get accentColor  => Colors.purple;

  @override
  bool get isAddMode => editingItemName.value == null;

  @override
  MobileScannerController? get sheetScanController => null;

  // ── BarcodeAwareMixin: lifecycle ───────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    initBarcodeListeners();
  }

  // ── BarcodeAwareMixin: item barcode scan ───────────────────────────────

  /// Called by [BarcodeAwareMixin._applyToScope] when a scan is routed to
  /// [ScanScope.itemBarcode] (Priority 1 focus win, Priority 2 first-empty,
  /// or Priority 3 fallback).
  ///
  /// Stores the raw EAN/barcode in [currentScannedEan] so the parent can
  /// read it synchronously during variant resolution, then delegates to
  /// [_parent.onItemBarcodeScanned] to run the full item-lookup flow
  /// (API call → prepareForItem).
  @override
  void onItemBarcodeScanned(String barcode) {
    if (isClosed) return;
    currentScannedEan = barcode;
    _parent.onItemBarcodeScanned(barcode);
  }

  // ── BarcodeAwareMixin: dual-rack scan routing ──────────────────────────

  /// Expose [targetRackController] so the mixin's focus-priority chain can
  /// write scanned barcodes directly into the target-rack field.
  @override
  TextEditingController? get _targetRackController => targetRackController;

  /// Expose [targetRackFocusNode] so the mixin can detect when the
  /// target-rack field is focused and route the scan accordingly.
  @override
  FocusNode? get _targetRackFocusNode => targetRackFocusNode;

  /// Validate the scanned barcode against the target warehouse rack list.
  @override
  void onTargetRackScanned(String barcode) {
    validateDualRack(barcode, false);
  }

  // ── RackFieldWithBrowseDelegate: picker flow (Commit 9) ──────────────────

  /// Returns true when the picker preconditions are satisfied:
  ///   • itemCode is non-empty (item has been selected)
  ///   • resolvedWarehouse is non-null (source warehouse is known)
  @override
  bool get canBrowseRacks =>
      itemCode.value.isNotEmpty && resolvedWarehouse != null;

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
  @override final FocusNode targetRackFocusNode              = FocusNode();
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
  RxnString get selectedFromWarehouse => _parent.selectedFromWarehouse;

  @override
  RxnString get selectedToWarehouse => _parent.selectedToWarehouse;

  @override
  RxString get selectedStockEntryType => _parent.selectedStockEntryType;

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
  /// (batchController / rackController / qtyController).
  @override
  void disposeControllers() {
    try { sourceRackController.dispose(); } catch (_) {}
    try { targetRackController.dispose(); } catch (_) {}
    try { targetRackFocusNode.dispose();  } catch (_) {}
    super.disposeControllers();
  }

  @override
  void onClose() {
    super.onClose(); // base defers disposeControllers + cancels _dwSub/_scanSub
  }
}
