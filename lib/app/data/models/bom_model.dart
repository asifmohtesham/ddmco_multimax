class BOM {
  final String name;
  final String item;
  final String itemName;
  final int isActive;
  final int isDefault;
  final int docstatus;
  final String status; // calculated usually
  final String currency;
  final double totalCost;

  BOM({
    required this.name,
    required this.item,
    required this.itemName,
    required this.isActive,
    required this.isDefault,
    required this.docstatus,
    required this.status,
    required this.currency,
    required this.totalCost,
  });

  factory BOM.fromJson(Map<String, dynamic> json) {
    return BOM(
      name: json['name'] ?? '',
      item: json['item'] ?? '',
      itemName: json['item_name'] ?? '',
      isActive: json['is_active'] as int? ?? 0,
      isDefault: json['is_default'] as int? ?? 0,
      docstatus: json['docstatus'] as int? ?? 0,
      status: (json['is_active'] == 1 ? 'Active' : 'Inactive'),
      currency: json['currency'] ?? 'USD',
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0.0,
    );
  }
}