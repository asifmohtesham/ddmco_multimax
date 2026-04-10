import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/barcode_aware_mixin.dart';
import 'package:multimax/app/shared/item_sheet/batch_no_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/qty_cap_delegate.dart';
import 'package:multimax/app/shared/item_sheet/qty_field_with_plus_minus_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';

/// Drives the visual state of the animated Save button in the item sheet.
enum SaveButtonState { idle, loading, success, error }

/// Base return type for batch-lookup results.
class BatchResult {
  final String batchNo;
  final double availableQty;
  final String? expiryDate;

  const BatchResult({
    required this.batchNo,
    required this.availableQty,
    this.expiryDate,
  });
}

// ──────────────────────────────────────────────────────────────────────────────────
// ItemSheetControllerBase
// ──────────────────────────────────────────────────────────────────────────────────
///
/// Shared state and behaviour for all item-sheet controllers (Stock Entry,
/// Delivery Note, Purchase Receipt …).
///
/// ## Responsibilities
///
///   • Batch validation lifecycle  — [validateBatch], [resetBatch],
///     [softResetBatch], [validateBatchOnInit], [isBatchValid], [batchError],
///     [batchInfoTooltip]
///   • Rack validation lifecycle   — [validateRack], [resetRack],
///     [softResetRack]
///   • Balance computation         — [maxQty], [batchBalance], [fetchBatchBalance]
///   • Save-button state           — [SaveButtonState], [saveButtonState]
///   • Sheet-valid gate            — [isSheetValid] (RxBool), [validateSheet]
///   • Dirty-check helpers         — [isDirty], snapshot tracking
///   • [openBatchPicker]           — canonical picker lifecycle shared by all
///     concrete controllers.  SE overrides to pre-fetch [batchWiseHistory].
///
/// ## TEC Lifecycle
///
/// All [TextEditingController], [FocusNode], and [ScrollController] fields
/// in this class and its subclasses MUST follow the four rules documented in
/// `tec_lifecycle_rules.dart`.  The disposal contract is:
///
///   • [disposeControllers] is the single disposal path — guarded by
///     [_controllersDisposed] so it is safe to call any number of times.
///   • [onClose] delegates to [disposeControllers]; it does NOT contain an
///     independent inline disposal block.
///   • Subclass [onClose] overrides that own additional TECs (e.g.
///     [StockEntryItemFormController.sourceRackController]) MUST defer their
///     disposal via `addPostFrameCallback` (Rule 1) and call `super.onClose()`
///     AFTER scheduling the deferred callback.
///   • [addSheetListeners] must always be preceded by [removeSheetListeners]
///     (Rule 3) — see [prepareForItem] in concrete subclasses.
///
/// ## Changelog
///
///   isSheetValid     — promoted from computed bool getter to RxBool so
///                      UniversalItemFormSheet can pass it as isSaveEnabledRx.
///                      Concrete controllers write this inside validateSheet().
///   liveRemaining    — concrete RxDouble(0.0); SE writes it in
///                      validateSheet(); SharedSerialField reads it on
///                      the base type.
///   editingItemName  — RxnString; null = add-mode, non-null = edit rowId.
///   formKey          — shared GlobalKey<FormState>.
///   itemName/Owner/Creation/Modified/ModifiedBy — shared metadata Rx fields.
///   qtyInfoText      — abstract String? getter (nullable); each controller
///                      supplies its own label or null (no chip).
///   qtyInfoTooltip   — CONCRETE RxnString field (promoted from abstract).
///                      SE writes it directly inside validateSheet().
///   adjustQty        — abstract; concrete controllers implement stepper.
///   deleteCurrentItem — abstract; concrete controllers implement deletion.
///   sheetScanController/isScanning — scan-bar integration.
///   isAddMode        — abstract bool (satisfies AutoFillRackMixin contract).
///   setupAutoSubmit  — wires the auto-close worker; available to all.
///   initBaseListeners/captureSnapshot — aliases for addSheetListeners /
///                      snapshotState used by PO and PS controllers.
///   sheetScrollController — concrete ScrollController exposed so parent
///                      orchestrators can pass it to UniversalItemFormSheet.
///   disposeControllers — public teardown helper; now idempotent via
///                      _controllersDisposed guard (Rule 2).
///   softResetBatch / softResetRack — reset validity flags without zeroing
///                      balances (DN-8 fix).
///   validateBatchOnInit — convenience post-frame wrapper.
///   validateRack     — base implementation delegates to fetchRackBalance.
///   RackFieldWithBrowseDelegate — base class implements (Commit 3 of 4).
///   BatchNoFieldWithBrowseDelegate — base class implements (Commit 7 of 7).
///   QtyFieldWithPlusMinusDelegate — base class implements (this commit).
///     isQtyValid     — dedicated RxBool field; written by validateSheet.
///     qtyError       — RxString(''); written by validateSheet.
///     isQtyReadOnly  — backed by _isQtyReadOnly; wired to docStatus == 1.
///     effectiveMaxQty — double.infinity base default; SE/DN/PR override.
///     docStatus      — RxInt(0); write to lock/unlock the qty field.
///   fix(item-sheet): defer TextEditingController disposal to post-frame
///     so the bottom-sheet exit animation completes before controllers are
///     invalidated.  Prevents "TextEditingController was used after being
///     disposed" crash triggered by back-nav with keyboard open.
///   fix(item-sheet): guard disposeControllers against double-dispose
///     — _controllersDisposed bool + onClose delegates to disposeControllers.
///   feat(barcode): add itemBarcodeFocusNode + batchFocusNode
///     — BarcodeAwareMixin resolves all focus nodes through the base type
///       without casting.  Both nodes disposed in disposeControllers().
///   feat(barcode): wire BarcodeAwareMixin
///     — initBarcodeListeners() called in onInit(); mixin applied on each
///       concrete subclass (SE, DN, PO, PR, PS) — NOT on this base class.
///   fix(barcode): remove circular `with BarcodeAwareMixin` from base class
///     — BarcodeAwareMixin is declared `on ItemSheetControllerBase`; applying
///       it here created a recursive superinterface cycle (issue #22 Group 1).
abstract class ItemSheetControllerBase extends GetxController
    implements
        RackFieldWithBrowseDelegate,
        BatchNoFieldWithBrowseDelegate,
        QtyFieldWithPlusMinusDelegate {
  // ── Reactive state ────────────────────────────────────────────────────────
  final RxBool   isBatchValid          = false.obs;
  final RxBool   isValidatingBatch     = false.obs;
  final RxBool   isBatchReadOnly       = false.obs;
  final RxString batchError            = RxString('');
  final RxnString batchInfoTooltip     = RxnString(null);
  final RxBool   isRackValid           = false.obs;
  final RxBool   isValidatingRack      = false.obs;
  final RxString rackError             = RxString('');
  final RxDouble batchBalance          = 0.0.obs;
  final RxDouble rackBalance           = 0.0.obs;
  final RxBool   saveButtonVisible     = true.obs;
  final Rx<SaveButtonState> saveButtonState = SaveButtonState.idle.obs;
  final RxBool   isSheetLoading        = false.obs;

  /// Whether the sheet scanner is active.
  final RxBool   isScanning            = false.obs;

  /// Remaining quantity after the entered qty is subtracted from the
  /// effective ceiling.  Written by [validateSheet] in concrete controllers
  /// that track a qty ceiling (e.g. SE).  Defaults to 0.0.
  final RxDouble liveRemaining         = 0.0.obs;

  /// Whether the sheet is valid and the Save button should be enabled.
  /// Concrete controllers write this inside [validateSheet].
  final RxBool   isSheetValid          = false.obs;

  /// Tooltip shown in the rack suffix when a rack is selected.
  final RxnString rackStockTooltip     = RxnString(null);

  // ── QtyFieldWithPlusMinusDelegate concrete fields ────────────────────────

  /// Whether the qty sub-field is valid.
  ///
  /// Dedicated [RxBool] — NOT an alias of [isSheetValid].  The sheet-level
  /// save gate should compose sub-validations:
  /// ```dart
  /// isSheetValid.value =
  ///     isQtyValid.value && isBatchValid.value && isRackValid.value;
  /// ```
  /// Concrete [validateSheet] implementations write this field directly.
  @override
  final RxBool isQtyValid = false.obs;

  /// Inline error text shown beneath the qty field.
  ///
  /// `''` = no error (same contract as [rackError] / [batchError]).
  /// Concrete [validateSheet] implementations write this field directly.
  @override
  final RxString qtyError = RxString('');

  /// Docstatus of the row being viewed / edited.
  ///
  /// Write `docStatus.value = row['docstatus']` in [initForEdit].
  /// The [ever] worker in [onInit] automatically locks the qty field
  /// when this reaches 1 (submitted).
  final RxInt docStatus = 0.obs;

  // Backing field for isQtyReadOnly — never expose as a getter literal
  // (.obs) because that allocates a new Rx on every access, breaking
  // Obx subscriptions in SharedQtyField.
  final RxBool _isQtyReadOnly = false.obs;

  /// Whether the qty field and ± buttons are read-only.
  ///
  /// Automatically `true` when [docStatus] == 1 (submitted).
  /// Concrete controllers may also set `_isQtyReadOnly.value = true`
  /// for DocType-specific pre-conditions (e.g. missing warehouse).
  @override
  RxBool get isQtyReadOnly => _isQtyReadOnly;

  /// The effective qty ceiling for the ± buttons and blur-clamp.
  ///
  /// Base default: [double.infinity] (uncapped).  SE, DN, and PR
  /// override this in Commit 6 with their DocType-specific formulas.
  @override
  double get effectiveMaxQty => double.infinity;

  // ── Edit-mode identity ───────────────────────────────────────────────────
  /// null = add-mode; non-null = the rowId / docName being edited.
  final RxnString editingItemName      = RxnString(null);

  // ── Item metadata (shown in sheet footer) ────────────────────────────────────
  final RxString  itemName             = ''.obs;
  final RxnString itemOwner            = RxnString(null);
  final RxnString itemCreation         = RxnString(null);
  final RxnString itemModified         = RxnString(null);
  final RxnString itemModifiedBy       = RxnString(null);

  // ── Form key ────────────────────────────────────────────────────────────────
  final GlobalKey<FormState> formKey   = GlobalKey<FormState>();

  // ── isAddingItemFlag (used by PO/PS controllers) ───────────────────────────
  bool isAddingItemFlag = false;

  // ── Text controllers ──────────────────────────────────────────────────────────
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();

  /// Backing text controller for the qty field.
  ///
  /// Exposed here (and via [QtyFieldDelegate.qtyController]) so
  /// [SharedQtyField] and all existing listeners ([addSheetListeners],
  /// [disposeControllers], [onClose]) can access it through a single
  /// concrete field.
  @override
  final TextEditingController qtyController   = TextEditingController();

  // ── Focus nodes ───────────────────────────────────────────────────────────

  /// FocusNode for the rack text field.
  final FocusNode rackFocusNode         = FocusNode();

  /// FocusNode for the item barcode / item-code field.
  ///
  /// Used by [BarcodeAwareMixin._focusedScope] to detect when the item
  /// barcode field has keyboard focus and route the next scan directly
  /// into [itemCode] without falling through to the empty-field chain.
  final FocusNode itemBarcodeFocusNode  = FocusNode();

  /// FocusNode for the Batch No field.
  ///
  /// Used by [BarcodeAwareMixin._focusedScope] to detect when the batch
  /// field has keyboard focus and route the next scan directly into
  /// [batchController] without falling through to the empty-field chain.
  final FocusNode batchFocusNode        = FocusNode();

  /// ScrollController for the sheet's scrollable body.
  ///
  /// Exposed so parent orchestrators (e.g. DeliveryNoteFormController) can
  /// pass it directly to UniversalItemFormSheet without requiring each
  /// concrete subclass to declare its own field (Group B — B1 fix).
  final ScrollController sheetScrollController = ScrollController();

  var itemCode = ''.obs;

  // ── batchWiseHistory defaults ──────────────────────────────────────────────────
  List<dynamic> get batchWiseHistory       => const [];
  RxBool        get isLoadingBatchHistory  => false.obs;
  Future<void>  fetchBatchWiseHistory()    async {}

  // ── maxQty default ────────────────────────────────────────────────────────────────
  double get maxQty => 0.0;

  // Dirty-tracking snapshots
  String _snapshotBatch = '';
  String _snapshotRack  = '';
  String _snapshotQty   = '';

  // ── Auto-submit worker ──────────────────────────────────────────────────────────
  Worker? _autoSubmitWorker;

  // ── TEC disposal guard (Rule 2 — tec_lifecycle_rules.dart) ─────────────────
  //
  // Set to true the first time disposeControllers() runs.  All subsequent
  // calls become no-ops, making the disposal path idempotent regardless of
  // whether GetX's onClose() or a parent-orchestrated cleanup fires first.
  bool _controllersDisposed = false;

  // ── Abstract interface ───────────────────────────────────────────────────────────

  /// The warehouse resolved at runtime for API calls (batch balance, rack
  /// stock).  Returns null when no warehouse has been selected yet.
  String? get resolvedWarehouse;

  /// Whether the current item requires a batch number.
  bool get requiresBatch;

  /// Whether the current item requires a rack selection.
  bool get requiresRack;

  /// Accent colour used for DocType-specific UI accents.
  Color get accentColor;

  /// Whether the sheet is in add-mode (true) or edit-mode (false).
  bool get isAddMode;

  /// The [MobileScannerController] driving the in-sheet camera scan bar.
  /// Return null for DocTypes that do not show the camera scan bar.
  MobileScannerController? get sheetScanController;

  /// Human-readable label shown in the qty info chip.
  /// Return null to hide the chip entirely.
  String? get qtyInfoText;

  /// Tooltip shown inside the qty info chip.
  final RxnString qtyInfoTooltip = RxnString(null);

  /// Adjust the qty field value by [delta] (positive = increment,
  /// negative = decrement).  Concrete controllers clamp to [effectiveMaxQty].
  void adjustQty(double delta);

  /// Delete the currently loaded item row.  Concrete controllers implement
  /// confirmation dialogs and parent-list mutations.
  void deleteCurrentItem();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    ever(docStatus, (_) {
      _isQtyReadOnly.value = docStatus.value == 1;
    });
    initBarcodeListeners();
  }

  // ── Sheet listener management (Rule 3) ────────────────────────────────────

  /// Wires [validateSheet] as a listener on all base-class TECs.
  ///
  /// Always call [removeSheetListeners] immediately before this method
  /// (Rule 3 — tec_lifecycle_rules.dart) to prevent listener accumulation
  /// across reused controller sessions.
  void addSheetListeners() {
    batchController.addListener(validateSheet);
    rackController.addListener(validateSheet);
    qtyController.addListener(validateSheet);
  }

  /// Alias used by PO / PS controllers that prefer the `initBaseListeners`
  /// naming convention.
  void initBaseListeners() => addSheetListeners();

  /// Removes [validateSheet] listeners from all base-class TECs.
  void removeSheetListeners() {
    batchController.removeListener(validateSheet);
    rackController.removeListener(validateSheet);
    qtyController.removeListener(validateSheet);
  }

  // ── Sheet validation (abstract) ────────────────────────────────────────────

  /// Concrete controllers compute validity and write [isSheetValid],
  /// [isQtyValid], [qtyError], [liveRemaining], and [qtyInfoTooltip] here.
  void validateSheet();

  // ── Snapshot / dirty tracking ─────────────────────────────────────────────

  /// Captures the current field values as the clean baseline for
  /// [isDirty] comparisons.
  void snapshotState() {
    _snapshotBatch = batchController.text;
    _snapshotRack  = rackController.text;
    _snapshotQty   = qtyController.text;
  }

  /// Alias used by PO / PS controllers.
  void captureSnapshot() => snapshotState();

  /// Returns true when any field has diverged from the last [snapshotState].
  bool get isDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Auto-submit worker ────────────────────────────────────────────────────

  /// Wires a [once] worker that calls [submit] the first time
  /// [isSheetValid] becomes true.
  ///
  /// Used by DocTypes (e.g. SE) that want the sheet to save automatically
  /// after a successful barcode scan completes all required fields.
  void setupAutoSubmit() {
    _autoSubmitWorker?.dispose();
    _autoSubmitWorker = once(isSheetValid, (bool valid) {
      if (valid) submit();
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  /// Saves the current item row.  Delegates to the parent form controller.
  Future<void> submit();

  // ── Batch validation ──────────────────────────────────────────────────────

  /// Validates [batchNo] against the ERPNext batch list for the current
  /// item + warehouse combination.
  ///
  /// Writes [isBatchValid], [isValidatingBatch], [batchError],
  /// [batchBalance], and [batchInfoTooltip] on completion.
  Future<void> validateBatch(String batchNo) async {
    if (batchNo.isEmpty) {
      resetBatch();
      return;
    }
    isValidatingBatch.value = true;
    isBatchValid.value      = false;
    batchError.value        = '';
    try {
      final result = await fetchBatchBalance(batchNo);
      batchBalance.value    = result.availableQty;
      batchInfoTooltip.value =
          result.expiryDate != null ? 'Exp: ${result.expiryDate}' : null;
      isBatchValid.value    = true;
    } catch (e) {
      batchError.value = e.toString();
      log('[Base] validateBatch error: $e', name: 'ItemSheet');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  /// Fetches the available batch balance from the API.
  /// Override to customise the warehouse source.
  Future<BatchResult> fetchBatchBalance(String batchNo) async {
    final data = await ApiProvider().getBatchBalance(
      itemCode:  itemCode.value,
      batchNo:   batchNo,
      warehouse: resolvedWarehouse,
    );
    return BatchResult(
      batchNo:      batchNo,
      availableQty: (data['qty'] as num?)?.toDouble() ?? 0.0,
      expiryDate:   data['expiry_date'] as String?,
    );
  }

  /// Resets all batch validation state and zeroes [batchBalance].
  void resetBatch() {
    batchController.clear();
    isBatchValid.value       = false;
    isValidatingBatch.value  = false;
    batchError.value         = '';
    batchBalance.value       = 0.0;
    batchInfoTooltip.value   = null;
    validateSheet();
  }

  /// Resets validity flags without zeroing [batchBalance] or clearing the
  /// controller — used during prepareForItem to re-validate an already-
  /// loaded batch without losing the displayed balance (DN-8 fix).
  void softResetBatch() {
    isBatchValid.value       = false;
    isValidatingBatch.value  = false;
    batchError.value         = '';
  }

  /// Convenience wrapper: defers [validateBatch] to the next frame so it
  /// can be called safely from [onInit] before the widget tree is attached.
  void validateBatchOnInit(String batchNo) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => validateBatch(batchNo),
    );
  }

  // ── Rack validation ───────────────────────────────────────────────────────

  /// Validates [rack] and updates [rackBalance] + [isRackValid].
  ///
  /// Base implementation delegates to [fetchRackBalance].  SE overrides
  /// this via [DualRackDelegate.validateDualRack].
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) {
      resetRack();
      return;
    }
    isValidatingRack.value = true;
    isRackValid.value      = false;
    rackError.value        = '';
    try {
      await fetchRackBalance(rack);
      isRackValid.value = true;
      rackError.value   = '';
    } catch (e) {
      rackError.value = e.toString();
      log('[Base] validateRack error: $e', name: 'ItemSheet');
    } finally {
      isValidatingRack.value = false;
      validateSheet();
    }
  }

  /// Fetches the rack stock balance from the API and writes [rackBalance]
  /// and [rackStockTooltip].
  Future<void> fetchRackBalance(String rack) async {
    final balance = await ApiProvider().getRackBalance(
      itemCode:  itemCode.value,
      rack:      rack,
      warehouse: resolvedWarehouse,
    );
    rackBalance.value      = (balance['qty'] as num?)?.toDouble() ?? 0.0;
    rackStockTooltip.value = 'Stock: ${_formatQty(rackBalance.value)}';
  }

  /// Resets all rack validation state and zeroes [rackBalance].
  void resetRack() {
    rackController.clear();
    isRackValid.value       = false;
    isValidatingRack.value  = false;
    rackError.value         = '';
    rackBalance.value       = 0.0;
    rackStockTooltip.value  = null;
    validateSheet();
  }

  /// Resets validity flags without zeroing [rackBalance] or clearing the
  /// controller (DN-8 fix — mirrors [softResetBatch]).
  void softResetRack() {
    isRackValid.value       = false;
    isValidatingRack.value  = false;
    rackError.value         = '';
  }

  // ── RackFieldWithBrowseDelegate — base no-ops ─────────────────────────────

  @override
  bool get canBrowseRacks => false;

  @override
  Future<RackPickerResult?> browseRacks() async => null;

  @override
  Future<void> handleRackPicked(RackPickerResult result) async {
    rackController.text = result.rackId;
    await validateRack(result.rackId);
  }

  // ── BatchNoFieldWithBrowseDelegate — base no-ops ──────────────────────────

  @override
  Future<void> openBatchPicker() async {
    final picked = await Get.bottomSheet<String>(
      BatchPickerSheet(controllerTag: tag ?? ''),
      isScrollControlled: true,
    );
    if (picked != null && picked.isNotEmpty) {
      batchController.text = picked;
      await validateBatch(picked);
    }
  }

  // ── QtyFieldWithPlusMinusDelegate — concrete implementations ─────────────

  @override
  void adjustQty(double delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next    = (current + delta).clamp(0.0, effectiveMaxQty);
    qtyController.text = _formatQty(next);
    validateSheet();
  }

  // ── Save-button helpers ───────────────────────────────────────────────────

  void _resetSaveStateOnEdit() {
    if (saveButtonState.value != SaveButtonState.idle) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) {
      return qty.toStringAsFixed(0);
    }
    final f = NumberFormat('#,##0.####');
    return f.format(qty);
  }

  // ── prepareForItem (concrete controllers override) ────────────────────────

  /// Resets the sheet to a clean state before loading a new item.
  ///
  /// Concrete controllers MUST:
  ///   1. Call [removeSheetListeners] first (Rule 3).
  ///   2. Clear / reset all fields.
  ///   3. Call [addSheetListeners] last.
  void prepareForItem() {
    removeSheetListeners();
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    softResetBatch();
    softResetRack();
    saveButtonState.value  = SaveButtonState.idle;
    isSheetLoading.value   = false;
    editingItemName.value  = null;
    itemName.value         = '';
    itemOwner.value        = null;
    itemCreation.value     = null;
    itemModified.value     = null;
    itemModifiedBy.value   = null;
    qtyInfoTooltip.value   = null;
    liveRemaining.value    = 0.0;
    isSheetValid.value     = false;
    isAddingItemFlag       = false;
    snapshotState();
    addSheetListeners();
  }

  // ── Disposal ──────────────────────────────────────────────────────────────

  /// Disposes all TECs, FocusNodes, and ScrollControllers owned by this
  /// class.
  ///
  /// Idempotent — safe to call multiple times.  The first call sets
  /// [_controllersDisposed] to prevent double-disposal (Rule 2).
  ///
  /// Subclasses that own additional TECs (e.g. [StockEntryItemFormController]
  /// with sourceRackController / targetRackController) MUST override this
  /// method, dispose their own resources first, then call super.
  void disposeControllers() {
    if (_controllersDisposed) return;
    _controllersDisposed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try { batchController.dispose();       } catch (_) {}
      try { rackController.dispose();        } catch (_) {}
      try { qtyController.dispose();         } catch (_) {}
      try { rackFocusNode.dispose();         } catch (_) {}
      try { itemBarcodeFocusNode.dispose();  } catch (_) {}
      try { batchFocusNode.dispose();        } catch (_) {}
      try { sheetScrollController.dispose(); } catch (_) {}
    });
  }

  @override
  void onClose() {
    _autoSubmitWorker?.dispose();
    disposeControllers();
    super.onClose();
  }
}
