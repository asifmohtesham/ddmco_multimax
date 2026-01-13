class SerialAndBatchBundle {
  String? name;
  final String itemCode;
  final String warehouse;
  final String? typeOfTransaction;
  final String? voucherType;
  final String? voucherNo;
  final String? voucherDetailNo;
  final String? company;
  final double totalQty;
  final int isCancelled;
  final int isRejected;
  final int docstatus;
  final List<SerialAndBatchEntry> entries;

  SerialAndBatchBundle({
    this.name,
    required this.itemCode,
    required this.warehouse,
    this.typeOfTransaction,
    this.voucherType,
    this.voucherNo,
    this.voucherDetailNo,
    this.company,
    this.totalQty = 0.0,
    this.isCancelled = 0,
    this.isRejected = 0,
    this.docstatus = 0,
    required this.entries,
  });

  factory SerialAndBatchBundle.fromJson(Map<String, dynamic> json) {
    var entriesList = json['entries'] as List? ?? [];
    List<SerialAndBatchEntry> entries = entriesList.map((i) => SerialAndBatchEntry.fromJson(i)).toList();

    return SerialAndBatchBundle(
      name: json['name']?.toString(),
      itemCode: json['item_code']?.toString() ?? '',
      warehouse: json['warehouse']?.toString() ?? '',
      typeOfTransaction: json['type_of_transaction']?.toString(),
      voucherType: json['voucher_type']?.toString(),
      voucherNo: json['voucher_no']?.toString(),
      voucherDetailNo: json['voucher_detail_no']?.toString(),
      company: json['company']?.toString(),
      totalQty: double.tryParse(json['total_qty']?.toString() ?? '0') ?? 0.0,
      isCancelled: int.tryParse(json['is_cancelled']?.toString() ?? '0') ?? 0,
      isRejected: int.tryParse(json['is_rejected']?.toString() ?? '0') ?? 0,
      docstatus: int.tryParse(json['docstatus']?.toString() ?? '0') ?? 0,
      entries: entries,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'warehouse': warehouse,
      'total_qty': totalQty,
      'entries': entries.map((e) => e.toJson()).toList(),
    };

    if (name != null) data['name'] = name;
    if (typeOfTransaction != null) data['type_of_transaction'] = typeOfTransaction;
    if (voucherType != null) data['voucher_type'] = voucherType;
    if (voucherNo != null) data['voucher_no'] = voucherNo;
    if (voucherDetailNo != null) data['voucher_detail_no'] = voucherDetailNo;
    if (company != null) data['company'] = company;
    data['is_cancelled'] = isCancelled;
    data['is_rejected'] = isRejected;
    data['docstatus'] = docstatus;

    return data;
  }
}

class SerialAndBatchEntry {
  String? batchNo;
  String? serialNo;
  String? warehouse;
  double qty;
  String? incomingRate;

  SerialAndBatchEntry({
    this.batchNo,
    this.serialNo,
    this.warehouse,
    required this.qty,
    this.incomingRate,
  });

  factory SerialAndBatchEntry.fromJson(Map<String, dynamic> json) {
    return SerialAndBatchEntry(
      batchNo: json['batch_no']?.toString(),
      serialNo: json['serial_no']?.toString(),
      warehouse: json['warehouse']?.toString(),
      qty: double.tryParse(json['qty']?.toString() ?? '0') ?? 0.0,
      incomingRate: json['incoming_rate']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {'qty': qty};
    if (batchNo != null) data['batch_no'] = batchNo;
    if (serialNo != null) data['serial_no'] = serialNo;
    if (warehouse != null) data['warehouse'] = warehouse;
    if (incomingRate != null) data['incoming_rate'] = incomingRate;
    return data;
  }
}