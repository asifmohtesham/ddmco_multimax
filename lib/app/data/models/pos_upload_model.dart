class PosUpload {
  /// The `status` values a POS Upload can be given, in the DocType's option
  /// order. Feeds the form's status dropdown, the list's status bar and the
  /// filter sheet, so keep it in step with the server.
  ///
  /// POS Upload is a site DocType (Selling module, custom). Its `status` is a
  /// Select with the options blank, Pending, In Progress, Completed and
  /// Cancelled (default Pending, permlevel 1), read on production (v16) on
  /// 16/11/2026. It is not submittable, so every upload has docstatus 0 and
  /// there is no "Draft" or "Submitted": the server rejects either on save and
  /// a filter on either matches nothing. Those two were left over from the
  /// first model, which derived the status from docstatus.
  ///
  /// The blank option is not offered: it is not a state anyone should set,
  /// and [PosUpload.fromJson] shows a blank status as "Pending".
  static const List<String> statusOptions = [
    'Pending',
    'In Progress',
    'Completed',
    'Cancelled',
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
