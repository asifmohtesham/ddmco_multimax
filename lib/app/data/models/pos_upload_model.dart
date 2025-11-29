class PosUpload {
  final String name;
  final String customer;
  final String date;
  final String modified;
  final String status;
  final double? totalAmount;
  final int? totalQty;
  final List<PosUploadItem> items;

  PosUpload({
    required this.name,
    required this.customer,
    required this.date,
    required this.modified,
    required this.status,
    this.totalAmount,
    this.totalQty,
    required this.items,
  });

  factory PosUpload.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PosUploadItem> items = itemsList.map((i) => PosUploadItem.fromJson(i)).toList();

    // Directly use the 'status' field from JSON, default to 'Pending' if null/empty
    final String docStatus = json['status'] ?? 'Pending';

    return PosUpload(
      name: json['name'] ?? '',
      customer: json['customer'] ?? '',
      date: json['date'] ?? '',
      modified: json['modified'] ?? '',
      status: docStatus,
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      totalQty: (json['total_qty'] as num?)?.toInt(),
      items: items,
    );
  }
}

class PosUploadItem {
  final String itemName;
  final double quantity;
  final double rate;
  final double amount;

  PosUploadItem({
    required this.itemName,
    required this.quantity,
    required this.rate,
    required this.amount,
  });

  factory PosUploadItem.fromJson(Map<String, dynamic> json) {
    return PosUploadItem(
      itemName: json['item_name'] ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      rate: (json['rate'] as num? ?? 0).toDouble(),
      amount: (json['amount'] as num? ?? 0).toDouble(),
    );
  }
}
