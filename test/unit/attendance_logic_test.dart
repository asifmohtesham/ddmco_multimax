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

  group('buildMonthStrip', () {
    final sep = DateTime(2026, 9);
    const hol = {'2026-09-06', '2026-09-13', '2026-09-20', '2026-09-27'};
    AttendanceRecord rec(int d, String status, {bool late = false, String leave = ''}) =>
        AttendanceRecord(
          name: 'ATT-$d',
          employee: tracked.name,
          employeeName: tracked.employeeName,
          date: DateTime(2026, 9, d),
          status: status,
          lateEntry: late,
          inTime: status == 'Present'
              ? DateTime(2026, 9, d, late ? 8 : 7, late ? 30 : 55)
              : null,
          leaveType: leave,
        );
    // 1–9 Sep: 5 present, 2 late (3rd, 8th), 1 absent (5th), Sun 6th holiday.
    final ledger = [
      rec(1, 'Present'), rec(2, 'Present'), rec(3, 'Present', late: true),
      rec(4, 'Present'), rec(5, 'Absent'), rec(7, 'Present'),
      rec(8, 'Present', late: true), rec(9, 'Present'),
    ];
    MonthStrip strip({
      List<AttendanceRecord>? l,
      AttendanceStatus todaySt = AttendanceStatus.notInYet,
      DateTime? now,
      DateTime? month,
    }) =>
        buildMonthStrip(
          month: month ?? sep,
          ledger: l ?? ledger,
          holidays: hol,
          today: EmployeeDayStatus(employee: tracked, status: todaySt),
          now: now ?? DateTime(2026, 9, 10, 8, 32),
          shift: shift,
          employee: tracked,
        );

    test('September so far: 5 present, 2 late, 1 absent, Sunday holiday', () {
      final s = strip();
      expect(s.days.length, 30);
      expect(s.days[0], AttendanceStatus.present);
      expect(s.days[2], AttendanceStatus.late);
      expect(s.days[4], AttendanceStatus.absent);
      expect(s.days[5], AttendanceStatus.holiday);
      expect((s.present, s.late, s.absent, s.leave), (5, 2, 1, 0));
      expect(s.tallyLabel, 'September · 5 present · 2 late · 1 absent');
    });

    test('today pending is null with todayIndex; future days null', () {
      final s = strip();
      expect(s.todayIndex, 9);
      expect(s.days[9], isNull);
      expect(s.days[10], isNull);
      expect(s.days[12], isNull); // a future Sunday stays faint
    });

    test('today late is drawn and counted once', () {
      final s = strip(todaySt: AttendanceStatus.late);
      expect(s.days[9], AttendanceStatus.late);
      expect(s.late, 3);
    });

    test('past working day with no ledger row is unknown, not absent', () {
      final s = strip(l: [rec(1, 'Present')]);
      expect(s.days[1], isNull);
      expect(s.absent, 0);
    });

    test('On Leave counts as leave and appears in the tally', () {
      final s = strip(l: [rec(2, 'On Leave', leave: 'Casual Leave')]);
      expect(s.days[1], AttendanceStatus.onLeave);
      expect(s.leave, 1);
      expect(s.tallyLabel, 'September · 0 present · 0 late · 0 absent · 1 leave');
    });

    test('a past month has no today', () {
      final s = strip(month: DateTime(2026, 8), l: const [], now: DateTime(2026, 9, 10, 9));
      expect(s.days.length, 31);
      expect(s.todayIndex, isNull);
    });

    test('February 2027 has 28 days', () {
      final s = strip(month: DateTime(2027, 2), l: const [], now: DateTime(2027, 2, 1, 9));
      expect(s.days.length, 28);
      expect(s.todayIndex, 0);
    });
  });

  group('myAttendanceHeadline', () {
    final now = DateTime(2026, 9, 10, 8, 32); // a Thursday
    (String, String) h(AttendanceStatus s, {DateTime? inTime, Duration? lateBy}) =>
        myAttendanceHeadline(
            EmployeeDayStatus(employee: tracked, status: s, inTime: inTime, lateBy: lateBy),
            shift,
            now);

    test('before the cut-off tells them what to do', () {
      expect(h(AttendanceStatus.notInYet), ('Not in yet', 'Punch before 08:15 to be on time'));
    });
    test('after the cut-off is true whatever the cause', () {
      expect(h(AttendanceStatus.absentSoFar), ('No check-in recorded yet', 'Shift started 08:00'));
    });
    test('on time', () {
      expect(h(AttendanceStatus.present, inTime: DateTime(2026, 9, 10, 7, 58)),
          ('In · 07:58', 'On time'));
    });
    test('late', () {
      expect(
          h(AttendanceStatus.late,
              inTime: DateTime(2026, 9, 10, 8, 27), lateBy: const Duration(minutes: 12)),
          ('In · 08:27', '12 min late'));
    });
    test('holiday names the weekday', () {
      expect(h(AttendanceStatus.holiday), ('Holiday', 'Thursday · no attendance expected'));
    });
    test('late without minutes never says on time', () {
      expect(h(AttendanceStatus.late, inTime: DateTime(2026, 9, 10, 8, 27)),
          ('In · 08:27', 'After the 08:15 cut-off'));
    });
    test('late with no in-time', () {
      expect(h(AttendanceStatus.late), ('Late', 'After the 08:15 cut-off'));
    });
  });

  test('unenrolledLabel pluralises', () {
    expect(unenrolledLabel(1), "1 employee isn't enrolled on the terminal");
    expect(unenrolledLabel(10), "10 employees aren't enrolled on the terminal");
  });

  group('two shifts', () {
    // The live Shift Types (setup-two-shifts.py): windows touch at 13:00 (Fri 13:15).
    const morning = ShiftRules(
        name: 'Morning', start: Duration(hours: 8), end: Duration(hours: 12, minutes: 15),
        graceMinutes: 15, earlyExitGraceMinutes: 15, checkInBeforeMinutes: 120, checkOutAfterMinutes: 45);
    const afternoon = ShiftRules(
        name: 'Afternoon', start: Duration(hours: 13, minutes: 30), end: Duration(hours: 20),
        graceMinutes: 15, earlyExitGraceMinutes: 15, checkInBeforeMinutes: 30, checkOutAfterMinutes: 120);
    const morningFri = ShiftRules(
        name: 'Morning (Fri)', start: Duration(hours: 8), end: Duration(hours: 12),
        graceMinutes: 15, earlyExitGraceMinutes: 15, checkInBeforeMinutes: 120, checkOutAfterMinutes: 75);
    const afternoonFri = ShiftRules(
        name: 'Afternoon (Fri)', start: Duration(hours: 14, minutes: 30), end: Duration(hours: 20),
        graceMinutes: 15, earlyExitGraceMinutes: 15, checkInBeforeMinutes: 75, checkOutAfterMinutes: 120);
    final sat = DateTime(2026, 9, 12);

    EmployeeCheckin p(int h, int m, [String logType = '', DateTime? on]) {
      final d = on ?? sat;
      return EmployeeCheckin(
          name: 'p$h:$m', employee: tracked.name, time: DateTime(d.year, d.month, d.day, h, m), logType: logType);
    }

    EmployeeDayStatus day2({
      required DateTime now,
      List<EmployeeCheckin> punches = const [],
      List<AttendanceRecord> ledgers = const [],
      DateTime? on,
      List<ShiftRules> shifts = const [morning, afternoon],
    }) =>
        deriveDayStatus(
          employee: tracked,
          day: on ?? sat,
          now: now,
          shift: shifts.first,
          shifts: shifts,
          isHoliday: false,
          punches: punches,
          ledgers: ledgers,
        );

    test('morning done and afternoon in: present, one segment per shift', () {
      final r = day2(
          now: DateTime(2026, 9, 12, 15), punches: [p(7, 58, 'IN'), p(12, 2, 'OUT'), p(13, 31, 'IN')]);
      expect(r.status, AttendanceStatus.present);
      expect(r.shifts.map((s) => s.shift.name), ['Morning', 'Afternoon']);
      expect(r.shifts[0].inTime, DateTime(2026, 9, 12, 7, 58));
      expect(r.shifts[0].outTime, DateTime(2026, 9, 12, 12, 2));
      expect(r.shifts[1].inTime, DateTime(2026, 9, 12, 13, 31));
      expect(r.shifts[1].outTime, isNull);
      expect(r.inTime, DateTime(2026, 9, 12, 7, 58));
    });

    test('late into the afternoon: late by the minutes past 13:45', () {
      final r = day2(
          now: DateTime(2026, 9, 12, 15), punches: [p(7, 58, 'IN'), p(12, 14, 'OUT'), p(13, 50, 'IN')]);
      expect(r.status, AttendanceStatus.late);
      expect(r.lateBy, const Duration(minutes: 5));
      expect(r.shifts[0].status, AttendanceStatus.present);
      expect(r.shifts[1].status, AttendanceStatus.late);
    });

    test('before the afternoon cut-off an unstarted afternoon does not count', () {
      final r = day2(now: DateTime(2026, 9, 12, 13, 40), punches: [p(7, 58, 'IN'), p(12, 5, 'OUT')]);
      expect(r.status, AttendanceStatus.present);
      expect(r.shifts[1].status, AttendanceStatus.notInYet);
    });

    test('no OUT once the morning window closes (13:00) is No check-out', () {
      final r = day2(now: DateTime(2026, 9, 12, 13, 10), punches: [p(7, 58, 'IN')]);
      expect(r.shifts[0].status, AttendanceStatus.noCheckOut);
      expect(r.status, AttendanceStatus.noCheckOut);
    });

    test('inside the morning window with no OUT yet is just present', () {
      expect(day2(now: DateTime(2026, 9, 12, 12, 30), punches: [p(7, 58, 'IN')]).status,
          AttendanceStatus.present);
    });

    test('missing the afternoon past its cut-off outranks a done morning', () {
      final r = day2(now: DateTime(2026, 9, 12, 14), punches: [p(7, 58, 'IN'), p(12, 2, 'OUT')]);
      expect(r.status, AttendanceStatus.absentSoFar);
    });

    test('a double tap keeps its direction; OUT comes from log_type', () {
      final r = day2(
          now: DateTime(2026, 9, 12, 15),
          punches: [p(7, 58, 'IN'), p(7, 59, 'IN'), p(12, 3, 'OUT'), p(13, 29, 'IN')]);
      expect(r.shifts[0].directions, [true, true, false]);
      expect(r.shifts[0].outTime, DateTime(2026, 9, 12, 12, 3));
      expect(r.status, AttendanceStatus.present);
    });

    test('rows without log_type alternate within each shift', () {
      final r = day2(now: DateTime(2026, 9, 12, 15), punches: [p(7, 58), p(12, 2), p(13, 31)]);
      expect(r.shifts[0].directions, [true, false]);
      expect(r.shifts[1].directions, [true]);
    });

    test('12:50 is still a Morning OUT; 13:00 belongs to the Afternoon', () {
      final r = day2(
          now: DateTime(2026, 9, 12, 15), punches: [p(7, 58, 'IN'), p(12, 50, 'OUT'), p(13, 0, 'IN')]);
      expect(r.shifts[0].punches.length, 2);
      expect(r.shifts[1].punches.single.time, DateTime(2026, 9, 12, 13));
    });

    test('Friday: 13:10 still closes the Morning; 14:25 is on time', () {
      final fri = DateTime(2026, 9, 18);
      final r = day2(
        on: fri,
        shifts: const [morningFri, afternoonFri],
        now: DateTime(2026, 9, 18, 15),
        punches: [p(7, 58, 'IN', fri), p(13, 10, 'OUT', fri), p(14, 25, 'IN', fri)],
      );
      expect(r.shifts[0].outTime, DateTime(2026, 9, 18, 13, 10));
      expect(r.shifts[1].status, AttendanceStatus.present);
    });

    test('early exit when the last OUT is before end − 15 min', () {
      final r = day2(
          now: DateTime(2026, 9, 12, 15), punches: [p(7, 58, 'IN'), p(11, 40, 'OUT'), p(13, 31, 'IN')]);
      expect(r.shifts[0].earlyExit, isTrue);
      expect(r.flag, 'Early exit');
    });

    AttendanceRecord rec(String shift, String status, {DateTime? inT, DateTime? outT}) => AttendanceRecord(
        name: 'A-$shift', employee: tracked.name, employeeName: '', date: sat, status: status,
        shift: shift, inTime: inT, outTime: outT);

    test('past day: two ledger rows, an Absent afternoon makes the day Absent', () {
      final r = day2(now: DateTime(2026, 9, 14, 9), ledgers: [
        rec('Morning', 'Present', inT: DateTime(2026, 9, 12, 7, 58), outT: DateTime(2026, 9, 12, 12, 2)),
        rec('Afternoon', 'Absent'),
      ]);
      expect(r.shifts[0].status, AttendanceStatus.present);
      expect(r.shifts[1].status, AttendanceStatus.absent);
      expect(r.status, AttendanceStatus.absent);
    });

    test('a Present ledger row with no out time is No check-out', () {
      final r = day2(now: DateTime(2026, 9, 14, 9), ledgers: [
        rec('Morning', 'Present', inT: DateTime(2026, 9, 12, 7, 58)),
        rec('Afternoon', 'Present',
            inT: DateTime(2026, 9, 12, 13, 29), outT: DateTime(2026, 9, 12, 20, 1)),
      ]);
      expect(r.shifts[0].status, AttendanceStatus.noCheckOut);
      expect(r.status, AttendanceStatus.noCheckOut);
    });

    test('a single-shift day never reports No check-out', () {
      final r = derive(now: DateTime(2026, 9, 10, 9), punches: [punch(8, 0)]);
      expect(r.status, AttendanceStatus.present);
      expect(r.shifts, isEmpty);
    });

    test('counts and the No check-out filter', () {
      final rows = [
        day2(now: DateTime(2026, 9, 12, 13, 10), punches: [p(7, 58, 'IN')]),
        day2(now: DateTime(2026, 9, 12, 13, 10), punches: [p(7, 58, 'IN'), p(12, 2, 'OUT')]),
      ];
      final c = AttendanceCounts.of(rows);
      expect((c.noOut, c.present, c.tracked), (1, 1, 2));
      expect(filterRows(rows, statusKey: 'No check-out').length, 1);
    });

    test('headline follows the shift in progress and names it', () {
      final now = DateTime(2026, 9, 12, 14);
      final r = day2(now: now, punches: [p(7, 58, 'IN'), p(12, 2, 'OUT'), p(13, 50, 'IN')]);
      expect(myAttendanceHeadline(r, morning, now), ('In · 13:50', 'Afternoon · 5 min late'));

      final noon = DateTime(2026, 9, 12, 13, 10);
      final r2 = day2(now: noon, punches: [p(7, 58, 'IN')]);
      expect(myAttendanceHeadline(r2, morning, noon),
          ('Not in yet', 'Afternoon · Punch before 13:45 to be on time'));
    });

    test('month strip: two rows a day, the worst shift wins, No check-out tallied', () {
      AttendanceRecord r2(int d, String shift, String status, {bool noOut = false}) => AttendanceRecord(
          name: 'A$d$shift', employee: tracked.name, employeeName: '', date: DateTime(2026, 9, d),
          status: status, shift: shift,
          inTime: status == 'Present' ? DateTime(2026, 9, d, 8) : null,
          outTime: status == 'Present' && !noOut ? DateTime(2026, 9, d, 12) : null);
      final s = buildMonthStrip(
        month: DateTime(2026, 9),
        ledger: [
          r2(12, 'Morning', 'Present'), r2(12, 'Afternoon', 'Present'),
          r2(14, 'Morning', 'Present'), r2(14, 'Afternoon', 'Absent'),
          r2(15, 'Morning', 'Present', noOut: true), r2(15, 'Afternoon', 'Present'),
        ],
        holidays: const {},
        today: null,
        now: DateTime(2026, 9, 16, 9),
        shift: morning,
        employee: tracked,
        catalog: const {'Morning': morning, 'Afternoon': afternoon},
      );
      expect(s.days[11], AttendanceStatus.present);
      expect(s.days[13], AttendanceStatus.absent);
      expect(s.days[14], AttendanceStatus.noCheckOut);
      expect((s.present, s.absent, s.noOut), (1, 1, 1));
      expect(s.tallyLabel, 'September · 1 present · 0 late · 1 absent · 1 no check-out');
    });

    test('resolveShifts: assignments first, then default shift, then fallback', () {
      final a = [
        ShiftAssignmentRow(
            employee: tracked.name, shiftType: 'Afternoon',
            startDate: DateTime(2026, 9, 12), endDate: DateTime(2026, 9, 12)),
        ShiftAssignmentRow(employee: tracked.name, shiftType: 'Morning', startDate: DateTime(2026, 9, 12)),
        ShiftAssignmentRow(employee: 'OTHER', shiftType: 'Night', startDate: DateTime(2026, 9, 1)),
      ];
      const cat = {'Morning': morning, 'Afternoon': afternoon};
      List<String> names(DateTime d, {TrackedEmployee e = tracked}) =>
          resolveShifts(employee: e, day: d, assignments: a, catalog: cat).map((s) => s.name).toList();
      expect(names(sat), ['Morning', 'Afternoon']);
      expect(names(DateTime(2026, 9, 13)), ['Morning']); // Afternoon ended on the 12th
      expect(names(DateTime(2026, 9, 11)), ['General']); // before any assignment
      const withDefault = TrackedEmployee(
          name: 'HR-EMP-00001', employeeName: 'x', deviceId: '7', defaultShift: 'Night');
      expect(names(DateTime(2026, 9, 11), e: withDefault), ['Night']);
    });

    test('resolveShifts: no assignment falls back to the ledger\'s own shift names', () {
      const cat = {'Morning': morning, 'Afternoon': afternoon};
      final withLedger = resolveShifts(
        employee: tracked,
        day: sat,
        assignments: const [],
        catalog: cat,
        ledgerNames: const ['Morning', 'Afternoon'],
      ).map((s) => s.name).toList();
      expect(withLedger, ['Morning', 'Afternoon']);

      // A Leave Application's blank shift name is not a usable ledger name.
      final blankOnly = resolveShifts(
        employee: tracked,
        day: sat,
        assignments: const [],
        catalog: cat,
        ledgerNames: const [''],
      ).map((s) => s.name).toList();
      expect(blankOnly, ['General']); // default/fallback, unaffected by ledgerNames
    });

    test('ShiftRules windows, short name and the new Frappe fields', () {
      expect(morning.windowEndOn(sat), DateTime(2026, 9, 12, 13));
      expect(afternoon.windowStartOn(sat), DateTime(2026, 9, 12, 13));
      expect(morningFri.shortName, 'Morning');
      final j = ShiftRules.fromJson({
        'name': 'Afternoon', 'start_time': '13:30:00', 'end_time': '20:00:00',
        'early_exit_grace_period': 15, 'allow_check_out_after_shift_end_time': 120,
      });
      expect((j.earlyExitGraceMinutes, j.checkOutAfterMinutes), (15, 120));
    });
  });
}
