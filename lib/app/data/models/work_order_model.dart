import 'package:multimax/app/data/models/work_order_operation_model.dart';

/// Model for the **Work Order** DocType.
///
/// ERPNext path: Manufacturing → Work Order
///
/// [operations] maps the `Work Order Operation` child table — populated
/// only when fetching a single document (GET /api/resource/Work Order/{name}).
/// List-view responses omit child tables; the field defaults to [].
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
  final String status;
  final String plannedStartDate;
  final String? expectedEndDate;
  final String? wip_warehouse;
  final String? fg_warehouse;
  final String? description;
  final String? modified;
  final int docstatus;

  // ── Operations child table ──────────────────────────────────────────────────
  /// Rows from the `Work Order Operation` child table.
  /// Empty when the Work Order has no routing / operations defined,
  /// or when loaded from a list view (child tables not included).
  final List<WorkOrderOperation> operations;

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
    required this.status,
    required this.plannedStartDate,
    this.expectedEndDate,
    this.wip_warehouse,
    this.fg_warehouse,
    this.description,
    this.modified,
    required this.docstatus,
    this.operations = const [],
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
      status:          json['status']            ?? 'Draft',
      plannedStartDate: json['planned_start_date'] ?? '',
      expectedEndDate: json['expected_end_date'],
      wip_warehouse:   json['wip_warehouse'],
      fg_warehouse:    json['fg_warehouse'],
      description:     json['description'],
      modified:        json['modified'],
      docstatus:       json['docstatus']         as int? ?? 0,
      // ── Child table ───────────────────────────────────────────────────────
      operations: (json['operations'] as List? ?? [])
          .map((e) => WorkOrderOperation.fromJson(e as Map<String, dynamic>))
          .toList(),
      // ── Transfer flags ────────────────────────────────────────────────────
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
    if (wip_warehouse   != null) 'wip_warehouse':     wip_warehouse,
    if (fg_warehouse    != null) 'fg_warehouse':      fg_warehouse,
    if (description     != null) 'description':       description,
    'docstatus': docstatus,
    // operations intentionally excluded — child table is read-only from app
  };
}
