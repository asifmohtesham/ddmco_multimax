import '../../../global_widgets/report_fields/report_field.dart';
import 'item_variant_details_logic.dart';

const _metadata = {'indent', 'template', 'currency'};

ReportFieldsDefinition itemVariantFields([List<DeskColumn>? columns]) {
  final listed = <ReportField>[];
  final unlisted = <ReportField>[];
  final seen = <String>{};

  ReportField field(DeskColumn column) => ReportField(
    key: column.fieldname,
    column: column,
    section: isFixedVariantField(column.fieldname)
        ? 'identity'
        : variantColumnLabels.containsKey(column.fieldname) ||
              column.fieldname == 'variant_of'
        ? 'card'
        : 'attributes',
    defaultVisible: defaultVariantField(column.fieldname),
    locked: isFixedVariantField(column.fieldname),
  );

  for (final column in columns ?? const <DeskColumn>[]) {
    final key = column.fieldname;
    if (key.isEmpty || _metadata.contains(key) || !seen.add(key)) continue;
    if (column.label.trim().isNotEmpty) {
      listed.add(field(column));
    } else if (variantColumnLabels[key] case final label?) {
      unlisted.add(field((fieldname: key, label: label)));
    } else {
      unlisted.add(field(column));
    }
  }
  for (final entry in variantColumnLabels.entries) {
    if (seen.add(entry.key)) {
      unlisted.add(field((fieldname: entry.key, label: entry.value)));
    }
  }
  if (seen.add('variant_of')) {
    unlisted.add(field((fieldname: 'variant_of', label: '')));
  }
  return ReportFieldsDefinition(
    id: 'item_variant_details',
    sections: const [
      (id: 'identity', title: 'Variant identity'),
      (id: 'card', title: 'Variant card'),
      (id: 'attributes', title: 'Variant attributes'),
    ],
    fields: listed,
    unlisted: unlisted,
    alwaysShown:
        'Variant and template identities, group totals and rack stock '
        'always stay visible.',
  );
}
