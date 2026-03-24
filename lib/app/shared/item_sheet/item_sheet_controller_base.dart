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
/// B-2 fix (revised):
///   • onClose() removes all TEC listeners synchronously (prevents any
///     in-flight notifications on the current frame from reaching the
///     already-logically-closed controller).
///   • dispose() calls for all TECs, FocusNode, and ScrollController are
///     deferred to a post-frame callback.  This is critical: GetX calls
///     onClose() synchronously during Get.delete(), which may fire while
///     Flutter's layout/draw pipeline is still mid-flight (the bottom-sheet
///     overlay entry may still be mounted).  If we dispose synchronously,
///     _AnimatedState.didUpdateWidget on the next sub-frame calls
///     ChangeNotifier.addListener() on the now-disposed TEC and throws:
///       "TextEditingController used after being disposed"
///     Deferring to addPostFrameCallback guarantees the sheet's render
///     subtree is fully deactivated before any dispose() call executes.
///
/// Concrete subclasses only need to implement the abstract members
/// and call [initBaseListeners] + [captureSnapshot] from their [initialise].
abstract class ItemSheetControllerBase extends GetxController {
  // ── Dependencies ─────────────────────────────────────────────
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Form infrastructure ────────────────────────────────────────────
  final GlobalKey<FormState> formKey               = GlobalKey<FormState>();
  final ScrollController     sheetScrollController = ScrollController();

  final TextEditingController qtyController   = TextEditingController();
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();
  final FocusNode rackFocusNode = FocusNode();

  // ── Core item identity ───────────────────────────────────────────
  var itemCode = ''.obs;
  var itemName = ''.obs;

  // ── Validation state ────────────────────────────────────────────
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

  // ── S1: Batch read-only toggle (promoted from PR + SE) ─────────────────
  var isBatchReadOnly = false.obs;

  // ── S1: EAN-8 scan context (promoted from PR/SE/DN) ───────────────────
  String currentScannedEan = '';

  // ── Item metadata (for GlobalItemFormSheet footer) ───────────────────
  var itemOwner      = RxnString();
  var itemCreation   = RxnString();
  var itemModified   = RxnString();
  var itemModifiedBy = RxnString();

  // ── Editing context ─────────────────────────────────────────────
  var editingItemName = RxnString();

  // ── Add / edit mode ─────────────────────────────────────────────
  bool isAddMode = true;

  // ── Option-3: animated save button state ────────────────────────────
  var saveButtonState = SaveButtonState.idle.obs;

  // ── Step-1: merged loading flag ──────────────────────────────────────
  RxBool isAddingItemFlag = false.obs;

  bool get isSheetLoading =>
      isValidatingBatch.value ||
      isValidatingRack.value  ||
      isAddingItemFlag.value  ||
      saveButtonState.value == SaveButtonState.loading;

  // ── Step-1: scan-bar state (promoted from DN parent) ──────────────────
  RxBool isScanning = false.obs;
  TextEditingController? sheetScanController;

  // ── Step-1: abstract qty info text ──────────────────────────────────
  String? get qtyInfoText;

  // ── Step-1: abstract delete dispatch ────────────────────────────────
  Future<void> deleteCurrentItem();

  // ── Snapshot for dirty-checking ──────────────────────────────────────
  String _snapshotBatch = '';
  String _snapshotRack  = '';
  String _snapshotQty   = '';

  // ── Auto-submit worker ────────────────────────────────────────────
  Worker? _autoSubmitWorker;

  // ── Abstract interface ─────────────────────────────────────────────
  String? get resolvedWarehouse;
  bool get requiresBatch;
  bool get requiresRack;
  void validateSheet();
  Future<void> submit();

  // ── Option-3: submitWithFeedback ────────────────────────────────────
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

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void onClose() {
    // Step 1 — remove all listeners synchronously.
    // This prevents any in-flight TEC notifications on the current frame
    // from reaching validateSheet / _resetSaveStateOnEdit after the
    // controller is logically closed.
    qtyController.removeListener(validateSheet);
    qtyController.removeListener(_resetSaveStateOnEdit);
    batchController.removeListener(validateSheet);
    batchController.removeListener(_resetSaveStateOnEdit);
    rackController.removeListener(validateSheet);
    rackController.removeListener(_resetSaveStateOnEdit);

    // Step 2 — dispose() is deferred to a post-frame callback.
    //
    // WHY: GetX calls onClose() synchronously during Get.delete(), which
    // fires while Flutter's layout/draw pipeline may still be mid-flight
    // (confirmed by crash stack frames #218-252: PipelineOwner.flushLayout
    // → _RenderLayoutBuilder → BuildOwner.buildScope). The bottom-sheet
    // overlay entry is still mounted at this point. On the next sub-frame
    // _AnimatedState.didUpdateWidget fires on the TextFormField, calls
    // ChangeNotifier.addListener() on the TEC — if already disposed, this
    // throws: "TextEditingController used after being disposed".
    //
    // addPostFrameCallback fires after RendererBinding.drawFrame() completes
    // and after the deactivation sweep, guaranteeing the sheet subtree is
    // fully unmounted before any dispose() call executes.
    final qtc   = qtyController;
    final btc   = batchController;
    final rtc   = rackController;
    final rfn   = rackFocusNode;
    final ssc   = sheetScrollController;
    final asw   = _autoSubmitWorker;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtc.dispose();
      btc.dispose();
      rtc.dispose();
      rfn.dispose();
      ssc.dispose();
      asw?.dispose();
    });

    super.onClose();
  }

  // ── Shared initialisation helper ─────────────────────────────────────

  void initBaseListeners() {
    qtyController.addListener(validateSheet);
    batchController.addListener(validateSheet);
    rackController.addListener(validateSheet);

    qtyController.addListener(_resetSaveStateOnEdit);
    batchController.addListener(_resetSaveStateOnEdit);
    rackController.addListener(_resetSaveStateOnEdit);
  }

  void _resetSaveStateOnEdit() {
    if (saveButtonState.value == SaveButtonState.success ||
        saveButtonState.value == SaveButtonState.error) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  void captureSnapshot() {
    _snapshotBatch = batchController.text;
    _snapshotRack  = rackController.text;
    _snapshotQty   = qtyController.text;
  }

  bool get isFieldsDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Auto-submit wiring ────────────────────────────────────────────

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

  // ── Qty helpers ──────────────────────────────────────────────────────

  void adjustQty(double delta) {
    double current = double.tryParse(qtyController.text) ?? 0;
    double next    = current + delta;
    if (next < 0) next = 0;
    if (maxQty.value > 0 && next > maxQty.value) next = maxQty.value;
    qtyController.text =
        next % 1 == 0 ? next.toInt().toString() : next.toString();
    validateSheet();
  }

  // ── P2-A: Batch validation ──────────────────────────────────────────

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

  // ── S1: validateBatchOnInit (promoted from PR/SE/DN) ───────────────────

  void validateBatchOnInit(String batch) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => validateBatch(batch));
  }

  void resetBatch() {
    isBatchValid.value    = false;
    isBatchReadOnly.value = false; // S1
    batchError.value      = null;
    validateSheet();
  }

  // ── Rack validation ──────────────────────────────────────────────────

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

  // ── P2-C: Stock / rack-map fetching ──────────────────────────────────────

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

  // ── P2-B: Base validation ─────────────────────────────────────────────

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
