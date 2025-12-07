class JobCard {
  final String name;
  final String workOrder;
  final String operation;
  final String? workstation;
  final String status; // Open, Work In Progress, Completed, Cancelled
  final double forQuantity;
  final double totalCompletedQty;
  final int docstatus;
  final String? postingDate;

  JobCard({
    required this.name,
    required this.workOrder,
    required this.operation,
    this.workstation,
    required this.status,
    required this.forQuantity,
    required this.totalCompletedQty,
    required this.docstatus,
    this.postingDate,
  });

  factory JobCard.fromJson(Map<String, dynamic> json) {
    return JobCard(
      name: json['name'] ?? '',
      workOrder: json['work_order'] ?? '',
      operation: json['operation'] ?? '',
      workstation: json['workstation'],
      status: json['status'] ?? 'Open',
      forQuantity: (json['for_quantity'] as num?)?.toDouble() ?? 0.0,
      totalCompletedQty: (json['total_completed_qty'] as num?)?.toDouble() ?? 0.0,
      docstatus: json['docstatus'] as int? ?? 0,
      postingDate: json['posting_date'],
    );
  }
}