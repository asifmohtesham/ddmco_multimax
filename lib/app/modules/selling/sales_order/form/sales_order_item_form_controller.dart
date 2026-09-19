import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'sales_order_form_controller.dart';

/// Item-level sheet controller for Sales Order.
///
/// Mirrors [PurchaseOrderItemFormController]: no batch/rack, no stock qty
/// cap. SO-specific: the row's rate/UOM/conversion-factor/warehouse are
/// primed from the server (`get_item_details`) rather than typed cold, and
/// `validateRow` (the pure v15-rule logic) gates save instead of an ad-hoc
/// qty/date check.
class SalesOrderItemFormController extends ItemSheetControllerBase {
  late SalesOrderFormController _parent;
  SalesOrderItem? _snapshot; // the row being edited; null in add mode

  // ── SO-specific field controllers ───────────────────────────────────────
  final rateController = TextEditingController();
  final deliveryDateController = TextEditingController();

  // ── SO-specific Rx ───────────────────────────────────────────────────────
  final uom = RxnString();
  final warehouse = RxnString();
  final priceListRate = 0.0.obs;
  final conversionFactor = 1.0.obs;
  final sheetRate = 0.0.obs;
  // Mirrors qtyController.text as an Rx so the Estimated Amount tile's Obx
  // (which only reads Rx values) repaints on every qty keystroke, not just
  // rate changes — see F6.
  final sheetQty = 0.0.obs;
  final isFetchingDetails = false.obs;
  final detailsError = RxnString();
  final rowErrors = <String, String>{}.obs; // from validateRow; field errors

  double get sheetAmount => sheetQty.value * sheetRate.value; // estimate only

  // ── ItemSheetControllerBase abstract overrides ──────────────────────────

  @override
  String? get resolvedWarehouse => warehouse.value;

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  @override
  Color get accentColor => AppColors.green500;

  @override
  bool get isAddMode => editingItemName.value == null;

  /// SO has no stock context; no qty-info label needed.
  @override
  String get qtyInfoText => '';

  @override
  RxnString get qtyInfoTooltip => RxnString(null);

  /// ±1 stepper, unbounded ceiling (an order line isn't capped by stock).
  @override
  void adjustQty(int delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final next = (current + delta).clamp(0.0, double.infinity);
    qtyController.text = next.truncateToDouble() == next
        ? next.toInt().toString()
        : next.toStringAsFixed(2);
    validateSheet();
  }

  // ── Listener helpers ─────────────────────────────────────────────────────
  void _addListeners() {
    rateController.addListener(_onRateChanged);
    deliveryDateController.addListener(validateSheet);
    qtyController.addListener(_onQtyChanged);
  }

  void _removeListeners() {
    rateController.removeListener(_onRateChanged);
    deliveryDateController.removeListener(validateSheet);
    qtyController.removeListener(_onQtyChanged);
  }

  void _onRateChanged() {
    sheetRate.value = double.tryParse(rateController.text) ?? 0.0;
    validateSheet();
  }

  // qtyController's other listener (validateSheet, wired by the base class's
  // addSheetListeners) already re-validates on every keystroke; this only
  // needs to keep sheetQty in sync for the Estimated Amount tile.
  void _onQtyChanged() {
    sheetQty.value = double.tryParse(qtyController.text) ?? 0.0;
  }

  String _fmtQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void onClose() {
    _removeListeners();
    final rtc = rateController;
    final ddc = deliveryDateController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rtc.dispose();
      ddc.dispose();
    });
    super.onClose();
  }

  // ── Initialise ───────────────────────────────────────────────────────────

  Future<void> initialise({
    required SalesOrderFormController parent,
    SalesOrderItem? row,
    String? itemCode,
  }) async {
    _parent = parent;
    final so = parent.so.value!;
    editingItemName.value = row?.name;
    this.itemCode.value = row?.itemCode ?? itemCode ?? '';
    itemName.value = row?.itemName ?? '';
    qtyController.text = _fmtQty(row?.qty ?? 1);
    sheetQty.value = row?.qty ?? 1;
    rateController.text = (row?.rate ?? 0).toStringAsFixed(2);
    sheetRate.value = row?.rate ?? 0;
    priceListRate.value = row?.priceListRate ?? 0;
    conversionFactor.value = row?.conversionFactor ?? 1;
    uom.value = row?.uom;
    warehouse.value = row?.warehouse ?? so.setWarehouse;
    // New rows inherit the header delivery date (desk behaviour).
    deliveryDateController.text = row?.deliveryDate ?? so.deliveryDate ?? '';
    _snapshot = row;
    initBaseListeners();
    _addListeners();
    captureSnapshot();
    if (row == null) await _loadDetails();
    // The sheet may have been dismissed (Get.delete → onClose) while the
    // get_item_details request above was in flight — see _loadDetails.
    if (isClosed) return;
    validateSheet();
  }

  /// get_item_details: server price-list rate, UOM, conversion, default wh.
  /// ponytail: conversion_rate/plc_conversion_rate sent as 1 (all live docs
  /// are AED in AED); pass real exchange rates if a foreign-currency price
  /// list is ever used.
  ///
  /// `openItemSheet` fires this via `unawaited(ctrl.initialise(...))`, so the
  /// user can dismiss the sheet before the network call returns. `Get.delete`
  /// disposes `rateController`/`deliveryDateController` on the next frame via
  /// `onClose`, so every write below is guarded by `isClosed` — matching the
  /// same guard already used around awaited fetches in
  /// StockEntryItemFormController.resolveRackWarehouse and
  /// DeliveryNoteItemFormController.
  Future<void> _loadDetails() async {
    final so = _parent.so.value!;
    isFetchingDetails.value = true;
    detailsError.value = null;
    try {
      final d = await Get.find<SalesOrderProvider>().getItemDetails({
        'item_code': itemCode.value,
        'doctype': 'Sales Order',
        'company': so.company,
        'customer': so.customer,
        'selling_price_list': so.sellingPriceList,
        'currency': so.currency,
        'price_list_currency': so.currency,
        'conversion_rate': 1,
        'plc_conversion_rate': 1,
        'transaction_date': so.transactionDate,
        'qty': double.tryParse(qtyController.text) ?? 1,
        'uom': uom.value,
        'warehouse': warehouse.value,
        'order_type': so.orderType,
      });
      if (isClosed) return;
      if (itemName.value.isEmpty) itemName.value = d.itemName;
      uom.value = d.uom ?? d.stockUom;
      conversionFactor.value = d.conversionFactor;
      priceListRate.value = d.priceListRate;
      warehouse.value ??= d.warehouse;
      rateController.text = d.rate.toStringAsFixed(2); // listener updates sheetRate
    } catch (e) {
      if (isClosed) return;
      // Fail open to manual entry; the server re-prices/validates on save.
      detailsError.value =
          'Could not load the price list rate. Enter the rate manually.';
    } finally {
      if (!isClosed) isFetchingDetails.value = false;
    }
  }

  SalesOrderItem _current() {
    final base = _snapshot ??
        SalesOrderItem(
          name: 'local_${DateTime.now().millisecondsSinceEpoch}',
          itemCode: itemCode.value,
          itemName: itemName.value,
          qty: 0,
        );
    return base.copyWith(
      qty: double.tryParse(qtyController.text) ?? 0,
      rate: double.tryParse(rateController.text) ?? 0,
      uom: uom.value,
      conversionFactor: conversionFactor.value,
      priceListRate: priceListRate.value,
      deliveryDate: deliveryDateController.text,
      warehouse: warehouse.value ?? '',
    );
  }

  @override
  void validateSheet() {
    if (!_parent.isEditable) {
      isSheetValid.value = false;
      return;
    }
    final row = _current();
    rowErrors.assignAll(validateRow(row, _parent.so.value!.transactionDate));
    final rateOk = (double.tryParse(rateController.text) ?? -1) >= 0;
    final changed = isAddMode ||
        _snapshot == null ||
        row.qty != _snapshot!.qty ||
        row.rate != _snapshot!.rate ||
        (row.deliveryDate ?? '') != (_snapshot!.deliveryDate ?? '') ||
        (row.warehouse ?? '') != (_snapshot!.warehouse ?? '');
    isSheetValid.value = rowErrors.isEmpty && rateOk && changed;
  }

  // ── deleteCurrentItem ────────────────────────────────────────────────────

  @override
  Future<void> deleteCurrentItem() async {
    if (editingItemName.value == null) return;
    final item = _parent.so.value?.items
        .firstWhereOrNull((i) => i.name == editingItemName.value);
    if (item == null) return;
    _parent.deleteItem(item);
  }

  // ── submit ───────────────────────────────────────────────────────────────

  @override
  Future<void> submit() async {
    validateSheet();
    if (!isSheetValid.value) return; // sheet stays open with errors
    final row = _current();
    final applied = isAddMode ? _parent.addItem(row) : _parent.updateItem(row);
    if (applied) Get.back();
  }
}
