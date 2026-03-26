import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';

/// Canonical, immutable data contract for a single line-item card
/// across all five DocTypes (PO, PR, SE, DN, PS).
///
/// The shared [DocItemCard] widget (Phase 2) accepts only this type,
/// enforcing Interface Segregation: no widget ever needs to import
/// a DocType model directly.
///
/// Construction:
///   Use the named factory constructors to map a DocType item model
///   to this contract in a single, auditable location.
///
///   ItemCardData.fromPurchaseOrderItem(item, isEditable: editable)
///   ItemCardData.fromPurchaseReceiptItem(item, ...)
///   ItemCardData.fromStockEntryItem(item, ...)
///   ItemCardData.fromDeliveryNoteItem(item, ...)
///   ItemCardData.fromPackingSlipItem(item, ...)
class ItemCardData {
  // ── Identity ──────────────────────────────────────────────────────────────────

  /// ERPNext row `name` (server-assigned UUID). Used as the stable Dismissible
  /// key and for controller look-ups. Null for locally-created rows not yet
  /// saved to the server.
  final String? rowName;

  /// 0-based position within a POS-Upload group.  When non-null the widget
  /// renders a numbered CircleAvatar badge to the left of the item code.
  /// Pass null in flat / non-grouped lists to suppress the badge.
  final int? index;

  // ── Core item fields ───────────────────────────────────────────────────────────────────

  final String itemCode;
  final String? itemName;

  /// custom_variant_of — shown as a blueGrey chip beneath the item name.
  final String? variantOf;

  // ── Quantity ───────────────────────────────────────────────────────────────────────

  /// The quantity on this row (qty / basic_qty / packed_qty depending on
  /// DocType). Always required; drives the Qty meta chip.
  final double qty;

  final String? uom;

  /// The reference quantity this row is being fulfilled against.
  /// Drives the DocItemProgressBar (Phase 3):
  ///   PO  → receivedQty  (qty already received against this PO line)
  ///   PR  → purchaseOrderQty  (the PO qty this receipt line is linked to)
  ///   SE  → row.requestedQty via copyWithTargetQty (MR entries only)
  ///   DN  → null  (DN has no per-item target; omit progress bar)
  ///   PS  → null  (PS has no per-item target; omit progress bar)
  final double? targetQty;

  // ── Pricing ────────────────────────────────────────────────────────────────────────

  /// Unit rate.  Optional — SE uses basicRate, PO/PR/DN use rate.
  /// PS omits this entirely (Packing Slip Item is a logistics document
  /// with no pricing fields in the ERPNext schema).
  final double? rate;

  /// Line total (rate × qty).  Shown only when the DocType provides it.
  /// PS omits this entirely for the same reason as [rate].
  final double? amount;

  // ── Warehouse / Location ──────────────────────────────────────────────────────────

  /// Source / single warehouse (PR warehouse, SE s_warehouse).
  final String? warehouse;

  /// Destination warehouse (SE t_warehouse only).
  final String? toWarehouse;

  // ── Batch / Rack ───────────────────────────────────────────────────────────────────

  final String? batchNo;

  /// Source rack (PR rack, SE rack, DN rack).
  final String? rack;

  /// Destination rack (SE to_rack only).
  final String? toRack;

  // ── Behaviour flags ──────────────────────────────────────────────────────────────────

  /// Whether edit / delete actions are rendered.
  /// Typically `docstatus == 0`.
  final bool isEditable;

  /// Drives the yellow AnimatedContainer flash for recently-scanned rows.
  final bool isHighlighted;

  // ── Constructor ─────────────────────────────────────────────────────────────────────

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
    required this.isEditable,
    this.isHighlighted = false,
  });

  // ── copyWith helpers ───────────────────────────────────────────────────────────────────

  /// Returns a copy of this object with [targetQty] replaced.
  ///
  /// Used by [MrItemsView] to inject [row.requestedQty] as the
  /// fulfilment target after the base factory has already run.
  ItemCardData copyWithTargetQty(double? targetQty) {
    return ItemCardData(
      rowName:       rowName,
      index:         index,
      itemCode:      itemCode,
      itemName:      itemName,
      variantOf:     variantOf,
      qty:           qty,
      uom:           uom,
      targetQty:     targetQty,
      rate:          rate,
      amount:        amount,
      warehouse:     warehouse,
      toWarehouse:   toWarehouse,
      batchNo:       batchNo,
      rack:          rack,
      toRack:        toRack,
      isEditable:    isEditable,
      isHighlighted: isHighlighted,
    );
  }

  // ── Named factory constructors ───────────────────────────────────────────────────────────────

  /// Maps a [PurchaseOrderItem] to [ItemCardData].
  ///
  /// [index]      — pass when rendering inside a POS-Upload group.
  /// [isEditable] — pass `docstatus == 0` from the parent PO.
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
      qty:           item.qty,
      uom:           item.uom,
      // receivedQty is the "done" quantity against this PO line.
      // The progress bar will show receivedQty / qty.
      targetQty:     item.receivedQty,
      rate:          item.rate,
      amount:        item.amount,
      isEditable:    isEditable,
      isHighlighted: isHighlighted,
    );
  }

  /// Maps a [PurchaseReceiptItem] to [ItemCardData].
  ///
  /// [isHighlighted] — pass `recentlyAddedItemCode == item.itemCode`.
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
      // purchaseOrderQty is the PO line qty this receipt row is linked to.
      // The progress bar shows qty / purchaseOrderQty.
      targetQty:     item.purchaseOrderQty,
      rate:          item.rate,
      warehouse:     item.warehouse,
      batchNo:       item.batchNo,
      rack:          item.rack,
      isEditable:    isEditable,
      isHighlighted: isHighlighted,
    );
  }

  /// Maps a [StockEntryItem] to [ItemCardData].
  ///
  /// For Material Request entries, call [copyWithTargetQty] afterwards
  /// to inject [row.requestedQty] as the fulfilment target.
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
      rate:          item.basicRate,
      warehouse:     item.sWarehouse,
      toWarehouse:   item.tWarehouse,
      batchNo:       item.batchNo,
      rack:          item.rack,
      toRack:        item.toRack,
      isEditable:    isEditable,
      isHighlighted: isHighlighted,
    );
  }

  /// Maps a [DeliveryNoteItem] to [ItemCardData].
  ///
  /// [isHighlighted] — pass the `recentlyAdded` logic result from the
  ///   controller so the widget remains stateless.
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
      batchNo:       item.batchNo,
      rack:          item.rack,
      // DN has no per-item target qty — progress bar is omitted.
      isEditable:    isEditable,
      isHighlighted: isHighlighted,
    );
  }

  /// Maps a [PackingSlipItem] to [ItemCardData].
  ///
  /// Note: ERPNext Packing Slip Item is a logistics/weight document.
  /// It has no pricing fields (no rate, no amount) in the standard
  /// schema — confirmed via frappe/erpnext packing_slip_item.json.
  /// rate and amount are therefore omitted (implicitly null).
  factory ItemCardData.fromPackingSlipItem(
    PackingSlipItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:       item.name,
      index:         index,
      itemCode:      item.itemCode,
      itemName:      item.itemName,
      qty:           item.qty,
      uom:           item.uom,
      // No rate / amount — Packing Slip Item has no pricing fields.
      isEditable:    isEditable,
      isHighlighted: isHighlighted,
    );
  }
}
