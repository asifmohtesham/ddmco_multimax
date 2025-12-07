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
    List<PurchaseReceiptItem> items = itemsList.map((i) => PurchaseReceiptItem.fromJson(i)).toList();

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
      totalQty: json['total_qty'] ?? 0,
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
  final String? purchaseOrderItem;

  // New Fields
  final int idx;
  final String? customVariantOf;
  final double? purchaseOrderQty;

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
    this.idx = 0,
    this.customVariantOf,
    this.purchaseOrderQty,
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
      warehouse: json['warehouse'],
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      purchaseOrderItem: json['purchase_order_item'],
      idx: json['idx'] as int? ?? 0,
      customVariantOf: json['custom_variant_of'],
      purchaseOrderQty: (json['purchase_order_qty'] as num?)?.toDouble(),
    );
  }

  // --- ADDED copyWith METHOD ---
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
    int? idx,
    String? customVariantOf,
    double? purchaseOrderQty,
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
      idx: idx ?? this.idx,
      customVariantOf: customVariantOf ?? this.customVariantOf,
      purchaseOrderQty: purchaseOrderQty ?? this.purchaseOrderQty,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'modified': modified,
      'modified_by': modifiedBy,
      'owner': owner,
      'creation': name,
      'item_code': itemCode,
      'qty': qty,
      'rate': rate,
      'batch_no': batchNo,
      'rack': rack,
      'purchase_order_item': purchaseOrderItem,
      'idx': idx,
    };
  }
}