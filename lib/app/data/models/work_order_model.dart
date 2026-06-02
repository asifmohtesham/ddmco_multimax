import 'package:multimax/app/data/models/work_order_item_model.dart';
import 'package:multimax/app/data/models/work_order_operation_model.dart';

/// Model for the **Work Order** DocType.
///
/// ERP path: Manufacturing → Work Order
///
/// [operations] maps the `Work Order Operation` child table — populated
/// only when fetching a single document (GET /api/resource/Work Order/{name}).
/// List-view responses omit child tables; the field defaults to [].
///
/// [requiredItems] maps the `Work Order Item` child table (`required_items`)
/// which lists the raw materials / components required for the production run.
/// Like [operations], it is only present in single-document responses.
///
/// [skipTransfer] and [transferMaterialAgainst] are needed by the
/// Job Card creation flow to determine WIP warehouse behaviour.
class WorkOrder {
  final String name;
  final String productionItem;
  final String itemName;
  final String bomNo;
  final double qty;
  final double producedQty;
  final double? materialTransferredForManufacturing;
  final String status;
  final String plannedStartDate;
  final String? expectedEndDate;
  final String? wipWarehouse;
  final String? fgWarehouse;
  final String? description;
  final String? modified;
  final int docstatus;

  // ── Operations child table ──────────────────────────────────────────────────
  /// Rows from the `Work Order Operation` child table.
  /// Empty when the Work Order has no routing / operations defined,
  /// or when loaded from a list view (child tables not included).
  final List<WorkOrderOperation> operations;

  // ── Required Items child table ─────────────────────────────────────────────
  /// Rows from the `Work Order Item` child table (`required_items` JSON key).
  /// Lists all raw materials / components required for this production run.
  /// Empty when loaded from a list view (child tables not included).
  final List<WorkOrderItem> requiredItems;

  // ── Material transfer flags ─────────────────────────────────────────────────
  /// When true, raw material transfer is skipped for this Work Order.
  /// Mirrors the ERPNext `skip_transfer` checkbox field.
  final bool skipTransfer;

  /// Controls whether material is transferred against the Work Order or
  /// against individual Job Cards.
  /// Values: `"Work Order"` | `"Job Card"` | null
  final String? transferMaterialAgainst;

  WorkOrder({
    required this.name,
    required this.productionItem,
    required this.itemName,
    required this.bomNo,
    required this.qty,
    required this.producedQty,
    this.materialTransferredForManufacturing,
    required this.status,
    required this.plannedStartDate,
    this.expectedEndDate,
    this.wipWarehouse,
    this.fgWarehouse,
    this.description,
    this.modified,
    required this.docstatus,
    this.operations = const [],
    this.requiredItems = const [],
    this.skipTransfer = false,
    this.transferMaterialAgainst,
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      name:            json['name']             ?? '',
      productionItem:  json['production_item']  ?? '',
      itemName:        json['item_name']         ?? '',
      bomNo:           json['bom_no']            ?? '',
      qty:             (json['qty']              as num?)?.toDouble() ?? 0.0,
      producedQty:     (json['produced_qty']     as num?)?.toDouble() ?? 0.0,
      materialTransferredForManufacturing: (json['material_transferred_for_manufacturing'] as num?)?.toDouble(),
      status:          json['status']            ?? 'Draft',
      plannedStartDate: json['planned_start_date'] ?? '',
      expectedEndDate: json['expected_end_date'],
      wipWarehouse:    json['wip_warehouse'],
      fgWarehouse:    json['fg_warehouse'],
      description:     json['description'],
      modified:        json['modified'],
      docstatus:       json['docstatus']         as int? ?? 0,
      // ── Operations child table ─────────────────────────────────────────────
      operations: (json['operations'] as List? ?? [])
          .map((e) => WorkOrderOperation.fromJson(e as Map<String, dynamic>))
          .toList(),
      // ── Required Items child table ─────────────────────────────────────────
      requiredItems: (json['required_items'] as List? ?? [])
          .map((e) => WorkOrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      // ── Transfer flags ─────────────────────────────────────────────────────
      skipTransfer: (json['skip_transfer'] as int? ?? 0) == 1,
      transferMaterialAgainst: json['transfer_material_against'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'production_item': productionItem,
    'bom_no':          bomNo,
    'qty':             qty,
    'planned_start_date': plannedStartDate,
    if (expectedEndDate != null) 'expected_end_date': expectedEndDate,
    if (wipWarehouse    != null) 'wip_warehouse':     wipWarehouse,
    if (fgWarehouse    != null) 'fg_warehouse':      fgWarehouse,
    if (description     != null) 'description':       description,
    'docstatus': docstatus,
    // operations and requiredItems are read-only from the app — excluded
  };
}
