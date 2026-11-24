class SuppliersByItemFilters {
  const SuppliersByItemFilters({
    this.items = const [],
    this.variantOf = const [],
    this.suppliers = const [],
    this.warehouses = const [],
    this.includeDrafts = true,
    this.expandBom = false,
  });

  final List<String> items;
  final List<String> variantOf;
  final List<String> suppliers;
  final List<String> warehouses;
  final bool includeDrafts;
  final bool expandBom;

  Map<String, List<String>> get linkFilters {
    final links =
        {
          'items': items,
          'variant_of': variantOf,
          'suppliers': suppliers,
          'warehouses': warehouses,
        }.map((key, codes) {
          final normalized = codes
              .map((code) => code.trim())
              .where((code) => code.isNotEmpty)
              .toSet()
              .toList();
          return MapEntry(key, normalized);
        });
    return links..removeWhere((_, codes) => codes.isEmpty);
  }

  Map<String, Object> toJson() => {
    ...linkFilters,
    'include_drafts': includeDrafts ? 1 : 0,
    'expand_bom': expandBom ? 1 : 0,
  };
}

class SuppliersByItemReportException implements Exception {
  const SuppliersByItemReportException(
    this.message, {
    this.permissionDenied = false,
  });

  static const denied =
      'You need the Purchase User or Stock User role to view Suppliers by Item.';

  final String message;
  final bool permissionDenied;

  @override
  String toString() => message;
}

enum SuppliersByItemRowKind {
  template,
  item,
  supplier,
  placeholder,
  bom,
  component,
}

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
    required this.bomNo,
    required this.isComponent,
    required Map row,
  }) : itemName = _text(row['item_name']),
       supplierName = _text(row['supplier_name']),
       supplierStatus = _text(row['supplier_status']),
       supplierPartNumber = _text(row['supplier_part_number']),
       sources = _text(row['sources']),
       openOrderQty = _number(row['open_order_qty']),
       draftOrderQty = _number(row['draft_order_qty']),
       leadTimeDays = _number(row['lead_time_days']),
       leadTimeReceipts = _number(row['lead_time_receipts'])?.toInt(),
       poCount = _number(row['po_count'])?.toInt(),
       receiptCount = _number(row['receipt_count'])?.toInt(),
       lastPurchaseDate = _text(row['last_purchase_date']),
       lastPurchaseReceipt = _text(row['last_purchase_receipt']),
       lastRate = _number(row['last_rate']),
       rateSource = _text(row['rate_source']),
       rateDate = _text(row['rate_date']),
       rateDocument = _text(row['rate_document']),
       currency = _text(row['currency']),
       rateUom = _text(row['rate_uom']),
       totalQtyReceived = _number(row['total_qty_received']),
       balanceQty = kind == SuppliersByItemRowKind.supplier
           ? null
           : _number(row['balance_qty']),
       projectedQty = kind == SuppliersByItemRowKind.supplier
           ? null
           : _number(row['projected_qty']),
       reorderLevel = kind == SuppliersByItemRowKind.supplier
           ? null
           : _number(row['reorder_level']),
       reorderQty = kind == SuppliersByItemRowKind.supplier
           ? null
           : _number(row['reorder_qty']),
       matchedSupplier =
           kind == SuppliersByItemRowKind.supplier &&
           _isChecked(row['matched_supplier']),
       stockUom = _text(row['stock_uom']),
       lastPoDate = _text(row['last_po_date']),
       supplierCount = _number(row['supplier_count'])?.toInt(),
       bomIsDefault = _isChecked(row['bom_is_default']),
       bomStatus = _text(row['bom_status']),
       componentCount = _number(row['component_count'])?.toInt(),
       componentSupplierCount = _number(
         row['component_supplier_count'],
       )?.toInt(),
       bomQtyPerUnit = _number(row['bom_qty_per_unit']),
       includeInManufacturing = row['include_in_manufacturing'] == null
           ? null
           : _isChecked(row['include_in_manufacturing']),
       usedInBomCount = _number(row['used_in_bom_count'])?.toInt(),
       bomCycle = _isChecked(row['bom_cycle']),
       bomDepthLimit = _isChecked(row['bom_depth_limit']);

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
  final String? supplierStatus;
  final String? supplierPartNumber;
  final String? sources;
  final num? openOrderQty;
  final num? draftOrderQty;
  final num? leadTimeDays;
  final int? leadTimeReceipts;
  final int? poCount;
  final int? receiptCount;
  final String? lastPurchaseDate;
  final String? lastPurchaseReceipt;
  final num? lastRate;
  final String? rateSource;
  final String? rateDate;
  final String? rateDocument;
  final String? currency;
  final String? rateUom;
  final num? totalQtyReceived;
  final num? balanceQty;
  final num? projectedQty;
  final num? reorderLevel;
  final num? reorderQty;
  final bool matchedSupplier;
  final String? stockUom;
  final String? lastPoDate;
  final int? supplierCount;
  final bool isComponent;
  final String? bomNo;
  final bool bomIsDefault;
  final String? bomStatus;
  final int? componentCount;
  final int? componentSupplierCount;
  final num? bomQtyPerUnit;
  final bool? includeInManufacturing;
  final int? usedInBomCount;
  final bool bomCycle;
  final bool bomDepthLimit;

  bool get isBelowReorderLevel {
    final projected = projectedQty;
    final level = reorderLevel;
    return projected != null && level != null && level > 0 && projected < level;
  }

  static SuppliersByItemRow? _parse(Map row) {
    final nodeId = _text(row['node_id']);
    if (nodeId == null) return null;
    final rowType = _text(row['row_type']);
    if (rowType == null && _isChecked(row['is_placeholder'])) return null;
    final separator = nodeId.indexOf(':');
    final kind = switch (rowType ??
        (separator < 0 ? null : nodeId.substring(0, separator))) {
      'template' => SuppliersByItemRowKind.template,
      'item' => SuppliersByItemRowKind.item,
      'supplier' => SuppliersByItemRowKind.supplier,
      'placeholder' || 'none' => SuppliersByItemRowKind.placeholder,
      'bom' => SuppliersByItemRowKind.bom,
      'component' => SuppliersByItemRowKind.component,
      _ => null,
    };
    if (kind == null) return null;

    final parentId = _text(row['parent_id']);
    final isComponent = _isChecked(row['is_component']);
    final hasPathId =
        isComponent ||
        kind == SuppliersByItemRowKind.bom ||
        kind == SuppliersByItemRowKind.component ||
        (parentId?.startsWith('component:') ?? false);
    final template =
        _text(row['template']) ??
        (hasPathId
            ? null
            : _identifier(
                kind == SuppliersByItemRowKind.template ? nodeId : parentId,
                'template:',
              ));
    final itemCode =
        _text(row['item_code']) ??
        (hasPathId
            ? null
            : _identifier(
                kind == SuppliersByItemRowKind.item ? nodeId : parentId,
                'item:',
              ));
    final supplier =
        _text(row['supplier']) ??
        (!hasPathId && kind == SuppliersByItemRowKind.supplier
            ? _supplierIdentifier(_identifier(nodeId, 'supplier:'), itemCode)
            : null);
    final bomNo = _text(row['bom_no']);
    final fallbackLabel = switch (kind) {
      SuppliersByItemRowKind.placeholder => 'No supplier recorded',
      SuppliersByItemRowKind.bom => bomNo ?? 'BOM',
      SuppliersByItemRowKind.component => itemCode ?? 'Component',
      SuppliersByItemRowKind.supplier when hasPathId => supplier ?? 'Supplier',
      _ => supplier ?? itemCode ?? template ?? nodeId,
    };
    final indent =
        _number(row['indent'])?.toInt() ??
        switch (kind) {
          SuppliersByItemRowKind.template => 0,
          SuppliersByItemRowKind.item => parentId == null ? 0 : 1,
          _ => 1,
        };
    return SuppliersByItemRow._(
      kind: kind,
      nodeId: nodeId,
      parentId: parentId,
      indent: indent,
      treeLabel: _text(row['tree_label']) ?? fallbackLabel,
      template: template,
      itemCode: itemCode,
      supplier: supplier,
      bomNo: bomNo,
      isComponent: isComponent,
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

  static bool _isChecked(Object? value) => value == true || _number(value) == 1;

  static num? _number(Object? value) {
    final number = value is num ? value : num.tryParse(_text(value) ?? '');
    return number != null && number.isFinite ? number : null;
  }
}

class SuppliersByItemQuantityTotals {
  const SuppliersByItemQuantityTotals({
    this.balanceQty,
    this.projectedQty,
    this.openOrderQty,
  });

  final num? balanceQty;
  final num? projectedQty;
  final num? openOrderQty;
}

class SuppliersByItemNode {
  const SuppliersByItemNode({required this.row, this.children = const []});

  final SuppliersByItemRow row;
  final List<SuppliersByItemNode> children;

  /// Checks the item's own suppliers, or its variants for a template.
  bool get hasSuppliers =>
      row.kind == SuppliersByItemRowKind.supplier ||
      children.any(
        (child) =>
            child.row.kind != SuppliersByItemRowKind.bom &&
            (row.kind == SuppliersByItemRowKind.component ||
                !child.row.isComponent) &&
            child.hasSuppliers,
      );

  /// Sums available quantity fields from top-level items and variants by UOM.
  static Map<String, SuppliersByItemQuantityTotals> quantityTotalsByUom(
    Iterable<SuppliersByItemNode> nodes,
  ) {
    final totals = <String, SuppliersByItemQuantityTotals>{};

    num? add(num? total, num? quantity) =>
        quantity == null ? total : (total ?? 0) + quantity;

    void addQuantities(Iterable<SuppliersByItemNode> nodes) {
      for (final node in nodes) {
        final row = node.row;
        if (row.isComponent) continue;
        if ((row.kind, row.stockUom)
            case (SuppliersByItemRowKind.item, final uom?)
            when row.balanceQty != null ||
                row.projectedQty != null ||
                row.openOrderQty != null) {
          final previous = totals[uom];
          totals[uom] = SuppliersByItemQuantityTotals(
            balanceQty: add(previous?.balanceQty, row.balanceQty),
            projectedQty: add(previous?.projectedQty, row.projectedQty),
            openOrderQty: add(previous?.openOrderQty, row.openOrderQty),
          );
        }
        addQuantities(node.children);
      }
    }

    addQuantities(nodes);
    return totals;
  }

  /// Builds the report tree in server order using the explicit parent IDs.
  /// Untyped legacy placeholder rows and non-tree totals are skipped.
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
        case (
          SuppliersByItemRowKind.item || SuppliersByItemRowKind.component,
          SuppliersByItemRowKind.supplier ||
              SuppliersByItemRowKind.placeholder ||
              SuppliersByItemRowKind.bom,
        ):
        case (SuppliersByItemRowKind.bom, SuppliersByItemRowKind.component):
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
