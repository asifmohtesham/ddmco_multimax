class PurchaseReceipt {
  final String name;
  final String? owner;
  final String creation; // Added
  final String modified;
  final String status;
  final int docstatus;
  final String supplier;
  final String postingDate;
  final String postingTime;
  final String? setWarehouse;
  final String currency;
  final double totalQty;
  final double grandTotal;
  final List<PurchaseReceiptItem> items;

  PurchaseReceipt({
    required this.name,
    required this.owner,
    required this.creation,
    required this.modified,
    required this.status,
    required this.docstatus,
    required this.postingDate,
    required this.postingTime,
    required this.supplier,
    this.setWarehouse,
    required this.currency,
    required this.totalQty,
    required this.grandTotal,
    required this.items,
  });

  factory PurchaseReceipt.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PurchaseReceiptItem> items = itemsList.map((i) => PurchaseReceiptItem.fromJson(i)).toList();

    return PurchaseReceipt(
      name: json['name'] ?? '',
      owner: json['owner'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(), // Added
      modified: json['modified'] ?? '',
      docstatus: json['docstatus'] as int? ?? 0,
      status: json['status'] ?? 'Draft',
      supplier: json['supplier'] ?? '',
      postingDate: json['posting_date'] ?? '',
      postingTime: json['posting_time'] ?? '',
      currency: json['currency'] ?? 'AED',
      setWarehouse: json['set_warehouse'],
      totalQty: json['total_qty'] ?? 0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      items: items,
    );
  }
}

class PurchaseReceiptItem {
  final String? name;
  final String owner;
  final String creation;
  final String? modified;
  final String? modifiedBy;
  final String itemCode;
  final String? itemName;
  final double qty;
  final double? rate;
  final String? batchNo;
  final String? rack;
  final String warehouse;
  final String? purchaseOrderItem; // Link to PO Item

  PurchaseReceiptItem({
    this.name,
    required this.owner,
    required this.creation,
    this.modified,
    this.modifiedBy,
    required this.itemCode,
    this.itemName,
    required this.qty,
    this.rate,
    this.batchNo,
    this.rack,
    required this.warehouse,
    this.purchaseOrderItem,
  });

  factory PurchaseReceiptItem.fromJson(Map<String, dynamic> json) {
    return PurchaseReceiptItem(
      name: json['name'],
      owner: json['owner'] ?? '',
      creation: json['creation'] ?? '',
      modified: json['modified'] ?? '',
      modifiedBy: json['modified_by'] ?? '',
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'],
      batchNo: json['batch_no'],
      rack: json['rack'],
      warehouse: json['warehouse'],
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      purchaseOrderItem: json['purchase_order_item'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'modified': modified,
      'modified_by': modifiedBy,
      'owner': owner,
      'creation': name,
      'item_code': itemCode,
      'qty': qty,
      'rate': rate,
      'batch_no': batchNo,
      'rack': rack,
      'purchase_order_item': purchaseOrderItem,
    };
  }
}
