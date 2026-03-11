// Bill of Materials Model - ERPNext Compliant
import 'package:json_annotation/json_annotation.dart';

part 'bom_model.g.dart';

@JsonSerializable()
class BomModel {
  final String name;
  @JsonKey(name: 'item')
  final String itemCode;
  @JsonKey(name: 'item_name')
  final String? itemName;
  final String? description;
  final double quantity;
  final String? uom;
  final String? company;
  final String? currency;
  @JsonKey(name: 'is_active')
  final int isActive;
  @JsonKey(name: 'is_default')
  final int isDefault;
  @JsonKey(name: 'with_operations')
  final int withOperations;
  @JsonKey(name: 'transfer_material_against')
  final String? transferMaterialAgainst;
  final List<BomItem>? items;
  final List<BomOperation>? operations;
  @JsonKey(name: 'scrap_items')
  final List<BomScrapItem>? scrapItems;
  @JsonKey(name: 'total_cost')
  final double? totalCost;
  @JsonKey(name: 'raw_material_cost')
  final double? rawMaterialCost;
  @JsonKey(name: 'operating_cost')
  final double? operatingCost;
  @JsonKey(name: 'scrap_material_cost')
  final double? scrapMaterialCost;
  final String? image;
  final String? modified;
  final String? creation;

  BomModel({
    required this.name,
    required this.itemCode,
    this.itemName,
    this.description,
    required this.quantity,
    this.uom,
    this.company,
    this.currency,
    this.isActive = 1,
    this.isDefault = 0,
    this.withOperations = 0,
    this.transferMaterialAgainst,
    this.items,
    this.operations,
    this.scrapItems,
    this.totalCost,
    this.rawMaterialCost,
    this.operatingCost,
    this.scrapMaterialCost,
    this.image,
    this.modified,
    this.creation,
  });

  factory BomModel.fromJson(Map<String, dynamic> json) => _$BomModelFromJson(json);
  Map<String, dynamic> toJson() => _$BomModelToJson(this);
}

@JsonSerializable()
class BomItem {
  final String? name;
  @JsonKey(name: 'item_code')
  final String itemCode;
  @JsonKey(name: 'item_name')
  final String? itemName;
  final String? description;
  final String? image;
  final double qty;
  final String? uom;
  @JsonKey(name: 'stock_qty')
  final double? stockQty;
  @JsonKey(name: 'stock_uom')
  final String? stockUom;
  final double? rate;
  final double? amount;
  @JsonKey(name: 'bom_no')
  final String? bomNo;
  @JsonKey(name: 'source_warehouse')
  final String? sourceWarehouse;
  final String? operation;
  @JsonKey(name: 'include_item_in_manufacturing')
  final int? includeItemInManufacturing;

  BomItem({
    this.name,
    required this.itemCode,
    this.itemName,
    this.description,
    this.image,
    required this.qty,
    this.uom,
    this.stockQty,
    this.stockUom,
    this.rate,
    this.amount,
    this.bomNo,
    this.sourceWarehouse,
    this.operation,
    this.includeItemInManufacturing,
  });

  factory BomItem.fromJson(Map<String, dynamic> json) => _$BomItemFromJson(json);
  Map<String, dynamic> toJson() => _$BomItemToJson(this);
}

@JsonSerializable()
class BomOperation {
  final String? name;
  final String operation;
  final String? workstation;
  @JsonKey(name: 'workstation_type')
  final String? workstationType;
  final String? description;
  @JsonKey(name: 'time_in_mins')
  final double? timeInMins;
  @JsonKey(name: 'batch_size')
  final double? batchSize;
  @JsonKey(name: 'operating_cost')
  final double? operatingCost;
  @JsonKey(name: 'hour_rate')
  final double? hourRate;
  @JsonKey(name: 'sequence_id')
  final int? sequenceId;

  BomOperation({
    this.name,
    required this.operation,
    this.workstation,
    this.workstationType,
    this.description,
    this.timeInMins,
    this.batchSize,
    this.operatingCost,
    this.hourRate,
    this.sequenceId,
  });

  factory BomOperation.fromJson(Map<String, dynamic> json) => _$BomOperationFromJson(json);
  Map<String, dynamic> toJson() => _$BomOperationToJson(this);
}

@JsonSerializable()
class BomScrapItem {
  final String? name;
  @JsonKey(name: 'item_code')
  final String itemCode;
  @JsonKey(name: 'item_name')
  final String? itemName;
  @JsonKey(name: 'stock_qty')
  final double stockQty;
  @JsonKey(name: 'stock_uom')
  final String? stockUom;
  final double? rate;
  final double? amount;

  BomScrapItem({
    this.name,
    required this.itemCode,
    this.itemName,
    required this.stockQty,
    this.stockUom,
    this.rate,
    this.amount,
  });

  factory BomScrapItem.fromJson(Map<String, dynamic> json) => _$BomScrapItemFromJson(json);
  Map<String, dynamic> toJson() => _$BomScrapItemToJson(this);
}
