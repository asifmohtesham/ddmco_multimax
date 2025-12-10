class PackingSlip {
  final String name;
  final String deliveryNote;
  final String modified;
  final String creation;
  final int docstatus;
  final String status;
  final String? customPoNo;
  final int? fromCaseNo;
  final int? toCaseNo;
  final String? owner;
  final String? customer;
  final List<PackingSlipItem> items;

  PackingSlip({
    required this.name,
    required this.deliveryNote,
    required this.modified,
    required this.creation,
    required this.docstatus,
    required this.status,
    this.customPoNo,
    this.fromCaseNo,
    this.toCaseNo,
    this.owner,
    this.customer,
    required this.items,
  });

  factory PackingSlip.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PackingSlipItem> items = itemsList.map((i) => PackingSlipItem.fromJson(i)).toList();

    // Sort items by custom_invoice_serial_number
    items.sort((a, b) {
      int aSerial = int.tryParse(a.customInvoiceSerialNumber ?? '0') ?? 0;
      int bSerial = int.tryParse(b.customInvoiceSerialNumber ?? '0') ?? 0;
      return aSerial.compareTo(bSerial);
    });

    return PackingSlip(
      name: json['name'] ?? '',
      deliveryNote: json['delivery_note'] ?? '',
      modified: json['modified'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(),
      docstatus: json['docstatus'] as int? ?? 0,
      status: json['status'] ?? (json['docstatus'] == 1 ? 'Submitted' : (json['docstatus'] == 2 ? 'Cancelled' : 'Draft')),
      customPoNo: json['custom_po_no'],
      fromCaseNo: json['from_case_no'] as int?,
      toCaseNo: json['to_case_no'] as int?,
      owner: json['owner'],
      customer: json['customer_name'] ?? json['customer'],
      items: items,
    );
  }

  PackingSlip copyWith({
    String? name,
    String? deliveryNote,
    String? modified,
    String? creation,
    int? docstatus,
    String? status,
    String? customPoNo,
    int? fromCaseNo,
    int? toCaseNo,
    String? owner,
    String? customer,
    List<PackingSlipItem>? items,
  }) {
    return PackingSlip(
      name: name ?? this.name,
      deliveryNote: deliveryNote ?? this.deliveryNote,
      modified: modified ?? this.modified,
      creation: creation ?? this.creation,
      docstatus: docstatus ?? this.docstatus,
      status: status ?? this.status,
      customPoNo: customPoNo ?? this.customPoNo,
      fromCaseNo: fromCaseNo ?? this.fromCaseNo,
      toCaseNo: toCaseNo ?? this.toCaseNo,
      owner: owner ?? this.owner,
      customer: customer ?? this.customer,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'delivery_note': deliveryNote,
      'modified': modified,
      'creation': creation,
      'docstatus': docstatus,
      'status': status,
      'custom_po_no': customPoNo,
      'from_case_no': fromCaseNo,
      'to_case_no': toCaseNo,
      'owner': owner,
      'customer': customer,
      'items': items.map((x) => x.toJson()).toList(),
    };
  }
}

class PackingSlipItem {
  final String name; // Unique ID
  final String dnDetail; // Link to Delivery Note Item
  final String itemCode;
  final String itemName;
  final double qty;
  final String uom;
  final String batchNo;
  final double netWeight;
  final double weightUom;
  final String? customInvoiceSerialNumber;
  final String? customVariantOf;
  final String? customCountryOfOrigin;
  final String? creation;

  PackingSlipItem({
    required this.name,
    required this.dnDetail,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.uom,
    required this.batchNo,
    required this.netWeight,
    required this.weightUom,
    this.customInvoiceSerialNumber,
    this.customVariantOf,
    this.customCountryOfOrigin,
    this.creation,
  });

  factory PackingSlipItem.fromJson(Map<String, dynamic> json) {
    return PackingSlipItem(
      name: json['name'] ?? '',
      dnDetail: json['dn_detail'] ?? '',
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      uom: json['uom'] ?? '',
      batchNo: json['batch_no'] ?? '',
      netWeight: (json['net_weight'] as num?)?.toDouble() ?? 0.0,
      weightUom: (json['weight_uom'] as num?)?.toDouble() ?? 0.0,
      customInvoiceSerialNumber: json['custom_invoice_serial_number']?.toString(),
      customVariantOf: json['custom_variant_of'],
      customCountryOfOrigin: json['custom_country_of_origin'],
      creation: json['creation'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dn_detail': dnDetail,
      'item_code': itemCode,
      'item_name': itemName,
      'qty': qty,
      'uom': uom,
      'batch_no': batchNo,
      'net_weight': netWeight,
      'weight_uom': weightUom,
      'custom_invoice_serial_number': customInvoiceSerialNumber,
      'custom_variant_of': customVariantOf,
      'custom_country_of_origin': customCountryOfOrigin,
      'creation': creation,
    };
  }
}