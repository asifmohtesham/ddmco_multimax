/// Pure parsing for the HRMS **Shift Attendance** script report.
///
/// Mirrors `hrms/hr/report/shift_attendance/shift_attendance.py`, checked
/// against the live site (HRMS 15.64.0, 2026-11-15):
///
/// * One row per **submitted Attendance** that has linked check-ins — on this
///   site that is one row per (employee, shift, day). The server applies no
///   ordering, so the app sorts.
/// * Times arrive as `"HH:MM:SS"` strings when they fall on the attendance
///   date, as a formatted datetime string when they do not, or null.
/// * `late_entry_hrs` / `early_exit_hrs` are already-formatted durations
///   (`"5m 33s"`) present only when there is something to report.
/// * With `include_attendance_without_checkins`, bare rows (typically Absent)
///   are appended with no shift times at all.
library;

import 'package:intl/intl.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';

/// Which punch, if any, the record is missing — the reason its hours read 0.
enum MissingPunch { none, checkIn, checkOut, both }

class ShiftAttendanceRow {
  const ShiftAttendanceRow({
    required this.name,
    required this.employee,
    required this.employeeName,
    required this.shift,
    required this.date,
    required this.status,
    required this.workingHours,
    this.shiftStart,
    this.shiftEnd,
    this.inTime,
    this.outTime,
    this.lateEntry = false,
    this.earlyExit = false,
    this.lateBy,
    this.earlyBy,
    this.department,
  });

  /// Attendance ID, e.g. `HR-ATT-2026-02676`.
  final String name;
  final String employee;
  final String employeeName;
  final String shift;
  final DateTime date;
  final String status;
  final double workingHours;

  final String? shiftStart;
  final String? shiftEnd;
  final String? inTime;
  final String? outTime;

  final bool lateEntry;
  final bool earlyExit;

  /// Server-formatted durations (`"5m 33s"`); null when not late / early.
  final String? lateBy;
  final String? earlyBy;

  final String? department;

  /// A check-in/out pair counts only when both ends exist, so a missing end
  /// understates the hours. Absent and On Leave records are not expected to
  /// have punches — on the live site the "without check-ins" branch returns
  /// bare Absent rows — so they never read as a missed tap.
  MissingPunch get missingPunch {
    if (status == 'Absent' || status == 'On Leave') return MissingPunch.none;
    if (inTime == null && outTime == null) return MissingPunch.both;
    if (inTime == null) return MissingPunch.checkIn;
    if (outTime == null) return MissingPunch.checkOut;
    return MissingPunch.none;
  }

  /// Whether the in time should read as a problem (late, by the server's own
  /// flag or a computed lateness).
  bool get isLate => lateEntry || lateBy != null;
  bool get isEarly => earlyExit || earlyBy != null;

  /// `"08:00–12:00"`, or null for a row with no shift times.
  String? get shiftWindow => shiftStart == null || shiftEnd == null
      ? null
      : '${displayTime(shiftStart)}–${displayTime(shiftEnd)}';

  static ShiftAttendanceRow? fromJson(Map<String, dynamic> row) {
    final employee = asText(row['employee']);
    final date = DateTime.tryParse(row['attendance_date']?.toString() ?? '');
    if (employee == null || date == null) return null;
    return ShiftAttendanceRow(
      name: asText(row['name']) ?? '',
      employee: employee,
      employeeName: asText(row['employee_name']) ?? employee,
      shift: asText(row['shift']) ?? '',
      date: date,
      status: asText(row['status']) ?? '',
      workingHours: asDouble(row['working_hours']),
      shiftStart: asText(row['shift_start']),
      shiftEnd: asText(row['shift_end']),
      inTime: asText(row['in_time']),
      outTime: asText(row['out_time']),
      lateEntry: asFlag(row['late_entry']),
      earlyExit: asFlag(row['early_exit']),
      lateBy: asText(row['late_entry_hrs']),
      earlyBy: asText(row['early_exit_hrs']),
      department: asText(row['department']),
    );
  }
}

/// Rows newest day first; within a day by shift start, then employee name.
/// Rows without an employee or a date are dropped.
List<ShiftAttendanceRow> parseShiftAttendance(Object? result) {
  final rows = [
    for (final raw in reportMaps(result))
      if (ShiftAttendanceRow.fromJson(raw) case final row?) row,
  ];
  rows.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    // "HH:MM:SS" compares correctly as text; rows with no shift go last.
    final byShift = (a.shiftStart ?? '~').compareTo(b.shiftStart ?? '~');
    if (byShift != 0) return byShift;
    final byShiftName = a.shift.compareTo(b.shift);
    if (byShiftName != 0) return byShiftName;
    return a.employeeName.toLowerCase().compareTo(b.employeeName.toLowerCase());
  });
  return rows;
}

final RegExp _clock = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$');

/// `"08:01:46"` → `"08:01"`. A formatted datetime (`"13-11-2026 21:05:00"`,
/// for a punch on another day) keeps its date and loses the seconds. Null or
/// blank → `"—"`.
String displayTime(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '—';
  final match = _clock.firstMatch(text);
  if (match == null) return text;
  final hh = match.group(1)!.padLeft(2, '0');
  final clock = '$hh:${match.group(2)}';
  final prefix = text.substring(0, match.start).trim();
  return prefix.isEmpty ? clock : '$prefix $clock';
}

/// Day bucket heading, e.g. `"Fri 13 Nov 2026"`.
String dayHeading(DateTime date) => DateFormat('EEE d MMM yyyy').format(date);

/// Totals for the end-of-list marker: record counts and summed hours — a
/// quantity, so it sums; no rate column is summed.
class ShiftAttendanceTotals {
  const ShiftAttendanceTotals({
    required this.records,
    required this.employees,
    required this.hours,
    required this.late,
    required this.early,
    required this.missingPunch,
  });

  factory ShiftAttendanceTotals.of(List<ShiftAttendanceRow> rows) =>
      ShiftAttendanceTotals(
        records: rows.length,
        employees: rows.map((r) => r.employee).toSet().length,
        hours: rows.fold(0, (sum, r) => sum + r.workingHours),
        late: rows.where((r) => r.isLate).length,
        early: rows.where((r) => r.isEarly).length,
        missingPunch: rows
            .where((r) => r.missingPunch != MissingPunch.none)
            .length,
      );

  final int records;
  final int employees;
  final double hours;
  final int late;
  final int early;
  final int missingPunch;

  String get label {
    if (records == 0) return 'End of results';
    return [
      '$records record${records == 1 ? '' : 's'}',
      '$employees employee${employees == 1 ? '' : 's'}',
      '${formatHours(hours)} worked',
      if (late > 0) '$late late',
      if (early > 0) '$early early exit${early == 1 ? '' : 's'}',
      if (missingPunch > 0) '$missingPunch missing a punch',
    ].join(' · ');
  }
}
