class PosUpload {
  /// All status values a POS Upload can have, in ERPNext option order.
  /// Must be kept in sync with the ERPNext DocType so status dropdowns
  /// and filter chips never miss (or invent) a status.
  static const List<String> statusOptions = [
    'Draft',
    'Pending',
    'In Progress',
    'Completed',
    'Cancelled',
    'Submitted',
  ];

  final String name;
  final String customer;
  final String date;
  final String modified;
  final String creation;
  final String status;
  final double? totalAmount;
  final double? totalQty;
  final List<PosUploadItem> items;

  PosUpload({
    required this.name,
    required this.customer,
    required this.date,
    required this.modified,
    required this.creation,
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
      creation: json['creation'] ?? '',
      status: docStatus,
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      totalQty: (json['total_qty'] as num?)?.toDouble(), // Corrected field name? usually total_qty
      items: items,
    );
  }
}

class PosUploadItem {
  final int idx;
  final String refCode;
  final String itemName;
  final double quantity;
  final double rate;
  final double amount;

  PosUploadItem({
    required this.idx,
    this.refCode = '',
    required this.itemName,
    required this.quantity,
    required this.rate,
    required this.amount,
  });

  factory PosUploadItem.fromJson(Map<String, dynamic> json) {
    return PosUploadItem(
      idx: json['idx'] ?? 0,
      refCode: json['ref_code'] ?? '',
      itemName: json['item_name'] ?? '',
      // Map 'qty' to 'quantity', fallback to 'quantity' if 'qty' is missing, defaulting to 0.0
      quantity: (json['qty'] as num?)?.toDouble() ?? (json['quantity'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
