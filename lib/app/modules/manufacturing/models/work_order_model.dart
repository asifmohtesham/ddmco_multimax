class WorkOrderModel {
  final String name;
  final String productionItem;
  final String? itemName;
  final String? bom;
  final double qty;
  final double producedQty;
  final double? materialTransferredQty;
  final String status; // Draft, Submitted, In Process, Completed, Stopped, Cancelled
  final String? company;
  final String? wip Warehouse;
  final String? fgWarehouse;
  final String? sourceWarehouse;
  final DateTime? plannedStartDate;
  final DateTime? plannedEndDate;
  final DateTime? actualStartDate;
  final DateTime? actualEndDate;
  final List<WorkOrderItem> requiredItems;
  final List<WorkOrderOperation> operations;
  final DateTime? modified;

  WorkOrderModel({
    required this.name,
    required this.productionItem,
    this.itemName,
    this.bom,
    required this.qty,
    required this.producedQty,
    this.materialTransferredQty,
    required this.status,
    this.company,
    this.wipWarehouse,
    this.fgWarehouse,
    this.sourceWarehouse,
    this.plannedStartDate,
    this.plannedEndDate,
    this.actualStartDate,
    this.actualEndDate,
    required this.requiredItems,
    required this.operations,
    this.modified,
  });

  factory WorkOrderModel.fromJson(Map<String, dynamic> json) {
    return WorkOrderModel(
      name: json['name'] ?? '',
      productionItem: json['production_item'] ?? '',
      itemName: json['item_name'],
      bom: json['bom_no'],
      qty: (json['qty'] ?? 0.0).toDouble(),
      producedQty: (json['produced_qty'] ?? 0.0).toDouble(),
      materialTransferredQty: json['material_transferred_for_manufacturing'] != null
          ? (json['material_transferred_for_manufacturing']).toDouble()
          : null,
      status: json['status'] ?? 'Draft',
      company: json['company'],
      wipWarehouse: json['wip_warehouse'],
      fgWarehouse: json['fg_warehouse'],
      sourceWarehouse: json['source_warehouse'],
      plannedStartDate: json['planned_start_date'] != null
          ? DateTime.parse(json['planned_start_date'])
          : null,
      plannedEndDate: json['planned_end_date'] != null
          ? DateTime.parse(json['planned_end_date'])
          : null,
      actualStartDate: json['actual_start_date'] != null
          ? DateTime.parse(json['actual_start_date'])
          : null,
      actualEndDate: json['actual_end_date'] != null
          ? DateTime.parse(json['actual_end_date'])
          : null,
      requiredItems: (json['required_items'] as List<dynamic>?)
          ?.map((item) => WorkOrderItem.fromJson(item))
          .toList() ?? [],
      operations: (json['operations'] as List<dynamic>?)
          ?.map((op) => WorkOrderOperation.fromJson(op))
          .toList() ?? [],
      modified: json['modified'] != null ? DateTime.parse(json['modified']) : null,
    );
  }

  double get progressPercentage => qty > 0 ? (producedQty / qty * 100).clamp(0, 100) : 0;
  bool get isCompleted => status == 'Completed';
  bool get isInProcess => status == 'In Process';
  bool get isStopped => status == 'Stopped';
}

class WorkOrderItem {
  final String itemCode;
  final String? itemName;
  final double requiredQty;
  final double transferredQty;
  final double consumedQty;
  final String? sourceWarehouse;
  final String? description;

  WorkOrderItem({
    required this.itemCode,
    this.itemName,
    required this.requiredQty,
    required this.transferredQty,
    required this.consumedQty,
    this.sourceWarehouse,
    this.description,
  });

  factory WorkOrderItem.fromJson(Map<String, dynamic> json) {
    return WorkOrderItem(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'],
      requiredQty: (json['required_qty'] ?? 0.0).toDouble(),
      transferredQty: (json['transferred_qty'] ?? 0.0).toDouble(),
      consumedQty: (json['consumed_qty'] ?? 0.0).toDouble(),
      sourceWarehouse: json['source_warehouse'],
      description: json['description'],
    );
  }

  bool get isFullyTransferred => transferredQty >= requiredQty;
  double get pendingQty => (requiredQty - transferredQty).clamp(0, double.infinity);
}

class WorkOrderOperation {
  final String operation;
  final String? workstation;
  final double timeInMins;
  final String status; // Pending, Work In Progress, Completed
  final double? completedQty;

  WorkOrderOperation({
    required this.operation,
    this.workstation,
    required this.timeInMins,
    required this.status,
    this.completedQty,
  });

  factory WorkOrderOperation.fromJson(Map<String, dynamic> json) {
    return WorkOrderOperation(
      operation: json['operation'] ?? '',
      workstation: json['workstation'],
      timeInMins: (json['time_in_mins'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'Pending',
      completedQty: json['completed_qty'] != null
          ? (json['completed_qty']).toDouble()
          : null,
    );
  }
}