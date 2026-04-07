// item_sheet_controller_base.dart
//
// Base class for all item-form sheet controllers (SE, PR, DN).
//
// Commit 2 addition:
//   • sheetContext — nullable BuildContext written by UniversalItemFormSheet
//     when the DraggableScrollableSheet builder fires.  Provides a scoped,
//     reliable context for popping the sheet from controller code.
//   • closeSheet() — preferred sheet-dismiss helper.  Uses
//     Navigator.of(sheetContext) when available; falls back to Get.back()
//     so existing call-sites remain safe even before the context is wired.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/rack_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/qty_field_with_plus_minus_delegate.dart';

/// Lifecycle rules for TextEditingControllers owned by this class.
/// See tec_lifecycle_rules.dart for the full contract.
library;

abstract class ItemSheetControllerBase extends GetxController
    implements RackFieldWithBrowseDelegate, QtyFieldWithPlusMinusDelegate {

  // ── Commit 2: sheet BuildContext ─────────────────────────────────────────
  /// The [BuildContext] captured from the [DraggableScrollableSheet] builder
  /// inside [UniversalItemFormSheet].  Set by the sheet widget immediately
  /// before it renders its children so controller code can use a scoped,
  /// valid context to pop the sheet.
  ///
  /// Null until the sheet is presented and the builder fires.
  BuildContext? sheetContext;

  /// Pops the item-form sheet using the most reliable available mechanism.
  ///
  /// Preference order:
  ///   1. [Navigator.of(sheetContext)] — scoped to the sheet's own route.
  ///   2. [Get.back()] — global fallback when [sheetContext] is null or
  ///      the navigator is no longer mounted.
  void closeSheet() {
    final ctx = sheetContext;
    if (ctx != null && ctx.mounted) {
      try {
        Navigator.of(ctx).pop();
        return;
      } catch (_) {
        // Context became stale between the null-check and the pop call;
        // fall through to Get.back().
      }
    }
    if (Get.isBottomSheetOpen == true) Get.back();
  }

  // ── Abstract API ─────────────────────────────────────────────────────────
  bool  get requiresBatch;
  bool  get requiresRack;
  Color get accentColor;
  bool  get isAddMode;
  MobileScannerController? get sheetScanController;

  // ── Abstract overrides (RackFieldWithBrowseDelegate) ─────────────────────
  @override bool get canBrowseRacks => false;
  @override Future<RackPickerResult?> browseRacks() async => null;
  @override Future<void> handleRackPicked(RackPickerResult result) async {
    rackController.text = result.rackId;
    await validateRack(result.rackId);
  }

  // ── Abstract overrides (QtyFieldWithPlusMinusDelegate) ───────────────────
  @override double get effectiveMaxQty => double.infinity;
  @override double get maxQty => 0.0;
  @override String? get qtyInfoText => null;
  @override RxnString get qtyInfoTooltip => RxnString(null);
  @override void adjustQty(int delta) {}

  // ── Core TECs (Rule 1 — disposed via addPostFrameCallback) ───────────────
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();
  final TextEditingController qtyController   = TextEditingController();

  // ── Reactive sheet state ─────────────────────────────────────────────────
  final RxBool   isSheetValid      = false.obs;
  final RxBool   saveButtonVisible = false.obs;
  final RxnString editingItemName  = RxnString(null);
  final RxInt    docStatus         = 0.obs;

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

  bool get isDirty =>
      batchController.text != _snapshotBatch ||
      rackController.text  != _snapshotRack  ||
      qtyController.text   != _snapshotQty;

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    // Lock qty field when the parent document is submitted.
    ever(docStatus, (int status) {
      isQtyReadOnly.value = status == 1;
    });
  }

  @override
  void onClose() {
    removeSheetListeners();
    // Rule 1: defer TEC disposal past the exit-animation frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      disposeControllers();
    });
    // Clear the context reference so it cannot be used after close.
    sheetContext = null;
    super.onClose();
  }

  /// Disposes all TECs owned by this base class.
  /// Subclasses override to additionally dispose their own TECs,
  /// then call super.
  void disposeControllers() {
    try { batchController.dispose(); } catch (_) {}
    try { rackController.dispose();  } catch (_) {}
    try { qtyController.dispose();   } catch (_) {}
  }

  // ── Sheet listener wiring ────────────────────────────────────────────────
  void addSheetListeners() {
    batchController.addListener(validateSheet);
    rackController.addListener(validateSheet);
    qtyController.addListener(validateSheet);
    qtyController.addListener(_resetSaveStateOnEdit);
  }

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

  // ── Sheet validity (subclass overrides) ──────────────────────────────────
  void validateSheet() {
    final qty = double.tryParse(qtyController.text);
    isSheetValid.value = (qty != null && qty > 0) &&
        (!requiresBatch || isBatchValid.value) &&
        (!requiresRack  || isRackValid.value);
  }

  // ── Submit (subclass implements) ─────────────────────────────────────────
  Future<void> submit() async {}

  // ── Delete (subclass implements) ─────────────────────────────────────────
  void deleteCurrentItem() {}

  // ── Batch helpers ────────────────────────────────────────────────────────
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

  // ── Batch validation (base; subclasses may override) ─────────────────────
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

  // ── Rack validation (base; subclasses may override) ──────────────────────
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

  // ── Batch picker ─────────────────────────────────────────────────────────
  Future<void> openBatchPicker() async {
    final ctx = sheetContext ?? Get.context;
    if (ctx == null) return;
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BatchPickerSheet(
        history:     batchWiseHistory,
        isLoading:   isLoadingBatchHistory,
        onSelected:  (batch) {
          batchController.text = batch;
          validateBatch(batch);
        },
      ),
    );
  }

  // ── itemCode convenience ─────────────────────────────────────────────────
  /// Subclasses expose their item code as [itemCode].  The base provides
  /// a concrete default backed by a local RxString so helpers like
  /// fetchBatchBalance() work without any subclass plumbing.
  final RxString itemCode = ''.obs;
  final RxString itemName = ''.obs;
}
