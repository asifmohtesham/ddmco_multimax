class WorkOrder {
  final String name;
  final String productionItem;
  final String itemName;
  final String bomNo;
  final double qty;
  final double producedQty;
  final String status; // Draft, Submitted, In Process, Completed, Cancelled
  final String plannedStartDate;
  final String? expectedEndDate;
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
      docstatus: json['docstatus'] as int? ?? 0,
    );
  }
}