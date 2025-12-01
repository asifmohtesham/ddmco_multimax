class PosUpload {
  final String name;
  final String customer;
  final String date;
  final String status;
  final double? totalAmount;
  final double? totalQty;
  final String modified;
  final List<PosUploadItem> items;

  PosUpload({
    required this.name,
    required this.customer,
    required this.date,
    required this.status,
    this.totalAmount,
    this.totalQty,
    required this.modified,
    required this.items,
  });

  factory PosUpload.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PosUploadItem> items = itemsList.map((i) => PosUploadItem.fromJson(i)).toList();

    return PosUpload(
      name: json['name'],
      customer: json['customer'],
      date: json['date'],
      status: json['status'],
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      totalQty: (json['total_quantity'] as num?)?.toDouble(),
      modified: json['modified'] ?? '',
      items: items,
    );
  }
}

class PosUploadItem {
  final int idx;
  final String itemName;
  final double quantity;
  final double rate;
  final double amount;

  PosUploadItem({
    required this.idx,
    required this.itemName,
    required this.quantity,
    required this.rate,
    required this.amount,
  });

  factory PosUploadItem.fromJson(Map<String, dynamic> json) {
    return PosUploadItem(
      idx: json['idx'] ?? 0,
      itemName: json['item_name'] ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
