// ── BOM header ────────────────────────────────────────────────────────────────
class BOM {
  final String  name;
  final String  item;
  final String? itemName;
  final double  quantity;
  final String? uom;
  final String  company;
  final int     isActive;
  final int     isDefault;
  final int     docstatus;
  final String? currency;
  final double  totalCost;
  final double  rawMaterialCost;
  final double  operatingCost;
  final int     withOperations;
  final String? rmCostAsPer;
  final String? defaultSourceWarehouse;
  final String? defaultTargetWarehouse;
  final double? processLossPercentage;
  final String? modified;
  final String? creation;
  final List<BomItem>         items;
  final List<BomExplodedItem> explodedItems;
  final List<BomOperation>    operations;

  const BOM({
    required this.name,
    required this.item,
    this.itemName,
    required this.quantity,
    this.uom,
    required this.company,
    required this.isActive,
    required this.isDefault,
    required this.docstatus,
    this.currency,
    required this.totalCost,
    required this.rawMaterialCost,
    required this.operatingCost,
    required this.withOperations,
    this.rmCostAsPer,
    this.defaultSourceWarehouse,
    this.defaultTargetWarehouse,
    this.processLossPercentage,
    this.modified,
    this.creation,
    required this.items,
    required this.explodedItems,
    this.operations = const [],
  });

  /// Derived display status — mirrors Frappe label logic.
  String get status {
    if (docstatus == 2) return 'Cancelled';
    if (docstatus == 1) return isActive == 1 ? 'Active' : 'Inactive';
    return 'Draft';
  }

  factory BOM.fromJson(Map<String, dynamic> json) {
    return BOM(
      name:     json['name']      as String? ?? '',
      item:     json['item']      as String? ?? '',
      itemName: json['item_name'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      uom:      json['uom']       as String?,
      company:  json['company']   as String? ?? '',
      isActive:  (json['is_active']  as num?)?.toInt() ?? 0,
      isDefault: (json['is_default'] as num?)?.toInt() ?? 0,
      docstatus: (json['docstatus']  as num?)?.toInt() ?? 0,
      currency:  json['currency']    as String?,
      totalCost:        (json['total_cost']         as num?)?.toDouble() ?? 0.0,
      rawMaterialCost:  (json['raw_material_cost']  as num?)?.toDouble() ?? 0.0,
      operatingCost:    (json['operating_cost']     as num?)?.toDouble() ?? 0.0,
      withOperations:   (json['with_operations']    as num?)?.toInt()    ?? 0,
      rmCostAsPer:           json['rm_cost_as_per']           as String?,
      defaultSourceWarehouse: json['default_source_warehouse'] as String?,
      defaultTargetWarehouse: json['default_target_warehouse'] as String?,
      processLossPercentage:
          (json['process_loss_percentage'] as num?)?.toDouble(),
      modified: json['modified'] as String?,
      creation: json['creation'] as String?,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => BomItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      explodedItems: (json['exploded_items'] as List<dynamic>? ?? [])
          .map((e) => BomExplodedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      operations: (json['operations'] as List<dynamic>? ?? [])
          .map((e) => BomOperation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Returns a copy with updated toggle fields — used for optimistic UI update.
  BOM copyWith({int? isActive, int? isDefault, String? modified}) {
    return BOM(
      name:     name,     item:     item,     itemName: itemName,
      quantity: quantity, uom:      uom,      company:  company,
      isActive:  isActive  ?? this.isActive,
      isDefault: isDefault ?? this.isDefault,
      docstatus: docstatus,
      currency:  currency,
      totalCost:       totalCost,
      rawMaterialCost: rawMaterialCost,
      operatingCost:   operatingCost,
      withOperations:  withOperations,
      rmCostAsPer:            rmCostAsPer,
      defaultSourceWarehouse: defaultSourceWarehouse,
      defaultTargetWarehouse: defaultTargetWarehouse,
      processLossPercentage:  processLossPercentage,
      modified: modified ?? this.modified,
      creation: creation,
      items:         items,
      explodedItems: explodedItems,
      operations:    operations,
    );
  }
}

// ── BOM Operation (child table: operations) ───────────────────────────────────
class BomOperation {
  final String  operation;
  final String? workstation;
  final String? workstationType;
  final double  timeInMins;
  final double  operatingCost;
  final int     sequenceId;
  final String? description;

  const BomOperation({
    required this.operation,
    this.workstation,
    this.workstationType,
    required this.timeInMins,
    required this.operatingCost,
    required this.sequenceId,
    this.description,
  });

  factory BomOperation.fromJson(Map<String, dynamic> json) => BomOperation(
    operation:       json['operation']        as String? ?? '',
    workstation:     json['workstation']      as String?,
    workstationType: json['workstation_type'] as String?,
    timeInMins:      (json['time_in_mins']    as num?)?.toDouble() ?? 0.0,
    operatingCost:   (json['operating_cost']  as num?)?.toDouble() ?? 0.0,
    sequenceId:      (json['sequence_id']     as num?)?.toInt()    ?? 0,
    description:     json['description']      as String?,
  );

  /// Converts to a Work Order `operations` child-table payload row.
  /// ERPNext Work Order Operation fields mirror BOM Operation fields.
  Map<String, dynamic> toWorkOrderOperationPayload() => {
    'operation':      operation,
    'workstation':    workstation     ?? '',
    'time_in_mins':   timeInMins,
    'operating_cost': operatingCost,
    'sequence_id':    sequenceId,
    if (description != null && description!.isNotEmpty)
      'description': description,
  };
}

// ── BOM Item (child table: items) ─────────────────────────────────────────────
class BomItem {
  final String  itemCode;
  final String? itemName;
  final double  qty;
  final String? uom;
  final double? stockQty;
  final double  rate;
  final double? amount;
  final String? sourceWarehouse;
  final String? bomNo;
  final int     isSubAssemblyItem;
  final int     includeItemInManufacturing;

  const BomItem({
    required this.itemCode,
    this.itemName,
    required this.qty,
    this.uom,
    this.stockQty,
    required this.rate,
    this.amount,
    this.sourceWarehouse,
    this.bomNo,
    required this.isSubAssemblyItem,
    required this.includeItemInManufacturing,
  });

  factory BomItem.fromJson(Map<String, dynamic> json) {
    return BomItem(
      itemCode:  json['item_code']  as String? ?? '',
      itemName:  json['item_name']  as String?,
      qty:       (json['qty']       as num?)?.toDouble() ?? 0.0,
      uom:       json['uom']        as String?,
      stockQty:  (json['stock_qty'] as num?)?.toDouble(),
      rate:      (json['rate']      as num?)?.toDouble() ?? 0.0,
      amount:    (json['amount']    as num?)?.toDouble(),
      sourceWarehouse: json['source_warehouse'] as String?,
      bomNo:           json['bom_no']           as String?,
      isSubAssemblyItem:
          (json['is_sub_assembly_item']       as num?)?.toInt() ?? 0,
      includeItemInManufacturing:
          (json['include_item_in_manufacturing'] as num?)?.toInt() ?? 0,
    );
  }
}

// ── BOM Exploded Item (child table: exploded_items) ───────────────────────────
class BomExplodedItem {
  final String  itemCode;
  final String? itemName;
  final double  qty;
  final String? uom;
  final double? rate;
  final double? amount;
  final String? sourceWarehouse;

  const BomExplodedItem({
    required this.itemCode,
    this.itemName,
    required this.qty,
    this.uom,
    this.rate,
    this.amount,
    this.sourceWarehouse,
  });

  factory BomExplodedItem.fromJson(Map<String, dynamic> json) {
    return BomExplodedItem(
      itemCode:  json['item_code']  as String? ?? '',
      itemName:  json['item_name']  as String?,
      qty:       (json['qty']       as num?)?.toDouble() ?? 0.0,
      uom:       json['uom']        as String?,
      rate:      (json['rate']      as num?)?.toDouble(),
      amount:    (json['amount']    as num?)?.toDouble(),
      sourceWarehouse: json['source_warehouse'] as String?,
    );
  }
}
