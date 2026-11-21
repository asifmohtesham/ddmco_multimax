// Pure helpers for the Item Variant Details report screen.
//
// ERPNext v16.55 changed the shape of this report's result. Up to v15 every
// row is a variant:
//
//   {variant_name: '2000308', colour: 'MIX', current_stock: 0, …}
//
// From v16.55 the variants of each template are listed under a subtotal row
// for the template itself, and every row says how deep it sits:
//
//   {variant_name: '---WAL', item_group: 'Wallets', indent: 0,
//    current_stock: 12, in_production: 0, open_orders: 1}      ← template
//   {variant_name: '1001439', template: '---WAL', indent: 1,
//    colour: 'MIX', current_stock: 12, …}                      ← variant
//
// The template row is a heading with totals, not a variant: it has no
// attributes, and its stock figures are null when its variants do not share
// a stock UOM.

/// The report fields a template row totals, in report order.
const kTemplateTotalFields = ['current_stock', 'in_production', 'open_orders'];

const _nonChipFields = {
  'variant_name',
  'item',
  'item_name',
  'variant_of',
  'item_group',
  'stock_uom',
  'current_stock',
  'in_production',
  'open_orders',
  'avg_buying_price_list_rate',
  'avg_selling_price_list_rate',
};

/// Populated chip values in the report's column order.
Iterable<({String label, String value})> variantChips(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> columns,
) sync* {
  for (final column in columns) {
    final field = column['fieldname'] as String?;
    if (field == null || _nonChipFields.contains(field)) continue;
    final value = row[field]?.toString().trim();
    if (value == null || value.isEmpty || value == '-' || value == '—') {
      continue;
    }
    yield (label: column['label'] as String? ?? field, value: value);
  }
}

/// Whether [row] is a template subtotal row rather than a variant.
///
/// Must hold on both server versions: a v15 row carries no `indent` at all
/// and is always a variant.
bool isTemplateRow(Map<String, dynamic> row) {
  // `indent` is the report's own statement of depth, so it is the signal
  // rather than a missing `template` key (v15 variants lack that too).
  // A missing indent is a v15 row; JSON may send the number as 0 or 0.0.
  final indent = row['indent'];
  return indent is num && indent == 0;
}

/// The rows of [rows] that are variants, in report order.
List<Map<String, dynamic>> variantRowsOf(Iterable<Map<String, dynamic>> rows) =>
    [
      for (final r in rows)
        if (!isTemplateRow(r)) r,
    ];

/// The totals a template [row] carries, as `label → value` in report order.
///
/// Labels are the report's own column labels from [columns], so the heading
/// reads the same as the Desk report. A figure the server left empty (mixed
/// stock UOMs) is omitted rather than shown as zero.
List<({String label, String value})> templateTotals(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> columns,
) {
  final labels = {
    for (final c in columns)
      if (c['fieldname'] is String)
        c['fieldname'] as String: (c['label'] as String?) ?? '',
  };
  return [
    for (final field in kTemplateTotalFields)
      if (formatReportNumber(row[field]).trim().isNotEmpty)
        (
          label: (labels[field]?.isNotEmpty ?? false) ? labels[field]! : field,
          value: formatStockQuantity(
            row[field],
            field == 'open_orders' ? null : row['stock_uom'],
          ),
        ),
  ];
}

/// A report figure without a trailing `.0` (`12.0` → `12`, `1.5` → `1.5`).
String formatReportNumber(dynamic value) {
  if (value is num) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }
  return value?.toString() ?? '';
}

/// Formats a stock figure using the unit supplied by the report.
String formatStockQuantity(dynamic value, Object? stockUom) {
  final quantity = formatReportNumber(value).trim();
  final unit = stockUom?.toString().trim();
  if (quantity.isEmpty ||
      unit == null ||
      unit.isEmpty ||
      unit == '-' ||
      unit == '—') {
    return quantity;
  }
  return '$quantity $unit';
}

/// Sums variant quantities by stock UOM. Template subtotals, sales-order
/// counts and rates are excluded.
List<String> variantQuantitySummary(
  Iterable<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> columns,
) {
  const quantityFields = ['current_stock', 'in_production'];
  final totalsByUom = <String, Map<String, num>>{};
  for (final row in rows) {
    if (isTemplateRow(row)) continue;
    final uom = row['stock_uom']?.toString() ?? '';
    final totals = totalsByUom.putIfAbsent(uom, () => {});
    for (final field in quantityFields) {
      final value = row[field];
      if (value is num) {
        totals.update(field, (sum) => sum + value, ifAbsent: () => value);
      }
    }
  }
  final labels = {
    for (final column in columns) column['fieldname']: column['label'],
  };
  return [
    for (final entry in totalsByUom.entries)
      for (final field in quantityFields)
        if (entry.value.containsKey(field))
          '${labels[field] ?? (field == 'current_stock' ? 'Current Stock' : 'In Production')} '
              '${formatReportNumber(entry.value[field])}'
              '${entry.key.isEmpty ? '' : ' ${entry.key}'}',
  ];
}

String variantCode(Map<String, dynamic> row) =>
    (row['variant_name'] ?? row['item'] ?? '').toString();

typedef VariantRow = Map<String, dynamic>;

class VariantGroup {
  final VariantRow? heading;
  final List<VariantRow> variants;

  const VariantGroup(this.heading, this.variants);

  String get code => heading == null ? '' : variantCode(heading!);
}

class VariantResults {
  static const collapseAboveVariants = 200;

  final groups = <VariantGroup>[];
  final variants = <VariantRow>[];
  final _searchText = <VariantRow, List<String>>{};
  final _templateCodes = <VariantGroup, String>{};
  final _overrides = <VariantGroup>{};
  late final int templateCount;
  late bool _collapsed;

  VariantResults(
    Iterable<VariantRow> rows,
    List<VariantRow> columns, {
    String? singleRequestedTemplate,
  }) {
    VariantGroup? group;
    for (final row in rows) {
      if (isTemplateRow(row)) {
        group = VariantGroup(row, []);
        groups.add(group);
        _templateCodes[group] = group.code.toLowerCase();
        continue;
      }
      if (group == null) {
        group = VariantGroup(null, []);
        groups.add(group);
      }
      group.variants.add(row);
      variants.add(row);
      _searchText[row] = [
        variantCode(row),
        if (row['item_name'] != null) row['item_name'].toString(),
        if (row['template'] != null) row['template'].toString(),
        if (row['variant_of'] != null) row['variant_of'].toString(),
        if (group.heading == null && singleRequestedTemplate != null)
          singleRequestedTemplate,
        ...variantChips(row, columns).map((chip) => chip.value),
      ].map((value) => value.toLowerCase()).toList();
    }
    templateCount = _templateCodes.length;
    _collapsed = variants.length > collapseAboveVariants;
  }

  ({bool collapsed, Set<VariantGroup> overrides}) get expansion =>
      (collapsed: _collapsed, overrides: _overrides.toSet());

  void restoreExpansion(({bool collapsed, Set<VariantGroup> overrides}) state) {
    _collapsed = state.collapsed;
    _overrides
      ..clear()
      ..addAll(state.overrides);
  }

  bool isExpanded(VariantGroup group) =>
      group.heading == null || _collapsed == _overrides.contains(group);

  void toggle(VariantGroup group) {
    if (!_overrides.add(group)) _overrides.remove(group);
  }

  void setAllExpanded(bool expanded) {
    _collapsed = !expanded;
    _overrides.clear();
  }

  List<({VariantGroup group, List<VariantRow> variants})> filter({
    String query = '',
    bool inStock = false,
    Map<String, VariantRow> details = const {},
  }) {
    final term = query.trim().toLowerCase();
    final result = <({VariantGroup group, List<VariantRow> variants})>[];
    for (final group in groups) {
      if (term.isEmpty && !inStock) {
        result.add((group: group, variants: group.variants));
        continue;
      }
      final headingMatches =
          term.isNotEmpty && (_templateCodes[group]?.contains(term) ?? false);
      final matches = [
        for (final row in group.variants)
          if ((!inStock ||
                  (num.tryParse('${row['current_stock']}') ?? 0) > 0) &&
              (term.isEmpty ||
                  headingMatches ||
                  _searchText[row]!.any((value) => value.contains(term)) ||
                  (details[variantCode(row)]?['item_name']
                          ?.toString()
                          .toLowerCase()
                          .contains(term) ??
                      false)))
            row,
      ];
      if (matches.isNotEmpty || (headingMatches && !inStock)) {
        result.add((group: group, variants: matches));
      }
    }
    return result;
  }
}
