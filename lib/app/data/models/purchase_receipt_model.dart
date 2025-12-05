class PurchaseReceipt {
  final String name;
  final String supplier;
  final double grandTotal;
  final String postingDate;
  final String? postingTime;
  final String modified;
  final String creation; // Added
  final String status;
  final int docstatus;
  final String? owner;
  final String currency;
  final String? setWarehouse;
  final List<PurchaseReceiptItem> items;

  PurchaseReceipt({
    required this.name,
    required this.supplier,
    required this.grandTotal,
    required this.postingDate,
    required this.postingTime,
    required this.modified,
    required this.creation,
    required this.status,
    required this.docstatus,
    required this.owner,
    this.setWarehouse,
    required this.currency,
    required this.items,
  });

  factory PurchaseReceipt.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PurchaseReceiptItem> items = itemsList.map((i) => PurchaseReceiptItem.fromJson(i)).toList();

    return PurchaseReceipt(
      name: json['name'] ?? '',
      owner: json['owner'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(), // Added
      docstatus: json['docstatus'] as int? ?? 0,
      supplier: json['supplier'] ?? '',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      postingDate: json['posting_date'] ?? '',
      postingTime: json['posting_time'] ?? '',
      modified: json['modified'] ?? '',
      status: json['status'] ?? 'Draft',
      currency: json['currency'] ?? 'USD',
      items: items,
    );
  }
}

class PurchaseReceiptItem {
  final String? name;
  final String itemCode;
  final String? variantOf;
  final String? itemGroup;
  final String? itemName;
  final double qty;
  final String? batchNo;
  final String? rack;
  final String? warehouse;

  PurchaseReceiptItem({
    this.name,
    required this.itemCode,
    this.variantOf,
    this.itemGroup,
    this.itemName,
    required this.qty,
    this.batchNo,
    this.rack,
    required this.warehouse,
  });

  factory PurchaseReceiptItem.fromJson(Map<String, dynamic> json) {
    return PurchaseReceiptItem(
      name: json['name'] ?? '',
      itemCode: json['item_code'] ?? '',
      variantOf: json['variant_of'] ?? '',
      itemGroup: json['item_group'],
      itemName: json['item_name'],
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      batchNo: json['batch_no'],
      rack: json['rack'],
      warehouse: json['warehouse'],
    );
  }
}
