class DeliveryNote {
  final String name;
  final String customer;
  final double grandTotal;
  final String postingDate;
  final String modified;
  final String status;
  final List<DeliveryNoteItem> items;

  DeliveryNote({
    required this.name,
    required this.customer,
    required this.grandTotal,
    required this.postingDate,
    required this.modified,
    required this.status,
    required this.items,
  });

  factory DeliveryNote.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<DeliveryNoteItem> items = itemsList.map((i) => DeliveryNoteItem.fromJson(i)).toList();

    return DeliveryNote(
      name: json['name'],
      customer: json['customer'],
      grandTotal: (json['grand_total'] as num).toDouble(),
      postingDate: json['posting_date'],
      modified: json['modified'],
      status: json['status'],
      items: items,
    );
  }
}

class DeliveryNoteItem {
  final String itemCode;
  final double qty;
  final double rate;

  DeliveryNoteItem({
    required this.itemCode,
    required this.qty,
    required this.rate,
  });

  factory DeliveryNoteItem.fromJson(Map<String, dynamic> json) {
    return DeliveryNoteItem(
      itemCode: json['item_code'],
      qty: (json['qty'] as num).toDouble(),
      rate: (json['rate'] as num).toDouble(),
    );
  }
}
