class MaterialRequest {
  final String name;
  final String transactionDate;
  final String scheduleDate;
  final String status;
  final int docstatus;
  final String materialRequestType;
  final String? owner;
  final List<MaterialRequestItem> items;

  MaterialRequest({
    required this.name,
    required this.transactionDate,
    required this.scheduleDate,
    required this.status,
    required this.docstatus,
    required this.materialRequestType,
    this.owner,
    required this.items,
  });

  factory MaterialRequest.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<MaterialRequestItem> items = itemsList.map((i) => MaterialRequestItem.fromJson(i)).toList();

    return MaterialRequest(
      name: json['name']?.toString() ?? 'No Name',
      transactionDate: json['transaction_date']?.toString() ?? '',
      scheduleDate: json['schedule_date']?.toString() ?? '',
      status: _getStatusFromDocstatus(_parseInt(json['docstatus']), json['status']?.toString()),
      docstatus: _parseInt(json['docstatus']),
      materialRequestType: json['material_request_type']?.toString() ?? 'Purchase',
      owner: json['owner']?.toString(),
      items: items,
    );
  }

  static String _getStatusFromDocstatus(int docstatus, String? serverStatus) {
    if (docstatus == 2) return 'Cancelled';
    if (docstatus == 0) return 'Draft';
    return serverStatus ?? 'Submitted';
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class MaterialRequestItem {
  final String? name;
  final String itemCode;
  final double qty;
  final double? scheduleDate;
  final String? warehouse;
  final String? description;
  final String? uom;

  MaterialRequestItem({
    this.name,
    required this.itemCode,
    required this.qty,
    this.scheduleDate,
    this.warehouse,
    this.description,
    this.uom,
  });

  factory MaterialRequestItem.fromJson(Map<String, dynamic> json) {
    return MaterialRequestItem(
      name: json['name']?.toString(),
      itemCode: json['item_code']?.toString() ?? '',
      qty: double.tryParse(json['qty']?.toString() ?? '0') ?? 0.0,
      warehouse: json['warehouse']?.toString(),
      description: json['description']?.toString(),
      uom: json['uom']?.toString(),
    );
  }
}