class DeliveryNote {
  final String name;
  final String customer;
  final double grandTotal;
  final String postingDate;
  final String modified;
  final String creation;
  final String status;
  final String currency;
  final String? poNo;
  final double totalQty;
  final int docstatus;
  final String? setWarehouse;
  final List<DeliveryNoteItem> items;

  DeliveryNote({
    required this.name,
    required this.customer,
    required this.grandTotal,
    required this.postingDate,
    required this.modified,
    required this.creation,
    required this.status,
    required this.currency,
    this.poNo,
    required this.totalQty,
    required this.docstatus,
    this.setWarehouse,
    required this.items,
  });

  factory DeliveryNote.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<DeliveryNoteItem> items = itemsList.map((i) => DeliveryNoteItem.fromJson(i)).toList();

    return DeliveryNote(
      name: json['name'] ?? '',
      customer: json['customer'] ?? '',
      grandTotal: _parseDouble(json['grand_total']),
      postingDate: json['posting_date'] ?? '',
      modified: json['modified'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(),
      status: json['status'] ?? 'Draft',
      currency: json['currency'] ?? 'AED',
      poNo: json['po_no'],
      totalQty: _parseDouble(json['total_qty']),
      docstatus: _parseInt(json['docstatus']),
      setWarehouse: json['set_warehouse'],
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modified': modified,
      'customer': customer,
      'posting_date': postingDate,
      'currency': currency,
      'po_no': poNo,
      'docstatus': docstatus,
      'set_warehouse': setWarehouse,
      'grand_total': grandTotal, // Added to prevent server-side NoneType error
      'total_qty': totalQty,     // Added to prevent server-side NoneType error
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  DeliveryNote copyWith({
    String? name,
    String? customer,
    double? grandTotal,
    String? postingDate,
    String? modified,
    String? creation,
    String? status,
    String? currency,
    String? poNo,
    double? totalQty,
    int? docstatus,
    String? setWarehouse,
    List<DeliveryNoteItem>? items,
  }) {
    return DeliveryNote(
      name: name ?? this.name,
      customer: customer ?? this.customer,
      grandTotal: grandTotal ?? this.grandTotal,
      postingDate: postingDate ?? this.postingDate,
      modified: modified ?? this.modified,
      creation: creation ?? this.creation,
      status: status ?? this.status,
      currency: currency ?? this.currency,
      poNo: poNo ?? this.poNo,
      totalQty: totalQty ?? this.totalQty,
      docstatus: docstatus ?? this.docstatus,
      setWarehouse: setWarehouse ?? this.setWarehouse,
      items: items ?? this.items,
    );
  }

  // --- Safe Parsing Helpers ---
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
      itemCode: json['item_code'] ?? '',
      qty: DeliveryNote._parseDouble(json['qty']),
      rate: DeliveryNote._parseDouble(json['rate']),
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
      idx: DeliveryNote._parseInt(json['idx']),
      customVariantOf: json['custom_variant_of'],
      itemGroup: json['item_group'],
      image: json['image'],
      packedQty: DeliveryNote._parseDouble(json['packed_qty']),
      companyTotalStock: DeliveryNote._parseDouble(json['company_total_stock']),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'qty': qty,
      'rate': rate,
      'uom': uom,
      'custom_invoice_serial_number': customInvoiceSerialNumber,
      'rack': rack,
      'batch_no': batchNo,
    };
    // Include 'name' only if it exists and is NOT a local temp ID
    if (name != null && !name!.startsWith('local_')) {
      data['name'] = name;
    }
    return data;
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