import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_logic.dart';

/// Rows shaped like HRMS 15.64 `employee_hours_utilization_based_on_timesheet`:
/// `employee_name` rides along although it is not a column.
const _rows = [
  {
    'employee': 'HR-EMP-00011',
    'employee_name': 'Arif Khan',
    'department': 'Warehouse - MM',
    'total_hours': 240.0,
    'billed_hours': 120.0,
    'non_billed_hours': 72.0,
    'untracked_hours': 48.0,
    'per_util': 80.0,
    'per_util_billed_only': 50.0,
  },
  {
    'employee': 'HR-EMP-00007',
    'employee_name': 'Jawwad Bilgi',
    'department': null,
    'total_hours': 240.0,
    'billed_hours': 0.0,
    'non_billed_hours': 100.5,
    'untracked_hours': 139.5,
    'per_util': 41.88,
    'per_util_billed_only': 0.0,
  },
];

void main() {
  group('parseUtilization', () {
    final rows = parseUtilization(_rows);

    test('keeps server order and reads every field', () {
      expect(rows.map((r) => r.employee), ['HR-EMP-00011', 'HR-EMP-00007']);
      final first = rows.first;
      expect(first.employeeName, 'Arif Khan');
      expect(first.department, 'Warehouse - MM');
      expect(first.totalHours, 240);
      expect(first.billedHours, 120);
      expect(first.nonBilledHours, 72);
      expect(first.untrackedHours, 48);
      expect(first.trackedHours, 192);
      expect(first.utilization, 80);
      expect(first.billedUtilization, 50);
      expect(first.belowTarget, isFalse);
      expect(rows.last.belowTarget, isTrue);
      expect(rows.last.department, isNull);
    });

    test('bar shares are fractions of T', () {
      final (billed, nonBilled, untracked) = rows.first.shares;
      expect(billed, 0.5);
      expect(nonBilled, 0.3);
      expect(untracked, 0.2);
    });

    test('overtime is clamped so the bar never overflows', () {
      final row = parseUtilization([
        {
          'employee': 'E',
          'total_hours': 100.0,
          'billed_hours': 90.0,
          'non_billed_hours': 30.0,
          'untracked_hours': 0.0,
          'per_util': 120.0,
          'per_util_billed_only': 90.0,
        },
      ]).single;
      final (b, nb, u) = row.shares;
      expect(b, 0.9);
      expect(nb, closeTo(0.1, 1e-9));
      expect(u, 0);
      expect(b + nb + u, lessThanOrEqualTo(1.0));
    });

    test('zero total hours yields an empty bar', () {
      final row = parseUtilization([
        {'employee': 'E', 'total_hours': 0},
      ]).single;
      expect(row.shares, (0.0, 0.0, 0.0));
      expect(row.employeeName, 'E');
    });

    test('drops rows without an employee; tolerates junk', () {
      expect(
        parseUtilization([
          {'employee': ''},
          'x',
          null,
        ]),
        isEmpty,
      );
      expect(parseUtilization(null), isEmpty);
    });
  });

  test('formatPercent', () {
    expect(formatPercent(80), '80%');
    expect(formatPercent(41.88), '41.9%');
    expect(formatPercent(0), '0%');
  });

  group('utilizationTotalsLabel', () {
    test('sums the hour columns only', () {
      expect(
        utilizationTotalsLabel(parseUtilization(_rows)),
        'End of list · 2 employees · Billed Hours (B) 120h · '
        'Non-Billed Hours (NB) 172h 30m · Untracked Hours (U) 187h 30m · '
        'Total Hours (T) 480h',
      );
    });

    test('empty', () {
      expect(utilizationTotalsLabel(const []), 'End of list');
    });
  });
}
