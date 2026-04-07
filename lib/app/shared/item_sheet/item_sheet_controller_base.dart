// item_sheet_controller_base.dart
//
// Base class for all item-form sheet controllers (SE, PR, DN, PO, PS).
//
// Commit 2 addition:
//   • sheetContext — nullable BuildContext written by UniversalItemFormSheet
//     when the DraggableScrollableSheet builder fires.  Provides a scoped,
//     reliable context for popping the sheet from controller code.
//   • closeSheet() — preferred sheet-dismiss helper.  Uses
//     Navigator.of(sheetContext) when available; falls back to Get.back()
//     so existing call-sites remain safe even before the context is wired.

// The library directive MUST appear before all other directives.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart'
    show SaveButtonState;
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/batch_no_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/qty_field_with_plus_minus_delegate.dart';

/// Lifecycle rules for TextEditingControllers owned by this class.
/// See tec_lifecycle_rules.dart for the full contract.
abstract class ItemSheetControllerBase extends GetxController
    implements RackFieldWithBrowseDelegate, QtyFieldWithPlusMinusDelegate,
               BatchNoFieldWithBrowseDelegate {

  // ── Commit 2: sheet BuildContext ─────────────────────────────────────────
  BuildContext? sheetContext;

  void closeSheet() {
    final ctx = sheetContext;
    if (ctx != null && ctx.mounted) {
      try {
        Navigator.of(ctx).pop();
        return;
      } catch (_) {}
    }
    if (Get.isBottomSheetOpen == true) Get.back();
  }

  // ── Abstract API ─────────────────────────────────────────────────────────
  bool  get requiresBatch;
  bool  get requiresRack;
  Color get accentColor;
  bool  get isAddMode;
  MobileScannerController? get sheetScanController;

  // ── RackFieldDelegate concrete impls ─────────────────────────────────────
  // rackFocusNode — owned and disposed here so subclasses need not duplicate it.
  final FocusNode _rackFocusNode = FocusNode();
  @override FocusNode get rackFocusNode => _rackFocusNode;

  // rackStockTooltip — null means no tooltip; subclasses may override.
  @override RxnString get rackStockTooltip => RxnString(null);

  // rackBalanceFor — default delegates to the in-memory rackBalance Rx.
  @override double rackBalanceFor(String rack) => rackBalance.value;

  // ── Abstract overrides (RackFieldWithBrowseDelegate) ─────────────────────
  @override bool get canBrowseRacks => false;
  @override Future<RackPickerResult?> browseRacks() async => null;
  @override Future<void> handleRackPicked(RackPickerResult result) async {
    rackController.text = result.rackId;
    await validateRack(result.rackId);
  }

  // ── Abstract overrides (BatchNoFieldWithBrowseDelegate) ──────────────────
  @override bool get canBrowseBatches => false;
  @override Future<String?> browseBatches() async => null;
  @override Future<void> handleBatchPicked(String batchNo) async {
    batchController.text = batchNo;
    await validateBatch(batchNo);
  }

  // ── Abstract overrides (QtyFieldWithPlusMinusDelegate) ───────────────────
  @override double get effectiveMaxQty => double.infinity;
  @override double get maxQty => 0.0;
  @override String? get qtyInfoText => null;
  @override RxnString get qtyInfoTooltip => RxnString(null);
  @override void adjustQty(int delta) {}

  // ── Core TECs ────────────────────────────────────────────────────────────
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();
  final TextEditingController qtyController   = TextEditingController();

  /// A shared ScrollController for the sheet's DraggableScrollableSheet.
  /// Populated by UniversalItemFormSheet / GlobalItemFormSheet when they
  /// pass the sc from the builder; subclasses may read this instead of
  /// maintaining their own.
  ScrollController? sheetScrollController;

  // ── Reactive sheet state ─────────────────────────────────────────────────
  final RxBool   isSheetValid      = false.obs;
  final RxBool   saveButtonVisible = false.obs;
  final RxnString editingItemName  = RxnString(null);
  final RxInt    docStatus         = 0.obs;

  // ── Save-button state (mirrors GlobalItemFormSheet.SaveButtonState) ───────
  final Rx<SaveButtonState> saveButtonState = SaveButtonState.idle.obs;

  // ── Metadata Rx fields (edit mode) ───────────────────────────────────────
  final RxnString itemOwner      = RxnString(null);
  final RxnString itemCreation   = RxnString(null);
  final RxnString itemModified   = RxnString(null);
  final RxnString itemModifiedBy = RxnString(null);

  // ── isAddingItemFlag (set by parent before opening sheet) ─────────────────
  bool isAddingItemFlag = false;

  // ── Qty validation ───────────────────────────────────────────────────────
  final RxBool    isQtyValid     = false.obs;
  final RxString  qtyError       = ''.obs;
  final RxBool    isQtyReadOnly  = false.obs;

  // ── Batch state ──────────────────────────────────────────────────────────
  final RxBool    isBatchValid        = false.obs;
  final RxBool    isBatchReadOnly     = false.obs;
  final RxString  batchError          = ''.obs;
  final RxnString batchInfoTooltip    = RxnString(null);
  final RxBool    isValidatingBatch   = false.obs;
  final RxDouble  batchBalance        = 0.0.obs;

  // ── Rack state ───────────────────────────────────────────────────────────
  final RxBool    isRackValid         = false.obs;
  final RxString  rackError           = ''.obs;
  final RxBool    isValidatingRack    = false.obs;
  final RxDouble  rackBalance         = 0.0.obs;

  // ── Batch-picker history (overridable) ───────────────────────────────────
  List<dynamic> get batchWiseHistory => const [];
  RxBool get isLoadingBatchHistory => false.obs;
  Future<void> fetchBatchWiseHistory() async {}

  // ── Warehouse accessor (subclass provides) ───────────────────────────────
  String? get resolvedWarehouse => null;

  // ── Dirty detection snapshot ─────────────────────────────────────────────
  String? _snapshotBatch;
  String? _snapshotRack;
  String? _snapshotQty;

  void snapshotState() {
    _snapshotBatch = batchController.text;
    _snapshotRack  = rackController.text;
    _snapshotQty   = qtyController.text;
  }

  /// Alias kept for subclasses that call captureSnapshot() by this name.
  void captureSnapshot() => snapshotState();

  bool get isDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    ever(docStatus, (int status) {
      isQtyReadOnly.value = status == 1;
    });
  }

  @override
  void onClose() {
    removeSheetListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      disposeControllers();
    });
    sheetContext = null;
    super.onClose();
  }

  void disposeControllers() {
    try { batchController.dispose(); } catch (_) {}
    try { rackController.dispose();  } catch (_) {}
    try { qtyController.dispose();   } catch (_) {}
    try { _rackFocusNode.dispose();  } catch (_) {}
  }

  // ── Sheet listener wiring ────────────────────────────────────────────────
  void addSheetListeners() {
    batchController.addListener(validateSheet);
    rackController.addListener(validateSheet);
    qtyController.addListener(validateSheet);
    qtyController.addListener(_resetSaveStateOnEdit);
  }

  /// Alias: some parent controllers call initBaseListeners() after child.initialise().
  void initBaseListeners() => addSheetListeners();

  void removeSheetListeners() {
    try { batchController.removeListener(validateSheet); } catch (_) {}
    try { rackController.removeListener(validateSheet);  } catch (_) {}
    try { qtyController.removeListener(validateSheet);   } catch (_) {}
    try { qtyController.removeListener(_resetSaveStateOnEdit); } catch (_) {}
  }

  void _resetSaveStateOnEdit() {
    if (isSheetValid.value) {
      saveButtonVisible.value = true;
    }
  }

  // ── Sheet validity ────────────────────────────────────────────────────────
  void validateSheet() {
    final qty = double.tryParse(qtyController.text);
    isSheetValid.value = (qty != null && qty > 0) &&
        (!requiresBatch || isBatchValid.value) &&
        (!requiresRack  || isRackValid.value);
  }

  // ── Submit ───────────────────────────────────────────────────────────────
  Future<void> submit() async {}

  /// Runs submit() and updates saveButtonState with loading/success/error.
  /// Returns true on success, false on error.
  Future<bool> submitWithFeedback() async {
    saveButtonState.value = SaveButtonState.loading;
    try {
      await submit();
      saveButtonState.value = SaveButtonState.success;
      Future.delayed(const Duration(seconds: 2), () {
        if (saveButtonState.value == SaveButtonState.success) {
          saveButtonState.value = SaveButtonState.idle;
        }
      });
      return true;
    } catch (e) {
      saveButtonState.value = SaveButtonState.error;
      Future.delayed(const Duration(seconds: 2), () {
        if (saveButtonState.value == SaveButtonState.error) {
          saveButtonState.value = SaveButtonState.idle;
        }
      });
      return false;
    }
  }

  /// Wires up an auto-submit worker that calls [onValid] when the sheet
  /// transitions to valid. Only fires once per sheet open (guarded by flag).
  Worker? _autoSubmitWorker;
  void setupAutoSubmit({required Future<void> Function() onValid}) {
    _autoSubmitWorker?.dispose();
    _autoSubmitWorker = ever(isSheetValid, (bool valid) async {
      if (valid) {
        _autoSubmitWorker?.dispose();
        _autoSubmitWorker = null;
        await onValid();
      }
    });
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  void deleteCurrentItem() {}

  // ── Batch helpers ─────────────────────────────────────────────────────────
  void resetBatch() {
    isBatchValid.value      = false;
    isBatchReadOnly.value   = false;
    batchError.value        = '';
    batchInfoTooltip.value  = null;
    batchBalance.value      = 0.0;
  }

  void resetRack() {
    isRackValid.value      = false;
    rackError.value        = '';
    rackBalance.value      = 0.0;
  }

  Future<void> fetchBatchBalance() async {
    try {
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: resolvedWarehouse,
        batchNo:   batchController.text.trim(),
      );
      double total = 0.0;
      for (final r in rows) {
        total += (r['qty'] as num?)?.toDouble() ?? 0.0;
      }
      batchBalance.value = total;
    } catch (_) {
      batchBalance.value = 0.0;
    }
  }

  Future<void> fetchRackBalance(String rack) async {
    try {
      final rows = await ApiProvider().getStockBalanceWithDimension(
        itemCode:  itemCode.value,
        warehouse: resolvedWarehouse,
        batchNo:   batchController.text.isEmpty ? null : batchController.text,
      );
      double total = 0.0;
      for (final r in rows) {
        if ((r['custom_rack'] ?? '').toString().trim().toLowerCase() ==
            rack.trim().toLowerCase()) {
          total += (r['qty'] as num?)?.toDouble() ?? 0.0;
        }
      }
      rackBalance.value = total;
    } catch (_) {
      rackBalance.value = 0.0;
    }
  }

  // ── Batch validation ──────────────────────────────────────────────────────
  Future<void> validateBatch(String batch) async {
    final trimmed = batch.trim();
    if (trimmed.isEmpty) { resetBatch(); validateSheet(); return; }

    isValidatingBatch.value = true;
    batchError.value        = '';
    isBatchValid.value      = false;

    try {
      final rows = await ApiProvider().getList(
        'Batch',
        filters: {'name': trimmed, 'item': itemCode.value},
        fields: ['name', 'expiry_date', 'manufacturing_date'],
      );

      if (rows.isEmpty) {
        batchError.value = 'Batch not found for this item.';
        validateSheet();
        return;
      }

      final row        = rows.first;
      final expiryRaw  = row['expiry_date']        as String?;
      final mfgRaw     = row['manufacturing_date'] as String?;
      final parts      = <String>[];
      if (mfgRaw    != null && mfgRaw.isNotEmpty)    parts.add('Mfg: $mfgRaw');
      if (expiryRaw != null && expiryRaw.isNotEmpty) parts.add('Exp: $expiryRaw');
      batchInfoTooltip.value = parts.isEmpty ? null : parts.join('  ·  ');

      isBatchValid.value    = true;
      isBatchReadOnly.value = true;
      await fetchBatchBalance();
      validateSheet();
    } catch (e) {
      batchError.value = 'Batch validation error: $e';
      validateSheet();
    } finally {
      isValidatingBatch.value = false;
    }
  }

  void validateBatchOnInit(String batch) {
    unawaited(validateBatch(batch));
  }

  // ── Rack validation ───────────────────────────────────────────────────────
  Future<void> validateRack(String rack) async {
    final trimmed = rack.trim();
    if (trimmed.isEmpty) { resetRack(); validateSheet(); return; }

    isValidatingRack.value = true;
    rackError.value        = '';
    isRackValid.value      = false;

    try {
      await fetchRackBalance(trimmed);
      isRackValid.value = true;
      validateSheet();
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
      validateSheet();
    } finally {
      isValidatingRack.value = false;
    }
  }

  // ── Batch picker ──────────────────────────────────────────────────────────
  // Updated to use the new showBatchPickerSheet() helper (BatchPickerSheet
  // constructor no longer accepts `history:` / `isLoading:` / `onSelected:`).
  Future<void> openBatchPicker() async {
    final ctx = sheetContext ?? Get.context;
    if (ctx == null) return;
    final selected = await showBatchPickerSheet(
      ctx,
      itemCode:    itemCode.value,
      warehouse:   resolvedWarehouse,
      accentColor: accentColor,
    );
    if (selected != null && selected.isNotEmpty) {
      batchController.text = selected;
      await validateBatch(selected);
    }
  }

  // ── itemCode / itemName convenience ──────────────────────────────────────
  final RxString itemCode = ''.obs;
  final RxString itemName = ''.obs;
}
