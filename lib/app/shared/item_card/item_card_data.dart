import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';

/// Canonical, immutable data contract for a single line-item card
/// across all five DocTypes (PO, PR, SE, DN, PS).
///
/// The shared [DocItemCard] widget (Phase 2) accepts only this type,
/// enforcing Interface Segregation: no widget ever imports a DocType
/// model directly.
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
  // ── Identity ─────────────────────────────────────────────────────────────────────────────────

  /// ERPNext row `name` (server-assigned UUID). Used as the stable Dismissible
  /// key and for controller look-ups. Null for locally-created rows not yet
  /// saved to the server.
  final String? rowName;

  /// 0-based position within a POS-Upload group. When non-null the widget
  /// renders a numbered CircleAvatar badge to the left of the item code.
  /// Pass null in flat / non-grouped lists to suppress the badge.
  final int? index;

  // ── Core item fields ───────────────────────────────────────────────────────────────────

  final String itemCode;
  final String? itemName;

  /// custom_variant_of — shown as an amber-tinted identity chip beneath
  /// the item name when non-null.
  final String? variantOf;

  // ── Quantity ──────────────────────────────────────────────────────────────────────────────

  /// The quantity on this row (qty / basic_qty / packed_qty depending on
  /// DocType). Always required; drives the Qty meta chip.
  final double qty;

  final String? uom;

  /// The reference quantity this row is being fulfilled against.
  /// Drives the DocItemProgressBar:
  ///   PO  → receivedQty  (qty already received against this PO line)
  ///   PR  → purchaseOrderQty  (the PO qty this receipt line is linked to)
  ///   SE  → row.requestedQty via copyWithTargetQty (MR entries only)
  ///   DN  → null  (DN has no per-item target; omit progress bar)
  ///   PS  → null  (PS has no per-item target; omit progress bar)
  final double? targetQty;

  // ── Pricing ──────────────────────────────────────────────────────────────────────────────

  /// Unit rate. Optional — SE uses basicRate, PO/PR/DN use rate.
  /// PS omits this entirely (Packing Slip Item is a logistics document
  /// with no pricing fields in the ERPNext schema).
  final double? rate;

  /// Line total (rate × qty). Shown only when the DocType provides it.
  /// PS omits this entirely for the same reason as [rate].
  final double? amount;

  // ── Warehouse / Location ────────────────────────────────────────────────────────────

  /// Source / single warehouse (PR warehouse, SE s_warehouse, DN warehouse).
  final String? warehouse;

  /// Destination warehouse (SE t_warehouse only).
  final String? toWarehouse;

  // ── Batch / Rack ────────────────────────────────────────────────────────────────────

  final String? batchNo;

  /// Source rack (PR rack, SE rack, DN rack). Inventory Dimension → Rack DocType.
  final String? rack;

  /// Destination rack (SE to_rack only). Inventory Dimension → Rack DocType.
  final String? toRack;

  // ── Label hints ──────────────────────────────────────────────────────────────────────

  /// Verbatim ERPNext `label` for the qty field of this DocType.
  ///
  /// Sourced from frappe/erpnext DocType JSONs:
  ///   SE  → 'Qty'           (stock_entry_detail.qty.label)
  ///   PR  → 'Accepted Qty'  (purchase_receipt_item.qty.label abbreviated)
  ///   DN  → 'Qty'           (delivery_note_item.qty.label abbreviated)
  ///   PO  → 'Qty'
  ///   PS  → 'Qty'
  ///
  /// [DocItemCard] falls back to 'Qty' when null.
  final String? qtyLabel;

  /// Verbatim ERPNext `label` for the rate field of this DocType.
  ///
  /// Sourced from frappe/erpnext DocType JSONs:
  ///   SE  → 'Basic Rate'  (stock_entry_detail.basic_rate.label abbreviated)
  ///   PR  → 'Rate'        (purchase_receipt_item.rate.label)
  ///   DN  → 'Rate'        (delivery_note_item.rate.label)
  ///   PO  → 'Rate'
  ///   PS  → null          (no pricing fields on Packing Slip Item)
  ///
  /// [DocItemCard] falls back to 'Rate' when null.
  final String? rateLabel;

  /// Verbatim ERPNext `label` for the warehouse field of this DocType.
  ///
  /// Sourced from frappe/erpnext DocType JSONs:
  ///   SE  → 'Source Warehouse'    (stock_entry_detail.s_warehouse.label)
  ///   PR  → 'Accepted Warehouse'  (purchase_receipt_item.warehouse.label)
  ///   DN  → 'Warehouse'           (delivery_note_item.warehouse.label)
  ///   PO  → null  (PO items carry no warehouse field in the standard schema)
  ///   PS  → null  (PS items carry no warehouse field)
  ///
  /// [DocItemCard] falls back to 'Warehouse' when null.
  final String? warehouseLabel;

  // ── Behaviour flags ─────────────────────────────────────────────────────────────────

  /// Whether edit / delete actions are rendered.
  /// Typically `docstatus == 0`.
  final bool isEditable;

  /// Drives the yellow AnimatedContainer flash for recently-scanned rows.
  final bool isHighlighted;

  // ── Constructor ──────────────────────────────────────────────────────────────────────

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

  // ── copyWith helpers ─────────────────────────────────────────────────────────────────

  /// Returns a copy of this object with [targetQty] replaced.
  ///
  /// Used by [MrItemsView] to inject [row.requestedQty] as the
  /// fulfilment target after the base factory has already run.
  /// All label hints are preserved as-is.
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

  // ── Named factory constructors ────────────────────────────────────────────────────────

  /// Maps a [PurchaseOrderItem] to [ItemCardData].
  ///
  /// Label hints: qty → 'Qty', rate → 'Rate'.
  /// PO items carry no warehouse field in the standard ERPNext schema.
  factory ItemCardData.fromPurchaseOrderItem(
    PurchaseOrderItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:        item.name,
      index:          index,
      itemCode:       item.itemCode,
      itemName:       item.itemName.isNotEmpty ? item.itemName : null,
      qty:            item.qty,
      uom:            item.uom,
      // receivedQty is the "done" quantity against this PO line.
      // The progress bar will show receivedQty / qty.
      targetQty:      item.receivedQty,
      rate:           item.rate,
      amount:         item.amount,
      // Label hints — verbatim ERPNext labels for PO
      qtyLabel:       'Qty',
      rateLabel:      'Rate',
      warehouseLabel: null,   // PO items have no warehouse in standard schema
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [PurchaseReceiptItem] to [ItemCardData].
  ///
  /// Label hints:
  ///   qty       → 'Accepted Qty'       (abbreviated from 'Accepted Quantity')
  ///   rate      → 'Rate'
  ///   warehouse → 'Accepted Warehouse' (verbatim purchase_receipt_item.warehouse.label)
  factory ItemCardData.fromPurchaseReceiptItem(
    PurchaseReceiptItem item, {
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
      // purchaseOrderQty is the PO line qty this receipt row is linked to.
      // The progress bar shows qty / purchaseOrderQty.
      targetQty:      item.purchaseOrderQty,
      rate:           item.rate,
      warehouse:      item.warehouse,
      batchNo:        item.batchNo,
      rack:           item.rack,
      // Label hints — verbatim ERPNext labels for PR
      qtyLabel:       'Accepted Qty',
      rateLabel:      'Rate',
      warehouseLabel: 'Accepted Warehouse',
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [StockEntryItem] to [ItemCardData].
  ///
  /// Label hints:
  ///   qty       → 'Qty'              (stock_entry_detail.qty.label)
  ///   rate      → 'Basic Rate'       (abbreviated from 'Basic Rate (as per Stock UOM)')
  ///   warehouse → 'Source Warehouse' (stock_entry_detail.s_warehouse.label)
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
      rowName:        item.name,
      index:          index,
      itemCode:       item.itemCode,
      itemName:       item.itemName,
      variantOf:      item.customVariantOf,
      qty:            item.qty,
      rate:           item.basicRate,
      warehouse:      item.sWarehouse,
      toWarehouse:    item.tWarehouse,
      batchNo:        item.batchNo,
      rack:           item.rack,
      toRack:         item.toRack,
      // Label hints — verbatim ERPNext labels for SE
      qtyLabel:       'Qty',
      rateLabel:      'Basic Rate',
      warehouseLabel: 'Source Warehouse',
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [DeliveryNoteItem] to [ItemCardData].
  ///
  /// Label hints:
  ///   qty       → 'Qty'        (abbreviated from 'Quantity' in delivery_note_item.json)
  ///   rate      → 'Rate'       (delivery_note_item.rate.label)
  ///   warehouse → 'Warehouse'  (delivery_note_item.warehouse.label)
  factory ItemCardData.fromDeliveryNoteItem(
    DeliveryNoteItem item, {
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
      batchNo:        item.batchNo,
      rack:           item.rack,
      // DN has no per-item target qty — progress bar is omitted.
      // Label hints — verbatim ERPNext labels for DN
      qtyLabel:       'Qty',
      rateLabel:      'Rate',
      warehouseLabel: 'Warehouse',
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }

  /// Maps a [PackingSlipItem] to [ItemCardData].
  ///
  /// Note: ERPNext Packing Slip Item is a logistics/weight document.
  /// It has no pricing fields (no rate, no amount) in the standard
  /// schema — confirmed via frappe/erpnext packing_slip_item.json.
  /// rate, amount, and rateLabel are therefore omitted (implicitly null).
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
      qty:            item.qty,
      uom:            item.uom,
      // No rate / amount — Packing Slip Item has no pricing fields.
      // No warehouse — Packing Slip Item has no warehouse in standard schema.
      qtyLabel:       'Qty',
      rateLabel:      null,
      warehouseLabel: null,
      isEditable:     isEditable,
      isHighlighted:  isHighlighted,
    );
  }
}
