import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
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
///   disposeControllers — public teardown helper.
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

  /// FocusNode for the rack text field.
  final FocusNode rackFocusNode = FocusNode();

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

  /// Mobile scanner controller backing the scan footer.
  MobileScannerController? get sheetScanController;

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

  // ── disposeControllers ─────────────────────────────────────────────────────────
  void disposeControllers() {
    try { sheetScrollController.dispose(); } catch (_) {}
    try { batchController.dispose(); } catch (_) {}
    try { rackController.dispose();  } catch (_) {}
    try { qtyController.dispose();   } catch (_) {}
    try { rackFocusNode.dispose();   } catch (_) {}
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────────
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
    if (saveButtonState.value != SaveButtonState.idle) {
      saveButtonState.value = SaveButtonState.idle;
    }
  }

  // ── setupAutoSubmit ──────────────────────────────────────────────────────────
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

  void softResetRack() {
    isRackValid.value      = false;
    rackError.value        = '';
    rackStockTooltip.value = null;
  }

  // ── Batch reset ────────────────────────────────────────────────────────────────

  @override
  void resetBatch() {
    isBatchValid.value     = false;
    isBatchReadOnly.value  = false;
    batchError.value       = '';
    batchInfoTooltip.value = null;
    batchBalance.value     = 0.0;
    resetRack();
  }

  void softResetBatch() {
    isBatchValid.value     = false;
    isBatchReadOnly.value  = false;
    batchError.value       = '';
    batchInfoTooltip.value = null;
    softResetRack();
  }

  // ── Fetch helpers ──────────────────────────────────────────────────────────────
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
        (r) => (r['rack'] as String?) == rack,
        orElse: () => {'qty': 0.0},
      );
      rackBalance.value = (match['qty'] as num).toDouble();
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
