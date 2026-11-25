import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

const utilizationFields = ReportFieldsDefinition(
  id: 'employee_hours_utilization',
  sections: [(id: 'employee', title: 'Employee card')],
  alwaysShown:
      'Employee identity, utilization target, summary and totals always show.',
  fields: [
    ReportField(
      key: 'employee',
      column: (fieldname: 'employee', label: 'Employee'),
      section: 'employee',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'department',
      column: (fieldname: 'department', label: 'Department'),
      section: 'employee',
      defaultVisible: true,
    ),
    ReportField(
      key: 'per_util',
      column: (fieldname: 'per_util', label: '% Utilization (B + NB) / T'),
      section: 'employee',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'per_util_billed_only',
      column: (
        fieldname: 'per_util_billed_only',
        label: '% Utilization (B / T)',
      ),
      section: 'employee',
      defaultVisible: true,
    ),
    ReportField(
      key: 'billed_hours',
      column: (fieldname: 'billed_hours', label: 'Billed Hours (B)'),
      section: 'employee',
      defaultVisible: true,
    ),
    ReportField(
      key: 'non_billed_hours',
      column: (fieldname: 'non_billed_hours', label: 'Non-Billed Hours (NB)'),
      section: 'employee',
      defaultVisible: true,
    ),
    ReportField(
      key: 'untracked_hours',
      column: (fieldname: 'untracked_hours', label: 'Untracked Hours (U)'),
      section: 'employee',
      defaultVisible: true,
    ),
    ReportField(
      key: 'total_hours',
      column: (fieldname: 'total_hours', label: 'Total Hours (T)'),
      section: 'employee',
      defaultVisible: true,
    ),
  ],
);

const utilizationFieldsAliases = <String, List<String>>{
  'per_util': ['%_utilization_(b_+_nb)_/_t'],
  'per_util_billed_only': ['%_utilization_(b_/_t)'],
  'billed_hours': ['billed_hours_(b)'],
  'non_billed_hours': ['non_billed_hours_(nb)'],
  'untracked_hours': ['untracked_hours_(u)'],
  'total_hours': ['total_hours_(t)'],
};
