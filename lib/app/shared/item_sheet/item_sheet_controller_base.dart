import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Drives the visual state of the animated Save button in the item sheet.
///
/// idle    — button is ready; shows save icon in blue/grey.
/// loading — API call in progress; shows spinner in orange.
/// success — save confirmed; shows green check for 700 ms then sheet closes.
/// error   — save failed; shows red error icon for 1 500 ms then resets to idle.
enum SaveButtonState { idle, loading, success, error }

/// Abstract base controller for every DocType item-sheet.
///
/// Owns all state that is identical across Stock Entry, Delivery Note,
/// Purchase Receipt, and Purchase Order item sheets:
///   • TextEditingControllers / FocusNode
///   • Batch & Rack validation (with post-frame-safe focus)
///   • Stock / rack map fetching
///   • Qty adjustment helpers
///   • Dirty-state & sheet-validity flags
///   • Auto-submit worker (enabled per-DocType via setupAutoSubmit)
///
/// Step-1 additions (UniversalItemFormSheet migration):
///   • [isSheetLoading]     — merged loading flag (validating OR parent saving)
///   • [qtyInfoText]        — abstract; DocType provides its qty-hint string
///   • [deleteCurrentItem]  — abstract; DocType resolves item and dispatches
///   • [isScanning]         — scan-bar active state (promoted from DN parent)
///   • [scanController]     — scan-bar TEC (promoted from DN parent)
///   • [isAddMode]          — true when no editingItemName
///
/// P2-A: validateBatch: batch with qty=0 is valid (no-stock warning only).
/// P2-A: isSheetLoading now also merges isValidatingRack.
/// P2-B: baseValidate: maxQty cap is a soft guard in edit-mode only.
/// P2-C: fetchAllRackStocks: loop runs to result.length (was length-1).
///
/// Standardisation S1:
///   • [isBatchReadOnly]    — promoted from PR/SE; locks batch field after scan/validation.
///   • [currentScannedEan]  — promoted from PR/SE/DN (was named currentScannedEan8 in SE/DN).
///   • [validateBatchOnInit] — promoted from PR/SE/DN; identical post-frame helper.
///   All three child declarations are now dead code and should be removed.
///
/// Option-3 (animated save button):
///   • [saveButtonState]     — drives icon/colour of the Save button widget.
///   • [submitWithFeedback]  — wraps submit() with idle→loading→success/error flow.
///                             Returns true on success; parent coordinator guards
///                             Get.back() on this return value (fixes overlay crash).
///   • [_resetSaveStateOnEdit] — resets saveButtonState to idle when user edits
///                               any field after a success or error result.
///
/// Concrete subclasses only need to implement the abstract members
/// and call [initBaseListeners] + [captureSnapshot] from their [initialise].
abstract class ItemSheetControllerBase extends GetxController {
  // ── Dependencies ─────────────────────────────────────────────────
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Form infrastructure ────────────────────────────────────────────────
  final GlobalKey<FormState> formKey               = GlobalKey<FormState>();
  final ScrollController     sheetScrollController = ScrollController();

  final TextEditingController qtyController   = TextEditingController();
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();
  final FocusNode rackFocusNode = FocusNode();

  // ── Core item identity ────────────────────────────────────────────────
  var itemCode = ''.obs;
  var itemName = ''.obs;

  // ── Validation state ──────────────────────────────────────────────────
  var isBatchValid      = false.obs;
  var isRackValid       = false.obs;
  var isValidatingBatch = false.obs;
  var isValidatingRack  = false.obs;
  var isSheetValid      = false.obs;
  var isFormDirty       = false.obs;
  var maxQty            = 0.0.obs;
  var batchError        = RxnString();
  var rackError         = RxnString();
  var batchInfoTooltip  = RxnString();
  var rackStockTooltip  = RxnString();
  var rackStockMap      = <String, double>{}.obs;

  // ── S1: Batch read-only toggle (promoted from PR + SE) ────────────────
  //
  // Controls whether the Batch field is locked after a successful scan
  // or validation.  Previously each child declared its own RxBool;
  // it lives here so SharedBatchField and resetBatch() share one source.
  //
  // Subclass [_loadExistingItem] sets: `isBatchReadOnly.value = isBatchValid.value;`
  // Subclass [validateBatch] sets:     `isBatchReadOnly.value = true;` on success.
  // Subclass [resetBatch] calls:        `super.resetBatch()` which also clears it.
  var isBatchReadOnly = false.obs;

  // ── S1: EAN-8 scan context (promoted from PR/SE/DN) ───────────────────
  //
  // Previously named [currentScannedEan] in PR and [currentScannedEan8]
  // in SE and DN.  Unified here so any shared scan-routing logic in a
  // future base mixin can reference a single field name.
  //
  // Set by concrete [initialise]  and [_loadExistingItem] whenever the
  // editing item's batchNo contains a '-' separator.
  String currentScannedEan = '';

  // ── Item metadata (for GlobalItemFormSheet footer) ────────────────────
  var itemOwner      = RxnString();
  var itemCreation   = RxnString();
  var itemModified   = RxnString();
  var itemModifiedBy = RxnString();

  // ── Editing context ───────────────────────────────────────────────
  /// Non-null when editing an existing child-table row.
  var editingItemName = RxnString();

  // ── Add / edit mode ─────────────────────────────────────────────────
  /// Set by concrete [initialise] after determining edit vs. add.
  /// True  → new item (no editingItemName).
  /// False → editing existing row.
  bool isAddMode = true;

  // ── Option-3: animated save button state ──────────────────────────────
  //
  // Drives the Save button widget in GlobalItemFormSheet.
  // Transitions: idle → loading (on tap) → success (API ok) → [sheet closes]
  //                                       → error   (API fail) → idle (after 1.5 s)
  //
  // Parent coordinators call [submitWithFeedback] instead of [submit] directly.
  // The sheet is closed by the coordinator only when [submitWithFeedback] returns true.
  var saveButtonState = SaveButtonState.idle.obs;

  // ── Step-1: merged loading flag ───────────────────────────────────────
  //
  // P2-A: isSheetLoading now also merges isValidatingRack.
  // Option-3: also blocks while saveButtonState == loading (prevents double-submit).
  // Subclasses that have additional async validation paths (e.g. SE dual-rack)
  // override this getter to OR-in their own flags.

  /// Parent-level "saving in progress" flag.
  /// Concrete subclass sets this in [initialise]:
  ///   `isAddingItemFlag = _parent.isAddingItem;`
  RxBool isAddingItemFlag = false.obs;

  /// Single merged loading state for UniversalItemFormSheet.
  /// True when batch-validation, rack-validation, parent save, or
  /// the save-button animation is in progress.
  bool get isSheetLoading =>
      isValidatingBatch.value ||
      isValidatingRack.value  ||
      isAddingItemFlag.value  ||
      saveButtonState.value == SaveButtonState.loading;

  // ── Step-1: scan-bar state (promoted from DN parent) ───────────────────
  //
  // SE does not use the scan bar in the item sheet (it routes scans
  // through the document-level scanner).  DN does.  Both will bind to
  // these fields so GlobalItemFormSheet can use a single code path.

  /// Whether the embedded scan bar is actively scanning.
  /// Non-final so concrete subclasses can reassign to the parent's observable:
  ///   `isScanning = _parent.isScanning;`
  RxBool isScanning = false.obs;

  /// TEC for the embedded barcode input inside the sheet.
  /// Concrete subclass assigns the parent's controller if it uses a scan bar:
  ///   `sheetScanController = _parent.barcodeController;`
  /// Leave null (default) if DocType does not embed a scan bar.
  TextEditingController? sheetScanController;

  // ── Step-1: abstract qty info text ───────────────────────────────────
  //
  // Each DocType returns its own human-readable qty hint that appears
  // below the quantity field.

  /// Human-readable qty hint shown below the Quantity field.
  /// Return null to hide the hint.
  String? get qtyInfoText;

  // ── Step-1: abstract delete dispatch ──────────────────────────────────

  /// Deletes (or confirms deletion of) the item currently being edited.
  /// Only called when [editingItemName] is non-null.
  Future<void> deleteCurrentItem();

  // ── Snapshot for dirty-checking ───────────────────────────────────────
  String _snapshotBatch = '';
  String _snapshotRack  = '';
  String _snapshotQty   = '';

  // ── Auto-submit worker ────────────────────────────────────────────────
  Worker? _autoSubmitWorker;

  // ── Abstract interface ───────────────────────────────────────────────

  /// The warehouse to use for stock/batch queries.
  /// Return null if not yet determined.
  String? get resolvedWarehouse;

  /// Whether this DocType requires a valid batch before the sheet can be saved.
  /// Enforced by [baseValidate].
  bool get requiresBatch;

  /// Whether this DocType requires a non-empty rack entry before saving.
  /// Enforced by [baseValidate].
  bool get requiresRack;

  /// DocType-specific validation rules applied ON TOP of [baseValidate].
  void validateSheet();

  /// Commits the current field values back to the parent document controller.
  /// Do NOT call this directly from the UI — call [submitWithFeedback] instead.
  Future<void> submit();

  // ── Option-3: submitWithFeedback ──────────────────────────────────────
  //
  // Called by the parent coordinator's onSubmit lambda instead of submit().
  // Drives saveButtonState through the full animation cycle and returns
  // true on success so the coordinator knows it is safe to call Get.back().
  //
  // This is the fix for Bug #1: Get.back() now only fires after the success
  // animation delay, by which time the sheet overlay is already settled,
  // so SnackbarController can never find a torn-down overlay context.

  /// Wraps [submit] with the animated-button feedback cycle.
  ///
  /// Returns true  → save succeeded; coordinator should call Get.back().
  /// Returns false → save failed;    sheet stays open, button resets to idle.
  Future<bool> submitWithFeedback() async {
    saveButtonState.value = SaveButtonState.loading;
    try {
      await submit();
      saveButtonState.value = SaveButtonState.success;
      await Future.delayed(const Duration(milliseconds: 700));
      return true;
    } catch (e) {
      log('[ItemSheet] submitWithFeedback error: $e', name: 'ItemSheet');
      saveButtonState.value = SaveButtonState.error;
      await Future.delayed(const Duration(milliseconds: 1500));
      saveButtonState.value = SaveButtonState.idle;
      return false;
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onClose() {
    qtyController.dispose();
    batchController.dispose();
    rackController.dispose();
    rackFocusNode.dispose();
    sheetScrollController.dispose();
    _autoSubmitWorker?.dispose();
    super.onClose();
  }

  // ── Shared initialisation helper ────────────────────────────────────────

  /// Call from concrete [initialise] after fields are populated.
  ///
  /// Wires validateSheet AND _resetSaveStateOnEdit to all three field TECs.
  void initBaseListeners() {
    qtyController.addListener(validateSheet);
    batchController.addListener(validateSheet);
    rackController.addListener(validateSheet);

    qtyController.addListener(_resetSaveStateOnEdit);
    batchController.addListener(_resetSaveStateOnEdit);
    rackController.addListener(_resetSaveStateOnEdit);
  }

  /// Resets [saveButtonState] to idle when the user edits any field after
  /// a success or error result, so the button is ready for the next save.
  void _resetSaveStateOnEdit() {
    if (saveButtonState.value == SaveButtonState.success ||
        saveButtonState.value == SaveButtonState.error) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  /// Capture current field values as the "clean" baseline for dirty checking.
  void captureSnapshot() {
    _snapshotBatch = batchController.text;
    _snapshotRack  = rackController.text;
    _snapshotQty   = qtyController.text;
  }

  /// Returns true when any tracked field has changed from its snapshot.
  bool get isFieldsDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Auto-submit wiring ───────────────────────────────────────────────

  void setupAutoSubmit({
    required bool            enabled,
    required int             delaySeconds,
    required RxBool          isSheetOpen,
    required bool Function() isSubmittable,
    required VoidCallback    onAutoSubmit,
  }) {
    _autoSubmitWorker?.dispose();
    if (!enabled) return;

    _autoSubmitWorker = ever(isSheetValid, (bool valid) {
      if (valid && isSheetOpen.value && isSubmittable()) {
        Future.delayed(Duration(seconds: delaySeconds), () async {
          if (isSheetValid.value && isSheetOpen.value) {
            onAutoSubmit();
          }
        });
      }
    });
  }

  // ── Qty helpers ──────────────────────────────────────────────────────────

  void adjustQty(double delta) {
    double current = double.tryParse(qtyController.text) ?? 0;
    double next    = current + delta;
    if (next < 0) next = 0;
    if (maxQty.value > 0 && next > maxQty.value) next = maxQty.value;
    qtyController.text =
        next % 1 == 0 ? next.toInt().toString() : next.toString();
    validateSheet();
  }

  // ── P2-A: Batch validation ──────────────────────────────────────────────

  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;
    batchError.value        = null;
    batchInfoTooltip.value  = null;
    isValidatingBatch.value = true;

    try {
      final batchRes = await _api.getDocumentList(
        'Batch',
        filters: {'name': batch, 'item': itemCode.value},
        fields: ['name', 'custom_packaging_qty'],
      );

      final batchList = batchRes.data['data'] as List? ?? [];
      if (batchList.isEmpty) throw Exception('Batch not found');

      final batchData = batchList.first as Map<String, dynamic>;
      final double pkgQty =
          (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
      if (pkgQty > 0 && qtyController.text.isEmpty) {
        qtyController.text =
            pkgQty % 1 == 0 ? pkgQty.toInt().toString() : pkgQty.toString();
      }

      final balRes = await _api.getBatchWiseBalance(
        itemCode.value,
        batch,
        warehouse: resolvedWarehouse,
      );

      double fetchedQty = 0.0;
      if (balRes.statusCode == 200 && balRes.data['message'] != null) {
        final result = balRes.data['message']['result'];
        if (result is List && result.isNotEmpty) {
          fetchedQty =
              (result.first['balance_qty'] as num?)?.toDouble() ?? 0.0;
        }
      }

      maxQty.value = fetchedQty;

      isBatchValid.value    = true;
      isBatchReadOnly.value = true; // S1: lock after successful validation

      final sb = StringBuffer('Batch Stock: $fetchedQty');
      if (rackStockTooltip.value != null) {
        sb.write('\n\nRack Availability:\n${rackStockTooltip.value}');
      }
      batchInfoTooltip.value = sb.toString().trim();

      if (fetchedQty > 0) {
        batchError.value = null;
        GlobalSnackbar.info(
            message: 'Batch found — Stock: ${fetchedQty.toStringAsFixed(0)}');
      } else {
        batchError.value = 'Warning: Batch has 0 stock in current warehouse';
        GlobalSnackbar.warning(
            message: 'Batch has 0 stock in the selected warehouse');
      }

      await fetchAllRackStocks();

    } catch (e) {
      isBatchValid.value     = false;
      isBatchReadOnly.value  = false; // S1: unlock on failure
      batchError.value       = 'Invalid Batch';
      maxQty.value           = 0.0;
      batchInfoTooltip.value = null;
      GlobalSnackbar.error(message: 'Batch validation failed');
      log('[ItemSheet] validateBatch error: $e', name: 'ItemSheet');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  // ── S1: validateBatchOnInit (promoted from PR/SE/DN) ─────────────────────
  //
  // All three child controllers declared this method identically.
  // The post-frame delay ensures the sheet's widget tree is fully built
  // before the first async validation call fires.

  /// Schedules [validateBatch] for the next frame.
  /// Call from [_loadNewItem] whenever a pre-filled batch is supplied.
  void validateBatchOnInit(String batch) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => validateBatch(batch));
  }

  /// Clears batch validity state and unlocks the batch field.
  /// S1: also clears [isBatchReadOnly] (was omitted in the base previously).
  void resetBatch() {
    isBatchValid.value    = false;
    isBatchReadOnly.value = false; // S1
    batchError.value      = null;
    validateSheet();
  }

  // ── Rack validation ────────────────────────────────────────────────────────

  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) {
      isRackValid.value = false;
      validateSheet();
      return;
    }
    isValidatingRack.value = true;

    try {
      final response = await _api.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        isRackValid.value = true;
        validateSheet();
        await fetchAllRackStocks();
      } else {
        isRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      isRackValid.value = false;
      GlobalSnackbar.error(message: 'Rack validation failed: $e');
    } finally {
      isValidatingRack.value = false;
      validateSheet();
    }
  }

  void resetRack() {
    isRackValid.value = false;
    rackError.value   = null;
    validateSheet();
  }

  // ── P2-C: Stock / rack-map fetching ───────────────────────────────────────

  Future<void> fetchAllRackStocks() async {
    final warehouse = resolvedWarehouse;
    if (warehouse == null || warehouse.isEmpty) return;

    try {
      final response = await _api.getStockBalance(
        itemCode:  itemCode.value,
        warehouse: warehouse,
        batchNo:   batchController.text.isNotEmpty ? batchController.text : null,
      );

      if (response.statusCode == 200 && response.data['message'] != null) {
        final result = response.data['message']['result'];
        if (result is List && result.isNotEmpty) {
          final Map<String, double> tempMap      = {};
          final List<String>        tooltipLines = [];

          for (int i = 0; i < result.length; i++) {
            final row = result[i];
            if (row is! Map) continue;
            final String? r   = row['rack'] as String?;
            final double  qty = (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
            if (r != null && r.isNotEmpty && qty > 0) {
              tempMap[r] = qty;
              tooltipLines.add('$r: $qty');
            }
          }

          rackStockMap.assignAll(tempMap);
          rackStockTooltip.value = tooltipLines.isNotEmpty
              ? tooltipLines.join('\n')
              : 'No stock in racks';
        }
      }
    } catch (e) {
      log('[ItemSheet] fetchAllRackStocks error: $e', name: 'ItemSheet');
    }
  }

  // ── P2-B: Base validation ───────────────────────────────────────────────

  /// Returns true when all base rules pass.
  bool baseValidate() {
    rackError.value = null;

    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return false;

    if (isAddMode && maxQty.value > 0 && qty > maxQty.value) return false;

    if (requiresBatch) {
      if (batchController.text.isEmpty || !isBatchValid.value) return false;
    } else {
      if (batchController.text.isNotEmpty && !isBatchValid.value) return false;
    }

    if (requiresRack) {
      if (rackController.text.isEmpty || !isRackValid.value) return false;
    } else {
      if (rackController.text.isNotEmpty && !isRackValid.value) return false;
    }

    final selectedRack = rackController.text;
    if (isAddMode && selectedRack.isNotEmpty && rackStockMap.isNotEmpty) {
      final available = rackStockMap[selectedRack] ?? 0.0;
      if (qty > available) {
        rackError.value = 'Only $available available in $selectedRack';
        return false;
      }
    }

    return true;
  }
}
