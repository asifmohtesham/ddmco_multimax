class StockEntry {
  final String name;
  final String purpose;
  final double totalAmount;
  final String postingDate;
  final String modified;
  final String creation;
  final String status;
  final int docstatus;
  // New fields
  final String? owner;
  final String? stockEntryType;
  final String? postingTime;
  final String? fromWarehouse;
  final String? toWarehouse;
  final double? customTotalQty;
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
      items: items,
    );
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
  final String itemCode;
  final double qty;
  final double basicRate;
  // New fields
  final String? itemGroup;
  final String? customVariantOf;
  final String? batchNo;
  final String? itemName;
  final String? rack;
  final String? toRack;
  final String? sWarehouse;
  final String? tWarehouse;

  StockEntryItem({
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
}
