import 'package:multimax/app/data/utils/formatting_helper.dart';

class SuppliersByItemFilters {
  const SuppliersByItemFilters({
    this.items = const [],
    this.variantOf = const [],
    this.suppliers = const [],
    this.warehouses = const [],
    this.fromDate,
    this.toDate,
  });

  final List<String> items;
  final List<String> variantOf;
  final List<String> suppliers;
  final List<String> warehouses;
  final DateTime? fromDate;
  final DateTime? toDate;

  bool get hasInvalidDateRange {
    final from = fromDate;
    final to = toDate;
    if (from == null || to == null) return false;
    return DateTime.utc(
      from.year,
      from.month,
      from.day,
    ).isAfter(DateTime.utc(to.year, to.month, to.day));
  }

  Map<String, Object> toJson() => {
    if (items.isNotEmpty) 'items': items,
    if (variantOf.isNotEmpty) 'variant_of': variantOf,
    if (suppliers.isNotEmpty) 'suppliers': suppliers,
    if (warehouses.isNotEmpty) 'warehouses': warehouses,
    if (fromDate case final date?)
      'from_date': FormattingHelper.formatDate(date),
    if (toDate case final date?) 'to_date': FormattingHelper.formatDate(date),
  };
}

class SuppliersByItemReportException implements Exception {
  const SuppliersByItemReportException(
    this.message, {
    this.permissionDenied = false,
  });

  static const invalidDateRange = 'From date must be on or before To date.';
  static const denied =
      'You need the Purchase User or Stock User role to view Suppliers by Item.';

  final String message;
  final bool permissionDenied;

  @override
  String toString() => message;
}

enum SuppliersByItemRowKind { template, item, supplier }

class SuppliersByItemRow {
  SuppliersByItemRow._({
    required this.kind,
    required this.nodeId,
    required this.parentId,
    required this.indent,
    required this.treeLabel,
    required this.template,
    required this.itemCode,
    required this.supplier,
    required Map row,
  }) : itemName = _text(row['item_name']),
       supplierName = _text(row['supplier_name']),
       supplierPartNumber = _text(row['supplier_part_number']),
       sources = _text(row['sources']),
       lastPurchaseDate = _text(row['last_purchase_date']),
       lastPurchaseReceipt = _text(row['last_purchase_receipt']),
       lastRate = _number(row['last_rate']),
       rateSource = _text(row['rate_source']),
       rateDate = _text(row['rate_date']),
       rateDocument = _text(row['rate_document']),
       currency = _text(row['currency']),
       rateUom = _text(row['rate_uom']),
       totalQtyReceived = _number(row['total_qty_received']),
       stockUom = _text(row['stock_uom']),
       lastPoDate = _text(row['last_po_date']),
       supplierCount = _number(row['supplier_count'])?.toInt();

  final SuppliersByItemRowKind kind;
  final String nodeId;
  final String? parentId;
  final int indent;
  final String treeLabel;
  final String? template;
  final String? itemCode;
  final String? supplier;
  final String? itemName;
  final String? supplierName;
  final String? supplierPartNumber;
  final String? sources;
  final String? lastPurchaseDate;
  final String? lastPurchaseReceipt;
  final num? lastRate;
  final String? rateSource;
  final String? rateDate;
  final String? rateDocument;
  final String? currency;
  final String? rateUom;
  final num? totalQtyReceived;
  final String? stockUom;
  final String? lastPoDate;
  final int? supplierCount;

  static SuppliersByItemRow? _parse(Map row) {
    if (_number(row['is_placeholder']) == 1) return null;
    final nodeId = _text(row['node_id']);
    if (nodeId == null) return null;
    final separator = nodeId.indexOf(':');
    if (separator < 0) return null;
    final kind = switch (nodeId.substring(0, separator)) {
      'template' => SuppliersByItemRowKind.template,
      'item' => SuppliersByItemRowKind.item,
      'supplier' => SuppliersByItemRowKind.supplier,
      _ => null,
    };
    if (kind == null) return null;

    final identifier = _text(nodeId.substring(separator + 1));
    final parentId = _text(row['parent_id']);
    final template =
        _text(row['template']) ??
        (kind == SuppliersByItemRowKind.template
            ? identifier
            : _identifier(parentId, 'template:'));
    final itemCode =
        _text(row['item_code']) ??
        (kind == SuppliersByItemRowKind.item
            ? identifier
            : _identifier(parentId, 'item:'));
    final supplier =
        _text(row['supplier']) ??
        (kind == SuppliersByItemRowKind.supplier
            ? _supplierIdentifier(identifier, itemCode)
            : null);
    final indent =
        _number(row['indent'])?.toInt() ??
        switch (kind) {
          SuppliersByItemRowKind.template => 0,
          SuppliersByItemRowKind.item => parentId == null ? 0 : 1,
          SuppliersByItemRowKind.supplier => 1,
        };
    return SuppliersByItemRow._(
      kind: kind,
      nodeId: nodeId,
      parentId: parentId,
      indent: indent,
      treeLabel:
          _text(row['tree_label']) ??
          supplier ??
          itemCode ??
          template ??
          nodeId,
      template: template,
      itemCode: itemCode,
      supplier: supplier,
      row: row,
    );
  }

  static String? _identifier(String? nodeId, String prefix) =>
      nodeId != null && nodeId.startsWith(prefix)
      ? _text(nodeId.substring(prefix.length))
      : null;

  // Older reports used supplier:<item code>:<supplier> with no plain fields.
  // The item parent supplies the prefix even when its code contains a colon.
  static String? _supplierIdentifier(String? identifier, String? itemCode) =>
      itemCode == null
      ? identifier
      : _identifier(identifier, '$itemCode:') ?? identifier;

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static num? _number(Object? value) {
    final number = value is num ? value : num.tryParse(_text(value) ?? '');
    return number != null && number.isFinite ? number : null;
  }
}

class SuppliersByItemNode {
  const SuppliersByItemNode({required this.row, this.children = const []});

  final SuppliersByItemRow row;
  final List<SuppliersByItemNode> children;

  bool get hasSuppliers =>
      row.kind == SuppliersByItemRowKind.supplier ||
      children.any((child) => child.hasSuppliers);

  /// Builds the report tree in server order using the explicit parent IDs.
  /// Desk-only placeholder rows and non-tree totals are skipped.
  /// Rows with missing parents stay visible.
  static List<SuppliersByItemNode> parseRows(List<dynamic> result) {
    final rows = <String, SuppliersByItemRow>{};
    for (final raw in result.whereType<Map>()) {
      final row = SuppliersByItemRow._parse(raw);
      if (row != null) rows.putIfAbsent(row.nodeId, () => row);
    }

    final roots = <SuppliersByItemRow>[];
    final children = <String, List<SuppliersByItemRow>>{};
    for (final row in rows.values) {
      final parent = rows[row.parentId];
      switch ((parent?.kind, row.kind)) {
        case (SuppliersByItemRowKind.template, SuppliersByItemRowKind.item):
        case (SuppliersByItemRowKind.item, SuppliersByItemRowKind.supplier):
          (children[parent!.nodeId] ??= []).add(row);
        default:
          roots.add(row);
      }
    }

    SuppliersByItemNode build(SuppliersByItemRow row) => SuppliersByItemNode(
      row: row,
      children: List.unmodifiable((children[row.nodeId] ?? []).map(build)),
    );
    return List.unmodifiable(roots.map(build));
  }
}
