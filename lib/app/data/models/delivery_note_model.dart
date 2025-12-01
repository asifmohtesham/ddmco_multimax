class DeliveryNote {
  final String name;
  final String customer;
  final double grandTotal;
  final String postingDate;
  final String modified;
  final String status;
  final String currency;
  final String? poNo;
  final List<DeliveryNoteItem> items;

  DeliveryNote({
    required this.name,
    required this.customer,
    required this.grandTotal,
    required this.postingDate,
    required this.modified,
    required this.status,
    required this.currency,
    this.poNo,
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
      currency: json['currency'],
      poNo: json['po_no'],
      items: items,
    );
  }

  DeliveryNote copyWith({
    String? name,
    String? customer,
    double? grandTotal,
    String? postingDate,
    String? modified,
    String? status,
    String? currency,
    String? poNo,
    List<DeliveryNoteItem>? items,
  }) {
    return DeliveryNote(
      name: name ?? this.name,
      customer: customer ?? this.customer,
      grandTotal: grandTotal ?? this.grandTotal,
      postingDate: postingDate ?? this.postingDate,
      modified: modified ?? this.modified,
      status: status ?? this.status,
      currency: currency ?? this.currency,
      poNo: poNo ?? this.poNo,
      items: items ?? this.items,
    );
  }
}

class DeliveryNoteItem {
  final String itemCode;
  final double qty;
  final double rate;
  final String? itemName;
  final String? countryOfOrigin;
  final String? uom;
  final String? customInvoiceSerialNumber;
  final String? rack;

  DeliveryNoteItem({
    required this.itemCode,
    required this.qty,
    required this.rate,
    this.itemName,
    this.countryOfOrigin,
    this.uom,
    this.customInvoiceSerialNumber,
    this.rack,
  });

  factory DeliveryNoteItem.fromJson(Map<String, dynamic> json) {
    return DeliveryNoteItem(
      itemCode: json['item_code'],
      qty: (json['qty'] as num).toDouble(),
      rate: (json['rate'] as num).toDouble(),
      itemName: json['item_name'],
      countryOfOrigin: json['country_of_origin'],
      uom: json['uom'],
      customInvoiceSerialNumber: json['custom_invoice_serial_number']?.toString(),
      rack: json['rack'],
    );
  }
}
