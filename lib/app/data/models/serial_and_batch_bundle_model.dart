class SerialAndBatchBundle {
  final String name;
  final String itemCode;
  final String warehouse;
  final String typeOfTransaction; // 'Inward' or 'Outward'
  final double totalQty;
  final List<SerialAndBatchEntry> entries;
  // --- NEW FIELDS ---
  final String? voucherType;
  final String? voucherNo;
  final String? company;

  SerialAndBatchBundle({
    required this.name,
    required this.itemCode,
    required this.warehouse,
    required this.typeOfTransaction,
    required this.totalQty,
    required this.entries,
    this.voucherType,
    this.voucherNo,
    this.company,
  });

  factory SerialAndBatchBundle.fromJson(Map<String, dynamic> json) {
    var list = json['entries'] as List? ?? [];
    List<SerialAndBatchEntry> entriesList = list.map((i) => SerialAndBatchEntry.fromJson(i)).toList();

    return SerialAndBatchBundle(
      name: json['name'] ?? '',
      itemCode: json['item_code'] ?? '',
      warehouse: json['warehouse'] ?? '',
      typeOfTransaction: json['type_of_transaction'] ?? 'Inward',
      totalQty: (json['total_qty'] as num?)?.toDouble() ?? 0.0,
      entries: entriesList,
      voucherType: json['voucher_type'],
      voucherNo: json['voucher_no'],
      company: json['company'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'warehouse': warehouse,
      'type_of_transaction': typeOfTransaction,
      'total_qty': totalQty,
      'entries': entries.map((e) => e.toJson()).toList(),
      // Send new fields
      'voucher_type': voucherType,
      'company': company,
    };

    // Only include voucher_no if it exists (to avoid issues with new/unsaved docs)
    if (voucherNo != null && voucherNo!.isNotEmpty) {
      data['voucher_no'] = voucherNo;
    }

    return data;
  }
}

class SerialAndBatchEntry {
  final String batchNo;
  final double qty;
  final String? serialNo;

  SerialAndBatchEntry({
    required this.batchNo,
    required this.qty,
    this.serialNo,
  });

  factory SerialAndBatchEntry.fromJson(Map<String, dynamic> json) {
    return SerialAndBatchEntry(
      batchNo: json['batch_no'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      serialNo: json['serial_no'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batch_no': batchNo,
      'qty': qty,
      'serial_no': serialNo,
    };
  }
}