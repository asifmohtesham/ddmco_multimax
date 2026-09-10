import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

void main() {
  const shift = ShiftRules(
    name: 'General',
    start: Duration(hours: 8),
    end: Duration(hours: 20),
    graceMinutes: 15,
  );
  const tracked = TrackedEmployee(
      name: 'HR-EMP-00001', employeeName: 'Ayesha Mohammed', deviceId: '7');
  const untracked = TrackedEmployee(name: 'HR-EMP-00021', employeeName: 'Chen Wei');
  final day = DateTime(2026, 9, 9);

  EmployeeCheckin punch(int h, int m) => EmployeeCheckin(
      name: 'x', employee: tracked.name, time: DateTime(2026, 9, 9, h, m));

  EmployeeDayStatus derive({
    TrackedEmployee employee = tracked,
    required DateTime now,
    List<EmployeeCheckin> punches = const [],
    AttendanceRecord? ledger,
    bool isHoliday = false,
  }) =>
      deriveDayStatus(
        employee: employee,
        day: day,
        now: now,
        shift: shift,
        isHoliday: isHoliday,
        punches: punches,
        ledger: ledger,
      );

  group('today from punches', () {
    test('first punch on or before 08:15 is Present', () {
      final r = derive(now: DateTime(2026, 9, 9, 10), punches: [punch(8, 15)]);
      expect(r.status, AttendanceStatus.present);
      expect(r.lateBy, isNull);
      expect(r.outTime, isNull);
    });

    test('first punch after 08:15 is Late with minutes', () {
      final r = derive(
          now: DateTime(2026, 9, 9, 10),
          punches: [punch(12, 2), punch(8, 31)]); // unsorted on purpose
      expect(r.status, AttendanceStatus.late);
      expect(r.lateBy, const Duration(minutes: 16));
      expect(r.inTime, DateTime(2026, 9, 9, 8, 31));
      expect(r.outTime, DateTime(2026, 9, 9, 12, 2)); // even count → last is OUT
      expect(r.flag, '16 min late');
    });

    test('odd punch count leaves out time blank', () {
      final r = derive(
          now: DateTime(2026, 9, 9, 13),
          punches: [punch(8, 0), punch(12, 0), punch(12, 40)]);
      expect(r.outTime, isNull);
    });

    test('no punch before cut-off is Not in yet', () {
      expect(derive(now: DateTime(2026, 9, 9, 7, 52)).status,
          AttendanceStatus.notInYet);
    });

    test('no punch at/after cut-off is Absent so far', () {
      expect(derive(now: DateTime(2026, 9, 9, 8, 15)).status,
          AttendanceStatus.absentSoFar);
    });

    test('no punch on a past day is Absent', () {
      expect(derive(now: DateTime(2026, 9, 10, 7)).status,
          AttendanceStatus.absent);
    });

    test('holiday wins; a punch is context, never lateness', () {
      final r = derive(
          now: DateTime(2026, 9, 9, 10),
          isHoliday: true,
          punches: [punch(9, 12)]);
      expect(r.status, AttendanceStatus.holiday);
      expect(r.flag, 'Punched on holiday');
      expect(r.flagIsWarning, isFalse);
    });

    test('untracked employee is Not tracked regardless of time', () {
      expect(derive(employee: untracked, now: DateTime(2026, 9, 9, 10)).status,
          AttendanceStatus.untracked);
    });
  });

  group('ledger', () {
    test('Present + late_entry is Late, in/out/hours from the row', () {
      final r = derive(
        now: DateTime(2026, 9, 12),
        ledger: AttendanceRecord(
          name: 'A1',
          employee: tracked.name,
          employeeName: tracked.employeeName,
          date: day,
          status: 'Present',
          lateEntry: true,
          inTime: DateTime(2026, 9, 9, 8, 31),
          outTime: DateTime(2026, 9, 9, 17, 32),
          workingHours: 9.02,
        ),
      );
      expect(r.status, AttendanceStatus.late);
      expect(r.lateBy, const Duration(minutes: 16));
      expect(r.workingHours, 9.02);
    });

    test('maps every ledger status', () {
      for (final (s, want) in [
        ('Absent', AttendanceStatus.absent),
        ('On Leave', AttendanceStatus.onLeave),
        ('Half Day', AttendanceStatus.halfDay),
        ('Work From Home', AttendanceStatus.workFromHome),
      ]) {
        final r = derive(
          now: DateTime(2026, 9, 12),
          ledger: AttendanceRecord(
              name: 'x', employee: tracked.name, employeeName: '', date: day, status: s),
        );
        expect(r.status, want, reason: s);
      }
    });
  });

  group('sorting, counts, filters', () {
    final rows = [
      derive(now: DateTime(2026, 9, 9, 10), punches: [punch(8, 0)]),
      derive(now: DateTime(2026, 9, 9, 10)),
      derive(now: DateTime(2026, 9, 9, 10), punches: [punch(9, 0)]),
      derive(employee: untracked, now: DateTime(2026, 9, 9, 10)),
    ]..sort(compareDayStatus);

    test('absent › late › present › untracked', () {
      expect(rows.map((r) => r.status), [
        AttendanceStatus.absentSoFar,
        AttendanceStatus.late,
        AttendanceStatus.present,
        AttendanceStatus.untracked,
      ]);
    });

    test('counts exclude untracked', () {
      final c = AttendanceCounts.of(rows);
      expect(c.tracked, 3);
      expect(c.present, 1);
      expect(c.late, 1);
      expect(c.absent, 1);
      expect(c.notIn, 0);
    });

    test('status filter Absent matches both absent variants', () {
      expect(filterRows(rows, statusKey: 'Absent').length, 1);
      expect(filterRows(rows, statusKey: 'Late').single.status,
          AttendanceStatus.late);
    });

    test('search matches name case-insensitively', () {
      expect(filterRows(rows, query: 'chen').single.employee, untracked);
    });
  });

  group('freshness', () {
    final now = DateTime(2026, 9, 9, 10, 42);
    test('relative under an hour, clock today, date otherwise', () {
      expect(freshnessLabel(now.subtract(const Duration(seconds: 20)), now),
          'Updated just now');
      expect(freshnessLabel(now.subtract(const Duration(minutes: 5)), now),
          'Updated 5 min ago');
      expect(freshnessLabel(DateTime(2026, 9, 9, 9, 15), now), 'Updated 09:15');
      expect(freshnessLabel(DateTime(2026, 8, 28, 19, 52), now), 'Updated 28 Aug');
      expect(freshnessLabel(null, now), 'Updating…');
    });
    test('stale past the 15-minute sync interval', () {
      expect(isStale(now.subtract(const Duration(minutes: 14)), now), isFalse);
      expect(isStale(now.subtract(const Duration(minutes: 42)), now), isTrue);
    });
  });

  test('ShiftRules parses Frappe time strings and labels', () {
    final s = ShiftRules.fromJson({
      'name': 'General',
      'start_time': '08:00:00',
      'end_time': '20:00:00',
      'late_entry_grace_period': 15,
      'holiday_list': 'Multimax 2026',
    });
    expect(s.cutoffLabel, '08:15');
    expect(s.cutoffOn(day), DateTime(2026, 9, 9, 8, 15));
    expect(s.endLabel, '20:00');
  });

  test('initials', () {
    expect(tracked.initials, 'AM');
    expect(const TrackedEmployee(name: 'x', employeeName: 'Ashal').initials, 'A');
  });
  group('dashboardAttendanceHighlights', () {
    EmployeeDayStatus row(String name, AttendanceStatus st, {String? id}) =>
        EmployeeDayStatus(
            employee: TrackedEmployee(
                name: id ?? name, employeeName: name, deviceId: '1'),
            status: st);

    test('drops untracked and self, orders attention-first, caps', () {
      final rows = [
        row('Zed Present', AttendanceStatus.present),
        row('Amy Late', AttendanceStatus.late),
        row('Bob Absent', AttendanceStatus.absentSoFar),
        row('Cal Not in', AttendanceStatus.notInYet),
        EmployeeDayStatus(employee: untracked, status: AttendanceStatus.untracked),
        row('Me Absent', AttendanceStatus.absentSoFar, id: 'ME'),
      ];
      final out = dashboardAttendanceHighlights(rows, selfEmployee: 'ME');
      expect(out.map((r) => r.employee.employeeName).toList(),
          ['Bob Absent', 'Amy Late', 'Cal Not in']);
    });

    test('max 0 returns nothing; holiday rows never appear', () {
      final rows = [
        row('A', AttendanceStatus.holiday),
        row('B', AttendanceStatus.holiday),
      ];
      expect(dashboardAttendanceHighlights(rows), isEmpty);
      expect(
          dashboardAttendanceHighlights([row('C', AttendanceStatus.late)], max: 0),
          isEmpty);
    });
  });
}
