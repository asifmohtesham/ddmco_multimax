class JobCardModel {
  final String name;
  final String workOrder;
  final String operation;
  final String? workstation;
  final String? employee;
  final String? employeeName;
  final double forQuantity;
  final double totalCompletedQty;
  final double? processLossQty;
  final String status; // Open, Work In Progress, Submitted, On Hold, Completed, Cancelled
  final DateTime? expectedStartDate;
  final DateTime? expectedEndDate;
  final DateTime? actualStartDate;
  final DateTime? actualEndDate;
  final double totalTimeInMins;
  final List<JobCardTimeLog> timeLogs;
  final List<JobCardItem> items;
  final DateTime? modified;

  JobCardModel({
    required this.name,
    required this.workOrder,
    required this.operation,
    this.workstation,
    this.employee,
    this.employeeName,
    required this.forQuantity,
    required this.totalCompletedQty,
    this.processLossQty,
    required this.status,
    this.expectedStartDate,
    this.expectedEndDate,
    this.actualStartDate,
    this.actualEndDate,
    required this.totalTimeInMins,
    required this.timeLogs,
    required this.items,
    this.modified,
  });

  factory JobCardModel.fromJson(Map<String, dynamic> json) {
    return JobCardModel(
      name: json['name'] ?? '',
      workOrder: json['work_order'] ?? '',
      operation: json['operation'] ?? '',
      workstation: json['workstation'],
      employee: json['employee'],
      employeeName: json['employee_name'],
      forQuantity: (json['for_quantity'] ?? 0.0).toDouble(),
      totalCompletedQty: (json['total_completed_qty'] ?? 0.0).toDouble(),
      processLossQty: json['process_loss_qty'] != null
          ? (json['process_loss_qty']).toDouble()
          : null,
      status: json['status'] ?? 'Open',
      expectedStartDate: json['expected_start_date'] != null
          ? DateTime.parse(json['expected_start_date'])
          : null,
      expectedEndDate: json['expected_end_date'] != null
          ? DateTime.parse(json['expected_end_date'])
          : null,
      actualStartDate: json['actual_start_date'] != null
          ? DateTime.parse(json['actual_start_date'])
          : null,
      actualEndDate: json['actual_end_date'] != null
          ? DateTime.parse(json['actual_end_date'])
          : null,
      totalTimeInMins: (json['total_time_in_mins'] ?? 0.0).toDouble(),
      timeLogs: (json['time_logs'] as List<dynamic>?)
          ?.map((log) => JobCardTimeLog.fromJson(log))
          .toList() ?? [],
      items: (json['job_card_item'] as List<dynamic>?)
          ?.map((item) => JobCardItem.fromJson(item))
          .toList() ?? [],
      modified: json['modified'] != null ? DateTime.parse(json['modified']) : null,
    );
  }

  double get progressPercentage =>
      forQuantity > 0 ? (totalCompletedQty / forQuantity * 100).clamp(0, 100) : 0;
  bool get isCompleted => status == 'Completed';
  bool get isInProgress => status == 'Work In Progress';
  bool get isOpen => status == 'Open';
  bool get hasActiveTimeLog => timeLogs.any((log) => log.toTime == null);
}

class JobCardTimeLog {
  final String? name;
  final DateTime fromTime;
  final DateTime? toTime;
  final double? timeInMins;
  final double? completedQty;

  JobCardTimeLog({
    this.name,
    required this.fromTime,
    this.toTime,
    this.timeInMins,
    this.completedQty,
  });

  factory JobCardTimeLog.fromJson(Map<String, dynamic> json) {
    return JobCardTimeLog(
      name: json['name'],
      fromTime: DateTime.parse(json['from_time']),
      toTime: json['to_time'] != null ? DateTime.parse(json['to_time']) : null,
      timeInMins: json['time_in_mins'] != null
          ? (json['time_in_mins']).toDouble()
          : null,
      completedQty: json['completed_qty'] != null
          ? (json['completed_qty']).toDouble()
          : null,
    );
  }

  bool get isActive => toTime == null;
}

class JobCardItem {
  final String itemCode;
  final String? itemName;
  final double requiredQty;
  final double transferredQty;
  final String? sourceWarehouse;

  JobCardItem({
    required this.itemCode,
    this.itemName,
    required this.requiredQty,
    required this.transferredQty,
    this.sourceWarehouse,
  });

  factory JobCardItem.fromJson(Map<String, dynamic> json) {
    return JobCardItem(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'],
      requiredQty: (json['required_qty'] ?? 0.0).toDouble(),
      transferredQty: (json['transferred_qty'] ?? 0.0).toDouble(),
      sourceWarehouse: json['source_warehouse'],
    );
  }

  double get pendingQty => (requiredQty - transferredQty).clamp(0, double.infinity);
}