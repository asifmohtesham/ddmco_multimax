import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';

const shiftAttendanceFields = ReportFieldsDefinition(
  id: 'shift_attendance',
  sections: [(id: 'attendance', title: 'Attendance card')],
  alwaysShown:
      'Employee, shift, date, status, warnings and totals always show.',
  fields: [
    ReportField(
      key: 'employee',
      column: (fieldname: 'employee', label: 'Employee'),
      section: 'attendance',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'employee_name',
      column: (fieldname: 'employee_name', label: 'Employee Name'),
      section: 'attendance',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'shift',
      column: (fieldname: 'shift', label: 'Shift'),
      section: 'attendance',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'attendance_date',
      column: (fieldname: 'attendance_date', label: 'Attendance Date'),
      section: 'attendance',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'status',
      column: (fieldname: 'status', label: 'Status'),
      section: 'attendance',
      defaultVisible: true,
      locked: true,
    ),
    ReportField(
      key: 'shift_start',
      column: (fieldname: 'shift_start', label: 'Shift Start Time'),
      section: 'attendance',
      defaultVisible: true,
    ),
    ReportField(
      key: 'shift_end',
      column: (fieldname: 'shift_end', label: 'Shift End Time'),
      section: 'attendance',
      defaultVisible: true,
    ),
    ReportField(
      key: 'in_time',
      column: (fieldname: 'in_time', label: 'In Time'),
      section: 'attendance',
      defaultVisible: true,
    ),
    ReportField(
      key: 'out_time',
      column: (fieldname: 'out_time', label: 'Out Time'),
      section: 'attendance',
      defaultVisible: true,
    ),
    ReportField(
      key: 'working_hours',
      column: (fieldname: 'working_hours', label: 'Total Working Hours'),
      section: 'attendance',
      defaultVisible: true,
    ),
    ReportField(
      key: 'late_entry_hrs',
      column: (fieldname: 'late_entry_hrs', label: 'Late Entry By'),
      section: 'attendance',
      defaultVisible: true,
    ),
    ReportField(
      key: 'early_exit_hrs',
      column: (fieldname: 'early_exit_hrs', label: 'Early Exit By'),
      section: 'attendance',
      defaultVisible: true,
    ),
  ],
);

const shiftAttendanceFieldsAliases = <String, List<String>>{
  'name': ['attendance_id'],
  'shift_start': ['shift_start_time'],
  'shift_end': ['shift_end_time'],
  'working_hours': ['total_working_hours'],
  'late_entry_hrs': ['late_entry_by'],
  'early_exit_hrs': ['early_exit_by'],
};
