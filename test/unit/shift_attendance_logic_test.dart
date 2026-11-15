import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_logic.dart';

/// Rows shaped exactly like the live report (erp.multimax.cloud, HRMS 15.64,
/// 2026-11-15), unordered as the server returns them.
const _rows = [
  {
    'name': 'HR-ATT-2026-02676',
    'employee': 'HR-EMP-00005',
    'employee_name': 'Asim Usman Sukri',
    'shift': 'Morning (Fri)',
    'attendance_date': '2026-11-13',
    'status': 'Present',
    'in_time': null,
    'out_time': '12:01:45',
    'working_hours': 0.0,
    'late_entry': 0,
    'early_exit': 0,
    'department': null,
    'company': 'Multimax',
    'shift_start': '08:00:00',
    'shift_end': '12:00:00',
    'shift_actual_start': '06:00:00',
    'shift_actual_end': '13:15:00',
    'enable_late_entry_marking': 1,
    'late_entry_grace_period': 15,
  },
  {
    'name': 'HR-ATT-2026-02690',
    'employee': 'HR-EMP-00007',
    'employee_name': 'Jawwad Bilgi',
    'shift': 'Afternoon',
    'attendance_date': '2026-11-12',
    'status': 'Present',
    'in_time': '13:32:39',
    'out_time': '19:00:13',
    'working_hours': 5.46,
    'late_entry': 0,
    'early_exit': 1,
    'early_exit_hrs': '44m 47s',
    'shift_start': '13:30:00',
    'shift_end': '20:00:00',
  },
  {
    'name': 'HR-ATT-2026-02678',
    'employee': 'HR-EMP-00007',
    'employee_name': 'Jawwad Bilgi',
    'shift': 'Morning (Fri)',
    'attendance_date': '2026-11-13',
    'status': 'Present',
    'in_time': '08:05:33',
    'out_time': '12:01:29',
    'working_hours': 3.93,
    'late_entry': 1,
    'early_exit': 0,
    'late_entry_hrs': '5m 33s',
    'shift_start': '08:00:00',
    'shift_end': '12:00:00',
  },
  {
    'name': 'HR-ATT-2026-02689',
    'employee': 'HR-EMP-00011',
    'employee_name': 'Arif Khan',
    'shift': 'Afternoon (Fri)',
    'attendance_date': '2026-11-13',
    'status': 'Present',
    'in_time': '14:31:00',
    'out_time': '20:01:19',
    'working_hours': 5.5,
    'late_entry': 0,
    'early_exit': 0,
    'shift_start': '14:30:00',
    'shift_end': '20:00:00',
  },
  // A "without check-ins" row: no shift times at all.
  {
    'name': 'HR-ATT-2026-02315',
    'employee': 'HR-EMP-00002',
    'employee_name': 'Mohammed Sajid Damda',
    'shift': 'Morning',
    'attendance_date': '2026-11-02',
    'status': 'Absent',
    'in_time': null,
    'out_time': null,
    'working_hours': 0.0,
    'late_entry': 0,
    'early_exit': 0,
    'department': null,
    'company': 'Multimax',
  },
];

void main() {
  group('parseShiftAttendance', () {
    final rows = parseShiftAttendance(_rows);

    test('sorts newest day first, then by shift start, then name', () {
      expect(rows.map((r) => r.name), [
        'HR-ATT-2026-02676', // 13 Nov 08:00 Asim
        'HR-ATT-2026-02678', // 13 Nov 08:00 Jawwad
        'HR-ATT-2026-02689', // 13 Nov 14:30
        'HR-ATT-2026-02690', // 12 Nov 13:30
        'HR-ATT-2026-02315', // 2 Nov, no shift times
      ]);
    });

    test('reads every field', () {
      final late = rows[1];
      expect(late.employee, 'HR-EMP-00007');
      expect(late.employeeName, 'Jawwad Bilgi');
      expect(late.shift, 'Morning (Fri)');
      expect(late.date, DateTime(2026, 11, 13));
      expect(late.status, 'Present');
      expect(late.workingHours, 3.93);
      expect(late.inTime, '08:05:33');
      expect(late.isLate, isTrue);
      expect(late.lateBy, '5m 33s');
      expect(late.isEarly, isFalse);
      expect(late.shiftWindow, '08:00–12:00');
      expect(late.missingPunch, MissingPunch.none);
    });

    test('flags missing punches', () {
      expect(rows[0].missingPunch, MissingPunch.checkIn);
      expect(rows.last.shiftWindow, isNull);
    });

    test('an Absent / On Leave record is not a missed punch', () {
      expect(rows.last.status, 'Absent');
      expect(rows.last.missingPunch, MissingPunch.none);
      final present = parseShiftAttendance(const [
        {
          'employee': 'E',
          'attendance_date': '2026-11-02',
          'status': 'Present',
          'in_time': null,
          'out_time': null,
        },
        {
          'employee': 'F',
          'attendance_date': '2026-11-02',
          'status': 'On Leave',
        },
      ]);
      expect(present[0].missingPunch, MissingPunch.both);
      expect(present[1].missingPunch, MissingPunch.none);
    });

    test('early exit carries the server duration', () {
      final early = rows[3];
      expect(early.isEarly, isTrue);
      expect(early.earlyBy, '44m 47s');
    });

    test('drops rows without an employee or a date; tolerates junk', () {
      expect(
        parseShiftAttendance([
          {'employee': '', 'attendance_date': '2026-11-01'},
          {'employee': 'X', 'attendance_date': 'not a date'},
          'junk',
          {
            'employee': 'HR-EMP-1',
            'attendance_date': '2026-11-01',
            'working_hours': '2.5',
          },
        ]).single.workingHours,
        2.5,
      );
      expect(parseShiftAttendance(null), isEmpty);
    });
  });

  group('displayTime', () {
    test('same-day clock drops the seconds', () {
      expect(displayTime('08:01:46'), '08:01');
      expect(displayTime('8:01:46'), '08:01');
      expect(displayTime('08:01:46.123456'), '08:01');
    });

    test('a formatted datetime keeps its date', () {
      expect(displayTime('13-11-2026 21:05:00'), '13-11-2026 21:05');
    });

    test('null / blank / non-time', () {
      expect(displayTime(null), '—');
      expect(displayTime('  '), '—');
      expect(displayTime('n/a'), 'n/a');
    });
  });

  test('dayHeading', () {
    expect(dayHeading(DateTime(2026, 11, 13)), 'Fri 13 Nov 2026');
  });

  group('ShiftAttendanceTotals', () {
    test('sums hours and counts flags, never rates', () {
      final totals = ShiftAttendanceTotals.of(parseShiftAttendance(_rows));
      expect(totals.records, 5);
      expect(totals.employees, 4);
      expect(totals.hours, closeTo(14.89, 1e-9));
      expect(totals.late, 1);
      expect(totals.early, 1);
      expect(totals.missingPunch, 1);
      expect(
        totals.label,
        '5 records · 4 employees · 14h 53m worked · 1 late · 1 early exit · 1 missing a punch',
      );
    });

    test('empty', () {
      expect(ShiftAttendanceTotals.of(const []).label, 'End of results');
    });
  });
}
