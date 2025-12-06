class PurchaseOrder {
  final String name;
  final String supplier;
  final String transactionDate;
  final double grandTotal;
  final String currency;
  final String status;
  final List<PurchaseOrderItem> items;

  PurchaseOrder({
    required this.name,
    required this.supplier,
    required this.transactionDate,
    required this.grandTotal,
    required this.currency,
    required this.status,
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
      status: json['status'] ?? '',
      items: items,
    );
  }
}

class PurchaseOrderItem {
  final String name; // Unique ID of the row
  final String itemCode;
  final String itemName;
  final double qty;
  final double receivedQty;
  final double rate;

  PurchaseOrderItem({
    required this.name,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.receivedQty,
    required this.rate,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      name: json['name'] ?? '',
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      receivedQty: (json['received_qty'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
