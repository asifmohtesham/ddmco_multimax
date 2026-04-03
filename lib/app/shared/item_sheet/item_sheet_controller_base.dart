import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';

/// Drives the visual state of the animated Save button in the item sheet.
enum SaveButtonState { idle, loading, success, error }

/// Base return type for batch-lookup results.
///
/// A batch that exists in the system and can be selected by the user.
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

// ─────────────────────────────────────────────────────────────────────────────
// ItemSheetControllerBase
// ─────────────────────────────────────────────────────────────────────────────
///
/// Shared state and behaviour for all item-sheet controllers (Stock Entry,
/// Delivery Note, Purchase Receipt …).
///
/// ## Responsibilities
///
///   • Batch validation lifecycle  — [validateBatch], [resetBatch],
///     [validateBatchOnInit], [isBatchValid], [batchError], [batchInfoTooltip]
///   • Rack validation lifecycle   — [validateRack],  [resetRack]
///   • Balance computation         — [maxQty], [batchBalance], [fetchBatchBalance]
///   • Save-button state           — [SaveButtonState], [saveButtonState]
///   • Sheet-valid gate            — [isSheetValid], [validateSheet]
///   • Dirty-check helpers         — [isDirty], snapshot tracking
///   • [openBatchPicker]           — canonical picker lifecycle shared by all
///     concrete controllers.  SE overrides to pre-fetch [batchWiseHistory].
///
/// ## Changelog
///
///   validateBatch()  — resets rackBalance = 0.0 on success so rack must
///                      be re-validated when the batch changes.
///   maxQty           — computed getter (double), not RxDouble.
///                      validateBatch() no longer writes maxQty directly.
abstract class ItemSheetControllerBase extends GetxController {
  // ── Reactive state ────────────────────────────────────────────────────
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

  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();
  final TextEditingController qtyController   = TextEditingController();

  var itemCode = ''.obs;

  // batchWiseHistory : Subclasses that support the batch-history picker
  // (e.g. SE) maintain this list.  Base provides an empty default so
  // widgets that read it compile without a cast.
  List<dynamic> get batchWiseHistory       => const [];
  RxBool        get isLoadingBatchHistory  => false.obs;
  Future<void>  fetchBatchWiseHistory()    async {}

  // batchBalance : Batch-Wise Balance for the selected batch in resolvedWarehouse.
  //                Populated by fetchBatchBalance() / validateBatch().
  //
  // maxQty  : The effective per-item quantity ceiling; computed from the
  //           narrowest of serial / batch / rack / MR ceilings.
  //           Concrete controllers override this getter.
  double get maxQty => 0.0;

  // Dirty-tracking snapshots (written by [snapshotState]).
  String _snapshotBatch = '';
  String _snapshotRack  = '';
  String _snapshotQty   = '';

  // ── Auto-submit worker ────────────────────────────────────────────────
  Worker? _autoSubmitWorker;

  // ── Abstract interface ────────────────────────────────────────────────
  String? get resolvedWarehouse;
  bool get requiresBatch;
  bool get requiresRack;
  /// The accent colour used by this sheet's UI elements.
  /// Each concrete controller returns its own brand colour.
  Color get accentColor;
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
    _autoSubmitWorker?.dispose();
    try { batchController.dispose(); } catch (_) {}
    try { rackController.dispose();  } catch (_) {}
    try { qtyController.dispose();   } catch (_) {}
    super.onClose();
  }

  // ── Listener wiring ───────────────────────────────────────────────────
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

  void _resetSaveStateOnEdit() {
    if (saveButtonState.value != SaveButtonState.idle) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  // ── Dirty-tracking ────────────────────────────────────────────────────
  void snapshotState() {
    _snapshotBatch = batchController.text;
    _snapshotRack  = rackController.text;
    _snapshotQty   = qtyController.text;
  }

  bool get isDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Sheet-valid gate ──────────────────────────────────────────────────
  bool get isSheetValid {
    if (requiresBatch && !isBatchValid.value) return false;
    if (requiresRack  && !isRackValid.value)  return false;
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0)              return false;
    return true;
  }

  // ── Rack reset ────────────────────────────────────────────────────────
  void resetRack() {
    rackController.clear();
    isRackValid.value  = false;
    rackError.value    = '';
    rackBalance.value  = 0.0;
  }

  // ── Batch reset ───────────────────────────────────────────────────────
  void resetBatch() {
    isBatchValid.value    = false;
    isBatchReadOnly.value = false;
    batchError.value      = '';
    batchInfoTooltip.value = null;
    batchBalance.value    = 0.0;
    resetRack();
  }

  // ── Fetch helpers ─────────────────────────────────────────────────────

  // Fetches the Batch-Wise Balance for [batchController.text] in
  // [resolvedWarehouse] and writes the total to [batchBalance].
  Future<void> fetchBatchBalance() async {
    final batch = batchController.text.trim();
    if (batch.isEmpty || itemCode.value.isEmpty) {
      batchBalance.value = 0.0;
      return;
    }
    final wh = resolvedWarehouse;
    try {
      final rows = await ApiProvider().getBatchWiseBalance(
        itemCode:  itemCode.value,
        warehouse: wh,
        batchNo:   batch,
      );
      batchBalance.value = rows.fold(0.0, (s, r) => s + (r['qty'] as num).toDouble());
    } catch (e) {
      log('[ItemSheet] fetchBatchBalance error: $e', name: 'ItemSheet');
    }
  }

  // Fetches the Stock Balance with Inventory Dimension for [itemCode]
  // in [resolvedWarehouse], then isolates the row whose rack matches
  // [rackController.text] and writes the result to [rackBalance].
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
      final match = rows.firstWhere(
        (r) => (r['custom_rack'] as String?) == rack,
        orElse: () => {'qty': 0.0},
      );
      rackBalance.value = (match['qty'] as num).toDouble();
    } catch (e) {
      log('[ItemSheet] fetchRackBalance error: $e', name: 'ItemSheet');
    }
  }

  // ── openBatchPicker (base) ───────────────────────────────────────────────
  //
  // Opens [BatchPickerSheet], writes the selected batch to [batchController],
  // and calls [validateBatch].  Subclasses may override to add pre-fetch
  // behaviour before delegating to super (e.g. SE pre-fetches batchWiseHistory).
  Future<void> openBatchPicker() async {
    final ctx = Get.context;
    if (ctx == null) return;
    final selected = await showBatchPickerSheet(
      ctx,
      itemCode:    itemCode.value,
      warehouse:   resolvedWarehouse,
      accentColor: accentColor,
    );
    if (selected == null || selected.isEmpty) return;
    batchController.text = selected;
    await validateBatch(selected);
  }

  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) { resetBatch(); return; }

    isValidatingBatch.value = true;
    batchError.value        = '';
    batchInfoTooltip.value  = null;
    isBatchValid.value      = false;

    try {
      final results = await ApiProvider().getList(
        doctype: 'Batch',
        filters: {'name': batch, 'item': itemCode.value},
        fields:  ['name', 'expiry_date', 'manufacturing_date'],
      );

      if (results.isEmpty) {
        batchError.value = 'Batch "$batch" not found for this item.';
        return;
      }

      final row        = results.first;
      final expiryRaw  = row['expiry_date'] as String?;
      final mfgRaw     = row['manufacturing_date'] as String?;

      // ── Expiry check ───────────────────────────────────────────────
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
            // fall-through → mark valid but keep the warning
          }
        }
      }

      // ── Tooltip (mfg + expiry info) ────────────────────────────────
      final parts = <String>[];
      if (mfgRaw    != null && mfgRaw.isNotEmpty)    parts.add('Mfg: $mfgRaw');
      if (expiryRaw != null && expiryRaw.isNotEmpty) parts.add('Exp: $expiryRaw');
      batchInfoTooltip.value = parts.isEmpty ? null : parts.join('  ·  ');

      isBatchValid.value    = true;
      isBatchReadOnly.value = true;
      rackBalance.value     = 0.0;
      await fetchBatchBalance();

    } catch (e) {
      batchError.value = 'Validation error: $e';
      log('[ItemSheet] validateBatch error: $e', name: 'ItemSheet');
    } finally {
      isValidatingBatch.value = false;
    }
  }

  // ── S1: validateBatchOnInit ───────────────────────────────────────────
  void validateBatchOnInit(String batch) {
    if (batch.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed) validateBatch(batch);
    });
  }

  // ── Auto-submit on valid ──────────────────────────────────────────────
  void setupAutoSubmitOnValid({required Future<void> Function() onValid}) {
    _autoSubmitWorker?.dispose();
    _autoSubmitWorker = ever(
      saveButtonState,
      (state) async {
        if (state == SaveButtonState.success) {
          await onValid();
        }
      },
    );
  }

  // ── Rack validation (base implementation) ─────────────────────────────
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) {
      resetRack();
      return;
    }
    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;

    try {
      await fetchRackBalance(rack);
      isRackValid.value = true;
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
      log('[ItemSheet] validateRack error: $e', name: 'ItemSheet');
    } finally {
      isValidatingRack.value = false;
    }
  }

  // ── Sheet-valid helper used by validateSheet implementations ──────────
  bool get isBatchRequiredAndInvalid =>
      requiresBatch && !isBatchValid.value;

  bool get isRackRequiredAndInvalid =>
      requiresRack && !isRackValid.value;

  // ── isSheetValid override hook ─────────────────────────────────────
  //
  // Concrete controllers may override [isSheetValid] and then call
  // super.isSheetValid to include the base checks.
  bool get baseSheetValid {
    if (requiresBatch && !isBatchValid.value) return false;
    if (requiresRack  && !isRackValid.value)  return false;
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0)              return false;
    return true;
  }
}
