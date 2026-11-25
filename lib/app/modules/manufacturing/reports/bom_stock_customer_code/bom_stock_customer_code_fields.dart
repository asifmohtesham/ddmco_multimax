import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

const bomStockFields = ReportFieldsDefinition(
  id: 'bom_stock_customer_code',
  sections: [
    (id: 'items', title: 'Flat cards and POS lines'),
    (id: 'flat', title: 'Flat cards'),
    (id: 'pos', title: 'Expanded POS lines'),
  ],
  alwaysShown:
      'Item and group identities, shortage status, POS line shortage and '
      'totals always show.',
  fields: [
    ReportField(
      key: 'item_code',
      column: (fieldname: 'item_code', label: 'Item'),
      section: 'items',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'item_name',
      column: (fieldname: 'item_name', label: 'Item Name'),
      section: 'items',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'customer_code',
      column: (fieldname: 'customer_code', label: 'Customer Code'),
      section: 'items',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'item_group',
      column: (fieldname: 'item_group', label: 'Item Group'),
      section: 'items',
      defaultVisible: true,
    ),
    ReportField(
      key: 'in_stock_qty',
      column: (fieldname: 'in_stock_qty', label: 'In Stock Qty'),
      section: 'items',
      defaultVisible: true,
    ),
    ReportField(
      key: 'required_qty',
      column: (fieldname: 'required_qty', label: 'Required Qty'),
      section: 'items',
      defaultVisible: true,
    ),
    ReportField(
      key: 'bom',
      column: (fieldname: 'bom', label: 'BOM'),
      section: 'flat',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'sl_no',
      column: (fieldname: 'sl_no', label: '#'),
      section: 'flat',
      defaultVisible: true,
    ),
    ReportField(
      key: 'shortage_qty',
      column: (fieldname: 'shortage_qty', label: 'Shortage Qty'),
      section: 'flat',
      defaultVisible: true,
      hint: 'POS lines and totals always show this field.',
    ),
    ReportField(
      key: 'enough_parts_to_build',
      column: (
        fieldname: 'enough_parts_to_build',
        label: 'Enough Parts to Build',
      ),
      section: 'flat',
      defaultVisible: true,
    ),
    ReportField(
      key: 'running_total',
      column: (fieldname: 'running_total', label: 'Running Total'),
      section: 'pos',
      defaultVisible: true,
    ),
  ],
);

const bomStockFieldsAliases = <String, List<String>>{
  'item_code': ['item'],
  'sl_no': ['#'],
};

String bomStockLabel(String key, FieldsState? fields) =>
    fields?.label(key) ?? bomStockFields.label(key)!;
