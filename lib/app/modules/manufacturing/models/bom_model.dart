class BomModel {
  final String name;
  final String item;
  final String? itemName;
  final double quantity;
  final String? uom;
  final bool isActive;
  final bool isDefault;
  final String? company;
  final List<BomItem> items;
  final List<BomOperation> operations;
  final double totalCost;
  final double operatingCost;
  final double rawMaterialCost;
  final String? description;
  final DateTime? modified;

  BomModel({
    required this.name,
    required this.item,
    this.itemName,
    required this.quantity,
    this.uom,
    required this.isActive,
    required this.isDefault,
    this.company,
    required this.items,
    required this.operations,
    required this.totalCost,
    required this.operatingCost,
    required this.rawMaterialCost,
    this.description,
    this.modified,
  });

  factory BomModel.fromJson(Map<String, dynamic> json) {
    return BomModel(
      name: json['name'] ?? '',
      item: json['item'] ?? '',
      itemName: json['item_name'],
      quantity: (json['quantity'] ?? 1.0).toDouble(),
      uom: json['uom'],
      isActive: json['is_active'] == 1,
      isDefault: json['is_default'] == 1,
      company: json['company'],
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => BomItem.fromJson(item))
          .toList() ?? [],
      operations: (json['operations'] as List<dynamic>?)
          ?.map((op) => BomOperation.fromJson(op))
          .toList() ?? [],
      totalCost: (json['total_cost'] ?? 0.0).toDouble(),
      operatingCost: (json['operating_cost'] ?? 0.0).toDouble(),
      rawMaterialCost: (json['raw_material_cost'] ?? 0.0).toDouble(),
      description: json['description'],
      modified: json['modified'] != null ? DateTime.parse(json['modified']) : null,
    );
  }
}

class BomItem {
  final String itemCode;
  final String? itemName;
  final double qty;
  final String? uom;
  final double rate;
  final double amount;
  final String? description;

  BomItem({
    required this.itemCode,
    this.itemName,
    required this.qty,
    this.uom,
    required this.rate,
    required this.amount,
    this.description,
  });

  factory BomItem.fromJson(Map<String, dynamic> json) {
    return BomItem(
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'],
      qty: (json['qty'] ?? 0.0).toDouble(),
      uom: json['uom'],
      rate: (json['rate'] ?? 0.0).toDouble(),
      amount: (json['amount'] ?? 0.0).toDouble(),
      description: json['description'],
    );
  }
}

class BomOperation {
  final String operation;
  final String? workstation;
  final double timeInMins;
  final double operatingCost;
  final String? description;

  BomOperation({
    required this.operation,
    this.workstation,
    required this.timeInMins,
    required this.operatingCost,
    this.description,
  });

  factory BomOperation.fromJson(Map<String, dynamic> json) {
    return BomOperation(
      operation: json['operation'] ?? '',
      workstation: json['workstation'],
      timeInMins: (json['time_in_mins'] ?? 0.0).toDouble(),
      operatingCost: (json['operating_cost'] ?? 0.0).toDouble(),
      description: json['description'],
    );
  }
}