class PurchaseReceipt {
  final String name;
  final String? owner;
  final String creation;
  final String modified;
  final String status;
  final int docstatus;
  final String supplier;
  final String postingDate;
  final String postingTime;
  final String? setWarehouse;
  final String currency;
  final double totalQty;
  final double grandTotal;
  final List<PurchaseReceiptItem> items;

  PurchaseReceipt({
    required this.name,
    required this.owner,
    required this.creation,
    required this.modified,
    required this.status,
    required this.docstatus,
    required this.postingDate,
    required this.postingTime,
    required this.supplier,
    this.setWarehouse,
    required this.currency,
    required this.totalQty,
    required this.grandTotal,
    required this.items,
  });

  factory PurchaseReceipt.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<PurchaseReceiptItem> items =
        itemsList.map((i) => PurchaseReceiptItem.fromJson(i)).toList();

    return PurchaseReceipt(
      name: json['name'] ?? '',
      owner: json['owner'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(),
      modified: json['modified'] ?? '',
      docstatus: json['docstatus'] as int? ?? 0,
      status: json['status'] ?? 'Draft',
      supplier: json['supplier'] ?? '',
      postingDate: json['posting_date'] ?? '',
      postingTime: json['posting_time'] ?? '',
      currency: json['currency'] ?? 'AED',
      setWarehouse: json['set_warehouse'],
      totalQty: (json['total_qty'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      items: items,
    );
  }
}

class PurchaseReceiptItem {
  final String? name;
  final String owner;
  final String creation;
  final String? modified;
  final String? modifiedBy;
  final String itemCode;
  final String? itemName;
  final double qty;
  final double? rate;
  final String? batchNo;
  final String? rack;
  final String warehouse;
  final String? purchaseOrderItem; // Unique row ID in the PO items child table
  final String? purchaseOrder;     // Name of the PO header document
  final String? uom;
  final String? stockUom;
  final double conversionFactor;
  final int idx;
  final String? customVariantOf;
  final double? purchaseOrderQty;
  final int docstatus;

  // ── PO linkage fields ──────────────────────────────────────────────────────
  // Populated by PurchaseReceiptFormController when the receipt is created
  // from a Purchase Order.  Stored on the item row so the item-form controller
  // can display and submit the originating PO reference without re-querying.
  final String? poName;  // Name of the source Purchase Order (po_name)
  final String? poItem;  // Row name / ID of the source PO item (po_item)
  final double? poQty;   // Ordered qty from the PO row (po_qty)
  final double? poRate;  // Rate from the PO row (po_rate)

  PurchaseReceiptItem({
    this.name,
    required this.owner,
    required this.creation,
    this.modified,
    this.modifiedBy,
    required this.itemCode,
    this.itemName,
    required this.qty,
    this.rate,
    this.batchNo,
    this.rack,
    required this.warehouse,
    this.purchaseOrderItem,
    this.purchaseOrder,
    this.uom,
    this.stockUom,
    this.conversionFactor = 1.0,
    this.idx = 0,
    this.customVariantOf,
    this.purchaseOrderQty,
    this.docstatus = 0,
    this.poName,
    this.poItem,
    this.poQty,
    this.poRate,
  });

  factory PurchaseReceiptItem.fromJson(Map<String, dynamic> json) {
    return PurchaseReceiptItem(
      name: json['name'],
      owner: json['owner'] ?? '',
      creation: json['creation'] ?? '',
      modified: json['modified'] ?? '',
      modifiedBy: json['modified_by'] ?? '',
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'],
      batchNo: json['batch_no'],
      rack: json['rack'],
      warehouse: json['warehouse'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      purchaseOrderItem: json['purchase_order_item'],
      purchaseOrder: json['purchase_order'],
      uom: json['uom'],
      stockUom: json['stock_uom'],
      conversionFactor:
          (json['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      idx: json['idx'] as int? ?? 0,
      customVariantOf: json['custom_variant_of'],
      purchaseOrderQty:
          (json['purchase_order_qty'] as num?)?.toDouble(),
      docstatus: json['docstatus'] as int? ?? 0,
      poName: json['po_name'] as String?,
      poItem: json['po_item'] as String?,
      poQty:  (json['po_qty']  as num?)?.toDouble(),
      poRate: (json['po_rate'] as num?)?.toDouble(),
    );
  }

  PurchaseReceiptItem copyWith({
    String? name,
    String? owner,
    String? creation,
    String? modified,
    String? modifiedBy,
    String? itemCode,
    String? itemName,
    double? qty,
    double? rate,
    String? batchNo,
    String? rack,
    String? warehouse,
    String? purchaseOrderItem,
    String? purchaseOrder,
    String? uom,
    String? stockUom,
    double? conversionFactor,
    int? idx,
    String? customVariantOf,
    double? purchaseOrderQty,
    int? docstatus,
    String? poName,
    String? poItem,
    double? poQty,
    double? poRate,
  }) {
    return PurchaseReceiptItem(
      name: name ?? this.name,
      owner: owner ?? this.owner,
      creation: creation ?? this.creation,
      modified: modified ?? this.modified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      qty: qty ?? this.qty,
      rate: rate ?? this.rate,
      batchNo: batchNo ?? this.batchNo,
      rack: rack ?? this.rack,
      warehouse: warehouse ?? this.warehouse,
      purchaseOrderItem: purchaseOrderItem ?? this.purchaseOrderItem,
      purchaseOrder: purchaseOrder ?? this.purchaseOrder,
      uom: uom ?? this.uom,
      stockUom: stockUom ?? this.stockUom,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      idx: idx ?? this.idx,
      customVariantOf: customVariantOf ?? this.customVariantOf,
      purchaseOrderQty: purchaseOrderQty ?? this.purchaseOrderQty,
      docstatus: docstatus ?? this.docstatus,
      poName: poName ?? this.poName,
      poItem: poItem ?? this.poItem,
      poQty:  poQty  ?? this.poQty,
      poRate: poRate ?? this.poRate,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'qty': qty,
      'received_qty': qty,
      'rate': rate,
      'batch_no': batchNo,
      'rack': rack,
      'warehouse': warehouse,
      'purchase_order_item': purchaseOrderItem,
      'purchase_order': purchaseOrder,
      'uom': uom,
      'stock_uom': stockUom ?? uom,
      'conversion_factor': conversionFactor,
      'idx': idx,
    };

    if (name != null && !name!.startsWith('local_')) {
      data['name'] = name;
    }
    return data;
  }
}
