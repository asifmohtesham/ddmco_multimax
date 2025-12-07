class PurchaseOrder {
  final String name;
  final String supplier;
  final String transactionDate;
  final double grandTotal;
  final String currency;
  final String status;
  final int docstatus;
  final String modified;
  final String creation;
  final List<PurchaseOrderItem> items;

  PurchaseOrder({
    required this.name,
    required this.supplier,
    required this.transactionDate,
    required this.grandTotal,
    required this.currency,
    required this.status,
    required this.docstatus,
    required this.modified,
    required this.creation,
    required this.items,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PurchaseOrderItem> items = itemsList.map((i) => PurchaseOrderItem.fromJson(i)).toList();

    return PurchaseOrder(
      name: json['name'] ?? '',
      supplier: json['supplier'] ?? '',
      transactionDate: json['transaction_date'] ?? '',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'USD',
      status: json['status'] ?? 'Draft',
      docstatus: json['docstatus'] as int? ?? 0,
      modified: json['modified'] ?? '',
      creation: json['creation'] ?? '',
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'supplier': supplier,
      'transaction_date': transactionDate,
      'currency': currency,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}

class PurchaseOrderItem {
  final String? name; // name is null for new items
  final String itemCode;
  final String itemName;
  final double qty;
  final double receivedQty;
  final double rate;
  final double amount;
  final String? uom;
  final String? description;

  PurchaseOrderItem({
    this.name,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.receivedQty,
    required this.rate,
    required this.amount,
    this.uom,
    this.description,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      name: json['name'],
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      receivedQty: (json['received_qty'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      uom: json['uom'],
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'qty': qty,
      'rate': rate,
      'uom': uom,
      'description': description,
    };
    if (name != null) data['name'] = name;
    return data;
  }
}