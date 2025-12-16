class ItemAttribute {
  final String attributeName;
  final String attributeValue;

  ItemAttribute({required this.attributeName, required this.attributeValue});

  factory ItemAttribute.fromJson(Map<String, dynamic> json) {
    return ItemAttribute(
      attributeName: json['attribute'] ?? '',
      attributeValue: json['attribute_value'] ?? '',
    );
  }
}

class ItemCustomerDetail {
  final String customerName;
  final String refCode;

  ItemCustomerDetail({required this.customerName, required this.refCode});

  factory ItemCustomerDetail.fromJson(Map<String, dynamic> json) {
    return ItemCustomerDetail(
      customerName: json['customer_name'] ?? '',
      refCode: json['ref_code'] ?? '',
    );
  }
}

class Item {
  final String name;
  final String itemName;
  final String itemCode;
  final String itemGroup;
  final String? image;
  final String? variantOf;
  final String? countryOfOrigin;
  final String? description;
  final String? stockUom;
  final List<ItemAttribute> attributes;
  final List<ItemCustomerDetail> customerItems; // Added

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
    this.attributes = const [],
    this.customerItems = const [], // Added
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    var attrList = json['attributes'] as List? ?? [];
    List<ItemAttribute> attributes = attrList.map((i) => ItemAttribute.fromJson(i)).toList();

    var custList = json['customer_items'] as List? ?? [];
    List<ItemCustomerDetail> customerItems = custList.map((i) => ItemCustomerDetail.fromJson(i)).toList();

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
      attributes: attributes,
      customerItems: customerItems,
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