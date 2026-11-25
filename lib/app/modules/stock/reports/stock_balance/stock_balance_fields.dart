import 'dart:convert';

import 'package:multimax/app/data/providers/api_provider.dart';

import '../../../global_widgets/report_fields/report_field.dart';

const stockBalanceAliases = <String, List<String>>{
  'item_code': ['item'],
  'bal_qty': ['balance_qty'],
  'val_rate': ['valuation_rate'],
  'bal_val': ['balance_value', 'balance_val'],
  'reserved_stock': ['reserved_qty'],
};

const stockBalanceHeaderLabels = <String, String>{
  'item_code': 'Item',
  'item_name': 'Item Name',
  'warehouse': 'Warehouse',
  'bal_qty': 'Balance Qty',
  'stock_uom': 'Stock UOM',
  'opening_qty': 'Opening Qty',
  'in_qty': 'In Qty',
  'out_qty': 'Out Qty',
  'val_rate': 'Valuation Rate',
  'bal_val': 'Balance Value',
  'reserved_stock': 'Reserved Stock',
  'average_age': 'Average Age',
  'earliest_age': 'Earliest Age',
  'latest_age': 'Latest Age',
};

const _sections = <FieldSection>[
  (id: 'balance', title: 'Balance row'),
  (id: 'movement', title: 'Movement strip'),
  (id: 'valuation', title: 'Valuation'),
  (id: 'reservation', title: 'Reservation detail'),
  (id: 'age', title: 'Age details'),
  (id: 'attributes', title: 'Card details'),
  (id: 'converted', title: 'Converted units'),
  (id: 'identity', title: 'Identity and location'),
];

ReportField _stockField(
  String key,
  String section, {
  bool visible = true,
  bool locked = false,
  String? requiresKey,
}) => ReportField(
  key: key,
  column: (fieldname: key, label: stockBalanceHeaderLabels[key]!),
  section: section,
  defaultVisible: visible,
  locked: locked,
  requiresKey: requiresKey,
);

const _nonResidual = {
  'item_code',
  'item',
  'item_name',
  'item_group',
  'description',
  'warehouse',
  'stock_uom',
  'opening_qty',
  'opening_val',
  'in_qty',
  'in_val',
  'out_qty',
  'out_val',
  'bal_qty',
  'bal_val',
  'val_rate',
  'balance_qty',
  'balance_value',
  'balance_val',
  'valuation_rate',
  'reserved_stock',
  'reserved_qty',
  'customer_code',
  'item_image',
  'company',
};

const _ageKeys = ['average_age', 'earliest_age', 'latest_age'];

ReportFieldsDefinition stockBalanceFields([
  List<Map<String, dynamic>>? columns,
]) {
  final descriptors = columns ?? const [];
  final dimensions = stockBalanceDimensionKeys(descriptors);
  final dynamicFields = <ReportField>[];
  final seen = <String>{};
  for (final col in stockBalanceResidualColumns(descriptors)) {
    final descriptor = decodeDeskColumn(col);
    if (descriptor == null || !seen.add(descriptor.fieldname)) continue;
    final key = descriptor.fieldname;
    final locked = dimensions.contains(key);
    final label = stockBalanceColumnLabel(col);
    if (_ageKeys.contains(key) || label.isEmpty) continue;
    dynamicFields.add(
      ReportField(
        key: key,
        column: (fieldname: key, label: label),
        section: locked
            ? 'identity'
            : key.endsWith('_alt') ||
                  key == 'alt_uom' ||
                  key == 'alt_uom_bal_qty'
            ? 'converted'
            : 'attributes',
        defaultVisible: locked || stockBalanceLegacyVisible(col),
        locked: locked,
        retainExplicitDefault: !locked &&
            stockBalanceLegacyVisible(col) &&
            col['legacy_fallback'] == true,
      ),
    );
  }

  final definition = ReportFieldsDefinition(
    id: 'stock_balance',
    sections: _sections,
    fields: [
      _stockField('bal_qty', 'balance'),
      _stockField('stock_uom', 'balance', requiresKey: 'bal_qty'),
      _stockField('opening_qty', 'movement'),
      _stockField('in_qty', 'movement'),
      _stockField('out_qty', 'movement'),
      _stockField('val_rate', 'valuation'),
      _stockField('bal_val', 'valuation'),
      _stockField('reserved_stock', 'reservation', visible: false),
      if (columns != null)
        for (final key in _ageKeys) _stockField(key, 'age'),
      _stockField('item_code', 'identity', locked: true),
      _stockField('item_name', 'identity', locked: true),
      _stockField('warehouse', 'identity', locked: true),
      ...dynamicFields,
    ],
    alwaysShown:
        'Item, warehouse, rack, stock status, drill-downs and totals stay visible.',
  );
  if (columns == null) return definition.immutable();
  return definition.withColumns([
    for (final column in columns)
      if (decodeDeskColumn(column) case final descriptor?)
        (
          fieldname: descriptor.fieldname,
          label: stockBalanceColumnLabel(column),
        ),
  ], aliases: stockBalanceAliases);
}

List<Map<String, dynamic>> stockBalanceResidualColumns(
  List<Map<String, dynamic>> columns,
) => [
  for (final column in columns)
    if (column['fieldname'] case final String key
        when key.isNotEmpty && !_nonResidual.contains(key.toLowerCase()))
      column,
];

String stockBalanceColumnLabel(Map<String, dynamic> column) {
  final label = column['label'];
  if (label is String && label.trim().isNotEmpty) return label;
  final key = column['fieldname'];
  if (stockBalanceHeaderLabels[key] case final verified?) return verified;
  for (final MapEntry(:key, :value) in stockBalanceAliases.entries) {
    if (value.contains(column['fieldname'])) {
      return stockBalanceHeaderLabels[key]!;
    }
  }
  return key == 'rack' ? 'Rack' : '';
}

bool stockBalanceLegacyVisible(Map<String, dynamic> column) {
  final key = column['fieldname'] as String? ?? '';
  return key.toLowerCase() != 'brand' &&
      (column['legacy_visible'] as bool? ?? true);
}

Object? stockBalanceColumnValue(
  Map<String, dynamic> row,
  Map<String, dynamic> column, {
  bool legacyMapLookup = false,
}) {
  final key = column['fieldname'];
  final legacy = column['legacy_fieldname'];
  if (legacyMapLookup &&
      row[ApiProvider.stockBalancePositionalRowKey] != true &&
      legacy is String) {
    return row[legacy];
  }
  if (row.containsKey(key)) return row[key];
  return column['legacy_fallback'] == true
      ? row[legacy]
      : null;
}

bool stockBalanceRackColumn(Map<String, dynamic> column) {
  final name = column['fieldname']?.toString().toLowerCase();
  final doctype = column['options']?.toString().toLowerCase();
  return name == 'rack' || doctype == 'rack' || doctype == 'warehouse rack';
}

Set<String> stockBalanceDimensionKeys(List<Map<String, dynamic>> columns) {
  final dimensions = <String>{};
  var dimensionBlock = false;
  for (final column in columns) {
    final key = column['fieldname'];
    if (key is! String || key.isEmpty) continue;
    if (key == 'warehouse') dimensionBlock = true;
    if (key == 'stock_uom') dimensionBlock = false;
    if (stockBalanceRackColumn(column) ||
        const {
          'batch_no',
          'serial_no',
          'serial_and_batch_bundle',
        }.contains(key) ||
        (dimensionBlock &&
            !_nonResidual.contains(key.toLowerCase()) &&
            column['fieldtype'] == 'Link')) {
      dimensions.add(key);
    }
  }
  return dimensions;
}

List<Object> stockBalanceOccurrenceIds(
  List<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> columns,
) {
  final occurrences = <String, int>{};
  final keys = stockBalanceDimensionKeys(columns);
  final dimensions = columns.where(
    (column) => keys.contains(column['fieldname']),
  );
  return [
    for (final row in rows)
      _stockBalanceOccurrence(row, dimensions, occurrences),
  ];
}

Object _stockBalanceOccurrence(
  Map<String, dynamic> row,
  Iterable<Map<String, dynamic>> dimensions,
  Map<String, int> occurrences,
) {
  final identity = jsonEncode([
    row['item_code'],
    row['company'],
    row['warehouse'],
    for (final column in dimensions) stockBalanceColumnValue(row, column),
  ]);
  final occurrence = occurrences.update(
    identity,
    (count) => count + 1,
    ifAbsent: () => 0,
  );
  return (identity: identity, occurrence: occurrence);
}
