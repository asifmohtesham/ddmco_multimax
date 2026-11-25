import 'package:multimax/app/data/utils/formatting_helper.dart';

import '../../../global_widgets/report_fields/report_field.dart';

const _ledgerLabels = <String, String>{
  'qty_after_transaction': 'Balance Qty',
  'voucher_no': 'Voucher #',
  'voucher_type': 'Voucher Type',
  'date': 'Date',
};

const _aliases = <String, List<String>>{
  'qty_after_transaction': ['balance_qty'],
  'voucher_no': ['voucher_#'],
  'date': ['posting_date'],
};

ReportFieldsDefinition stockLedgerFields([List<DeskColumn>? columns]) {
  return ReportFieldsDefinition(
    id: 'stock_ledger',
    sections: const [
      (id: 'movement', title: 'Ledger movement'),
      (id: 'identity', title: 'Document identity'),
    ],
    fields: [
      for (final MapEntry(:key, :value) in _ledgerLabels.entries)
        ReportField(
          key: key,
          column: (fieldname: key, label: value),
          section: key == 'qty_after_transaction' ? 'movement' : 'identity',
          defaultVisible: true,
          locked: key != 'qty_after_transaction',
        ),
    ],
    alwaysShown:
        'Item, warehouse, vouchers, dates, signed movements and totals stay visible.',
  ).withColumns(columns, aliases: _aliases);
}

String stockLedgerLabel(FieldsState fields, String key) =>
    fields.label(key) ?? _ledgerLabels[key]!;

List<Object> stockLedgerOccurrenceIds(List<Map<String, dynamic>> rows) {
  final counts = <Object, int>{};
  return [for (final row in rows) _ledgerOccurrenceId(row, counts)];
}

Object _ledgerOccurrenceId(Map<String, dynamic> row, Map<Object, int> counts) {
  final name = row['name']?.toString();
  final Object identity = name != null && name.isNotEmpty
      ? name
      : (
          row['voucher_no'],
          row['voucher_type'],
          row['timestamp'] ?? row['date'],
        );
  return (
    identity,
    counts.update(identity, (count) => count + 1, ifAbsent: () => 0),
  );
}

String stockLedgerFooterLabel(
  List<Map<String, dynamic>> rows,
  List<DeskColumn>? columns,
) {
  var inLabel = 'In Qty';
  var outLabel = 'Out Qty';
  for (final column in columns ?? const <DeskColumn>[]) {
    if (column.label.trim().isEmpty) continue;
    if (column.fieldname == 'in_qty') inLabel = column.label;
    if (column.fieldname == 'out_qty') outLabel = column.label;
  }
  final totals = <String, ({double? incoming, double? outgoing})>{};
  for (final row in rows) {
    final signed = row['qty'] as num?;
    final unit = row['stock_uom']?.toString().trim() ?? '';
    final incoming =
        (row['in_qty'] as num?)?.toDouble() ??
        signed?.clamp(0.0, double.infinity).toDouble();
    final outgoing =
        (row['out_qty'] as num?)?.toDouble() ??
        signed?.clamp(double.negativeInfinity, 0.0).toDouble();
    final previous = totals[unit];
    totals[unit] = previous == null
        ? (incoming: incoming, outgoing: outgoing)
        : (
            incoming: _addKnown(previous.incoming, incoming),
            outgoing: _addKnown(previous.outgoing, outgoing),
          );
  }
  return [
    'End of list · ${rows.length} ${rows.length == 1 ? 'movement' : 'movements'}',
    for (final MapEntry(:key, :value) in totals.entries)
      '$inLabel ${_formatMovement(value.incoming)} · '
          '$outLabel ${_formatMovement(value.outgoing)} · '
          '${key.isEmpty ? 'Unknown unit' : key}',
  ].join('\n');
}

double? _addKnown(double? a, double? b) =>
    a == null || b == null ? null : a + b;

String _formatMovement(double? value) {
  if (value == null) return '—';
  final amount = FormattingHelper.formatQtyGrouped(value.abs());
  return value < 0 ? '−$amount' : amount;
}
