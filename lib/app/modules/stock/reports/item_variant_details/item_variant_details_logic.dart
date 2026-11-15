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
    [for (final r in rows) if (!isTemplateRow(r)) r];

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
      if (row[field] != null)
        (
          label: (labels[field]?.isNotEmpty ?? false) ? labels[field]! : field,
          value: formatReportNumber(row[field]),
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
