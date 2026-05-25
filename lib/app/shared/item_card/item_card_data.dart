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
/// Declares which rack chips DocItemCard should render for this row.
///
/// The widget uses this enum — never raw null-checks — to decide layout.
enum RackDisplayMode {
  /// No rack chips shown (PO, PS, any DocType without rack tracking).
  none,

  /// Single chip labelled "Target Rack" — receipt flows (PR, SE Material Receipt).
  targetOnly,

  /// Single chip labelled "Source Rack" — issue / outgoing flows (SE Material Issue, DN).
  sourceOnly,

  /// Two chips "Source Rack → Target Rack" — transfer flows (SE Material Transfer).
  sourceAndTarget,
}

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

  /// Packed qty from packing slips (DN only). Drives a packed progress bar
  /// rendered immediately below the item headline in DocItemCard.
  final double? packedQty;

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

  final RackDisplayMode rackDisplayMode;

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
    this.packedQty,
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
    this.rackDisplayMode = RackDisplayMode.none,
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
      packedQty:      packedQty,
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
      rackDisplayMode: rackDisplayMode,
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
    // purchaseOrderQty is populated by the API on persisted docs.
    // For locally-added rows (new PR from PO), fall back to poQty which is
    // set by addItem() via the child controller's poQty field.
    final double? resolvedTargetQty =
    (item.purchaseOrderQty != null && item.purchaseOrderQty! > 0)
        ? item.purchaseOrderQty
        : (item.poQty != null && item.poQty! > 0)
        ? item.poQty
        : null;

    return ItemCardData(
      rowName:       item.name,
      index:         index,
      itemCode:      item.itemCode,
      itemName:      item.itemName,
      variantOf:     item.customVariantOf,
      qty:           item.qty,
      uom:           item.uom,
      targetQty:     resolvedTargetQty,
      // rate / amount suppressed — C11
      rate:          null,
      amount:        null,
      // warehouse suppressed — C11
      warehouse:      null,
      toWarehouse:    null,
      batchNo:        item.batchNo,
      rack:           item.rack,
      toRack:         null,
      rackDisplayMode: item.rack != null && item.rack!.isNotEmpty
          ? RackDisplayMode.targetOnly
          : RackDisplayMode.none,
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
    required String stockEntryType,
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    final RackDisplayMode mode = _rackModeForStockEntry(
      stockEntryType: stockEntryType,
      rack: item.rack,
      toRack: item.toRack,
    );

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
      rackDisplayMode: mode,
      qtyLabel:       'Qty',
      rateLabel:      null,
      warehouseLabel: null,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Derives the correct rack display mode from the SE's stockEntryType string.
  static RackDisplayMode _rackModeForStockEntry({
    required String  stockEntryType,
    required String? rack,
    required String? toRack,
  }) {
    final hasRack   = rack   != null && rack.isNotEmpty;
    final hasToRack = toRack != null && toRack.isNotEmpty;

    switch (stockEntryType) {
      case 'Material Receipt':
      case 'Manufacture':       // FG row arrives into target rack
        return hasRack ? RackDisplayMode.targetOnly : RackDisplayMode.none;

      case 'Material Transfer':
      case 'Material Transfer for Manufacture':
        if (!hasRack) return RackDisplayMode.none;
        return hasToRack
            ? RackDisplayMode.sourceAndTarget
            : RackDisplayMode.sourceOnly;

      case 'Material Issue':
      default:
        return hasRack ? RackDisplayMode.sourceOnly : RackDisplayMode.none;
    }
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
      packedQty:     item.packedQty,
      // rate / amount suppressed — C11
      rate:          null,
      amount:        null,
      // warehouse suppressed — C11
      warehouse:      null,
      toWarehouse:    null,
      batchNo:        item.batchNo,
      rack:           item.rack,
      toRack:         null,
      rackDisplayMode: item.rack != null && item.rack!.isNotEmpty
          ? RackDisplayMode.sourceOnly
          : RackDisplayMode.none,
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
