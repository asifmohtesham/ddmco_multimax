import 'dart:convert';

class Item {
  final String name;
  final String itemName;
  final String itemCode;
  final String itemGroup;
  final String? image;
  final String? variantOf;
  final String? countryOfOrigin;
  // Other attributes can be added here
  final String? description;

  Item({
    required this.name,
    required this.itemName,
    required this.itemCode,
    required this.itemGroup,
    this.image,
    this.variantOf,
    this.countryOfOrigin,
    this.description,
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
    );
  }
}

class WarehouseStock {
  final String warehouse;
  final double quantity;
  final String? rack; // Added Rack field

  WarehouseStock({
    required this.warehouse,
    required this.quantity,
    this.rack,
  });

  factory WarehouseStock.fromJson(Map<String, dynamic> json) {
    return WarehouseStock(
      warehouse: json['warehouse'] ?? '',
      quantity: (json['bal_qty'] as num?)?.toDouble() ?? 0.0,
      rack: json['rack']?.toString(), // Parse rack
    );
  }
}