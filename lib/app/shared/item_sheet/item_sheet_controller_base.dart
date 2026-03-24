import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Abstract base controller for every item-row bottom-sheet in the app.
///
/// Concrete subclasses live alongside their parent form controller:
///   delivery_note/form/controllers/delivery_note_item_form_controller.dart
///   purchase_receipt/form/controllers/purchase_receipt_item_form_controller.dart
///   purchase_order/form/controllers/purchase_order_item_form_controller.dart
///   stock_entry/form/controllers/stock_entry_item_form_controller.dart  (already exists)
///
/// SOLID compliance:
///   S – this class owns sheet-row state only; parent owns document CRUD.
///   O – new DocTypes extend this without modifying it.
///   L – every concrete subclass can be used anywhere the base is expected.
///   I – optional behaviour (POS serial, auto-fill rack) is in separate mixins.
///   D – depends on ApiProvider abstraction, not concrete HTTP calls.
abstract class ItemSheetControllerBase extends GetxController {
  // ─── Infrastructure ────────────────────────────────────────────────────────
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ─── Form ──────────────────────────────────────────────────────────────────
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  /// Wrapped in Rx so that QuantityInputWidget's Obx always binds the
  /// live instance. If GetX disposes and recreates this controller mid-rebuild,
  /// the Rx emits, Obx re-runs, and TextFormField receives the new TEC
  /// instead of calling addListener on the already-disposed one.
  final qtyController   = TextEditingController().obs;
  final TextEditingController batchController = TextEditingController();
  final TextEditingController rackController  = TextEditingController();

  /// Dedicated FocusNode for the rack field.
  /// Always request focus via [requestRackFocus] — never call
  /// rackFocusNode.requestFocus() directly, as it may fire during a build.
  final FocusNode rackFocusNode = FocusNode();

  // ─── Item identity ─────────────────────────────────────────────────────────
  var itemCode = ''.obs;
  var itemName = ''.obs;

  // ─── Metadata (displayed by GlobalItemFormSheet) ───────────────────────────
  var itemOwner      = RxnString();
  var itemCreation   = RxnString();
  var itemModified   = RxnString();
  var itemModifiedBy = RxnString();

  // ─── Validation state ──────────────────────────────────────────────────────
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

  // ─── Stock availability per rack ───────────────────────────────────────────
  var rackStockMap     = <String, double>{}.obs;
  var rackStockTooltip = RxnString();

  // ───────────────────────────────────────────────────────────────────────────
  // Abstract interface — every concrete subclass must implement these.
  // ───────────────────────────────────────────────────────────────────────────

  /// The warehouse to use for stock / batch queries.
  /// Typically provided by the parent controller (setWarehouse, fromWarehouse).
  String? get resolvedWarehouse;

  /// Whether a non-empty batch value is mandatory for this DocType.
  bool get requiresBatch;

  /// Whether a non-empty rack value is mandatory for this DocType.
  bool get requiresRack;

  /// DocType-specific validation layer.
  /// Implementations MUST call [baseValidate] and layer their own rules:
  /// ```dart
  /// @override
  /// void validateSheet() {
  ///   bool ok = baseValidate();
  ///   ok = ok && myCustomCheck();
  ///   isSheetValid.value = ok;
  /// }
  /// ```
  void validateSheet();

  /// Commit the current sheet values to the parent controller and
  /// (optionally) trigger a document save.  Called by the Save button.
  Future<void> submit({bool closeSheet = true});

  // ───────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ───────────────────────────────────────────────────────────────────────────

  @override
  void onClose() {
    qtyController.value.dispose(); // dispose the inner TEC; Rx is handled by GetX
    batchController.dispose();
    rackController.dispose();
    rackFocusNode.dispose();
    super.onClose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared concrete logic
  // ───────────────────────────────────────────────────────────────────────────

  /// Base validation rules shared by every DocType.
  /// Returns true when the core fields are in a valid state.
  bool baseValidate() {
    final qty = double.tryParse(qtyController.value.text) ?? 0;
    if (qty <= 0) return false;
    if (maxQty.value > 0 && qty > maxQty.value) return false;
    if (requiresBatch && batchController.text.isEmpty) return false;
    if (batchController.text.isNotEmpty && !isBatchValid.value) return false;
    if (requiresRack   && rackController.text.isEmpty)  return false;
    if (rackController.text.isNotEmpty  && !isRackValid.value)  return false;
    return true;
  }

  /// Adjusts qty by [delta], clamped to [0, maxQty].
  void adjustQty(double delta) {
    double current = double.tryParse(qtyController.value.text) ?? 0;
    double next    = current + delta;
    if (next < 0) next = 0;
    if (maxQty.value > 0 && next > maxQty.value) next = maxQty.value;
    qtyController.value.text = next % 1 == 0 ? next.toInt().toString() : next.toString();
    validateSheet();
  }

  /// Safe post-frame focus request — never triggers during a widget build.
  /// Replaces all direct rackFocusNode.requestFocus() call-sites.
  void requestRackFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rackFocusNode.canRequestFocus) rackFocusNode.requestFocus();
    });
  }

  /// Resets batch validation state and re-validates the sheet.
  void resetBatch() {
    isBatchValid.value     = false;
    batchError.value       = null;
    batchInfoTooltip.value = null;
    validateSheet();
  }

  /// Resets rack validation state and re-validates the sheet.
  void resetRack() {
    isRackValid.value = false;
    rackError.value   = null;
    validateSheet();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Batch validation
  // ───────────────────────────────────────────────────────────────────────────

  /// Validates [batchNo] via Batch-Wise Balance History.
  ///
  /// On success: sets [isBatchValid], updates [maxQty], and calls
  /// [requestRackFocus] so focus moves to the rack field automatically.
  /// On failure: sets [batchError].
  ///
  /// Override in subclasses that need different validation logic
  /// (e.g. Stock Entry bundle flow).
  Future<void> validateBatch(String batchNo) async {
    if (batchNo.isEmpty) return;

    isValidatingBatch.value = true;
    batchError.value        = null;
    batchInfoTooltip.value  = null;

    try {
      // 1. Verify batch exists for this item.
      final batchResponse = await _apiProvider.getDocumentList(
        'Batch',
        filters: {'name': batchNo, 'item': itemCode.value},
        fields: ['name', 'custom_packaging_qty'],
      );

      final batchList = batchResponse.data['data'] as List? ?? [];
      if (batchList.isEmpty) throw Exception('Batch not found');

      final batchData = batchList.first as Map<String, dynamic>;
      final double pkgQty =
          (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
      if (pkgQty > 0) {
        qtyController.value.text =
            pkgQty % 1 == 0 ? pkgQty.toInt().toString() : pkgQty.toString();
      }

      // 2. Fetch balance history to get available stock.
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final balanceResponse = await _apiProvider.getBatchWiseBalance(
        itemCode:  itemCode.value,
        batchNo:   batchNo,
        warehouse: resolvedWarehouse,
        fromDate:  today,
        toDate:    today,
      );

      double batchQty = 0.0;
      if (balanceResponse.statusCode == 200 &&
          balanceResponse.data['message'] != null) {
        final result = balanceResponse.data['message']['result'];
        if (result is List && result.isNotEmpty) {
          batchQty = (result.first['balance_qty'] as num?)?.toDouble() ?? 0.0;
        }
      }

      if (batchQty > 0) {
        maxQty.value       = batchQty;
        isBatchValid.value = true;
        batchInfoTooltip.value = 'Batch stock: $batchQty';
        requestRackFocus(); // Safe post-frame
      } else {
        isBatchValid.value = false;
        batchError.value   = 'Batch has no available stock';
        GlobalSnackbar.error(message: 'Batch has 0 stock');
      }
    } catch (e) {
      isBatchValid.value = false;
      batchError.value   = 'Invalid Batch';
      maxQty.value       = 0.0;
      GlobalSnackbar.error(message: 'Batch validation failed');
      log('[ItemSheet:validateBatch] error: $e');
    } finally {
      isValidatingBatch.value = false;
      validateSheet();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Rack validation
  // ───────────────────────────────────────────────────────────────────────────

  /// Validates [rack] via the Rack doctype API.
  ///
  /// On success: sets [isRackValid] and refreshes rack stock map.
  /// On failure: sets [rackError].
  ///
  /// Subclasses may override to apply additional warehouse derivation
  /// (e.g. the DN "ZONE-WH-RACK" parse rule).
  Future<void> validateRack(String rack) async {
    if (rack.isEmpty) {
      resetRack();
      return;
    }

    isValidatingRack.value = true;
    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        isRackValid.value = true;
        await fetchRackStocks();
      } else {
        isRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      isRackValid.value = false;
      GlobalSnackbar.error(message: 'Rack validation failed: $e');
      log('[ItemSheet:validateRack] error: $e');
    } finally {
      isValidatingRack.value = false;
      validateSheet();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Rack stock map
  // ───────────────────────────────────────────────────────────────────────────

  /// Fetches all rack stock for the current item + [resolvedWarehouse].
  /// Populates [rackStockMap] and [rackStockTooltip].
  Future<void> fetchRackStocks() async {
    final wh = resolvedWarehouse;
    if (wh == null || wh.isEmpty) return;

    try {
      final response = await _apiProvider.getStockBalance(
        itemCode:  itemCode.value,
        warehouse: wh,
        batchNo: batchController.text.isNotEmpty ? batchController.text : null,
      );

      if (response.statusCode == 200 && response.data['message'] != null) {
        final result = response.data['message']['result'];
        if (result is List && result.isNotEmpty) {
          final Map<String, double> tempMap = {};
          final List<String> tooltipLines  = [];

          // Last row is the totals row — skip it.
          for (int i = 0; i < result.length - 1; i++) {
            final row = result[i];
            final String? r = row['rack'];
            final double qty =
                (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
            if (r != null && r.isNotEmpty && qty > 0) {
              tempMap[r] = qty;
              tooltipLines.add('$r: $qty');
            }
          }

          rackStockMap.assignAll(tempMap);
          rackStockTooltip.value = tooltipLines.isNotEmpty
              ? tooltipLines.join('\n')
              : 'No stock in racks';

          onRackStocksLoaded(); // hook for AutoFillRackMixin
        }
      }
    } catch (e) {
      log('[ItemSheet:fetchRackStocks] error: $e');
    }
  }

  /// Called after [fetchRackStocks] completes.
  /// Overridden by [AutoFillRackMixin] to trigger auto-fill logic.
  void onRackStocksLoaded() {}

  // ───────────────────────────────────────────────────────────────────────────
  // Shared initialisation helpers
  // ───────────────────────────────────────────────────────────────────────────

  /// Loads metadata fields from individual strings.
  void loadMetadata({
    String? owner,
    String? creation,
    String? modified,
    String? modifiedBy,
  }) {
    itemOwner.value      = owner;
    itemCreation.value   = creation;
    itemModified.value   = modified;
    itemModifiedBy.value = modifiedBy;
  }

  /// Resets all sheet state to defaults.  Call at the start of every
  /// [initialise] implementation before populating with item data.
  void resetSheetState() {
    itemCode.value = '';
    itemName.value = '';
    itemOwner.value = itemCreation.value =
        itemModified.value = itemModifiedBy.value = null;
    qtyController.value.text = '';
    batchController.text = '';
    rackController.text  = '';
    isBatchValid.value      = false;
    isRackValid.value       = false;
    isValidatingBatch.value = false;
    isValidatingRack.value  = false;
    isSheetValid.value      = false;
    isFormDirty.value       = false;
    maxQty.value            = 0.0;
    batchError.value        = null;
    rackError.value         = null;
    batchInfoTooltip.value  = null;
    rackStockTooltip.value  = null;
    rackStockMap.clear();
  }
}
