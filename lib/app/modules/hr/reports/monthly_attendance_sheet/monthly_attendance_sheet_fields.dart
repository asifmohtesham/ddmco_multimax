import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'monthly_attendance_sheet_logic.dart';

const monthlySummaryHeaders = <String, String>{
  'total_present': 'Total Present',
  'total_leaves': 'Total Leaves',
  'total_absent': 'Total Absent',
  'total_holidays': 'Total Holidays',
  'unmarked_days': 'Unmarked Days',
  'total_late_entries': 'Total Late Entries',
  'total_early_exits': 'Total Early Exits',
};

ReportFieldsDefinition monthlyAttendanceFields({
  bool summarized = false,
  bool monthMode = true,
  List<DeskColumn>? columns,
  List<SheetSummaryColumn> leaveTypes = const [],
}) {
  final section = summarized ? 'summary' : 'calendar';
  return ReportFieldsDefinition(
    id: 'monthly_attendance_sheet',
    sections: [
      (id: section, title: summarized ? 'Summary card' : 'Attendance calendar'),
    ],
    alwaysShown:
        'Employee, groups, calendar statuses, shift identities and totals '
        'always show.',
    fields: [
      for (final column in const [
        (fieldname: 'employee', label: 'Employee'),
        (fieldname: 'employee_name', label: 'Employee Name'),
      ])
        ReportField(
          key: column.fieldname,
          column: column,
          section: section,
          defaultVisible: true,
          locked: true,
        ),
      if (!summarized)
        ReportField(
          key: 'shift',
          column: (fieldname: 'shift', label: 'Shift'),
          section: section,
          defaultVisible: true,
          locked: !monthMode,
          hint: monthMode ? 'Shift list on the employee card' : null,
        ),
      if (summarized) ...[
        for (final MapEntry(:key, :value) in monthlySummaryHeaders.entries)
          ReportField(
            key: key,
            column: (fieldname: key, label: value),
            section: section,
            defaultVisible: true,
          ),
        for (final type in leaveTypes)
          if (type.label.trim().isNotEmpty)
            ReportField(
              key: type.fieldname,
              column: (fieldname: type.fieldname, label: type.label),
              section: section,
              defaultVisible: true,
            ),
      ],
    ],
  ).withColumns(columns);
}
