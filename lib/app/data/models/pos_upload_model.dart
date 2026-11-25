class PosUpload {
  /// POS Upload statuses in list filter order, including the delivery workflow
  /// states on sites where it is installed.
  ///
  /// POS Upload is a custom, non-submittable site DocType. Without the workflow,
  /// its permlevel 1 Status select accepts blank, Pending, In Progress,
  /// Completed and Cancelled. The form offers the four non-blank manual
  /// statuses, and [PosUpload.fromJson] displays blank as Pending.
  static const List<String> statusOptions = [
    'Pending',
    'In Progress',
    'To Deliver',
    'Out for Delivery',
    'Delivered',
    'Completed',
    'Cancelled',
  ];

  final String name;
  final String customer;
  final String date;
  final String modified;
  final String creation;
  final String status;
  final String? returnReason;
  final double? totalAmount;
  final double? totalQty;
  final List<PosUploadItem> items;

  bool get isInPreparation => status == 'Pending' || status == 'In Progress';

  PosUpload({
    required this.name,
    required this.customer,
    required this.date,
    required this.modified,
    required this.creation,
    required this.status,
    this.returnReason,
    this.totalAmount,
    this.totalQty,
    required this.items,
  });

  factory PosUpload.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PosUploadItem> items = itemsList.map((i) => PosUploadItem.fromJson(i)).toList();

    final status = json['status']?.toString() ?? '';
    final returnReason = json['custom_return_reason']?.toString() ?? '';

    return PosUpload(
      name: json['name'] ?? '',
      customer: json['customer'] ?? '',
      date: json['date'] ?? '',
      modified: json['modified'] ?? '',
      creation: json['creation'] ?? '',
      status: status.trim().isEmpty ? 'Pending' : status,
      returnReason: returnReason.trim().isEmpty ? null : returnReason,
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

  /// Unit the [rate] is quoted in (e.g. `Doz`, `Nos`). Empty on rows uploaded
  /// before the field existed. [quantity] is always in single pieces.
  final String uom;
  final double amount;

  PosUploadItem({
    required this.idx,
    this.refCode = '',
    required this.itemName,
    required this.quantity,
    required this.rate,
    this.uom = '',
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
      uom: json['uom'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
