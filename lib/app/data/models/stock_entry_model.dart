class StockEntry {
  final String name;
  final String purpose;
  final double totalAmount;
  final String postingDate;
  final String modified;
  final String creation;
  final String status;
  final int docstatus;
  final String? owner;
  final String? stockEntryType;
  final String? postingTime;
  final String? fromWarehouse;
  final String? toWarehouse;
  final double? customTotalQty;
  final String? customReferenceNo; 
  final List<StockEntryItem> items;

  StockEntry({
    required this.name,
    required this.purpose,
    required this.totalAmount,
    required this.postingDate,
    required this.modified,
    required this.creation,
    required this.status,
    required this.docstatus,
    this.owner,
    this.stockEntryType,
    this.postingTime,
    this.fromWarehouse,
    this.toWarehouse,
    this.customTotalQty,
    this.customReferenceNo,
    required this.items,
  });

  factory StockEntry.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<StockEntryItem> items = itemsList.map((i) => StockEntryItem.fromJson(i)).toList();

    return StockEntry(
      name: json['name'] ?? 'No Name',
      purpose: json['purpose'] ?? 'No Purpose',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      postingDate: json['posting_date'] ?? '',
      modified: json['modified'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(),
      docstatus: json['docstatus'] as int? ?? 0,
      status: _getStatusFromDocstatus(json['docstatus'] as int? ?? 0),
      owner: json['owner'],
      stockEntryType: json['stock_entry_type'],
      postingTime: json['posting_time'],
      fromWarehouse: json['from_warehouse'],
      toWarehouse: json['to_warehouse'],
      customTotalQty: (json['custom_total_qty'] as num?)?.toDouble(),
      customReferenceNo: json['custom_reference_no'],
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stock_entry_type': stockEntryType,
      'posting_date': postingDate,
      'posting_time': postingTime,
      'from_warehouse': fromWarehouse,
      'to_warehouse': toWarehouse,
      'custom_reference_no': customReferenceNo,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }

  static String _getStatusFromDocstatus(int docstatus) {
    switch (docstatus) {
      case 0:
        return 'Draft';
      case 1:
        return 'Submitted';
      case 2:
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }
}

class StockEntryItem {
  final String? name; // Unique Row ID
  final String itemCode;
  final double qty;
  final double basicRate;
  final String? itemGroup;
  final String? customVariantOf;
  final String? batchNo;
  final String? itemName;
  final String? rack;
  final String? toRack;
  final String? sWarehouse;
  final String? tWarehouse;

  StockEntryItem({
    this.name,
    required this.itemCode,
    required this.qty,
    required this.basicRate,
    this.itemGroup,
    this.customVariantOf,
    this.batchNo,
    this.itemName,
    this.rack,
    this.toRack,
    this.sWarehouse,
    this.tWarehouse,
  });

  factory StockEntryItem.fromJson(Map<String, dynamic> json) {
    return StockEntryItem(
      name: json['name'],
      itemCode: json['item_code'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      basicRate: (json['basic_rate'] as num?)?.toDouble() ?? 0.0,
      itemGroup: json['item_group'],
      customVariantOf: json['custom_variant_of'],
      batchNo: json['batch_no'],
      itemName: json['item_name'],
      rack: json['rack'],
      toRack: json['to_rack'],
      sWarehouse: json['s_warehouse'],
      tWarehouse: json['t_warehouse'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'qty': qty,
      'basic_rate': basicRate,
      'batch_no': batchNo,
      's_warehouse': sWarehouse,
      't_warehouse': tWarehouse,
      'rack': rack,
      'to_rack': toRack,
    };
    if (name != null) {
      data['name'] = name;
    }
    return data;
  }
}
