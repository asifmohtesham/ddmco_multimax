import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Drives the visual state of the animated Save button in the item sheet.
enum SaveButtonState { idle, loading, success, error }

/// Abstract base controller for every DocType item-sheet.
///
/// C-1 : [qtyInfoTooltip] — default-null getter.
/// C-5 : [liveRemaining] — concrete RxDouble (default 0.0).
///   Subclasses that compute a ceiling (e.g. StockEntryItemFormController)
///   can write to this field directly.  SharedSerialField subscribes to it
///   without any duck-type or try/catch, eliminating the zero-subscription
///   Obx crash.
///
/// Fix TEC-1 (stability): TECs are disposed synchronously in [onClose].
///   The previous addPostFrameCallback deferral opened a one-frame race
///   window: keyboard show => LayoutBuilder rebuild => _AnimatedState
///   re-subscribed to an already-disposed TEC, producing the
///   "TextEditingController used after being disposed" assertion.
///   Synchronous disposal is safe because GetX only calls onClose() after
///   the owning widget has left the tree.
///
/// Fix TEC-2 (IME-dispose): TEC dispose() calls are now wrapped in a
///   try/catch.  The primary protection against premature disposal is
///   registering DeliveryNoteItemFormController (and any sheet controller)
///   with permanent: true in Get.put() so GetX cannot auto-delete it
///   during the MediaQuery resize triggered by hiding the keyboard.
///   This try/catch is defence-in-depth: if onClose() is somehow
///   invoked twice (e.g. hot-restart race or future refactor), the second
///   call silently no-ops rather than crashing with a secondary error
///   that would mask the original stack trace.
///
/// Commit Balance-Base:
///   [batchBalance]        — Batch-Wise Balance in resolved warehouse.
///   [rackBalance]         — Stock Balance with Inventory Dimension (rack row).
///   [fetchBatchBalance]   — promoted from SE's _updateBatchBalance().
///   [fetchRackBalance]    — extracted from SE's _updateAvailableStock().
///
/// Commit 3:
///   [qtyInfoText]    — concrete; shows batch/rack/MIN breakdown.
///   [qtyInfoTooltip] — concrete; detailed balance lines via _fmtQty().
///   validateBatch()  — resets rackBalance = 0.0 on success so rack must
///                      be re-confirmed after any batch change.
///
/// Commit 4 (this commit):
///   [maxQty] — replaced mutable RxDouble with computed getter:
///              MIN(batchBalance, rackBalance) when both > 0,
///              else whichever is known, else 0.0 (no cap).
///              validateBatch() no longer writes maxQty directly.
abstract class ItemSheetControllerBase extends GetxController {
  // ── Dependencies ──────────────────────────────────────────────────────
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Form infrastructure ───────────────────────────────────────────────
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
  var batchError        = RxnString();
  var rackError         = RxnString();
  var batchInfoTooltip  = RxnString();
  var rackStockTooltip  = RxnString();
  var rackStockMap      = <String, double>{}.obs;

  // ── Balance state (universal) ─────────────────────────────────────────
  //
  // batchBalance : Batch-Wise Balance for the selected batch in resolvedWarehouse.
  //                Populated by fetchBatchBalance() / validateBatch().
  // rackBalance  : Stock Balance with Inventory Dimension isolated to the
  //                selected rack row. Populated by fetchRackBalance(rack).
  //
  // These fields are declared here so every DocType item-sheet
  // (Stock Entry, Delivery Note, etc.) shares the same balance model
  // without duplicating fetcher logic in each subclass.
  var batchBalance          = 0.0.obs;
  var rackBalance           = 0.0.obs;
  var isLoadingBatchBalance = false.obs;
  var isLoadingRackBalance  = false.obs;

  // ── Computed qty ceiling (Commit 4) ───────────────────────────────────
  //
  // maxQty is derived — never stored — so it is always consistent with
  // the live balance values:
  //   • Both balances known (> 0) → MIN(batchBalance, rackBalance)
  //   • Only batch known           → batchBalance
  //   • Only rack  known           → rackBalance
  //   • Neither known              → 0.0  (no cap enforced)
  //
  // Widgets and validators read this as a plain double — no .value needed.
  double get maxQty {
    final b = batchBalance.value;
    final r = rackBalance.value;
    if (b > 0 && r > 0) return b < r ? b : r;
    if (b > 0) return b;
    if (r > 0) return r;
    return 0.0;
  }

  // ── Ceiling for POS / serial-cap display (C-5) ───────────────────────
  var liveRemaining = 0.0.obs;

  // ── S1: Batch read-only toggle ────────────────────────────────────────
  var isBatchReadOnly = false.obs;

  // ── S1: EAN scan context ──────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Item metadata ─────────────────────────────────────────────────────
  var itemOwner      = RxnString();
  var itemCreation   = RxnString();
  var itemModified   = RxnString();
  var itemModifiedBy = RxnString();

  // ── Editing context ───────────────────────────────────────────────────
  var editingItemName = RxnString();

  // ── Add / edit mode ───────────────────────────────────────────────────
  bool isAddMode = true;

  // ── Option-3: animated save button state ─────────────────────────────
  var saveButtonState = SaveButtonState.idle.obs;

  // ── Step-1: merged loading flag ───────────────────────────────────────
  RxBool isAddingItemFlag = false.obs;

  bool get isSheetLoading =>
      isValidatingBatch.value ||
      isValidatingRack.value  ||
      isAddingItemFlag.value  ||
      saveButtonState.value == SaveButtonState.loading;

  // ── Step-1: scan-bar state ────────────────────────────────────────────
  RxBool isScanning = false.obs;
  TextEditingController? sheetScanController;

  // ── Qty label (Commit 3: concrete in base) ────────────────────────────
  //
  // Returns a short pill label summarising the effective qty cap:
  //   • Both known  → 'Max: N'  (MIN of batch and rack)
  //   • Batch only  → 'Batch: N'
  //   • Rack only   → 'Rack: N'
  //   • Neither     → null (badge hidden)
  //
  // Subclasses that need extra lines (POS serial cap, MR cap) should
  // override, call super, then append their own suffix.
  String? get qtyInfoText {
    final b = batchBalance.value;
    final r = rackBalance.value;
    if (b > 0 && r > 0) {
      final min = b < r ? b : r;
      return 'Max: ${_fmtQty(min)}';
    }
    if (b > 0) return 'Batch: ${_fmtQty(b)}';
    if (r > 0) return 'Rack: ${_fmtQty(r)}';
    return null;
  }

  // Returns a multi-line breakdown shown in the tap dialog.
  // Subclasses may override and call super to prepend base lines.
  String? get qtyInfoTooltip {
    final b = batchBalance.value;
    final r = rackBalance.value;
    final parts = <String>[];
    if (b > 0) parts.add('Batch balance : ${_fmtQty(b)}');
    if (r > 0) parts.add('Rack balance  : ${_fmtQty(r)}');
    if (b > 0 && r > 0) {
      final min = b < r ? b : r;
      parts.add('Effective max : ${_fmtQty(min)}');
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  // ── Abstract delete dispatch ──────────────────────────────────────────
  Future<void> deleteCurrentItem();

  // ── Snapshot for dirty-checking ───────────────────────────────────────
  String _snapshotBatch = '';
  String _snapshotRack  = '';
  String _snapshotQty   = '';

  // ── Auto-submit worker ────────────────────────────────────────────────
  Worker? _autoSubmitWorker;

  // ── Abstract interface ────────────────────────────────────────────────
  String? get resolvedWarehouse;
  bool get requiresBatch;
  bool get requiresRack;
  void validateSheet();
  Future<void> submit();

  // ── Option-3: submitWithFeedback ──────────────────────────────────────
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

  // ── Lifecycle ─────────────────────────────────────────────────────────
  @override
  void onClose() {
    // Remove listeners first — safe to call even if controller is disposed.
    try { qtyController.removeListener(validateSheet); } catch (_) {}
    try { qtyController.removeListener(_resetSaveStateOnEdit); } catch (_) {}
    try { batchController.removeListener(validateSheet); } catch (_) {}
    try { batchController.removeListener(_resetSaveStateOnEdit); } catch (_) {}
    try { rackController.removeListener(validateSheet); } catch (_) {}
    try { rackController.removeListener(_resetSaveStateOnEdit); } catch (_) {}

    // fix(TEC-2): wrap each dispose() in try/catch as defence-in-depth.
    // Primary protection is permanent: true in Get.put() (see
    // delivery_note_form_controller._openItemSheet), which prevents GetX
    // from calling onClose() prematurely during an IME-triggered rebuild.
    // If onClose() is somehow called a second time, these no-op silently.
    try { qtyController.dispose(); } catch (_) {}
    try { batchController.dispose(); } catch (_) {}
    try { rackController.dispose(); } catch (_) {}
    try { rackFocusNode.dispose(); } catch (_) {}
    try { sheetScrollController.dispose(); } catch (_) {}
    _autoSubmitWorker?.dispose();

    super.onClose();
  }

  // ── Shared initialisation helper ──────────────────────────────────────
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

  // ── Auto-submit wiring ────────────────────────────────────────────────
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

  // ── Qty helpers ───────────────────────────────────────────────────────
  void adjustQty(double delta) {
    double current = double.tryParse(qtyController.text) ?? 0;
    double next    = current + delta;
    if (next < 0) next = 0;
    final cap = maxQty;
    if (cap > 0 && next > cap) next = cap;
    qtyController.text =
        next % 1 == 0 ? next.toInt().toString() : next.toString();
    validateSheet();
  }

  // ── Formatting helper ─────────────────────────────────────────────────
  String _fmtQty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  // ── fetchBatchBalance ─────────────────────────────────────────────────
  //
  // Fetches the Batch-Wise Balance for [batchController.text] in
  // [resolvedWarehouse] and writes the total to [batchBalance].
  //
  // Promoted from SE's _updateBatchBalance() so every DocType item-sheet
  // (Stock Entry, Delivery Note, etc.) can use the same logic without
  // duplicating it in each subclass.
  Future<void> fetchBatchBalance() async {
    final batch = batchController.text.trim();
    if (batch.isEmpty || itemCode.value.isEmpty) {
      batchBalance.value = 0.0;
      return;
    }
    final wh = resolvedWarehouse;
    if (wh == null || wh.isEmpty) {
      batchBalance.value = 0.0;
      return;
    }

    isLoadingBatchBalance.value = true;
    try {
      final res = await _api.getBatchWiseBalance(
        itemCode.value,
        batch,
        warehouse: wh,
      );
      if (res.statusCode == 200 &&
          res.data['message']?['result'] != null) {
        double total = 0.0;
        for (final row in res.data['message']['result'] as List) {
          if (row is! Map) continue;
          final val = row['balance_qty'] ??
              row['bal_qty'] ??
              row['qty_after_transaction'] ??
              row['qty'];
          total += (val as num?)?.toDouble() ?? 0.0;
        }
        batchBalance.value = total;
      } else {
        batchBalance.value = 0.0;
      }
    } catch (e) {
      batchBalance.value = 0.0;
      log('[ItemSheet] fetchBatchBalance error: $e', name: 'ItemSheet');
    } finally {
      isLoadingBatchBalance.value = false;
    }
  }

  // ── fetchRackBalance ──────────────────────────────────────────────────
  //
  // Fetches the Stock Balance with Inventory Dimension for [itemCode]
  // in [resolvedWarehouse], then isolates the row whose rack matches
  // [rack] and writes that qty to [rackBalance].
  //
  // Extracted from SE's _updateAvailableStock() rack-row logic so that
  // all DocType item-sheets share a single, tested implementation.
  Future<void> fetchRackBalance(String rack) async {
    if (rack.isEmpty || itemCode.value.isEmpty) {
      rackBalance.value = 0.0;
      return;
    }
    final wh = resolvedWarehouse;
    if (wh == null || wh.isEmpty) {
      rackBalance.value = 0.0;
      return;
    }

    isLoadingRackBalance.value = true;
    final batch = batchController.text.trim();
    try {
      final res = await _api.getStockBalance(
        itemCode:  itemCode.value,
        warehouse: wh,
        batchNo:   batch.isNotEmpty ? batch : null,
      );
      if (res.statusCode == 200 &&
          res.data['message']?['result'] != null) {
        double rackBal = 0.0;
        for (final row in res.data['message']['result'] as List) {
          if (row is! Map) continue;
          if (row['rack'] == rack) {
            rackBal += (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
          }
        }
        rackBalance.value = rackBal;
      } else {
        rackBalance.value = 0.0;
      }
    } catch (e) {
      rackBalance.value = 0.0;
      log('[ItemSheet] fetchRackBalance error: $e', name: 'ItemSheet');
    } finally {
      isLoadingRackBalance.value = false;
    }
  }

  // ── P2-A: Batch validation ────────────────────────────────────────────
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

      // Write batchBalance — maxQty is now computed from this + rackBalance.
      batchBalance.value    = fetchedQty;
      // Reset rackBalance so the rack must be re-confirmed after a batch
      // change — maxQty stays 0 (no cap) until rack is re-validated.
      rackBalance.value     = 0.0;
      isBatchValid.value    = true;
      isBatchReadOnly.value = true;

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
      isBatchReadOnly.value  = false;
      batchError.value       = 'Invalid Batch';
      batchBalance.value     = 0.0;
      rackBalance.value      = 0.0;
      batchInfoTooltip.value = null;
      GlobalSnackbar.error(message: 'Batch validation failed');
      log('[ItemSheet] validateBatch error: $e', name: 'ItemSheet');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  // ── S1: validateBatchOnInit ───────────────────────────────────────────
  void validateBatchOnInit(String batch) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => validateBatch(batch));
  }

  void resetBatch() {
    isBatchValid.value    = false;
    isBatchReadOnly.value = false;
    batchError.value      = null;
    batchBalance.value    = 0.0;
    rackBalance.value     = 0.0;
    validateSheet();
  }

  // ── Rack validation ───────────────────────────────────────────────────
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) {
      isRackValid.value = false;
      rackBalance.value = 0.0;
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
        await fetchRackBalance(rack);
      } else {
        isRackValid.value = false;
        rackBalance.value = 0.0;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      isRackValid.value = false;
      rackBalance.value = 0.0;
      GlobalSnackbar.error(message: 'Rack validation failed: $e');
    } finally {
      isValidatingRack.value = false;
      validateSheet();
    }
  }

  void resetRack() {
    isRackValid.value = false;
    rackError.value   = null;
    rackBalance.value = 0.0;
    validateSheet();
  }

  // ── P2-C: Stock / rack-map fetching ──────────────────────────────────
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

    final cap = maxQty;
    if (isAddMode && cap > 0 && qty > cap) return false;

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
