import 'package:equatable/equatable.dart';

/// Domain entity for Serial and Batch Bundle
class SerialAndBatchBundle extends Equatable {
  final String? name;
  final String? owner;
  final DateTime? creation;
  final DateTime? modified;
  final int? docstatus;
  final String itemCode;
  final String? warehouse;
  final String voucherType;
  final String? voucherNo;
  final String? voucherDetailNo;
  final String? company;
  final double totalQty;
  final double? totalAmount;
  final double? avgRate;
  final DateTime? postingDate;
  final String? postingTime;
  final List<SerialAndBatchEntry> entries;
  final bool? isCancelled;
  final bool? isRejected;

  const SerialAndBatchBundle({
    this.name,
    this.owner,
    this.creation,
    this.modified,
    this.docstatus,
    required this.itemCode,
    this.warehouse,
    required this.voucherType,
    this.voucherNo,
    this.voucherDetailNo,
    this.company,
    required this.totalQty,
    this.totalAmount,
    this.avgRate,
    this.postingDate,
    this.postingTime,
    required this.entries,
    this.isCancelled,
    this.isRejected,
  });

  bool get isNew => name == null || name!.isEmpty;

  SerialAndBatchBundle copyWith({
    String? name,
    String? owner,
    DateTime? creation,
    DateTime? modified,
    int? docstatus,
    String? itemCode,
    String? warehouse,
    String? voucherType,
    String? voucherNo,
    String? voucherDetailNo,
    String? company,
    double? totalQty,
    double? totalAmount,
    double? avgRate,
    DateTime? postingDate,
    String? postingTime,
    List<SerialAndBatchEntry>? entries,
    bool? isCancelled,
    bool? isRejected,
  }) {
    return SerialAndBatchBundle(
      name: name ?? this.name,
      owner: owner ?? this.owner,
      creation: creation ?? this.creation,
      modified: modified ?? this.modified,
      docstatus: docstatus ?? this.docstatus,
      itemCode: itemCode ?? this.itemCode,
      warehouse: warehouse ?? this.warehouse,
      voucherType: voucherType ?? this.voucherType,
      voucherNo: voucherNo ?? this.voucherNo,
      voucherDetailNo: voucherDetailNo ?? this.voucherDetailNo,
      company: company ?? this.company,
      totalQty: totalQty ?? this.totalQty,
      totalAmount: totalAmount ?? this.totalAmount,
      avgRate: avgRate ?? this.avgRate,
      postingDate: postingDate ?? this.postingDate,
      postingTime: postingTime ?? this.postingTime,
      entries: entries ?? this.entries,
      isCancelled: isCancelled ?? this.isCancelled,
      isRejected: isRejected ?? this.isRejected,
    );
  }

  @override
  List<Object?> get props => [name, itemCode, totalQty, entries];
}

/// Domain entity for Serial and Batch Entry
class SerialAndBatchEntry extends Equatable {
  final String? name;
  final int? idx;
  final String? serialNo;
  final String? batchNo;
  final double qty;
  final String? warehouse;
  final double? incomingRate;

  const SerialAndBatchEntry({
    this.name,
    this.idx,
    this.serialNo,
    this.batchNo,
    required this.qty,
    this.warehouse,
    this.incomingRate,
  });

  bool get isSerial => serialNo != null && serialNo!.isNotEmpty;
  bool get isBatch => batchNo != null && batchNo!.isNotEmpty;

  SerialAndBatchEntry copyWith({
    String? name,
    int? idx,
    String? serialNo,
    String? batchNo,
    double? qty,
    String? warehouse,
    double? incomingRate,
  }) {
    return SerialAndBatchEntry(
      name: name ?? this.name,
      idx: idx ?? this.idx,
      serialNo: serialNo ?? this.serialNo,
      batchNo: batchNo ?? this.batchNo,
      qty: qty ?? this.qty,
      warehouse: warehouse ?? this.warehouse,
      incomingRate: incomingRate ?? this.incomingRate,
    );
  }

  @override
  List<Object?> get props => [name, serialNo, batchNo, qty];
}
