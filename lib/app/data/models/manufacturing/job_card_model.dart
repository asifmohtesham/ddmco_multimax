// Job Card Model - ERPNext Compliant
import 'package:json_annotation/json_annotation.dart';

part 'job_card_model.g.dart';

@JsonSerializable()
class JobCardModel {
  final String name;
  @JsonKey(name: 'work_order')
  final String workOrder;
  final String? operation;
  final String? workstation;
  @JsonKey(name: 'operation_id')
  final String? operationId;
  @JsonKey(name: 'sequence_id')
  final int? sequenceId;
  final String status;
  @JsonKey(name: 'production_item')
  final String? productionItem;
  @JsonKey(name: 'item_name')
  final String? itemName;
  @JsonKey(name: 'for_quantity')
  final double? forQuantity;
  @JsonKey(name: 'total_completed_qty')
  final double? totalCompletedQty;
  @JsonKey(name: 'total_time_in_mins')
  final double? totalTimeInMins;
  @JsonKey(name: 'expected_time_in_mins')
  final double? expectedTimeInMins;
  @JsonKey(name: 'time_logs')
  final List<JobCardTimeLog>? timeLogs;
  @JsonKey(name: 'job_card_item')
  final List<JobCardItem>? items;
  @JsonKey(name: 'posting_date')
  final String? postingDate;
  @JsonKey(name: 'employee')
  final List<JobCardEmployee>? employees;
  @JsonKey(name: 'remarks')
  final String? remarks;
  final String? modified;
  final String? creation;

  JobCardModel({
    required this.name,
    required this.workOrder,
    this.operation,
    this.workstation,
    this.operationId,
    this.sequenceId,
    required this.status,
    this.productionItem,
    this.itemName,
    this.forQuantity,
    this.totalCompletedQty,
    this.totalTimeInMins,
    this.expectedTimeInMins,
    this.timeLogs,
    this.items,
    this.postingDate,
    this.employees,
    this.remarks,
    this.modified,
    this.creation,
  });

  factory JobCardModel.fromJson(Map<String, dynamic> json) => _$JobCardModelFromJson(json);
  Map<String, dynamic> toJson() => _$JobCardModelToJson(this);

  // Progress calculation
  double get progress {
    if (totalCompletedQty == null || forQuantity == null || forQuantity == 0) return 0.0;
    return (totalCompletedQty! / forQuantity! * 100).clamp(0.0, 100.0);
  }

  // Time efficiency
  double? get timeEfficiency {
    if (totalTimeInMins == null || expectedTimeInMins == null || expectedTimeInMins == 0) return null;
    return (expectedTimeInMins! / totalTimeInMins! * 100).clamp(0.0, double.infinity);
  }

  // Status color
  String get statusColor {
    switch (status.toLowerCase()) {
      case 'open':
        return 'grey';
      case 'work in progress':
        return 'blue';
      case 'completed':
        return 'green';
      case 'on hold':
        return 'orange';
      case 'cancelled':
        return 'red';
      default:
        return 'grey';
    }
  }
}

@JsonSerializable()
class JobCardTimeLog {
  final String? name;
  @JsonKey(name: 'from_time')
  final String? fromTime;
  @JsonKey(name: 'to_time')
  final String? toTime;
  @JsonKey(name: 'time_in_mins')
  final double? timeInMins;
  @JsonKey(name: 'completed_qty')
  final double? completedQty;
  final String? employee;
  @JsonKey(name: 'employee_name')
  final String? employeeName;

  JobCardTimeLog({
    this.name,
    this.fromTime,
    this.toTime,
    this.timeInMins,
    this.completedQty,
    this.employee,
    this.employeeName,
  });

  factory JobCardTimeLog.fromJson(Map<String, dynamic> json) => _$JobCardTimeLogFromJson(json);
  Map<String, dynamic> toJson() => _$JobCardTimeLogToJson(this);
}

@JsonSerializable()
class JobCardItem {
  final String? name;
  @JsonKey(name: 'item_code')
  final String itemCode;
  @JsonKey(name: 'item_name')
  final String? itemName;
  @JsonKey(name: 'required_qty')
  final double requiredQty;
  @JsonKey(name: 'transferred_qty')
  final double? transferredQty;
  @JsonKey(name: 'consumed_qty')
  final double? consumedQty;
  @JsonKey(name: 'source_warehouse')
  final String? sourceWarehouse;
  final String? uom;

  JobCardItem({
    this.name,
    required this.itemCode,
    this.itemName,
    required this.requiredQty,
    this.transferredQty,
    this.consumedQty,
    this.sourceWarehouse,
    this.uom,
  });

  factory JobCardItem.fromJson(Map<String, dynamic> json) => _$JobCardItemFromJson(json);
  Map<String, dynamic> toJson() => _$JobCardItemToJson(this);
}

@JsonSerializable()
class JobCardEmployee {
  final String? name;
  final String employee;
  @JsonKey(name: 'employee_name')
  final String? employeeName;
  @JsonKey(name: 'completed_qty')
  final double? completedQty;

  JobCardEmployee({
    this.name,
    required this.employee,
    this.employeeName,
    this.completedQty,
  });

  factory JobCardEmployee.fromJson(Map<String, dynamic> json) => _$JobCardEmployeeFromJson(json);
  Map<String, dynamic> toJson() => _$JobCardEmployeeToJson(this);
}
