import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

const posDetailHeaders = {
  'item_group': 'Item Group',
  'customer_group': 'Customer Group',
  'upload_qty': 'POS Qty',
  'upload_rate': 'POS Rate',
  'dn_qty': 'DN Qty',
};

const posIdentityHeaders = {
  'status': 'Status',
  'ref_code': 'Customer Code',
  'item_code': 'Item Code',
  'dn_item': 'DN Item Name',
  'upload_item': 'POS Item Name',
  'customer': 'Customer',
  'dn_name': 'DN #',
  'pos_upload': 'POS #',
  'idx': 'Invoice Serial Number',
};

final _posFieldsByCaption = {
  for (final entry in {...posDetailHeaders, ...posIdentityHeaders}.entries)
    entry.value.toLowerCase(): entry.key,
};

List<DeskColumn> decodePosColumns(List<dynamic> descriptors) {
  final columns = decodeDeskColumns(descriptors);
  return List.unmodifiable(
    columns.indexed.map(((int, DeskColumn) entry) {
      final (index, column) = entry;
      final fieldname = descriptors[index] is String
          ? _posFieldsByCaption[column.label.toLowerCase()]
          : null;
      return (fieldname: fieldname ?? column.fieldname, label: column.label);
    }),
  );
}

final posFields = ReportFieldsDefinition(
  id: 'pos_dn_item_rate',
  sections: const [(id: 'leaves', title: 'Report rows')],
  fields: [
    for (final entry in posDetailHeaders.entries)
      ReportField(
        key: entry.key,
        column: (fieldname: entry.key, label: entry.value),
        section: 'leaves',
        defaultVisible: true,
      ),
  ],
  alwaysShown:
      'Row identities, status, voucher links, groups and quantity totals always show.',
);

String posFieldLabel(FieldsState? fields, String key) =>
    fields?.label(key) ?? posDetailHeaders[key] ?? posIdentityHeaders[key]!;
