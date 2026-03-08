import 'package:equatable/equatable.dart';
import 'stock_entry_item.dart';

/// Domain entity for Stock Entry
class StockEntry extends Equatable {
  final String? name;
  final String? owner;
  final DateTime? creation;
  final DateTime? modified;
  final String? modifiedBy;
  final int? docstatus;
  final String? parent;
  final String? parentfield;
  final String? parenttype;
  final int? idx;
  final String namingSeries;
  final String stockEntryType;
  final String? purpose;
  final DateTime? postingDate;
  final String? postingTime;
  final String? company;
  final String? fromWarehouse;
  final String? toWarehouse;
  final String? fromBom;
  final String? bomNo;
  final String? workOrder;
  final String? purchaseOrder;
  final String? deliveryNoteNo;
  final String? salesInvoiceNo;
  final List<StockEntryItem> items;
  final String? remarks;
  final double? totalOutgoingValue;
  final double? totalIncomingValue;
  final double? valueAdjusted;
  final double? totalAmount;
  final bool? isCancelled;
  final bool? isRejected;

  const StockEntry({
    this.name,
    this.owner,
    this.creation,
    this.modified,
    this.modifiedBy,
    this.docstatus,
    this.parent,
    this.parentfield,
    this.parenttype,
    this.idx,
    required this.namingSeries,
    required this.stockEntryType,
    this.purpose,
    this.postingDate,
    this.postingTime,
    this.company,
    this.fromWarehouse,
    this.toWarehouse,
    this.fromBom,
    this.bomNo,
    this.workOrder,
    this.purchaseOrder,
    this.deliveryNoteNo,
    this.salesInvoiceNo,
    required this.items,
    this.remarks,
    this.totalOutgoingValue,
    this.totalIncomingValue,
    this.valueAdjusted,
    this.totalAmount,
    this.isCancelled,
    this.isRejected,
  });

  bool get isNew => name == null || name!.isEmpty;
  bool get isDraft => docstatus == 0;
  bool get isSubmitted => docstatus == 1;
  bool get isCanceled => docstatus == 2;

  StockEntry copyWith({
    String? name,
    String? owner,
    DateTime? creation,
    DateTime? modified,
    String? modifiedBy,
    int? docstatus,
    String? parent,
    String? parentfield,
    String? parenttype,
    int? idx,
    String? namingSeries,
    String? stockEntryType,
    String? purpose,
    DateTime? postingDate,
    String? postingTime,
    String? company,
    String? fromWarehouse,
    String? toWarehouse,
    String? fromBom,
    String? bomNo,
    String? workOrder,
    String? purchaseOrder,
    String? deliveryNoteNo,
    String? salesInvoiceNo,
    List<StockEntryItem>? items,
    String? remarks,
    double? totalOutgoingValue,
    double? totalIncomingValue,
    double? valueAdjusted,
    double? totalAmount,
    bool? isCancelled,
    bool? isRejected,
  }) {
    return StockEntry(
      name: name ?? this.name,
      owner: owner ?? this.owner,
      creation: creation ?? this.creation,
      modified: modified ?? this.modified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      docstatus: docstatus ?? this.docstatus,
      parent: parent ?? this.parent,
      parentfield: parentfield ?? this.parentfield,
      parenttype: parenttype ?? this.parenttype,
      idx: idx ?? this.idx,
      namingSeries: namingSeries ?? this.namingSeries,
      stockEntryType: stockEntryType ?? this.stockEntryType,
      purpose: purpose ?? this.purpose,
      postingDate: postingDate ?? this.postingDate,
      postingTime: postingTime ?? this.postingTime,
      company: company ?? this.company,
      fromWarehouse: fromWarehouse ?? this.fromWarehouse,
      toWarehouse: toWarehouse ?? this.toWarehouse,
      fromBom: fromBom ?? this.fromBom,
      bomNo: bomNo ?? this.bomNo,
      workOrder: workOrder ?? this.workOrder,
      purchaseOrder: purchaseOrder ?? this.purchaseOrder,
      deliveryNoteNo: deliveryNoteNo ?? this.deliveryNoteNo,
      salesInvoiceNo: salesInvoiceNo ?? this.salesInvoiceNo,
      items: items ?? this.items,
      remarks: remarks ?? this.remarks,
      totalOutgoingValue: totalOutgoingValue ?? this.totalOutgoingValue,
      totalIncomingValue: totalIncomingValue ?? this.totalIncomingValue,
      valueAdjusted: valueAdjusted ?? this.valueAdjusted,
      totalAmount: totalAmount ?? this.totalAmount,
      isCancelled: isCancelled ?? this.isCancelled,
      isRejected: isRejected ?? this.isRejected,
    );
  }

  @override
  List<Object?> get props => [
        name,
        docstatus,
        stockEntryType,
        postingDate,
        items,
      ];
}
