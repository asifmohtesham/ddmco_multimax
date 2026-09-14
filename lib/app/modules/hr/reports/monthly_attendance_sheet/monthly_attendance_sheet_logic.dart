/// Pure parsing for the HRMS **Monthly Attendance Sheet** script report.
///
/// Kept free of Flutter/GetX so the wire contract can be unit-tested without a
/// binding or a network. Everything here mirrors
/// `hrms/hr/report/monthly_attendance_sheet/monthly_attendance_sheet.py`
/// (verified against hrms 15.64.0 on the live site):
///
/// * Detailed view emits **one row per (employee, shift)** — a two-shift
///   employee produces two rows, both carrying the same `employee`.
/// * Day columns are named `dd-MM-yyyy` and labelled `"1 Tue"`. The row keys
///   use the same `dd-MM-yyyy` string, so day columns are discovered from the
///   `columns` array rather than rebuilt from the month/year filters.
/// * `group_by` injects bare marker rows (`{'department': 'Sales'}`) that carry
///   no `employee` — they label the rows that follow.
/// * Summarized view's leave-type columns are built from the Leave Type table
///   at runtime, so they are discovered, never hardcoded.
library;

/// Status abbreviations from the report's `status_map`, plus the empty string
/// the report writes for a day it has nothing to say about.
enum SheetStatus {
  present('P', 'Present'),
  absent('A', 'Absent'),
  halfDayAbsent('HD/A', 'Half Day / Other Half Absent'),
  halfDayPresent('HD/P', 'Half Day / Other Half Present'),
  workFromHome('WFH', 'Work From Home'),
  onLeave('L', 'On Leave'),
  holiday('H', 'Holiday'),
  weeklyOff('WO', 'Weekly Off'),
  unmarked('', 'Unmarked');

  const SheetStatus(this.abbr, this.label);

  final String abbr;
  final String label;

  static SheetStatus fromAbbr(Object? value) =>
      switch (value?.toString().trim().toUpperCase() ?? '') {
        'P' => present,
        'A' => absent,
        'HD/A' => halfDayAbsent,
        'HD/P' => halfDayPresent,
        'WFH' => workFromHome,
        'L' => onLeave,
        'H' => holiday,
        'WO' => weeklyOff,
        _ => unmarked,
      };

  /// Attention first, so merging two shifts that disagree about a day keeps the
  /// one the user needs to act on.
  int get severity => switch (this) {
        absent => 0,
        halfDayAbsent => 1,
        halfDayPresent => 2,
        onLeave => 3,
        workFromHome => 4,
        present => 5,
        weeklyOff => 6,
        holiday => 7,
        unmarked => 99,
      };

  /// Whether the day counts as one the employee was expected to work.
  bool get isWorkingDay => switch (this) {
        holiday || weeklyOff || unmarked => false,
        _ => true,
      };
}

/// One day column of the sheet, in the order the server returned it.
class SheetDay {
  const SheetDay({required this.key, required this.label, required this.date});

  /// `dd-MM-yyyy` — both the column fieldname and the row key.
  final String key;

  /// `"1 Tue"`, exactly as the server localised it.
  final String label;

  final DateTime date;

  /// The `1` of `"1 Tue"`, without re-deriving it from [date].
  String get dayNumber => label.split(' ').first;
}

/// One shift's row of day statuses for a single employee.
class SheetShift {
  const SheetShift({required this.shift, required this.statuses});

  /// The shift name the server wrote; blank when the Attendance rows carry no
  /// shift.
  final String shift;

  /// Day key (`dd-MM-yyyy`) to status.
  final Map<String, SheetStatus> statuses;

  SheetStatus statusOn(String dayKey) =>
      statuses[dayKey] ?? SheetStatus.unmarked;
}

/// Every row the report emitted for one employee, folded into a single card.
class SheetEmployee {
  SheetEmployee({
    required this.employee,
    required this.employeeName,
    required this.shifts,
    this.group,
  });

  final String employee;
  final String employeeName;

  /// The `group_by` bucket these rows fell under, when grouping is on.
  final String? group;

  final List<SheetShift> shifts;

  bool get hasMultipleShifts => shifts.length > 1;

  /// The worst status per day across every shift — what the compact strip and
  /// the per-employee counts read from.
  Map<String, SheetStatus> get merged {
    final out = <String, SheetStatus>{};
    for (final shift in shifts) {
      shift.statuses.forEach((key, status) {
        final current = out[key];
        if (current == null || status.severity < current.severity) {
          out[key] = status;
        }
      });
    }
    return out;
  }

  SheetStatus statusOn(String dayKey) => merged[dayKey] ?? SheetStatus.unmarked;

  /// Day counts by status, attention first.
  Map<SheetStatus, int> get counts {
    final out = <SheetStatus, int>{};
    for (final status in merged.values) {
      out[status] = (out[status] ?? 0) + 1;
    }
    return _bySeverity(out);
  }
}

/// One summarized-view row: the fixed totals plus whatever leave-type columns
/// the site defines.
class SheetSummary {
  const SheetSummary({
    required this.employee,
    required this.employeeName,
    required this.values,
    this.group,
  });

  final String employee;
  final String employeeName;
  final String? group;

  /// Column fieldname to value, for every numeric column in the response.
  final Map<String, num> values;

  num operator [](String fieldname) => values[fieldname] ?? 0;
}

/// A numeric summarized-view column, carrying the server's own label.
class SheetSummaryColumn {
  const SheetSummaryColumn({required this.fieldname, required this.label});

  final String fieldname;
  final String label;
}

/// The fixed numeric columns of the summarized view, in server order. Anything
/// numeric that is not in this list is a Leave Type column.
const List<String> kSheetTotalFields = [
  'total_present',
  'total_leaves',
  'total_absent',
  'total_holidays',
  'unmarked_days',
  'total_late_entries',
  'total_early_exits',
];

final RegExp _dayFieldname = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$');

/// Day columns, in server order, discovered from the response's `columns`.
///
/// Returns empty for a summarized-view response (it has no day columns), which
/// is what tells the caller which shape it is holding.
List<SheetDay> parseDayColumns(Object? columns) {
  final days = <SheetDay>[];
  for (final column in _maps(columns)) {
    final fieldname = column['fieldname']?.toString() ?? '';
    final match = _dayFieldname.firstMatch(fieldname);
    if (match == null) continue;
    days.add(SheetDay(
      key: fieldname,
      label: column['label']?.toString() ?? '',
      date: DateTime(
        int.parse(match.group(3)!),
        int.parse(match.group(2)!),
        int.parse(match.group(1)!),
      ),
    ));
  }
  return days;
}

/// Numeric columns of a summarized-view response that are Leave Types — the
/// site's own Leave Type list, which varies per site.
List<SheetSummaryColumn> parseLeaveTypeColumns(Object? columns) => [
      for (final column in _maps(columns))
        if (column['fieldtype'] == 'Float' &&
            !kSheetTotalFields.contains(column['fieldname']?.toString()))
          SheetSummaryColumn(
            fieldname: column['fieldname']?.toString() ?? '',
            label: column['label']?.toString() ?? '',
          ),
    ];

/// Detailed-view rows folded into one [SheetEmployee] per employee, preserving
/// the server's ordering and carrying any `group_by` label down onto the rows
/// that follow its marker.
List<SheetEmployee> parseDetailed(Object? result, {String? groupByField}) {
  final byEmployee = <String, SheetEmployee>{};
  String? group;

  for (final row in _maps(result)) {
    final employee = row['employee']?.toString() ?? '';

    // A `group_by` marker row carries only the bucket value.
    if (employee.isEmpty) {
      group = _groupValue(row, groupByField);
      continue;
    }

    final statuses = <String, SheetStatus>{};
    row.forEach((key, value) {
      if (_dayFieldname.hasMatch(key)) {
        statuses[key] = SheetStatus.fromAbbr(value);
      }
    });

    final entry = byEmployee[employee] ??= SheetEmployee(
      employee: employee,
      employeeName: row['employee_name']?.toString() ?? employee,
      group: group,
      shifts: [],
    );
    entry.shifts.add(SheetShift(
      shift: row['shift']?.toString() ?? '',
      statuses: statuses,
    ));
  }

  return byEmployee.values.toList();
}

/// Summarized-view rows, with `group_by` markers applied the same way.
List<SheetSummary> parseSummarized(Object? result, {String? groupByField}) {
  final rows = <SheetSummary>[];
  String? group;

  for (final row in _maps(result)) {
    final employee = row['employee']?.toString() ?? '';
    if (employee.isEmpty) {
      group = _groupValue(row, groupByField);
      continue;
    }

    rows.add(SheetSummary(
      employee: employee,
      employeeName: row['employee_name']?.toString() ?? employee,
      group: group,
      values: {
        for (final entry in row.entries)
          if (entry.value is num) entry.key: entry.value as num,
      },
    ));
  }

  return rows;
}

/// Day counts by status across every employee — the report's totals line.
Map<SheetStatus, int> totalCounts(List<SheetEmployee> employees) {
  final out = <SheetStatus, int>{};
  for (final employee in employees) {
    employee.counts.forEach((status, n) => out[status] = (out[status] ?? 0) + n);
  }
  return _bySeverity(out);
}

/// `"16 employees · 234 present · 41 absent"` for the end-of-list footer.
/// Days, never rates — summing a rate column is meaningless.
String totalsLabel(List<SheetEmployee> employees) {
  if (employees.isEmpty) return 'End of results';
  final counts = totalCounts(employees);
  return [
    '${employees.length} employee${employees.length == 1 ? '' : 's'}',
    for (final entry in counts.entries)
      if (entry.value > 0) '${entry.value} ${entry.key.label.toLowerCase()}',
  ].join(' · ');
}

String? _groupValue(Map<String, dynamic> row, String? groupByField) {
  if (groupByField != null) return row[groupByField]?.toString();
  return row.values.isEmpty ? null : row.values.first?.toString();
}

Map<SheetStatus, int> _bySeverity(Map<SheetStatus, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) => a.key.severity.compareTo(b.key.severity));
  return {for (final e in entries) e.key: e.value};
}

Iterable<Map<String, dynamic>> _maps(Object? raw) sync* {
  if (raw is! List) return;
  for (final entry in raw) {
    if (entry is Map) yield Map<String, dynamic>.from(entry);
  }
}
