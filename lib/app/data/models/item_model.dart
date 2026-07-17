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

/// One row of `Item.reorder_levels` — the ERPNext `Item Reorder` child DocType.
///
/// Desk labels, for reference:
///   warehouse_group        → "Check in (group)"   (optional)
///   warehouse              → "Request for"        (mandatory)
///   warehouse_reorder_level→ "Re-order Level"
///   warehouse_reorder_qty  → "Re-order Qty"
///   material_request_type  → "Material Request Type" (mandatory)
///
/// `warehouse_group` is where stock is *measured*; `warehouse` is where the
/// Material Request is *raised*.
class ItemReorder {
  /// Child-row name. Null for a row that has never been saved — [toJson]
  /// omits the key so Frappe inserts rather than tries to update.
  final String? name;

  /// "Check in (group)". Null when unset; [toJson] defaults it to [warehouse],
  /// mirroring erpnext item.py:508-509.
  final String? warehouseGroup;

  /// "Request for". Mandatory server-side.
  final String warehouse;

  final double warehouseReorderLevel;
  final double warehouseReorderQty;

  /// Mandatory server-side. One of `Purchase`, `Transfer`, `Material Issue`,
  /// `Manufacture` — empty string when unset.
  final String materialRequestType;

  const ItemReorder({
    this.name,
    this.warehouseGroup,
    required this.warehouse,
    this.warehouseReorderLevel = 0,
    this.warehouseReorderQty = 0,
    this.materialRequestType = '',
  });

  factory ItemReorder.fromJson(Map<String, dynamic> json) {
    final group = json['warehouse_group']?.toString();
    return ItemReorder(
      name: json['name']?.toString(),
      // Frappe returns '' for an unset Link; normalise so the UI and the
      // dirty-diff see one canonical "unset".
      warehouseGroup: (group == null || group.isEmpty) ? null : group,
      warehouse: json['warehouse']?.toString() ?? '',
      warehouseReorderLevel:
          (json['warehouse_reorder_level'] as num?)?.toDouble() ?? 0.0,
      warehouseReorderQty:
          (json['warehouse_reorder_qty'] as num?)?.toDouble() ?? 0.0,
      materialRequestType: json['material_request_type']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        // item.py:508-509 defaults a blank group to the warehouse on save.
        // Applying it here keeps the payload identical to what Desk would
        // persist, so the dirty-diff baseline matches what comes back.
        'warehouse_group':
            (warehouseGroup == null || warehouseGroup!.isEmpty)
                ? warehouse
                : warehouseGroup,
        'warehouse': warehouse,
        'warehouse_reorder_level': warehouseReorderLevel,
        'warehouse_reorder_qty': warehouseReorderQty,
        'material_request_type': materialRequestType,
      };

  ItemReorder copyWith({
    String? name,
    String? warehouseGroup,
    bool clearWarehouseGroup = false,
    String? warehouse,
    double? warehouseReorderLevel,
    double? warehouseReorderQty,
    String? materialRequestType,
  }) =>
      ItemReorder(
        name: name ?? this.name,
        warehouseGroup:
            clearWarehouseGroup ? null : (warehouseGroup ?? this.warehouseGroup),
        warehouse: warehouse ?? this.warehouse,
        warehouseReorderLevel:
            warehouseReorderLevel ?? this.warehouseReorderLevel,
        warehouseReorderQty: warehouseReorderQty ?? this.warehouseReorderQty,
        materialRequestType: materialRequestType ?? this.materialRequestType,
      );
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
  final List<ItemReorder> reorderLevels;

  /// Desk hides the Auto re-order section when this is false
  /// (`depends_on: "is_stock_item"`).
  final bool isStockItem;

  /// Seeds a new reorder row's type — see `defaultReorderTypeFor`.
  final String? defaultMaterialRequestType;

  /// Optimistic-lock token sent back on update.
  final String? modified;

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
    this.reorderLevels = const [],
    this.isStockItem = false,
    this.defaultMaterialRequestType,
    this.modified,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    var attrList = json['attributes'] as List? ?? [];
    List<ItemAttribute> attributes = attrList.map((i) => ItemAttribute.fromJson(i)).toList();

    var custList = json['customer_items'] as List? ?? [];
    List<ItemCustomerDetail> customerItems = custList.map((i) => ItemCustomerDetail.fromJson(i)).toList();

    var reorderList = json['reorder_levels'] as List? ?? [];
    List<ItemReorder> reorderLevels = reorderList
        .whereType<Map<String, dynamic>>()
        .map((i) => ItemReorder.fromJson(i))
        .toList();

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
      reorderLevels: reorderLevels,
      // Frappe Check fields arrive as int 0/1; tolerate bool/string too.
      isStockItem: json['is_stock_item'] == 1 ||
          json['is_stock_item'] == true ||
          json['is_stock_item'] == '1',
      defaultMaterialRequestType: json['default_material_request_type'],
      modified: json['modified'],
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
