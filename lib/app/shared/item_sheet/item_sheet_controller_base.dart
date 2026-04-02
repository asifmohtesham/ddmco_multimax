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
///   window: keyboard show → LayoutBuilder rebuild → _AnimatedState
///   re-subscribed to an already-disposed TEC, producing the
///   "TextEditingController used after being disposed" assertion.
///   Synchronous disposal is safe because GetX only calls onClose() after
///   the owning widget has left the tree.
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
  var maxQty            = 0.0.obs;
  var batchError        = RxnString();
  var rackError         = RxnString();
  var batchInfoTooltip  = RxnString();
  var rackStockTooltip  = RxnString();
  var rackStockMap      = <String, double>{}.obs;

  // ── Ceiling for POS / serial-cap display (C-5) ───────────────────────
  //
  // Concrete RxDouble so any Obx in the widget tree can subscribe to it
  // without duck-typing.  Default 0.0 (no ceiling known).
  // StockEntryItemFormController writes to this whenever its ceiling
  // recomputes; all other DocType controllers leave it at 0.0.
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

  // ── Qty label (abstract — DocType provides the string) ────────────────
  //
  // qtyInfoText   : short badge label, e.g. 'Max: 3'.
  // qtyInfoTooltip: breakdown shown on badge tap; null → no tap target.
  String? get qtyInfoText;
  String? get qtyInfoTooltip => null;

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
  //
  // Fix TEC-1: listeners are removed first, then TECs are disposed
  // synchronously — no addPostFrameCallback deferral.
  //
  // Rationale: GetX invokes onClose() only after the widget that owns this
  // controller has been unmounted.  At that point no mounted widget holds a
  // reference to any of these TECs, so immediate disposal is safe and
  // eliminates the one-frame race that caused _AnimatedState to
  // re-subscribe to a disposed TEC when the keyboard appeared.
  @override
  void onClose() {
    qtyController.removeListener(validateSheet);
    qtyController.removeListener(_resetSaveStateOnEdit);
    batchController.removeListener(validateSheet);
    batchController.removeListener(_resetSaveStateOnEdit);
    rackController.removeListener(validateSheet);
    rackController.removeListener(_resetSaveStateOnEdit);

    qtyController.dispose();
    batchController.dispose();
    rackController.dispose();
    rackFocusNode.dispose();
    sheetScrollController.dispose();
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
    if (maxQty.value > 0 && next > maxQty.value) next = maxQty.value;
    qtyController.text =
        next % 1 == 0 ? next.toInt().toString() : next.toString();
    validateSheet();
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

      maxQty.value          = fetchedQty;
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
      maxQty.value           = 0.0;
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
    validateSheet();
  }

  // ── Rack validation ───────────────────────────────────────────────────
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
