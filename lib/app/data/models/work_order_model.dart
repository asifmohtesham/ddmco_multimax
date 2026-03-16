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
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      name: json['name'] ?? '',
      productionItem: json['production_item'] ?? '',
      itemName: json['item_name'] ?? '',
      bomNo: json['bom_no'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      producedQty: (json['produced_qty'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'Draft',
      plannedStartDate: json['planned_start_date'] ?? '',
      expectedEndDate: json['expected_end_date'],
      wip_warehouse: json['wip_warehouse'],
      fg_warehouse: json['fg_warehouse'],
      description: json['description'],
      modified: json['modified'],
      docstatus: json['docstatus'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'production_item': productionItem,
        'bom_no': bomNo,
        'qty': qty,
        'planned_start_date': plannedStartDate,
        if (expectedEndDate != null) 'expected_end_date': expectedEndDate,
        if (wip_warehouse != null) 'wip_warehouse': wip_warehouse,
        if (fg_warehouse != null) 'fg_warehouse': fg_warehouse,
        if (description != null) 'description': description,
        'docstatus': docstatus,
      };
}
