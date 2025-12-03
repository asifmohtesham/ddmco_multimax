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
  final String? name;
  final String itemCode;
  final double qty;
  final double rate;
  final String? itemName;
  final String? countryOfOrigin;
  final String? uom;
  final String? customInvoiceSerialNumber;
  final String? rack;
  final String? batchNo;
  // Additional fields
  final String? owner;
  final String? creation;
  final String? modifiedBy;
  final String? modified;
  final int? idx;
  final String? customVariantOf;
  final String? itemGroup;
  final String? image;
  final double? packedQty;
  final double? companyTotalStock;

  DeliveryNoteItem({
    this.name,
    required this.itemCode,
    required this.qty,
    required this.rate,
    this.itemName,
    this.countryOfOrigin,
    this.uom,
    this.customInvoiceSerialNumber,
    this.rack,
    this.batchNo,
    this.owner,
    this.creation,
    this.modifiedBy,
    this.modified,
    this.idx,
    this.customVariantOf,
    this.itemGroup,
    this.image,
    this.packedQty,
    this.companyTotalStock,
  });

  factory DeliveryNoteItem.fromJson(Map<String, dynamic> json) {
    return DeliveryNoteItem(
      name: json['name'],
      itemCode: json['item_code'],
      qty: (json['qty'] as num).toDouble(),
      rate: (json['rate'] as num).toDouble(),
      itemName: json['item_name'],
      countryOfOrigin: json['country_of_origin'],
      uom: json['uom'],
      customInvoiceSerialNumber: json['custom_invoice_serial_number']?.toString(),
      rack: json['rack'],
      batchNo: json['batch_no'],
      owner: json['owner'],
      creation: json['creation'],
      modifiedBy: json['modified_by'],
      modified: json['modified'],
      idx: json['idx'] as int?,
      customVariantOf: json['custom_variant_of'],
      itemGroup: json['item_group'],
      image: json['image'],
      packedQty: (json['packed_qty'] as num?)?.toDouble(),
      companyTotalStock: (json['company_total_stock'] as num?)?.toDouble(),
    );
  }

  DeliveryNoteItem copyWith({
    String? name,
    String? itemCode,
    double? qty,
    double? rate,
    String? itemName,
    String? countryOfOrigin,
    String? uom,
    String? customInvoiceSerialNumber,
    String? rack,
    String? batchNo,
    String? owner,
    String? creation,
    String? modifiedBy,
    String? modified,
    int? idx,
    String? customVariantOf,
    String? itemGroup,
    String? image,
    double? packedQty,
    double? companyTotalStock,
  }) {
    return DeliveryNoteItem(
      name: name ?? this.name,
      itemCode: itemCode ?? this.itemCode,
      qty: qty ?? this.qty,
      rate: rate ?? this.rate,
      itemName: itemName ?? this.itemName,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      uom: uom ?? this.uom,
      customInvoiceSerialNumber: customInvoiceSerialNumber ?? this.customInvoiceSerialNumber,
      rack: rack ?? this.rack,
      batchNo: batchNo ?? this.batchNo,
      owner: owner ?? this.owner,
      creation: creation ?? this.creation,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      modified: modified ?? this.modified,
      idx: idx ?? this.idx,
      customVariantOf: customVariantOf ?? this.customVariantOf,
      itemGroup: itemGroup ?? this.itemGroup,
      image: image ?? this.image,
      packedQty: packedQty ?? this.packedQty,
      companyTotalStock: companyTotalStock ?? this.companyTotalStock,
    );
  }
}
