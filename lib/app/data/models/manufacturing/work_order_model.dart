// Work Order Model - ERPNext Compliant
import 'package:json_annotation/json_annotation.dart';

part 'work_order_model.g.dart';

@JsonSerializable()
class WorkOrderModel {
  final String name;
  final String status;
  @JsonKey(name: 'production_item')
  final String productionItem;
  @JsonKey(name: 'item_name')
  final String? itemName;
  final String? image;
  @JsonKey(name: 'bom_no')
  final String? bomNo;
  final double qty;
  @JsonKey(name: 'produced_qty')
  final double? producedQty;
  @JsonKey(name: 'material_transferred_for_manufacturing')
  final double? materialTransferredQty;
  final String? company;
  @JsonKey(name: 'fg_warehouse')
  final String? fgWarehouse;
  @JsonKey(name: 'wip_warehouse')
  final String? wipWarehouse;
  @JsonKey(name: 'source_warehouse')
  final String? sourceWarehouse;
  @JsonKey(name: 'scrap_warehouse')
  final String? scrapWarehouse;
  @JsonKey(name: 'planned_start_date')
  final String? plannedStartDate;
  @JsonKey(name: 'planned_end_date')
  final String? plannedEndDate;
  @JsonKey(name: 'expected_delivery_date')
  final String? expectedDeliveryDate;
  @JsonKey(name: 'actual_start_date')
  final String? actualStartDate;
  @JsonKey(name: 'actual_end_date')
  final String? actualEndDate;
  @JsonKey(name: 'required_items')
  final List<WorkOrderItem>? requiredItems;
  final List<WorkOrderOperation>? operations;
  @JsonKey(name: 'skip_transfer')
  final int? skipTransfer;
  @JsonKey(name: 'use_multi_level_bom')
  final int? useMultiLevelBom;
  @JsonKey(name: 'total_operating_cost')
  final double? totalOperatingCost;
  @JsonKey(name: 'additional_operating_cost')
  final double? additionalOperatingCost;
  final String? project;
  @JsonKey(name: 'sales_order')
  final String? salesOrder;
  final String? description;
  final String? modified;
  final String? creation;

  WorkOrderModel({
    required this.name,
    required this.status,
    required this.productionItem,
    this.itemName,
    this.image,
    this.bomNo,
    required this.qty,
    this.producedQty,
    this.materialTransferredQty,
    this.company,
    this.fgWarehouse,
    this.wipWarehouse,
    this.sourceWarehouse,
    this.scrapWarehouse,
    this.plannedStartDate,
    this.plannedEndDate,
    this.expectedDeliveryDate,
    this.actualStartDate,
    this.actualEndDate,
    this.requiredItems,
    this.operations,
    this.skipTransfer,
    this.useMultiLevelBom,
    this.totalOperatingCost,
    this.additionalOperatingCost,
    this.project,
    this.salesOrder,
    this.description,
    this.modified,
    this.creation,
  });

  factory WorkOrderModel.fromJson(Map<String, dynamic> json) => _$WorkOrderModelFromJson(json);
  Map<String, dynamic> toJson() => _$WorkOrderModelToJson(this);

  // Progress calculation
  double get progress {
    if (producedQty == null || qty == 0) return 0.0;
    return (producedQty! / qty * 100).clamp(0.0, 100.0);
  }

  // Status color helper
  String get statusColor {
    switch (status.toLowerCase()) {
      case 'not started':
        return 'grey';
      case 'in process':
        return 'blue';
      case 'completed':
        return 'green';
      case 'stopped':
        return 'orange';
      case 'cancelled':
        return 'red';
      default:
        return 'grey';
    }
  }
}

@JsonSerializable()
class WorkOrderItem {
  final String? name;
  @JsonKey(name: 'item_code')
  final String itemCode;
  @JsonKey(name: 'item_name')
  final String? itemName;
  final String? description;
  final String? image;
  @JsonKey(name: 'required_qty')
  final double requiredQty;
  @JsonKey(name: 'transferred_qty')
  final double? transferredQty;
  @JsonKey(name: 'consumed_qty')
  final double? consumedQty;
  @JsonKey(name: 'returned_qty')
  final double? returnedQty;
  @JsonKey(name: 'available_qty_at_source_warehouse')
  final double? availableQty;
  @JsonKey(name: 'source_warehouse')
  final String? sourceWarehouse;
  final String? uom;
  final double? rate;
  final double? amount;

  WorkOrderItem({
    this.name,
    required this.itemCode,
    this.itemName,
    this.description,
    this.image,
    required this.requiredQty,
    this.transferredQty,
    this.consumedQty,
    this.returnedQty,
    this.availableQty,
    this.sourceWarehouse,
    this.uom,
    this.rate,
    this.amount,
  });

  factory WorkOrderItem.fromJson(Map<String, dynamic> json) => _$WorkOrderItemFromJson(json);
  Map<String, dynamic> toJson() => _$WorkOrderItemToJson(this);

  // Transfer progress
  double get transferProgress {
    if (transferredQty == null || requiredQty == 0) return 0.0;
    return (transferredQty! / requiredQty * 100).clamp(0.0, 100.0);
  }
}

@JsonSerializable()
class WorkOrderOperation {
  final String? name;
  final String operation;
  final String? workstation;
  @JsonKey(name: 'sequence_id')
  final int? sequenceId;
  final String? status;
  @JsonKey(name: 'time_in_mins')
  final double? timeInMins;
  @JsonKey(name: 'actual_operation_time')
  final double? actualOperationTime;
  @JsonKey(name: 'completed_qty')
  final double? completedQty;
  @JsonKey(name: 'actual_start_time')
  final String? actualStartTime;
  @JsonKey(name: 'actual_end_time')
  final String? actualEndTime;
  final String? description;

  WorkOrderOperation({
    this.name,
    required this.operation,
    this.workstation,
    this.sequenceId,
    this.status,
    this.timeInMins,
    this.actualOperationTime,
    this.completedQty,
    this.actualStartTime,
    this.actualEndTime,
    this.description,
  });

  factory WorkOrderOperation.fromJson(Map<String, dynamic> json) => _$WorkOrderOperationFromJson(json);
  Map<String, dynamic> toJson() => _$WorkOrderOperationToJson(this);
}
