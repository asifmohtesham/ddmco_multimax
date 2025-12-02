class StockEntry {
  final String name;
  final String purpose;
  final double totalAmount;
  final String postingDate;
  final String modified;
  final String status;
  final List<StockEntryItem> items;

  StockEntry({
    required this.name,
    required this.purpose,
    required this.totalAmount,
    required this.postingDate,
    required this.modified,
    required this.status,
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
      status: _getStatusFromDocstatus(json['docstatus'] as int? ?? 0),
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

  StockEntryItem({
    required this.itemCode,
    required this.qty,
    required this.basicRate,
  });

  factory StockEntryItem.fromJson(Map<String, dynamic> json) {
    return StockEntryItem(
      itemCode: json['item_code'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      basicRate: (json['basic_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
