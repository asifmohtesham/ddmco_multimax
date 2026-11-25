import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

const bomSearchFields = ReportFieldsDefinition(
  id: 'bom_search',
  sections: [(id: 'document', title: 'Document')],
  alwaysShown:
      'Document identity, distinguishing types and the result count always show.',
  fields: [
    ReportField(
      key: 'parent',
      column: (fieldname: 'parent', label: 'BOM'),
      section: 'document',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'doctype',
      column: (fieldname: 'doctype', label: 'Type'),
      section: 'document',
      defaultVisible: true,
      hint:
          'Normal BOM rows only. The type stays visible when it distinguishes the document.',
    ),
  ],
);

const bomSearchFieldsAliases = <String, List<String>>{
  'parent': ['bom'],
  'doctype': ['type'],
};
