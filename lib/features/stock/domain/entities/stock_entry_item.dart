import 'package:equatable/equatable.dart';

/// Domain entity for Stock Entry Item
class StockEntryItem extends Equatable {
  final String? name;
  final String? owner;
  final DateTime? creation;
  final DateTime? modified;
  final String? modifiedBy;
  final int? docstatus;
  final int? idx;
  final String itemCode;
  final String? itemName;
  final String? description;
  final String? itemGroup;
  final String? imageUrl;
  final double qty;
  final String? uom;
  final String? stockUom;
  final double? conversionFactor;
  final double? transferQty;
  final String? sWarehouse; // Source warehouse
  final String? tWarehouse; // Target warehouse
  final String? serialAndBatchBundle;
  final String? batchNo; // Legacy single batch field
  final String? customSourceRack;
  final String? customTargetRack;
  final double? basicRate;
  final double? basicAmount;
  final double? valuationRate;
  final double? amount;
  final bool? allowZeroValuationRate;
  final String? expenseAccount;
  final String? costCenter;
  final String? actualQty;
  final String? transferredQty;
  final bool? isFinishedItem;
  final bool? isScrapItem;

  const StockEntryItem({
    this.name,
    this.owner,
    this.creation,
    this.modified,
    this.modifiedBy,
    this.docstatus,
    this.idx,
    required this.itemCode,
    this.itemName,
    this.description,
    this.itemGroup,
    this.imageUrl,
    required this.qty,
    this.uom,
    this.stockUom,
    this.conversionFactor,
    this.transferQty,
    this.sWarehouse,
    this.tWarehouse,
    this.serialAndBatchBundle,
    this.batchNo,
    this.customSourceRack,
    this.customTargetRack,
    this.basicRate,
    this.basicAmount,
    this.valuationRate,
    this.amount,
    this.allowZeroValuationRate,
    this.expenseAccount,
    this.costCenter,
    this.actualQty,
    this.transferredQty,
    this.isFinishedItem,
    this.isScrapItem,
  });

  bool get isNew => name == null || name!.isEmpty;
  bool get hasBatchBundle => serialAndBatchBundle != null && serialAndBatchBundle!.isNotEmpty;
  bool get hasLegacyBatch => batchNo != null && batchNo!.isNotEmpty;

  StockEntryItem copyWith({
    String? name,
    String? owner,
    DateTime? creation,
    DateTime? modified,
    String? modifiedBy,
    int? docstatus,
    int? idx,
    String? itemCode,
    String? itemName,
    String? description,
    String? itemGroup,
    String? imageUrl,
    double? qty,
    String? uom,
    String? stockUom,
    double? conversionFactor,
    double? transferQty,
    String? sWarehouse,
    String? tWarehouse,
    String? serialAndBatchBundle,
    String? batchNo,
    String? customSourceRack,
    String? customTargetRack,
    double? basicRate,
    double? basicAmount,
    double? valuationRate,
    double? amount,
    bool? allowZeroValuationRate,
    String? expenseAccount,
    String? costCenter,
    String? actualQty,
    String? transferredQty,
    bool? isFinishedItem,
    bool? isScrapItem,
  }) {
    return StockEntryItem(
      name: name ?? this.name,
      owner: owner ?? this.owner,
      creation: creation ?? this.creation,
      modified: modified ?? this.modified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      docstatus: docstatus ?? this.docstatus,
      idx: idx ?? this.idx,
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      description: description ?? this.description,
      itemGroup: itemGroup ?? this.itemGroup,
      imageUrl: imageUrl ?? this.imageUrl,
      qty: qty ?? this.qty,
      uom: uom ?? this.uom,
      stockUom: stockUom ?? this.stockUom,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      transferQty: transferQty ?? this.transferQty,
      sWarehouse: sWarehouse ?? this.sWarehouse,
      tWarehouse: tWarehouse ?? this.tWarehouse,
      serialAndBatchBundle: serialAndBatchBundle ?? this.serialAndBatchBundle,
      batchNo: batchNo ?? this.batchNo,
      customSourceRack: customSourceRack ?? this.customSourceRack,
      customTargetRack: customTargetRack ?? this.customTargetRack,
      basicRate: basicRate ?? this.basicRate,
      basicAmount: basicAmount ?? this.basicAmount,
      valuationRate: valuationRate ?? this.valuationRate,
      amount: amount ?? this.amount,
      allowZeroValuationRate: allowZeroValuationRate ?? this.allowZeroValuationRate,
      expenseAccount: expenseAccount ?? this.expenseAccount,
      costCenter: costCenter ?? this.costCenter,
      actualQty: actualQty ?? this.actualQty,
      transferredQty: transferredQty ?? this.transferredQty,
      isFinishedItem: isFinishedItem ?? this.isFinishedItem,
      isScrapItem: isScrapItem ?? this.isScrapItem,
    );
  }

  @override
  List<Object?> get props => [
        name,
        itemCode,
        qty,
        sWarehouse,
        tWarehouse,
      ];
}
