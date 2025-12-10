class Item {
  final String name;
  final String itemName;
  final String itemCode;
  final String itemGroup;
  final String? image;
  final String? variantOf;
  final String? countryOfOrigin;
  final String? description;
  final String? stockUom; // Added: Essential ERPNext field

  Item({
    required this.name,
    required this.itemName,
    required this.itemCode,
    required this.itemGroup,
    this.image,
    this.variantOf,
    this.countryOfOrigin,
    this.description,
    this.stockUom,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      name: json['name'] ?? '',
      itemName: json['item_name'] ?? '',
      itemCode: json['item_code'] ?? '',
      itemGroup: json['item_group'] ?? '',
      image: json['image'],
      variantOf: json['variant_of'],
      countryOfOrigin: json['country_of_origin'],
      description: json['description'],
      stockUom: json['stock_uom'],
    );
  }
}

class WarehouseStock {
  final String warehouse;
  final double quantity;
  final String? rack;

  WarehouseStock({
    required this.warehouse,
    required this.quantity,
    this.rack,
  });

  factory WarehouseStock.fromJson(Map<String, dynamic> json) {
    return WarehouseStock(
      warehouse: json['warehouse'] ?? '',
      quantity: (json['bal_qty'] as num?)?.toDouble() ?? 0.0,
      rack: json['rack']?.toString(),
    );
  }
}