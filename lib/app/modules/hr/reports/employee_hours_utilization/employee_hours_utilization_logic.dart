/// Pure parsing for the HRMS **Employee Hours Utilization Based On Timesheet**
/// script report.
///
/// Mirrors `hrms/hr/report/employee_hours_utilization_based_on_timesheet/
/// employee_hours_utilization_based_on_timesheet.py` (HRMS 15.64):
///
/// * One row per employee with submitted Timesheets in the range. Rows carry
///   `employee_name` although the columns do not list it.
/// * Total hours (T) = HR Settings "Standard Working Hours" × the day span
///   (`to_date − from_date`, end day not counted). Untracked (U) = T − billed
///   − non-billed, floored at 0. Both percentages are of T.
/// * Rows arrive sorted by `per_util`, highest first; the app keeps that.
/// * The server throws when From is not before To, or when Standard Working
///   Hours is unset; the report needs read/report access on **Timesheet**.
library;

import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'employee_hours_utilization_fields.dart';

/// Desk colours the summary red below this average utilisation.
const double kUtilizationTarget = 70.0;

class EmployeeUtilizationRow {
  const EmployeeUtilizationRow({
    required this.employee,
    required this.employeeName,
    required this.totalHours,
    required this.billedHours,
    required this.nonBilledHours,
    required this.untrackedHours,
    required this.utilization,
    required this.billedUtilization,
    this.department,
  });

  final String employee;
  final String employeeName;
  final String? department;

  /// T — the hours the period offers at standard working hours.
  final double totalHours;

  /// B, NB, U.
  final double billedHours;
  final double nonBilledHours;
  final double untrackedHours;

  /// `per_util` — (B + NB) / T × 100.
  final double utilization;

  /// `per_util_billed_only` — B / T × 100.
  final double billedUtilization;

  double get trackedHours => billedHours + nonBilledHours;

  bool get belowTarget => utilization < kUtilizationTarget;

  /// Bar segment shares of T, each in 0…1 and summing to at most 1. Overtime
  /// (tracked > T) is clamped so the bar fills rather than overflows.
  (double, double, double) get shares {
    final base = totalHours > 0 ? totalHours : (trackedHours + untrackedHours);
    if (base <= 0) return (0, 0, 0);
    final billed = (billedHours / base).clamp(0.0, 1.0);
    final nonBilled = (nonBilledHours / base).clamp(0.0, 1.0 - billed);
    final untracked = (untrackedHours / base).clamp(
      0.0,
      1.0 - billed - nonBilled,
    );
    return (billed, nonBilled, untracked);
  }

  static EmployeeUtilizationRow? fromJson(Map<String, dynamic> row) {
    final employee = asText(row['employee']);
    if (employee == null) return null;
    return EmployeeUtilizationRow(
      employee: employee,
      employeeName: asText(row['employee_name']) ?? employee,
      department: asText(row['department']),
      totalHours: asDouble(row['total_hours']),
      billedHours: asDouble(row['billed_hours']),
      nonBilledHours: asDouble(row['non_billed_hours']),
      untrackedHours: asDouble(row['untracked_hours']),
      utilization: asDouble(row['per_util']),
      billedUtilization: asDouble(row['per_util_billed_only']),
    );
  }
}

/// Rows in server order (highest utilisation first).
List<EmployeeUtilizationRow> parseUtilization(Object? result) => [
  for (final raw in reportMaps(result))
    if (EmployeeUtilizationRow.fromJson(raw) case final row?) row,
];

/// `"82.5%"` — at most one decimal, none when whole.
String formatPercent(double value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}%'
      : '${rounded.toStringAsFixed(1)}%';
}

/// End-of-list totals: hour columns sum; the percentage columns never do.
String utilizationTotalsLabel(
  List<EmployeeUtilizationRow> rows, {
  FieldsState? fields,
}) {
  if (rows.isEmpty) return 'End of list';
  double sum(double Function(EmployeeUtilizationRow) pick) =>
      rows.fold(0, (total, row) => total + pick(row));
  String measure(String key, double hours) =>
      '${fields?.label(key) ?? utilizationFields.label(key)!} ${formatHours(hours)}';
  return [
    'End of list',
    '${rows.length} employee${rows.length == 1 ? '' : 's'}',
    measure('billed_hours', sum((r) => r.billedHours)),
    measure('non_billed_hours', sum((r) => r.nonBilledHours)),
    measure('untracked_hours', sum((r) => r.untrackedHours)),
    measure('total_hours', sum((r) => r.totalHours)),
  ].join(' · ');
}
