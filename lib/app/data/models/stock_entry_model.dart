import 'dart:developer';

class StockEntry {
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
  final List<StockEntryItem> items;

  StockEntry({
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

  factory StockEntry.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<StockEntryItem> items = itemsList.map((i) => StockEntryItem.fromJson(i)).toList();

    return StockEntry(
      name: json['name']?.toString() ?? 'No Name',
      purpose: json['purpose']?.toString() ?? 'No Purpose',
      totalAmount: _parseDouble(json['total_amount']),
      postingDate: json['posting_date']?.toString() ?? '',
      modified: json['modified']?.toString() ?? '',
      creation: json['creation']?.toString() ?? DateTime.now().toString(),
      docstatus: _parseInt(json['docstatus']),
      status: _getStatusFromDocstatus(_parseInt(json['docstatus'])),
      owner: json['owner']?.toString(),
      modifiedBy: json['modified_by']?.toString(),
      stockEntryType: json['stock_entry_type']?.toString(),
      postingTime: json['posting_time']?.toString(),
      fromWarehouse: json['from_warehouse']?.toString(),
      toWarehouse: json['to_warehouse']?.toString(),
      customTotalQty: _parseDoubleNullable(json['custom_total_qty']),
      customReferenceNo: json['custom_reference_no']?.toString(),
      currency: json['currency']?.toString() ?? 'AED',
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stock_entry_type': stockEntryType,
      'posting_date': postingDate,
      'posting_time': postingTime,
      'from_warehouse': fromWarehouse,
      'to_warehouse': toWarehouse,
      'custom_reference_no': customReferenceNo,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }

  static String _getStatusFromDocstatus(int docstatus) {
    switch (docstatus) {
      case 0: return 'Draft';
      case 1: return 'Submitted';
      case 2: return 'Cancelled';
      default: return 'Unknown';
    }
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double? _parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return value.isEmpty ? null : double.tryParse(value);
    return null;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class StockEntryItem {
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
  // Link Fields
  final String? materialRequest;
  final String? materialRequestItem;
  // Metadata Fields
  final String? owner;
  final String? creation;
  final String? modified;
  final String? modifiedBy;

  StockEntryItem({
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
    this.owner,
    this.creation,
    this.modified,
    this.modifiedBy,
  });

  factory StockEntryItem.fromJson(Map<String, dynamic> json) {
    return StockEntryItem(
      name: json['name']?.toString(),
      itemCode: json['item_code']?.toString() ?? '',
      qty: StockEntry._parseDouble(json['qty']),
      basicRate: StockEntry._parseDouble(json['basic_rate']),
      itemGroup: json['item_group']?.toString(),
      customVariantOf: json['custom_variant_of']?.toString(),
      batchNo: json['batch_no']?.toString(),
      itemName: json['item_name']?.toString(),
      rack: json['rack']?.toString(),
      toRack: json['to_rack']?.toString(),
      sWarehouse: json['s_warehouse']?.toString(),
      tWarehouse: json['t_warehouse']?.toString(),
      customInvoiceSerialNumber: json['custom_invoice_serial_number']?.toString(),
      serialAndBatchBundle: json['serial_and_batch_bundle']?.toString(),
      useSerialBatchFields: StockEntry._parseInt(json['use_serial_batch_fields']),
      materialRequest: json['material_request']?.toString(),
      materialRequestItem: json['material_request_item']?.toString(),
      owner: json['owner']?.toString(),
      creation: json['creation']?.toString(),
      modified: json['modified']?.toString(),
      modifiedBy: json['modified_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'qty': qty,
      'basic_rate': basicRate,
      'batch_no': batchNo,
      's_warehouse': sWarehouse,
      't_warehouse': tWarehouse,
      'rack': rack,
      'to_rack': toRack,
      'custom_invoice_serial_number': customInvoiceSerialNumber,
      'serial_and_batch_bundle': serialAndBatchBundle,
      'use_serial_batch_fields': useSerialBatchFields,
      'material_request': materialRequest,
      'material_request_item': materialRequestItem,
    };
    if (name != null) {
      data['name'] = name;
    }
    return data;
  }
}

class SerialAndBatchBundle {
  final String? name;
  final String itemCode;
  final String warehouse;
  final String? typeOfTransaction;
  final String? voucherType;
  final String? voucherNo;
  final String? voucherDetailNo;
  final String? company;
  final double totalQty;
  final double totalAmount;
  final double avgRate;
  final int isCancelled;
  final int isRejected;
  final String? postingDate;
  final String? postingTime;
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
    this.totalAmount = 0.0,
    this.avgRate = 0.0,
    this.isCancelled = 0,
    this.isRejected = 0,
    this.postingDate,
    this.postingTime,
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
      totalQty: StockEntry._parseDouble(json['total_qty']),
      totalAmount: StockEntry._parseDouble(json['total_amount']),
      avgRate: StockEntry._parseDouble(json['avg_rate']),
      isCancelled: StockEntry._parseInt(json['is_cancelled']),
      isRejected: StockEntry._parseInt(json['is_rejected']),
      postingDate: json['posting_date']?.toString(),
      postingTime: json['posting_time']?.toString(),
      docstatus: StockEntry._parseInt(json['docstatus']),
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

    // Optional fields mapping
    if (name != null) data['name'] = name;
    if (typeOfTransaction != null) data['type_of_transaction'] = typeOfTransaction;
    if (voucherType != null) data['voucher_type'] = voucherType;
    if (voucherNo != null) data['voucher_no'] = voucherNo;
    if (voucherDetailNo != null) data['voucher_detail_no'] = voucherDetailNo;
    if (company != null) data['company'] = company;
    if (postingDate != null) data['posting_date'] = postingDate;
    if (postingTime != null) data['posting_time'] = postingTime;

    data['is_cancelled'] = isCancelled;
    data['is_rejected'] = isRejected;
    data['docstatus'] = docstatus;

    return data;
  }
}

class SerialAndBatchEntry {
  final String? batchNo;
  final String? serialNo;
  final String? warehouse;
  final double qty;
  final String? incomingRate;

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
      qty: StockEntry._parseDouble(json['qty']),
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