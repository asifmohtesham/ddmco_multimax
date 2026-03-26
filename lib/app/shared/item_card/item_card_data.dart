import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';

/// Canonical, immutable data contract for a single line-item card
/// across all five DocTypes (PO, PR, SE, DN, PS).
///
/// Field-test decisions (C11):
///   • Rate, Amount     — suppressed globally (null in all factories)
///   • Warehouse fields — suppressed globally (null in all factories)
///   • Variant Of       — now mapped in all five factories
///
/// The fields themselves are retained in the model for potential future
/// re-use; they are simply not populated by any factory at this time.
class ItemCardData {
  // ── Identity ──────────────────────────────────────────────────────────────

  final String? rowName;
  final int?    index;

  // ── Core item fields ───────────────────────────────────────────────────────

  final String  itemCode;
  final String? itemName;

  /// custom_variant_of — shown as an identity chip beneath the item name.
  /// Now mapped across ALL DocTypes (C11).
  final String? variantOf;

  // ── Quantity ───────────────────────────────────────────────────────────────

  final double  qty;
  final String? uom;

  /// Drives the DocItemProgressBar:
  ///   PO → receivedQty, PR → purchaseOrderQty, SE/DN/PS → null
  final double? targetQty;

  // ── Pricing (retained in model; suppressed in all factories — C11) ─────────

  final double? rate;
  final double? amount;

  // ── Warehouse / Location (retained; suppressed in all factories — C11) ─────

  final String? warehouse;
  final String? toWarehouse;

  // ── Batch / Rack ───────────────────────────────────────────────────────────

  final String? batchNo;
  final String? rack;
  final String? toRack;

  // ── Label hints ────────────────────────────────────────────────────────────

  final String? qtyLabel;
  final String? rateLabel;       // null in all factories (C11)
  final String? warehouseLabel;  // null in all factories (C11)

  // ── Behaviour flags ────────────────────────────────────────────────────────

  final bool isEditable;
  final bool isHighlighted;

  // ── Constructor ───────────────────────────────────────────────────────────

  const ItemCardData({
    this.rowName,
    this.index,
    required this.itemCode,
    this.itemName,
    this.variantOf,
    required this.qty,
    this.uom,
    this.targetQty,
    this.rate,
    this.amount,
    this.warehouse,
    this.toWarehouse,
    this.batchNo,
    this.rack,
    this.toRack,
    this.qtyLabel,
    this.rateLabel,
    this.warehouseLabel,
    required this.isEditable,
    this.isHighlighted = false,
  });

  // ── copyWith helpers ───────────────────────────────────────────────────────

  /// Returns a copy with [targetQty] replaced.
  /// Used by MrItemsView to inject row.requestedQty after factory construction.
  ItemCardData copyWithTargetQty(double? targetQty) {
    return ItemCardData(
      rowName:        rowName,
      index:          index,
      itemCode:       itemCode,
      itemName:       itemName,
      variantOf:      variantOf,
      qty:            qty,
      uom:            uom,
      targetQty:      targetQty,
      rate:           rate,
      amount:         amount,
      warehouse:      warehouse,
      toWarehouse:    toWarehouse,
      batchNo:        batchNo,
      rack:           rack,
      toRack:         toRack,
      qtyLabel:       qtyLabel,
      rateLabel:      rateLabel,
      warehouseLabel: warehouseLabel,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  // ── Named factory constructors ─────────────────────────────────────────────

  /// Maps a [PurchaseOrderItem] to [ItemCardData].
  ///
  /// C11: rate, amount suppressed (null).
  /// variantOf now mapped.
  factory ItemCardData.fromPurchaseOrderItem(
    PurchaseOrderItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:       item.name,
      index:         index,
      itemCode:      item.itemCode,
      itemName:      item.itemName.isNotEmpty ? item.itemName : null,
      variantOf:     item.customVariantOf,
      qty:           item.qty,
      uom:           item.uom,
      targetQty:     item.receivedQty,
      // rate / amount suppressed — C11 field-test decision
      rate:          null,
      amount:        null,
      // warehouse suppressed — C11 field-test decision
      warehouse:      null,
      toWarehouse:    null,
      qtyLabel:       'Qty',
      rateLabel:      null,
      warehouseLabel: null,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [PurchaseReceiptItem] to [ItemCardData].
  ///
  /// C11: rate, amount, warehouse, warehouseLabel suppressed (null).
  factory ItemCardData.fromPurchaseReceiptItem(
    PurchaseReceiptItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:       item.name,
      index:         index,
      itemCode:      item.itemCode,
      itemName:      item.itemName,
      variantOf:     item.customVariantOf,
      qty:           item.qty,
      uom:           item.uom,
      targetQty:     item.purchaseOrderQty,
      // rate / amount suppressed — C11
      rate:          null,
      amount:        null,
      // warehouse suppressed — C11
      warehouse:      null,
      toWarehouse:    null,
      batchNo:        item.batchNo,
      rack:           item.rack,
      qtyLabel:       'Accepted Qty',
      rateLabel:      null,
      warehouseLabel: null,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [StockEntryItem] to [ItemCardData].
  ///
  /// C11: basicRate, sWarehouse, tWarehouse, warehouseLabel suppressed (null).
  /// For Material Request entries call [copyWithTargetQty] afterwards.
  factory ItemCardData.fromStockEntryItem(
    StockEntryItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:       item.name,
      index:         index,
      itemCode:      item.itemCode,
      itemName:      item.itemName,
      variantOf:     item.customVariantOf,
      qty:           item.qty,
      // rate / warehouse suppressed — C11
      rate:          null,
      amount:        null,
      warehouse:      null,
      toWarehouse:    null,
      batchNo:        item.batchNo,
      rack:           item.rack,
      toRack:         item.toRack,
      qtyLabel:       'Qty',
      rateLabel:      null,
      warehouseLabel: null,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [DeliveryNoteItem] to [ItemCardData].
  ///
  /// C11: rate, amount, warehouse, warehouseLabel suppressed (null).
  factory ItemCardData.fromDeliveryNoteItem(
    DeliveryNoteItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:       item.name,
      index:         index,
      itemCode:      item.itemCode,
      itemName:      item.itemName,
      variantOf:     item.customVariantOf,
      qty:           item.qty,
      // rate / amount suppressed — C11
      rate:          null,
      amount:        null,
      // warehouse suppressed — C11
      warehouse:      null,
      toWarehouse:    null,
      batchNo:        item.batchNo,
      rack:           item.rack,
      qtyLabel:       'Qty',
      rateLabel:      null,
      warehouseLabel: null,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [PackingSlipItem] to [ItemCardData].
  ///
  /// Packing Slip Item is a logistics document with no pricing or
  /// warehouse fields in the ERPNext schema.
  /// C11: variantOf now mapped.
  factory ItemCardData.fromPackingSlipItem(
    PackingSlipItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:        item.name,
      index:          index,
      itemCode:       item.itemCode,
      itemName:       item.itemName,
      variantOf:      item.customVariantOf,
      qty:            item.qty,
      uom:            item.uom,
      qtyLabel:       'Qty',
      rateLabel:      null,
      warehouseLabel: null,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }
}
