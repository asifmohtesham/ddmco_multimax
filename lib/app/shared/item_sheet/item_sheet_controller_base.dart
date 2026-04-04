import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';

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
///   qtyInfoText      — abstract; each controller supplies its own label.
///   qtyInfoTooltip   — CONCRETE RxnString field (promoted from abstract).
///                      SE writes it directly inside validateSheet() (Commit 5
///                      intent: single backing store, no shadowing override).
///                      PS and other subclasses may override the getter to
///                      return their own RxnString instance if needed.
///   adjustQty        — abstract; concrete controllers implement stepper.
///   deleteCurrentItem — abstract; concrete controllers implement deletion.
///   sheetScanController/isScanning — scan-bar integration.
///   isAddMode        — abstract bool (satisfies AutoFillRackMixin contract).
///   setupAutoSubmit  — wires the auto-close worker; available to all.
///   initBaseListeners/captureSnapshot — aliases for addSheetListeners /
///                      snapshotState used by PO and PS controllers.
///   sheetScrollController — concrete ScrollController exposed so parent
///                      orchestrators can pass it to UniversalItemFormSheet
///                      without needing a subclass override (Group B fix).
///   disposeControllers — public teardown helper called by parent
///                      orchestrators post-sheet-close (Group B fix).
///   softResetBatch / softResetRack — DN-8: reset validity flags and errors
///                      without zeroing batchBalance / rackBalance so the
///                      BalanceChip does not flash blank between initForEdit
///                      reset and the subsequent API fetch completing.
abstract class ItemSheetControllerBase extends GetxController {
  // ── Reactive state ──────────────────────────────────────────────────────
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

  // ── Edit-mode identity ───────────────────────────────────────────────────
  /// null = add-mode; non-null = the rowId / docName being edited.
  final RxnString editingItemName      = RxnString(null);

  // ── Item metadata (shown in sheet footer) ────────────────────────────────
  final RxString  itemName             = ''.obs;
  final RxnString itemOwner            = RxnString(null);
  final RxnString itemCreation         = RxnString(null);
  final RxnString itemModified         = RxnString(null);
  final RxnString itemModifiedBy       = RxnString(null);

  // ── Form key ────────────────────────────────────────────────────────────
  final GlobalKey<FormState> formKey   = GlobalKey<FormState>();

  // ── isAddingItemFlag (used by PO/PS controllers) ─────────────────────────
  bool isAddingItemFlag = false;

  // ── Text controllers ────────────────────────────────────────────────────
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();
  final TextEditingController qtyController   = TextEditingController();

  /// FocusNode for the rack text field.
  final FocusNode rackFocusNode = FocusNode();

  /// ScrollController for the sheet's scrollable body.
  ///
  /// Exposed so parent orchestrators (e.g. DeliveryNoteFormController) can
  /// pass it directly to UniversalItemFormSheet without requiring each
  /// concrete subclass to declare its own field (Group B — B1 fix).
  final ScrollController sheetScrollController = ScrollController();

  var itemCode = ''.obs;

  // ── batchWiseHistory defaults ─────────────────────────────────────────────
  List<dynamic> get batchWiseHistory       => const [];
  RxBool        get isLoadingBatchHistory  => false.obs;
  Future<void>  fetchBatchWiseHistory()    async {}

  // ── maxQty default ────────────────────────────────────────────────────────
  double get maxQty => 0.0;

  /// Rack-name → available-qty map.
  Map<String, double> get rackStockMap => const {};

  // Dirty-tracking snapshots
  String _snapshotBatch = '';
  String _snapshotRack  = '';
  String _snapshotQty   = '';

  // ── Auto-submit worker ───────────────────────────────────────────────────
  Worker? _autoSubmitWorker;

  // ── Abstract interface ───────────────────────────────────────────────────
  String? get resolvedWarehouse;
  bool get requiresBatch;
  bool get requiresRack;

  /// The accent colour used by this sheet's UI elements.
  Color get accentColor;

  void validateSheet();
  Future<void> submit();

  /// Whether the sheet is in add-mode (true) or edit-mode (false).
  /// Satisfies [AutoFillRackMixin.isAddMode].
  bool get isAddMode;

  /// Qty-info label shown next to the qty field (e.g. 'Max: 12').
  String get qtyInfoText;

  /// Tooltip backing the qty-info label; null = no tap target rendered.
  ///
  /// Concrete field — NOT abstract.  SE writes this directly inside
  /// validateSheet() so that SharedBatchField observes the same [RxnString]
  /// reference without any shadowing override (Commit 5 intent).  Subclasses
  /// that need their own RxnString instance (e.g. PS) may override the getter
  /// to return a different [RxnString], but must NOT declare a new field with
  /// the same name — override the getter only.
  // ignore: prefer_final_fields
  RxnString qtyInfoTooltip = RxnString(null);

  /// Mobile scanner controller backing the scan footer.
  MobileScannerController? get sheetScanController;

  /// Increment (+1) or decrement (-1) the qty field.
  void adjustQty(int delta);

  /// Delete the item currently being edited.
  void deleteCurrentItem();

  // ── submitWithFeedback ──────────────────────────────────────────────────
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

  // ── disposeControllers ──────────────────────────────────────────────────
  /// Explicit teardown called by parent orchestrators immediately after the
  /// sheet closes (e.g. in a post-frame callback) before Get.delete().
  ///
  /// Disposes [sheetScrollController] and the three text controllers.  Safe
  /// to call multiple times — each disposal is wrapped in a try/catch.
  /// (Group B — B2 fix)
  void disposeControllers() {
    try { sheetScrollController.dispose(); } catch (_) {}
    try { batchController.dispose(); } catch (_) {}
    try { rackController.dispose();  } catch (_) {}
    try { qtyController.dispose();   } catch (_) {}
    try { rackFocusNode.dispose();   } catch (_) {}
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────
  @override
  void onClose() {
    _autoSubmitWorker?.dispose();
    try { sheetScrollController.dispose(); } catch (_) {}
    try { batchController.dispose(); } catch (_) {}
    try { rackController.dispose();  } catch (_) {}
    try { qtyController.dispose();   } catch (_) {}
    try { rackFocusNode.dispose();   } catch (_) {}
    super.onClose();
  }

  // ── Listener wiring ──────────────────────────────────────────────────────
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
    if (saveButtonState.value != SaveButtonState.idle) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  // ── setupAutoSubmit ──────────────────────────────────────────────────────
  void setupAutoSubmit({required Future<void> Function() onValid}) {
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

  /// Backwards-compat alias.
  void setupAutoSubmitOnValid({required Future<void> Function() onValid}) =>
      setupAutoSubmit(onValid: onValid);

  // ── Dirty-tracking ───────────────────────────────────────────────────────
  void snapshotState() {
    _snapshotBatch = batchController.text;
    _snapshotRack  = rackController.text;
    _snapshotQty   = qtyController.text;
  }

  bool get isDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Rack reset ──────────────────────────────────────────────────────────

  /// Full rack reset — clears the text field, zeros the balance, and
  /// resets all validity state.  Called when the user explicitly clears
  /// the rack field.
  void resetRack() {
    rackController.clear();
    isRackValid.value      = false;
    rackError.value        = '';
    rackBalance.value      = 0.0;
    rackStockTooltip.value = null;
  }

  /// Soft rack reset — resets validity flags, error text, and tooltip
  /// but does NOT zero [rackBalance].
  ///
  /// Use during [initForEdit] before re-seeding the rack value so that
  /// the [BalanceChip] does not flash blank between the reset and the
  /// subsequent [validateRack] / [fetchRackBalance] completing (DN-8).
  void softResetRack() {
    isRackValid.value      = false;
    rackError.value        = '';
    rackStockTooltip.value = null;
    // rackBalance intentionally NOT zeroed — old value persists until
    // fetchRackBalance() overwrites it with the freshly-fetched value.
  }

  // ── Batch reset ─────────────────────────────────────────────────────────

  /// Full batch reset — zeros balances and resets all validity state.
  /// Called when the user explicitly clears / edits the batch field.
  void resetBatch() {
    isBatchValid.value     = false;
    isBatchReadOnly.value  = false;
    batchError.value       = '';
    batchInfoTooltip.value = null;
    batchBalance.value     = 0.0;
    resetRack();
  }

  /// Soft batch reset — resets validity flags and errors without zeroing
  /// [batchBalance] or [rackBalance].
  ///
  /// Use during [initForEdit] before re-seeding existing batch/rack values
  /// so that [BalanceChip] widgets do not flash blank between the reset and
  /// the API fetch completing (DN-8).
  void softResetBatch() {
    isBatchValid.value     = false;
    isBatchReadOnly.value  = false;
    batchError.value       = '';
    batchInfoTooltip.value = null;
    // batchBalance intentionally NOT zeroed — old value persists until
    // fetchBatchBalance() overwrites it with the freshly-fetched value.
    softResetRack();
  }

  // ── Fetch helpers ────────────────────────────────────────────────────────
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

  /// Fetches the available rack balance for [rack] from the Stock Balance
  /// report (via [ApiProvider.getStockBalanceWithDimension]) and writes the
  /// result to [rackBalance].
  ///
  /// Fix 3: the previous implementation matched rows on the key 'custom_rack'
  /// but [getStockBalanceWithDimension] normalises the rack field to 'rack'.
  /// The mismatch caused [firstWhere] to always fall through to orElse and
  /// return {'qty': 0.0}.  Changed the match key to 'rack'.
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
      // Fix 3: match on 'rack' — the key getStockBalanceWithDimension
      // normalises to — not 'custom_rack'.
      final match = rows.firstWhere(
        (r) => (r['rack'] as String?) == rack,
        orElse: () => {'qty': 0.0},
      );
      rackBalance.value = (match['qty'] as num).toDouble();
    } catch (e) {
      log('[ItemSheet] fetchRackBalance error: $e', name: 'ItemSheet');
    }
  }

  // ── openBatchPicker (base) ──────────────────────────────────────────────
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
        'Batch',
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
      if (parts.isNotEmpty) batchInfoTooltip.value = parts.join('  •  ');

      isBatchValid.value = true;
      await fetchBatchBalance();
    } catch (e) {
      batchError.value = 'Error validating batch: $e';
    } finally {
      isValidatingBatch.value = false;
    }
  }
}
