import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_checker.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';
import 'package:multimax/app/shared/item_sheet/batch_no_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/qty_cap_delegate.dart';
import 'package:multimax/app/shared/item_sheet/qty_field_with_plus_minus_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/widgets/older_stock_sheet.dart';

/// Drives the visual state of the animated Save button in the item sheet.
enum SaveButtonState { idle, loading, success, error }

class ItemSheetSubmissionCancelled implements Exception {
  const ItemSheetSubmissionCancelled();
}

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
///   formKey          — shared `GlobalKey<FormState>`.
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
abstract class ItemSheetControllerBase extends GetxController
    implements
        RackFieldWithBrowseDelegate,
        BatchNoFieldWithBrowseDelegate,
        QtyFieldWithPlusMinusDelegate {
  // ── Reactive state ────────────────────────────────────────────────────────
  @override
  final RxBool   isBatchValid          = false.obs;
  @override
  final RxBool   isValidatingBatch     = false.obs;
  @override
  final RxBool   isBatchReadOnly       = false.obs;
  @override
  final RxString batchError            = RxString('');
  @override
  final RxnString batchInfoTooltip     = RxnString(null);
  @override
  final RxBool   isRackValid           = false.obs;
  @override
  final RxBool   isValidatingRack      = false.obs;
  @override
  final RxString rackError             = RxString('');

  /// Why the last Add/Update was refused, shown above the save button.
  /// (A snackbar would render under the modal sheet and never be seen.)
  final RxString submitError           = RxString('');
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
  @override
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
  @override
  final TextEditingController batchController = TextEditingController();
  @override
  final TextEditingController rackController  = TextEditingController();

  /// Backing text controller for the qty field.
  ///
  /// Exposed here (and via [QtyFieldDelegate.qtyController]) so
  /// [SharedQtyField] and all existing listeners ([addSheetListeners],
  /// [disposeControllers], [onClose]) can access it through a single
  /// concrete field.
  @override
  final TextEditingController qtyController   = TextEditingController();

  /// FocusNode for the rack text field.
  @override
  final FocusNode rackFocusNode = FocusNode();

  /// ScrollController for the sheet's scrollable body.
  ///
  /// Exposed so parent orchestrators (e.g. DeliveryNoteFormController) can
  /// pass it directly to UniversalItemFormSheet without requiring each
  /// concrete subclass to declare its own field (Group B — B1 fix).
  final ScrollController sheetScrollController = ScrollController();

  @override
  var itemCode = ''.obs;
  final RxString itemGroup = ''.obs;
  final RxString variantOf = ''.obs;

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
  String? get resolvedWarehouse;
  bool get requiresBatch;
  bool get requiresRack;

  /// The accent colour used by this sheet's UI elements.
  Color get accentColor;

  @override
  void validateSheet();
  Future<void> submit();

  /// Whether the sheet is in add-mode (true) or edit-mode (false).
  /// Satisfies [AutoFillRackMixin.isAddMode].
  bool get isAddMode;

  /// Qty-info label shown on the [QtyCapBadge] chip.
  ///
  /// Returns `null` to suppress the badge entirely.
  /// Examples: `'Max: 12'`, `'Max: 6.5 Kg'`, `null`.
  ///
  /// Satisfies [QtyCapDelegate.qtyInfoText] (nullable String getter).
  @override
  String? get qtyInfoText;

  /// Tooltip backing the qty-info label; null = no tap target rendered.
  ///
  /// Concrete field — NOT abstract.  SE writes this directly inside
  /// validateSheet() so that SharedBatchField observes the same [RxnString]
  /// reference without any shadowing override.  Subclasses that need their
  /// own RxnString instance (e.g. PS) may override the getter to return a
  /// different [RxnString], but must NOT declare a new field with the same
  /// name — override the getter only.
  // ignore: prefer_final_fields
  @override
  RxnString qtyInfoTooltip = RxnString(null);

  // ── Camera state ──────────────────────────────────────────────────────────

  /// Whether the camera viewfinder panel is currently expanded.
  final isCameraExpanded = false.obs;

  MobileScannerController? _sheetScanController;

  /// The live scanner controller. Non-null on Android/iOS from [onInit] onward
  /// (`autoStart: false` so the camera is off until the panel mounts).
  /// Always null on desktop/web. Disposed in [disposeControllers].
  MobileScannerController? get sheetScanController => _sheetScanController;

  /// True when running on Android or iOS (camera hardware available).
  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Expand or collapse the camera viewfinder panel.
  /// No-op on desktop / web.
  void toggleCamera() {
    if (!isMobile) return;
    isCameraExpanded.value = !isCameraExpanded.value;
  }

  /// Camera-scan entry point.
  ///
  /// Called by [GlobalItemFormSheet] when [CameraViewfinderPanel] detects a
  /// barcode.  Base implementation is a no-op; [BarcodeAwareMixin] overrides
  /// this to forward through [onBarcodeScanned] → [handleScan].
  Future<void> onCameraBarcode(String raw) async {}

  /// Increment (+1) or decrement (-1) the qty field.
  ///
  /// Implementors MUST:
  /// 1. Clamp `(current + delta)` to `[0.0, effectiveMaxQty]`.
  /// 2. Write the result back to [qtyController].
  /// 3. Call [validateSheet] to refresh the save gate.
  @override
  void adjustQty(int delta);

  /// Delete the item currently being edited.
  void deleteCurrentItem();

  // ── Lifecycle ──────────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    // Create the scanner controller upfront on mobile (autoStart: false keeps
    // the camera off until the CameraViewfinderPanel widget mounts).
    // This ensures sheetScanController is never null at widget-build time on
    // mobile, so GlobalItemFormSheet renders the camera toggle immediately.
    if (isMobile) {
      _sheetScanController = MobileScannerController();
    }
    // Lock / unlock the qty field based on docstatus.
    ever(docStatus, (_) {
      _isQtyReadOnly.value = docStatus.value == 1;
    });
  }

  // ── BatchNoFieldWithBrowseDelegate defaults (Commit 7 of 7) ────────────────
  //
  // See the full design note in the previous version of this file.
  //
  // BatchNoFieldDelegate members (isBatchValid, isValidatingBatch,
  // isBatchReadOnly, batchError, batchInfoTooltip, batchController,
  // resetBatch, validateBatch) are all concrete fields / methods already
  // declared below — they satisfy the interface automatically.

  @override
  double batchBalanceFor(String batchNo) => batchBalance.value;

  @override
  String? get resolvedWarehouseForBatch => resolvedWarehouse;

  @override
  bool get canBrowseBatches => false;

  @override
  Future<String?> browseBatches() async {
    await openBatchPicker();
    return null;
  }

  @override
  List<dynamic> get preloadedBatchRows => const [];

  @override
  Future<void> handleBatchPicked(String batchNo) async {
    batchController.text = batchNo;
    await validateBatch(batchNo);
  }

  // ── RackFieldWithBrowseDelegate defaults (Commit 3 of 4 — confirmed) ───────
  //
  // See the full design note in the previous version of this file.

  @override
  double rackBalanceFor(String rack) => rackBalance.value;

  @override
  bool get canBrowseRacks => false;

  @override
  Future<RackPickerResult?> browseRacks() async => null;

  @override
  Future<void> handleRackPicked(RackPickerResult result) async {
    rackController.text = result.rackId;
    await validateRack(result.rackId);
  }

  // ── submitWithFeedback ─────────────────────────────────────────────────────────
  bool _submissionInFlight = false;

  Future<bool> submitWithFeedback() async {
    if (_submissionInFlight) return false;
    // Wait for any in-flight batch/rack validation to settle first.
    if (isValidatingBatch.value || isValidatingRack.value) {
      GlobalSnackbar.warning(message: 'Validation in progress, please wait.');
      return false;
    }
    _submissionInFlight = true;
    saveButtonState.value = SaveButtonState.loading;
    submitError.value = '';
    try {
      await submit();
      saveButtonState.value = SaveButtonState.success;
      await Future.delayed(const Duration(milliseconds: 700));
      return true;
    } on ItemSheetSubmissionCancelled {
      if (!isClosed) saveButtonState.value = SaveButtonState.idle;
      return false;
    } catch (e) {
      log('[ItemSheet] submitWithFeedback error: $e', name: 'ItemSheet');
      // submit() throws user-facing reasons ("Choose the invoice serial…");
      // without this the sheet only flashed red and staff could not tell why.
      submitError.value = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : 'Could not save this item.';
      saveButtonState.value = SaveButtonState.error;
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!isClosed) saveButtonState.value = SaveButtonState.idle;
      return false;
    } finally {
      _submissionInFlight = false;
    }
  }

  // ── disposeControllers ─────────────────────────────────────────────────────────
  /// Public teardown helper — the single authoritative disposal path for all
  /// TECs, FocusNodes, and ScrollControllers owned by this base class.
  ///
  /// ## Idempotency (Rule 2 — tec_lifecycle_rules.dart)
  ///
  /// This method is guarded by [_controllersDisposed].  It is safe to call
  /// any number of times and from any combination of:
  ///   • GetX's automatic [onClose] (called on `Get.delete` / route pop), and
  ///   • Parent-orchestrated cleanup (e.g. `StockEntryFormController
  ///     .closeItemSheet()` calling `itemController.disposeControllers()`).
  ///
  /// ## Deferred disposal (Rule 1 — tec_lifecycle_rules.dart)
  ///
  /// Disposal is scheduled via `Future.delayed(400 ms)` so both the
  /// sheet exit animation (~300 ms) and any concurrent keyboard-dismissal
  /// animation (~300 ms) finish before any [TextEditingController] is
  /// invalidated.  `_EditableTextState.dispose()` calls `removeListener()`
  /// only after the animation completes; disposing earlier causes it to
  /// throw in debug mode:
  ///
  ///   "A TextEditingController was used after being disposed."
  ///
  /// ## Subclass contract
  ///
  /// Subclasses that declare additional TECs (e.g. [sourceRackController],
  /// [targetRackController] in [StockEntryItemFormController]) MUST:
  ///   1. Capture their controllers into local variables before calling
  ///      `super.onClose()`.
  ///   2. Schedule disposal via `Future.delayed(400ms)` (Rule 1).
  ///   3. Call `super.onClose()` — which calls this method — AFTER
  ///      scheduling the deferred callback.
  void disposeControllers() {
    if (_controllersDisposed) return; // ← idempotent guard (Rule 2)
    _controllersDisposed = true;

    removeSheetListeners(); // ← Rule 3: remove before invalidating controllers

    // Dispose camera controller immediately (not a TEC; no frame dependency).
    _sheetScanController?.dispose();
    _sheetScanController = null;

    final textControllers = <TextEditingController>[
      batchController,
      rackController,
      qtyController,
    ];
    final scroll = sheetScrollController;
    final focus  = rackFocusNode;

    // Delay TEC disposal by 400 ms — must outlast both the sheet exit
    // animation (~300 ms) and any concurrent keyboard-dismissal animation
    // (~300 ms) that may still be running when the controller is deleted.
    // The earlier double-post-frame (~32 ms) was insufficient: when the
    // keyboard was open, MediaQuery.viewInsets changes drove widget
    // rebuilds past frame 3, and _EditableTextState.dispose() called
    // removeListener() on an already-disposed TEC, crashing in debug mode.
    Future.delayed(const Duration(milliseconds: 400), () {
      for (final c in textControllers) {
        try { c.dispose(); } catch (_) {}
      }
      try { scroll.dispose(); } catch (_) {}
      try { focus.dispose();  } catch (_) {}
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────────
  @override
  void onClose() {
    _autoSubmitWorker?.dispose();
    // Delegate to the single guarded disposal path — never inline dispose here.
    // See disposeControllers() Dartdoc and tec_lifecycle_rules.dart Rule 2.
    disposeControllers();
    super.onClose();
  }

  // ── Listener wiring ───────────────────────────────────────────────────────────
  void removeSheetListeners() {
    try { batchController.removeListener(validateSheet); } catch (_) {}
    try { batchController.removeListener(_resetSaveStateOnEdit); } catch (_) {}
    try { rackController.removeListener(validateSheet);  } catch (_) {}
    try { rackController.removeListener(_resetSaveStateOnEdit);  } catch (_) {}
    try { qtyController.removeListener(validateSheet);   } catch (_) {}
    try { qtyController.removeListener(_resetSaveStateOnEdit);   } catch (_) {}
  }

  void addSheetListeners() {
    batchController.addListener(validateSheet);
    rackController.addListener(validateSheet);
    qtyController.addListener(validateSheet);

    batchController.addListener(_resetSaveStateOnEdit);
    rackController.addListener(_resetSaveStateOnEdit);
    qtyController.addListener(_resetSaveStateOnEdit);
  }

  /// Alias used by PO / PS controllers.
  void initBaseListeners() => addSheetListeners();

  /// Alias used by PO / PS controllers.
  void captureSnapshot() => snapshotState();

  void _resetSaveStateOnEdit() {
    if (submitError.value.isNotEmpty) submitError.value = '';
    if (saveButtonState.value != SaveButtonState.idle) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  // ── setupAutoSubmit ──────────────────────────────────────────────────────────
  void setupAutoSubmit({required Future<void> Function() onValid}) {
    _autoSubmitWorker?.dispose();
    bool handling = false;
    _autoSubmitWorker = ever(
      saveButtonState,
      (state) async {
        if (state == SaveButtonState.success && !handling) {
          handling = true;
          await onValid();
          handling = false;
        }
      },
    );
  }

  /// Backwards-compat alias.
  void setupAutoSubmitOnValid({required Future<void> Function() onValid}) =>
      setupAutoSubmit(onValid: onValid);

  // ── Dirty-tracking ─────────────────────────────────────────────────────────────
  void snapshotState() {
    _snapshotBatch = batchController.text;
    _snapshotRack  = rackController.text;
    _snapshotQty   = qtyController.text;
  }

  bool get isDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Rack reset ─────────────────────────────────────────────────────────────────

  @override
  void resetRack() {
    rackController.clear();
    isRackValid.value      = false;
    rackError.value        = '';
    rackBalance.value      = 0.0;
    rackStockTooltip.value = null;
  }

  @override
  void softResetRack() {
    isRackValid.value      = false;
    rackError.value        = '';
    rackStockTooltip.value = null;
  }

  // ── Batch reset ────────────────────────────────────────────────────────────────

  @override
  void resetBatch() {
    invalidateBatchValidation();
    isBatchReadOnly.value  = false;
    batchError.value       = '';
    batchInfoTooltip.value = null;
    resetRack();
  }

  void softResetBatch() {
    invalidateBatchValidation();
    isBatchReadOnly.value  = false;
    batchError.value       = '';
    batchInfoTooltip.value = null;
    softResetRack();
  }

  // ── Oldest stock first ───────────────────────────────────────────────────────
  //
  // A batch is refused while an older batch of the item still has stock.
  // Rule: batch_age_rule.dart · lookups: batch_age_checker.dart ·
  // design: docs/batch_age_validation.md.

  /// Whether this sheet refuses a batch while older stock of the item
  /// remains. Off by default; outbound sheets (Delivery Note, Stock Entry
  /// issues) opt in.
  bool get enforcesBatchAge => false;

  /// The warehouse the row is picked from. The rule only covers `WH-`
  /// warehouses; null (not known yet) skips the check until it resolves —
  /// see [recheckBatchAge].
  String? get batchAgePickWarehouse => resolvedWarehouse;

  /// The open document's in-memory lines for this item, without the row being
  /// edited. Their quantity is taken off the older batches' balance.
  List<BatchDraftLine> get batchAgeOwnLines => const [];

  /// The open document as saved on the server, so its saved rows are replaced
  /// by [batchAgeOwnLines] rather than counted twice.
  String? get batchAgeOwnDoctype => null;
  String? get batchAgeOwnDocName => null;

  /// The item's name for the refusal sheet's heading. Sheets that keep the
  /// name somewhere other than [itemName] override this.
  String get batchAgeItemName => itemName.value;

  /// The batch the edited row was saved with. Re-opening a row never refuses
  /// the batch it already carries (a supervisor may have entered it in Desk).
  String? get batchAgeExemptBatch => null;

  /// The older batches behind the current refusal, oldest first. Empty when
  /// the batch was not refused.
  final RxList<OlderBatch> olderBatches = <OlderBatch>[].obs;

  int _batchValidationGeneration = 0;

  /// Supersedes pending lookups when a row, field, or warehouse changes.
  void invalidateBatchValidation() {
    _batchValidationGeneration++;
    isValidatingBatch.value = false;
    isBatchValid.value = false;
    batchBalance.value = 0;
    _clearBatchAgeRefusal();
  }

  String? _batchAgeScope;
  String? _batchAgeRefusedWarehouse;

  /// `batch|warehouse` of the last check, so a warehouse that resolves later
  /// (rack scan) triggers exactly one re-check.
  String _batchAgeCheckedKey = '';

  String _batchAgeKey(String batch, String? warehouse) =>
      '${batch.trim()}|${warehouse?.trim() ?? ''}';

  void _clearBatchAgeRefusal() {
    if (olderBatches.isNotEmpty) olderBatches.clear();
    _batchAgeScope = null;
    _batchAgeRefusedWarehouse = null;
    _batchAgeCheckedKey = '';
  }

  /// True when [batch] may be used. On refusal writes [batchError], fills
  /// [olderBatches] and opens the explanation sheet. A lookup that fails
  /// refuses too: a hard rule must not vanish with the connection.
  ///
  /// Returns false silently when the field moved on while the lookup ran.
  Future<bool> _passesBatchAge(
    String batch, {
    required bool Function() isCurrent,
  }) async {
    if (!enforcesBatchAge) return true;
    final scanned   = batch.trim();
    final warehouse = batchAgePickWarehouse;
    _batchAgeCheckedKey = _batchAgeKey(scanned, warehouse);

    final exempt = batchAgeExemptBatch?.trim() ?? '';
    if (exempt.isNotEmpty && exempt == scanned) return true;
    if (!batchAgeRuleApplies(warehouse)) return true;

    final BatchAgeVerdict verdict;
    try {
      verdict = await BatchAgeChecker.create().check(
        itemCode:      itemCode.value,
        pickWarehouse: warehouse,
        batchNo:       scanned,
        ownLines:      batchAgeOwnLines,
        ownDoctype:    batchAgeOwnDoctype,
        ownDocName:    batchAgeOwnDocName,
      );
    } catch (e) {
      log('[ItemSheet] batch age check failed: $e', name: 'ItemSheet');
      if (!isCurrent()) return false;
      batchError.value = 'Could not check for older stock. '
          'Check the connection and scan the batch again.';
      return false;
    }
    if (!isCurrent()) return false;
    if (!verdict.isRefused) return true;

    olderBatches.assignAll(verdict.older);
    _batchAgeScope            = verdict.scopeWarehouse;
    _batchAgeRefusedWarehouse = warehouse;
    batchError.value          = kOlderStockMessage;
    showOlderStock();
    return false;
  }

  /// Runs the age check again when the pick warehouse resolves or changes
  /// after the batch was validated (batch scanned before the rack).
  Future<void> recheckBatchAge() async {
    if (!enforcesBatchAge || isClosed) return;
    final batch = batchController.text.trim();
    if (batch.isEmpty || !isBatchValid.value || isValidatingBatch.value) return;
    if (_batchAgeKey(batch, batchAgePickWarehouse) == _batchAgeCheckedKey) {
      return;
    }

    final generation = ++_batchValidationGeneration;
    final code = itemCode.value;
    final warehouse = batchAgePickWarehouse;
    bool ownsCheck() => !isClosed && generation == _batchValidationGeneration;
    bool sameBatch() => batchController.text.trim() == batch && itemCode.value == code;
    bool isCurrent() => ownsCheck() && sameBatch() && batchAgePickWarehouse == warehouse;

    isValidatingBatch.value = true;
    try {
      final allowed = await _passesBatchAge(batch, isCurrent: isCurrent);
      if (!allowed && isCurrent()) isBatchValid.value = false;
    } finally {
      if (ownsCheck()) {
        isValidatingBatch.value = false;
        validateSheet();
        if (sameBatch() && batchAgePickWarehouse != warehouse) {
          unawaited(recheckBatchAge());
        }
      }
    }
  }

  /// Opens the sheet that explains the current refusal: the older batches
  /// that must ship first and the racks the item is kept in.
  void showOlderStock() {
    if (olderBatches.isEmpty) return;
    // No overlay to draw on (controller driven outside a running app).
    final ctx = Get.key.currentContext;
    if (ctx == null) return;
    final refused   = batchController.text.trim();
    final warehouse = _batchAgeRefusedWarehouse;
    final scope     = _batchAgeScope;
    final code      = itemCode.value;

    showOlderStockSheet(
      ctx,
      itemLabel: [code, batchAgeItemName]
          .where((s) => s.trim().isNotEmpty)
          .toSet() // a name that only repeats the code is shown once
          .join(' · '),
      refusedBatch: refused,
      older:        olderBatches.toList(),
      loadRacks: () => BatchAgeChecker.create().racks(
        itemCode:      code,
        pickWarehouse: warehouse ?? '',
        scope:         scope,
      ),
    ).then((scanOlder) {
      if (scanOlder != true || isClosed) return;
      // Clear the refused batch so the next scan is read as a batch.
      batchController.clear();
      resetBatch();
    });
  }

  // ── Fetch helpers ──────────────────────────────────────────────────────────────
  ApiProvider get _batchApi => Get.isRegistered<ApiProvider>()
      ? Get.find<ApiProvider>()
      : ApiProvider();

  Future<void> fetchBatchBalance() async {
    final batch = batchController.text.trim();
    if (batch.isEmpty || itemCode.value.isEmpty) {
      batchBalance.value = 0.0;
      return;
    }
    final wh = resolvedWarehouse;
    final code = itemCode.value;
    final generation = _batchValidationGeneration;
    try {
      final rows = await _batchApi.getBatchWiseBalance(
        itemCode: code,
        warehouse: wh,
        batchNo: batch,
      );
      if (isClosed ||
          generation != _batchValidationGeneration ||
          itemCode.value != code ||
          batchController.text.trim() != batch ||
          resolvedWarehouse != wh) {
        return;
      }
      batchBalance.value = rows.fold(0.0, (s, r) => s + (r['qty'] as num).toDouble());
    } catch (e) {
      log('[ItemSheet] fetchBatchBalance error: $e', name: 'ItemSheet');
    }
  }

  Future<void> fetchRackBalance(String rack) async {
    if (rack.isEmpty || itemCode.value.isEmpty) {
      rackBalance.value = 0.0;
      return;
    }
    final wh = resolvedWarehouse;
    try {
      final batch = batchController.text.trim();
      final rows  = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: wh,
        batchNo:   batch.isEmpty ? null : batch,
      );
      final match = rows.whereType<Map<String, dynamic>>().firstWhere(
            (r) => (r['rack'] as String?) == rack,
        orElse: () => <String, dynamic>{},   // ← empty sentinel; no default qty
      );
      // API returns 'bal_qty'; fall back to 'qty' for forward-compat.
      final raw = match['bal_qty'] ?? match['qty'];
      rackBalance.value = (raw as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      log('[ItemSheet] fetchRackBalance error: $e', name: 'ItemSheet');
    }
  }

  // ── openBatchPicker (base) ───────────────────────────────────────────────────────
  Future<void> openBatchPicker() async {
    final ctx = Get.context;
    if (ctx == null) return;
    final selected = await showBatchPickerSheet(
      ctx,
      itemCode:    itemCode.value,
      warehouse:   resolvedWarehouse,
      accentColor: accentColor,
      oldestFirst: enforcesBatchAge,
    );
    if (selected == null || selected.isEmpty) return;
    batchController.text = selected;
    await validateBatch(selected);
  }

  @override
  Future<void> validateBatch(String batch) async {
    batch = batch.trim();
    if (batch.isEmpty) { resetBatch(); return; }

    final generation = ++_batchValidationGeneration;
    final code = itemCode.value;
    final warehouse = resolvedWarehouse;
    final ageWarehouse = batchAgePickWarehouse;
    bool ownsCheck() => !isClosed && generation == _batchValidationGeneration;
    bool sameBatch() => batchController.text.trim() == batch && itemCode.value == code;
    bool sameWarehouse() =>
        resolvedWarehouse == warehouse && batchAgePickWarehouse == ageWarehouse;
    bool isCurrent() => ownsCheck() && sameBatch() && sameWarehouse();

    isValidatingBatch.value = true;
    batchBalance.value = 0;
    batchError.value        = '';
    batchInfoTooltip.value  = null;
    isBatchValid.value      = false;
    _clearBatchAgeRefusal();

    try {
      // Try strict lookup first (batch name + item). Falls back to name-only
      // when the Batch doctype's item field differs from the DN item_code
      // (e.g. batch created against a template item while stock is under a
      // variant, causing a data mismatch in ERPNext).
      var results = await _batchApi.getList(
        'Batch',
        filters: {'name': batch, 'item': itemCode.value},
        fields:  ['name', 'expiry_date', 'manufacturing_date'],
      );

      if (!isCurrent()) return;
      if (results.isEmpty && code.isNotEmpty) {
        results = await _batchApi.getList(
          'Batch',
          filters: {'name': batch},
          fields:  ['name', 'expiry_date', 'manufacturing_date'],
        );
      }

      if (!isCurrent()) return;
      if (results.isEmpty) {
        batchError.value = 'Batch "$batch" not found for this item.';
        return;
      }

      final row        = results.first;
      final expiryRaw  = row['expiry_date'] as String?;
      final mfgRaw     = row['manufacturing_date'] as String?;

      if (expiryRaw != null && expiryRaw.isNotEmpty) {
        final expiry = DateTime.tryParse(expiryRaw);
        if (expiry != null) {
          final today = DateTime.now();
          if (expiry.isBefore(DateTime(today.year, today.month, today.day))) {
            batchError.value =
                'Batch expired on ${DateFormat('dd MMM yyyy').format(expiry)}.';
            return;
          }
          if (expiry.isBefore(today.add(const Duration(days: 30)))) {
            batchError.value =
                'Batch expires soon: ${DateFormat('dd MMM yyyy').format(expiry)}';
          }
        }
      }

      final parts = <String>[];
      if (mfgRaw    != null && mfgRaw.isNotEmpty) {
        final mfg = DateTime.tryParse(mfgRaw);
        if (mfg != null) parts.add('Mfg: ${DateFormat('dd MMM yyyy').format(mfg)}');
      }
      if (expiryRaw != null && expiryRaw.isNotEmpty) {
        final expiry = DateTime.tryParse(expiryRaw);
        if (expiry != null) parts.add('Exp: ${DateFormat('dd MMM yyyy').format(expiry)}');
      }
      if (parts.isNotEmpty) batchInfoTooltip.value = parts.join('  \u2022  ');

      // Oldest stock first: a hard stop, checked last so "not found" and
      // "expired" are reported ahead of it.
      if (!await _passesBatchAge(batch, isCurrent: isCurrent) || !isCurrent()) {
        return;
      }

      await fetchBatchBalance();
      if (isCurrent()) isBatchValid.value = true;
    } catch (e) {
      if (isCurrent()) batchError.value = 'Error validating batch: $e';
    } finally {
      if (ownsCheck()) {
        isValidatingBatch.value = false;
        validateSheet();
        if (sameBatch() && !sameWarehouse()) unawaited(validateBatch(batch));
      }
    }
  }

  void validateBatchOnInit(String batch) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed) validateBatch(batch);
    });
  }

  // ── Rack validation (base) ───────────────────────────────────────────────────────
  @override
  Future<void> validateRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) { resetRack(); return; }

    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;

    try {
      await fetchRackBalance(trimmed);
      isRackValid.value = true;
    } catch (e) {
      rackError.value = 'Error validating rack: $e';
      log('[ItemSheet] validateRack error: $e', name: 'ItemSheet');
    } finally {
      isValidatingRack.value = false;
    }
  }
}
