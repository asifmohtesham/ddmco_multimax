import '../../../global_widgets/report_fields/report_field.dart';
import '../../../global_widgets/report_fields/report_fields_store.dart';
import 'stock_ageing_logic.dart';

ReportFieldsDefinition stockAgeingFields([List<ReportColumn>? columns]) {
  final visible = <ReportField>[];
  final unlisted = <ReportField>[];
  final seen = <String>{};
  for (final column in columns ?? const <ReportColumn>[]) {
    if (!seen.add(column.fieldname)) continue;
    final section = StockAgeingLogic.fixedCardFields.contains(column.fieldname)
        ? 'identity'
        : column.fieldname.startsWith('range')
        ? 'buckets'
        : 'card';
    final field = ReportField(
      key: column.fieldname,
      column: (fieldname: column.fieldname, label: column.label),
      section: section,
      defaultVisible:
          section == 'identity' ||
          StockAgeingLogic.defaultCardFields.contains(column.fieldname),
      locked: section == 'identity',
      hint: column.rangeHint,
    );
    (column.listed ? visible : unlisted).add(field);
  }
  for (final key in StockAgeingLogic.fixedCardFields) {
    if (seen.add(key)) {
      unlisted.add(
        ReportField(
          key: key,
          column: (fieldname: key, label: StockAgeingLogic.fixedLabels[key]!),
          section: 'identity',
          defaultVisible: true,
          locked: true,
        ),
      );
    }
  }
  return ReportFieldsDefinition(
    id: 'stock_ageing',
    sections: const [
      (id: 'identity', title: 'Always shown on card'),
      (id: 'card', title: 'Card details'),
      (id: 'buckets', title: 'Card buckets'),
    ],
    fields: visible,
    unlisted: unlisted,
    alwaysShown:
        'Item, warehouse, available quantity and totals always stay '
        'visible. Tap a card to see every column.',
  );
}

const stockAgeingView = ReportFieldsDefinition(
  id: ScopedReportFieldsStore.stockAgeingView,
  sections: [(id: 'card', title: 'Card display')],
  fields: [
    ReportField(
      key: 'ageBar',
      column: (fieldname: 'ageBar', label: 'Age bar'),
      section: 'card',
      defaultVisible: true,
    ),
  ],
  alwaysShown: 'The summary chart is always shown.',
);
