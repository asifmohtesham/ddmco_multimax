class StockEntry {
  final String name;
  final String purpose;
  final String? company;
  final double totalAmount;
  String postingDate;
  final String modified;
  final String creation;
  final String status;
  final int docstatus;
  final String? owner;
  final String? modifiedBy;
  final String? stockEntryType;
  String? postingTime;
  final String? fromWarehouse;
  final String? toWarehouse;
  final double? customTotalQty;
  final String? customReferenceNo;
  final String? workOrder;
  final bool    fromBom;
  final String? bomNo;
  final double  fgCompletedQty;
  final String currency;
  final List<StockEntryItem> items;

  StockEntry({
    required this.name,
    required this.purpose,
    this.company,
    required this.totalAmount,
    required this.postingDate,
    required this.modified,
    required this.creation,
    required this.status,
    required this.docstatus,
    this.owner,
    this.modifiedBy,
    this.stockEntryType,
    this.postingTime,
    this.fromWarehouse,
    this.toWarehouse,
    this.customTotalQty,
    this.customReferenceNo,
    this.workOrder,
    required this.currency,
    required this.items,
    this.fromBom       = false,
    this.bomNo,
    this.fgCompletedQty = 0.0,
  });

  factory StockEntry.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<StockEntryItem> items =
        itemsList.map((i) => StockEntryItem.fromJson(i)).toList();

    return StockEntry(
      name:               json['name']?.toString() ?? 'No Name',
      purpose:            json['purpose']?.toString() ?? 'No Purpose',
      company:            json['company']?.toString(),
      totalAmount:        _parseDouble(json['total_amount']),
      postingDate:        json['posting_date']?.toString() ?? '',
      modified:           json['modified']?.toString() ?? '',
      creation:           json['creation']?.toString() ?? DateTime.now().toString(),
      docstatus:          _parseInt(json['docstatus']),
      status:             _getStatusFromDocstatus(_parseInt(json['docstatus'])),
      owner:              json['owner']?.toString(),
      modifiedBy:         json['modified_by']?.toString(),
      stockEntryType:     json['stock_entry_type']?.toString(),
      postingTime:        json['posting_time']?.toString(),
      fromWarehouse:      json['from_warehouse']?.toString(),
      toWarehouse:        json['to_warehouse']?.toString(),
      customTotalQty:     _parseDoubleNullable(json['custom_total_qty']),
      customReferenceNo:  json['custom_reference_no']?.toString(),
      workOrder:          json['work_order']?.toString(),
      fromBom:            (json['from_bom'] == 1 || json['from_bom'] == true),
      bomNo:              json['bom_no']?.toString(),
      fgCompletedQty:     _parseDouble(json['fg_completed_qty']),
      currency:           json['currency']?.toString() ?? 'AED',
      items:              items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stock_entry_type':     stockEntryType,
      'posting_date':         postingDate,
      'posting_time':         postingTime,
      'from_warehouse':       fromWarehouse,
      'to_warehouse':         toWarehouse,
      'custom_reference_no':  customReferenceNo,
      'work_order':           workOrder,
      // ── BOM / FG: only include when from_bom is true ──────────────────
      // Sending from_bom=0 with fg_completed_qty=0 on a manual SE is harmless,
      // but being explicit avoids accidental WO status side-effects.
      'from_bom':             fromBom ? 1 : 0,
      if (fromBom && bomNo != null) 'bom_no': bomNo,
      if (fromBom) 'fg_completed_qty': fgCompletedQty,
      'items': items.map((i) => i.toJson(purpose: purpose)).toList(),
    };
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

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double? _parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return value.isEmpty ? null : double.tryParse(value);
    return null;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is bool) return value ? 1 : 0;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class StockEntryItem {
  final String? name;
  final String itemCode;
  final double qty;
  final double basicRate;
  final String? itemGroup;
  final String? customVariantOf;
  final String? batchNo;
  final String? itemName;
  final String? rack;
  final String? toRack;
  final String? sWarehouse;
  final String? tWarehouse;
  final String? customInvoiceSerialNumber;
  // Link Fields
  final String? materialRequest;
  final String? materialRequestItem;
  // Manufacture: marks the Finished Good row (is_finished_item = 1).
  // Returned by make_stock_entry; must be echoed back on save so ERP
  // does not raise FinishedGoodError.
  final int isFinishedItem;
  final String? secondaryItemType;
  final String? valuationType;
  // Metadata Fields
  final String? owner;
  final String? creation;
  final String? modified;
  final String? modifiedBy;
  final int docstatus;

  StockEntryItem({
    this.name,
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
    this.customInvoiceSerialNumber,
    this.materialRequest,
    this.materialRequestItem,
    this.isFinishedItem = 0,
    this.secondaryItemType,
    this.valuationType,
    this.owner,
    this.creation,
    this.modified,
    this.modifiedBy,
    this.docstatus = 0,
  });

  factory StockEntryItem.fromJson(Map<String, dynamic> json) {
    return StockEntryItem(
      name: json['name']?.toString(),
      itemCode: json['item_code']?.toString() ?? '',
      qty: StockEntry._parseDouble(json['qty']),
      basicRate: StockEntry._parseDouble(json['basic_rate']),
      itemGroup: json['item_group']?.toString(),
      customVariantOf: json['custom_variant_of']?.toString(),
      batchNo: json['batch_no']?.toString(),
      itemName: json['item_name']?.toString(),
      rack: json['rack']?.toString(),
      toRack: json['to_rack']?.toString(),
      sWarehouse: json['s_warehouse']?.toString(),
      tWarehouse: json['t_warehouse']?.toString(),
      customInvoiceSerialNumber:
          json['custom_invoice_serial_number']?.toString(),
      materialRequest: json['material_request']?.toString(),
      materialRequestItem: json['material_request_item']?.toString(),
      isFinishedItem: StockEntry._parseInt(json['is_finished_item']),
      secondaryItemType: json['secondary_item_type']?.toString(),
      valuationType: json['valuation_type']?.toString(),
      owner: json['owner']?.toString(),
      creation: json['creation']?.toString(),
      modified: json['modified']?.toString(),
      modifiedBy: json['modified_by']?.toString(),
      docstatus: StockEntry._parseInt(json['docstatus']),
    );
  }

  bool get isOutput => isFinishedItem == 1 ||
      (secondaryItemType?.trim().isNotEmpty ?? false) ||
      (valuationType?.trim().isNotEmpty ?? false);

  /// Applicable movement sides for the ERP purpose and this row's role.
  ({bool source, bool target}) movementSides(String purpose) {
    return switch (purpose) {
      'Material Issue' || 'Material Consumption for Manufacture' =>
        (source: true, target: false),
      'Material Receipt' => (source: false, target: true),
      'Material Transfer' || 'Material Transfer for Manufacture' =>
        (source: true, target: true),
      'Manufacture' || 'Repack' =>
        (source: !isOutput, target: isOutput),
      _ => (
        source: sWarehouse?.trim().isNotEmpty ?? false,
        target: tWarehouse?.trim().isNotEmpty ?? false,
      ),
    };
  }

  StockEntryItem withLocations(
    String? source,
    String? target, {
    String? sourceRack,
    String? targetRack,
  }) =>
      StockEntryItem(
        name: name,
        itemCode: itemCode,
        qty: qty,
        basicRate: basicRate,
        itemGroup: itemGroup,
        customVariantOf: customVariantOf,
        batchNo: batchNo,
        itemName: itemName,
        rack: sourceRack ?? rack,
        toRack: targetRack ?? toRack,
        sWarehouse: source,
        tWarehouse: target,
        customInvoiceSerialNumber: customInvoiceSerialNumber,
        materialRequest: materialRequest,
        materialRequestItem: materialRequestItem,
        isFinishedItem: isFinishedItem,
        secondaryItemType: secondaryItemType,
        valuationType: valuationType,
        owner: owner,
        creation: creation,
        modified: modified,
        modifiedBy: modifiedBy,
        docstatus: docstatus,
      );

  Map<String, dynamic> toJson({String? purpose}) {
    final sides = purpose == null
        ? (source: !isOutput, target: true)
        : movementSides(purpose);
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'qty': qty,
      'basic_rate': basicRate,
      'batch_no': batchNo,
      if (sides.source) 's_warehouse': sWarehouse,
      if (sides.target) 't_warehouse': tWarehouse,
      'rack': rack,
      'to_rack': toRack,
      'custom_invoice_serial_number': customInvoiceSerialNumber,
      'material_request':      materialRequest,
      'material_request_item': materialRequestItem,
      'use_serial_batch_fields': 1,
      'is_finished_item':      isFinishedItem,
      if (secondaryItemType != null) 'secondary_item_type': secondaryItemType,
      if (valuationType != null) 'valuation_type': valuationType,
    };
    if (name != null) data['name'] = name;
    return data;
  }
}
