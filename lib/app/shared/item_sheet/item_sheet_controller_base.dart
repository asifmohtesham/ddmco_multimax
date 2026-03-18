import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Abstract base controller for every DocType item-sheet.
///
/// Owns all state that is identical across Stock Entry, Delivery Note,
/// Purchase Receipt, and Purchase Order item sheets:
///   • TextEditingControllers / FocusNode
///   • Batch & Rack validation (with post-frame-safe focus)
///   • Stock / rack map fetching
///   • Qty adjustment helpers
///   • Dirty-state & sheet-validity flags
///
/// Concrete subclasses only need to implement the four abstract members
/// and call [initialise] from their own [initialise] method.
abstract class ItemSheetControllerBase extends GetxController {
  // ── Dependencies ─────────────────────────────────────────────────────
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Form infrastructure ───────────────────────────────────────────────
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final ScrollController sheetScrollController = ScrollController();

  final TextEditingController qtyController   = TextEditingController();
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();
  final FocusNode rackFocusNode = FocusNode();

  // ── Core item identity ──────────────────────────────────────────────────
  var itemCode = ''.obs;
  var itemName = ''.obs;

  // ── Validation state ───────────────────────────────────────────────────
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

  // ── Item metadata (for GlobalItemFormSheet footer) ──────────────────────
  var itemOwner      = RxnString();
  var itemCreation   = RxnString();
  var itemModified   = RxnString();
  var itemModifiedBy = RxnString();

  // ── Editing context ──────────────────────────────────────────────────
  /// Non-null when editing an existing child-table row.
  var editingItemName = RxnString();

  // ── Snapshot for dirty-checking ──────────────────────────────────────────
  String _snapshotBatch = '';
  String _snapshotRack  = '';
  String _snapshotQty   = '';

  // ── Abstract interface ──────────────────────────────────────────────────

  /// The warehouse to use for stock/batch queries.
  /// Return null if not yet determined.
  String? get resolvedWarehouse;

  /// Whether this DocType requires a valid batch before saving.
  bool get requiresBatch;

  /// Whether this DocType requires a rack entry.
  bool get requiresRack;

  /// DocType-specific validation rules applied ON TOP of [_baseValidate].
  /// Implementations should call [_baseValidate] first, then add their checks.
  void validateSheet();

  /// Commits the current field values back to the parent document controller.
  Future<void> submit();

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void onClose() {
    qtyController.dispose();
    batchController.dispose();
    rackController.dispose();
    rackFocusNode.dispose();
    sheetScrollController.dispose();
    super.onClose();
  }

  // ── Shared initialisation helper ──────────────────────────────────────────

  /// Call from concrete [initialise] after fields are populated.
  /// Sets the dirty-check snapshot and registers field listeners.
  void initBaseListeners() {
    qtyController.addListener(validateSheet);
    batchController.addListener(validateSheet);
    rackController.addListener(validateSheet);
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

  // ── Qty helpers ──────────────────────────────────────────────────────────

  void adjustQty(double delta) {
    double current = double.tryParse(qtyController.text) ?? 0;
    double next    = current + delta;
    if (next < 0) next = 0;
    if (maxQty.value > 0 && next > maxQty.value) next = maxQty.value;
    qtyController.text = next % 1 == 0 ? next.toInt().toString() : next.toString();
    validateSheet();
  }

  // ── Batch validation ─────────────────────────────────────────────────────

  /// Validates [batch] against Batch-Wise Balance History.
  /// Sets [isBatchValid], [maxQty], [batchError], and focuses the rack field
  /// on success via a post-frame callback (prevents mid-rebuild focus crash).
  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;
    batchError.value        = null;
    batchInfoTooltip.value  = null;
    isValidatingBatch.value = true;

    try {
      // 1. Confirm batch exists for this item
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
      if (pkgQty > 0) {
        qtyController.text =
            pkgQty % 1 == 0 ? pkgQty.toInt().toString() : pkgQty.toString();
      }

      // 2. Fetch balance — positional args; ApiProvider builds its own dates
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

      // 3. Build tooltip
      final sb = StringBuffer('Batch Stock: $fetchedQty');
      if (rackStockTooltip.value != null) {
        sb.write('\n\nRack Availability:\n${rackStockTooltip.value}');
      }
      batchInfoTooltip.value = sb.toString().trim();

      if (fetchedQty > 0) {
        isBatchValid.value = true;
        batchError.value   = null;
        _focusRack(); // post-frame safe
      } else {
        isBatchValid.value = false;
        batchError.value   = 'Batch has no stock';
        GlobalSnackbar.error(message: 'Batch has 0 stock');
      }

      // 4. Refresh rack stocks after batch is known
      await fetchAllRackStocks();

    } catch (e) {
      isBatchValid.value = false;
      batchError.value   = 'Invalid Batch';
      maxQty.value       = 0.0;
      GlobalSnackbar.error(message: 'Batch validation failed');
      log('[ItemSheet] validateBatch error: $e', name: 'ItemSheet');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  void resetBatch() {
    isBatchValid.value = false;
    batchError.value   = null;
    validateSheet();
  }

  // ── Rack validation ──────────────────────────────────────────────────────

  /// Validates [rack] via the Rack doctype API.
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

  // ── Stock / rack-map fetching ───────────────────────────────────────────────

  /// Fetches per-rack stock availability for the current item + warehouse.
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
          final Map<String, double> tempMap = {};
          final List<String> tooltipLines = [];

          // Last row is the totals row — skip it
          for (int i = 0; i < result.length - 1; i++) {
            final row = result[i] as Map<String, dynamic>;
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

  // ── Base validation helper ──────────────────────────────────────────────────

  /// Returns true when all base rules pass.
  bool baseValidate() {
    rackError.value = null;

    final qty = double.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) return false;
    if (maxQty.value > 0 && qty > maxQty.value) return false;

    if (batchController.text.isNotEmpty && !isBatchValid.value) return false;
    if (rackController.text.isNotEmpty  && !isRackValid.value)  return false;

    // Rack-wise stock availability check
    final selectedRack = rackController.text;
    if (selectedRack.isNotEmpty && rackStockMap.isNotEmpty) {
      final available = rackStockMap[selectedRack] ?? 0.0;
      if (qty > available) {
        rackError.value = 'Only $available available in $selectedRack';
        return false;
      }
    }

    return true;
  }

  // ── Focus helpers ──────────────────────────────────────────────────────────

  void _focusRack() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rackFocusNode.canRequestFocus) {
        rackFocusNode.requestFocus();
      }
    });
  }
}
