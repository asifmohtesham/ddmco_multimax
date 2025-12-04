class PurchaseReceipt {
  final String name;
  final String supplier;
  final double grandTotal;
  final String postingDate;
  final String modified;
  final String creation; // Added
  final String status;
  final String currency;
  final List<PurchaseReceiptItem> items;

  PurchaseReceipt({
    required this.name,
    required this.supplier,
    required this.grandTotal,
    required this.postingDate,
    required this.modified,
    required this.creation,
    required this.status,
    required this.currency,
    required this.items,
  });

  factory PurchaseReceipt.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PurchaseReceiptItem> items = itemsList.map((i) => PurchaseReceiptItem.fromJson(i)).toList();

    return PurchaseReceipt(
      name: json['name'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(), // Added
      supplier: json['supplier'] ?? '',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      postingDate: json['posting_date'] ?? '',
      modified: json['modified'] ?? '',
      status: json['status'] ?? 'Draft',
      currency: json['currency'] ?? 'USD',
      items: items,
    );
  }
}

class PurchaseReceiptItem {
  final String itemCode;
  final String? itemName;
  final double qty;
  final double rate;
  final String? batchNo;
  final String? rack;

  PurchaseReceiptItem({
    required this.itemCode,
    this.itemName,
    required this.qty,
    required this.rate,
    this.batchNo,
    this.rack,
  });

  factory PurchaseReceiptItem.fromJson(Map<String, dynamic> json) {
    return PurchaseReceiptItem(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'],
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      batchNo: json['batch_no'],
      rack: json['rack'],
    );
  }
}
