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
  // Added customer field if available on parent
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
      customer: json['customer_name'] ?? json['customer'], // Try both common field names
      items: items,
    );
  }
}

class PackingSlipItem {
  final String itemCode;
  final String itemName;
  final double qty;
  final String uom;
  final String batchNo;
  final double netWeight;
  final double weightUom;
  // New fields
  final String? customInvoiceSerialNumber;
  final String? customVariantOf;
  final String? customCountryOfOrigin;

  PackingSlipItem({
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
  });

  factory PackingSlipItem.fromJson(Map<String, dynamic> json) {
    return PackingSlipItem(
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
    );
  }
}
