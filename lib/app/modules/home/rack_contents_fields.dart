import '../global_widgets/report_fields/report_field.dart';
import 'rack_contents_logic.dart';

const rackContentsLabels = <String, String>{
  'bal_qty': 'Balance Qty',
  'stock_uom': 'Stock UOM',
  'item_group': 'Item Group',
};

ReportFieldsDefinition rackContentsFields([List<DeskColumn>? columns]) {
  return ReportFieldsDefinition(
    id: 'rack_contents',
    sections: const [(id: 'stock', title: 'Rack stock card')],
    fields: [
      for (final MapEntry(:key, :value) in rackContentsLabels.entries)
        ReportField(
          key: key,
          column: (fieldname: key, label: value),
          section: 'stock',
          defaultVisible: true,
          requiresKey: key == 'stock_uom' ? 'bal_qty' : null,
        ),
    ],
    alwaysShown:
        'Rack, item and batch identities, availability messages and totals stay visible.',
  ).withColumns(
    columns,
    aliases: const {
      'bal_qty': ['balance_qty'],
    },
  );
}

String rackContentsIdentityLabel(List<DeskColumn>? columns, String fieldname) {
  for (final column in columns ?? const <DeskColumn>[]) {
    if (column.fieldname == fieldname && column.label.trim().isNotEmpty) {
      return column.label;
    }
  }
  return const {
    'batch_no': 'Batch No',
    'item_code': 'Item',
    'item_name': 'Item Name',
    'warehouse': 'Warehouse',
  }[fieldname]!;
}

List<Object> rackContentsOccurrenceIds(
  String rack,
  List<RackContentsEntry> entries,
) {
  final counts = <(String, String?), int>{};
  return [
    for (final entry in entries)
      (
        rack,
        entry.itemCode,
        entry.batchNo,
        counts.update(
          (entry.itemCode, entry.batchNo),
          (count) => count + 1,
          ifAbsent: () => 0,
        ),
      ),
  ];
}
