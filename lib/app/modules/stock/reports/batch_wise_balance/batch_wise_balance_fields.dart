import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

const batchQuantityHeaders = {
  'opening_qty': 'Opening Qty',
  'in_qty': 'In Qty',
  'out_qty': 'Out Qty',
  'balance_qty': 'Balance Qty',
};

final batchFields = ReportFieldsDefinition(
  id: 'batch_wise_balance',
  sections: const [
    (id: 'batch', title: 'Batch rows'),
    (id: 'identity', title: 'Fixed identity'),
  ],
  fields: [
    const ReportField(
      key: 'balance_qty',
      column: (fieldname: 'balance_qty', label: 'Balance Qty'),
      section: 'batch',
      defaultVisible: true,
    ),
    for (final column in const {
      'item': 'Item',
      'item_name': 'Item Name',
      'warehouse': 'Warehouse',
      'batch': 'Batch',
    }.entries)
      ReportField(
        key: column.key,
        column: (fieldname: column.key, label: column.value),
        section: 'identity',
        defaultVisible: true,
        locked: true,
      ),
  ],
  alwaysShown: 'Item, item name, warehouse, batch and totals always show.',
);

const batchColumnAliases = {
  'batch': ['batch_no'],
  'balance_qty': ['bal_qty', 'balance'],
};

typedef BatchOccurrence = ({
  Object? item,
  Object? warehouse,
  Object? batch,
  int occurrence,
});

List<BatchOccurrence> batchOccurrences(List<Map<String, dynamic>> rows) {
  final next = <(Object?, Object?, Object?), int>{};
  return [
    for (final row in rows)
      (
        item: row['item'],
        warehouse: row['warehouse'],
        batch: row['batch'],
        occurrence: next.update(
          (row['item'], row['warehouse'], row['batch']),
          (count) => count + 1,
          ifAbsent: () => 0,
        ),
      ),
  ];
}

num? batchQuantity(Object? value) {
  final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
  return parsed?.isFinite == true ? parsed : null;
}

Map<String, Map<String, num>> batchTotals(List<Map<String, dynamic>> rows) {
  final result = <String, Map<String, num>>{};
  for (final row in rows) {
    final unit = row['uom']?.toString().trim() ?? '';
    for (final key in batchQuantityHeaders.keys) {
      final quantity = batchQuantity(row[key]);
      if (quantity == null) continue;
      result
          .putIfAbsent(unit, () => {})
          .update(key, (total) => total + quantity, ifAbsent: () => quantity);
    }
  }
  return result;
}
