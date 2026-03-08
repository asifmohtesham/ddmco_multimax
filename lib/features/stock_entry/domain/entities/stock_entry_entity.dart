import 'package:equatable/equatable.dart';

/// Domain entity for Stock Entry
/// Contains only business logic, no framework dependencies
class StockEntryEntity extends Equatable {
  final String name;
  final String purpose;
  final double totalAmount;
  final String postingDate;
  final String modified;
  final String creation;
  final String status;
  final int docstatus;
  final String? owner;
  final String? modifiedBy;
  final String? stockEntryType;
  final String? postingTime;
  final String? fromWarehouse;
  final String? toWarehouse;
  final double? customTotalQty;
  final String? customReferenceNo;
  final String currency;
  final List<StockEntryItemEntity> items;

  const StockEntryEntity({
    required this.name,
    required this.purpose,
    required this.totalAmount,
    required this.postingDate,
    required this.modified,
    required this.creation,
    required this.status,
    required this.docstatus,
    this.owner,
    this.modifiedBy,
    this.stockEntryType,
    this.postingTime,
    this.fromWarehouse,
    this.toWarehouse,
    this.customTotalQty,
    this.customReferenceNo,
    required this.currency,
    required this.items,
  });

  bool get isDraft => docstatus == 0;
  bool get isSubmitted => docstatus == 1;
  bool get isCancelled => docstatus == 2;

  @override
  List<Object?> get props => [
        name,
        purpose,
        totalAmount,
        postingDate,
        modified,
        status,
        docstatus,
        items,
      ];
}

class StockEntryItemEntity extends Equatable {
  final String? name;
  final String itemCode;
  final double qty;
  final double basicRate;
  final String? itemGroup;
  final String? customVariantOf;
  final String? batchNo;
  final String? itemName;
  final String? rack;
  final String? toRack;
  final String? sWarehouse;
  final String? tWarehouse;
  final String? customInvoiceSerialNumber;
  final String? serialAndBatchBundle;
  final int? useSerialBatchFields;
  final String? materialRequest;
  final String? materialRequestItem;

  const StockEntryItemEntity({
    this.name,
    required this.itemCode,
    required this.qty,
    required this.basicRate,
    this.itemGroup,
    this.customVariantOf,
    this.batchNo,
    this.itemName,
    this.rack,
    this.toRack,
    this.sWarehouse,
    this.tWarehouse,
    this.customInvoiceSerialNumber,
    this.serialAndBatchBundle,
    this.useSerialBatchFields,
    this.materialRequest,
    this.materialRequestItem,
  });

  double get totalValue => qty * basicRate;
  bool get hasBatch => batchNo != null && batchNo!.isNotEmpty;
  bool get hasBundle => serialAndBatchBundle != null && serialAndBatchBundle!.isNotEmpty;

  @override
  List<Object?> get props => [
        name,
        itemCode,
        qty,
        basicRate,
        sWarehouse,
        tWarehouse,
      ];
}

class SerialBatchBundleEntity extends Equatable {
  final String? name;
  final String itemCode;
  final String warehouse;
  final double totalQty;
  final List<SerialBatchEntryEntity> entries;

  const SerialBatchBundleEntity({
    this.name,
    required this.itemCode,
    required this.warehouse,
    required this.totalQty,
    required this.entries,
  });

  bool get hasEntries => entries.isNotEmpty;
  int get entryCount => entries.length;

  @override
  List<Object?> get props => [name, itemCode, warehouse, totalQty, entries];
}

class SerialBatchEntryEntity extends Equatable {
  final String? batchNo;
  final String? serialNo;
  final double qty;

  const SerialBatchEntryEntity({
    this.batchNo,
    this.serialNo,
    required this.qty,
  });

  bool get isBatch => batchNo != null && batchNo!.isNotEmpty;
  bool get isSerial => serialNo != null && serialNo!.isNotEmpty;

  @override
  List<Object?> get props => [batchNo, serialNo, qty];
}
