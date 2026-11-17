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

    test('no punch at/after cut-off is Absent', () {
      expect(derive(now: DateTime(2026, 9, 9, 8, 15)).status,
          AttendanceStatus.absent);
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
        AttendanceStatus.absent,
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

    test('status filter Absent matches absent rows', () {
      expect(filterRows(rows, statusKey: 'Absent').length, 1);
      expect(filterRows(rows, statusKey: 'Late').single.status,
          AttendanceStatus.late);
    });

    test('search matches name case-insensitively', () {
      expect(filterRows(rows, query: 'chen').single.employee, untracked);
    });

    test('No check-out counts toward Present and is included by the Present filter', () {
      final noOutRows = [
        EmployeeDayStatus(employee: tracked, status: AttendanceStatus.noCheckOut),
      ];
      final c = AttendanceCounts.of(noOutRows);
      expect(c.present, 1);
      expect(c.noOut, 1);
      expect(filterRows(noOutRows, statusKey: 'Present'), noOutRows);
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
        row('Bob Absent', AttendanceStatus.absent),
        row('Cal Not in', AttendanceStatus.notInYet),
        EmployeeDayStatus(employee: untracked, status: AttendanceStatus.untracked),
        row('Me Absent', AttendanceStatus.absent, id: 'ME'),
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
    test('after the cut-off reads Absent, never blaming the terminal', () {
      expect(h(AttendanceStatus.absent), ('Absent', 'No check-in recorded'));
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
    test('a named holiday heads with its name; other days ignore it', () {
      final hol = EmployeeDayStatus(employee: tracked, status: AttendanceStatus.holiday);
      expect(myAttendanceHeadline(hol, shift, now, holidayName: 'Eid al-Fitr'),
          ('Eid al-Fitr', 'Thursday · no attendance expected'));
      final absent = EmployeeDayStatus(employee: tracked, status: AttendanceStatus.absent);
      expect(myAttendanceHeadline(absent, shift, now, holidayName: 'Eid al-Fitr'),
          ('Absent', 'No check-in recorded'));
    });
    test('late without minutes never says on time', () {
      expect(h(AttendanceStatus.late, inTime: DateTime(2026, 9, 10, 8, 27)),
          ('In · 08:27', 'After the 08:15 cut-off'));
    });
    test('late with no in-time', () {
      expect(h(AttendanceStatus.late), ('Late', 'After the 08:15 cut-off'));
    });
  });

  test('withNamedHolidays: each holiday before its own and earlier days', () {
    AttendanceRecord rec(int d) => AttendanceRecord(
        name: 'A$d', employee: 'E', employeeName: 'E', date: DateTime(2026, 3, d, 9), status: 'Present');
    final out = withNamedHolidays(
      [rec(23), rec(22), rec(19)], // newest first, as the screen sorts them
      [
        (date: DateTime(2026, 3, 20), name: 'Eid al-Fitr'),
        (date: DateTime(2026, 3, 21), name: 'Eid al-Fitr'),
        (date: DateTime(2026, 3, 2), name: 'Earliest'),
        (date: DateTime(2026, 3, 30), name: 'Latest'),
      ],
    );
    String key(Object e) => e is AttendanceRecord
        ? 'r${e.date.day}'
        : 'h${(e as ({DateTime date, String name})).date.day}';
    expect(out.map(key), ['h30', 'r23', 'r22', 'h21', 'h20', 'r19', 'h2']);
    // No holidays: the rows unchanged; no rows: just the holidays.
    expect(withNamedHolidays([rec(5)], const []).map(key), ['r5']);
    expect(withNamedHolidays(const [], [(date: DateTime(2026, 3, 20), name: 'x')]).map(key), ['h20']);
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

    test('missing the afternoon past its cut-off: Morning Present, Afternoon Absent', () {
      final r = day2(now: DateTime(2026, 9, 12, 14), punches: [p(7, 58, 'IN'), p(12, 2, 'OUT')]);
      expect(r.shifts[0].status, AttendanceStatus.present);
      expect(r.shifts[1].status, AttendanceStatus.absent);
      // The day status still orders and counts the row by its attention-worthy shift.
      expect(r.status, AttendanceStatus.absent);
    });

    test('an open afternoon read as Absent stays pending in today\'s month strip', () {
      final now = DateTime(2026, 9, 12, 14);
      final r = day2(now: now, punches: [p(7, 58, 'IN'), p(12, 2, 'OUT')]);
      final s = buildMonthStrip(
        month: DateTime(2026, 9),
        ledger: const [],
        holidays: const {},
        today: r,
        now: now,
        shift: morning,
        employee: tracked,
      );
      expect(s.todayIndex, 11);
      expect(s.days[11], isNull);
      expect(s.absent, 0);
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
      // No check-out is on site (just missing an OUT), so it also counts
      // toward Present (F3) — was (1, 1, 2) before that counted them nowhere.
      expect((c.noOut, c.present, c.tracked), (1, 2, 2));
      expect(filterRows(rows, statusKey: 'No check-out').length, 1);
    });

    test('an On Leave row with no matching shift wins the whole day', () {
      final onLeave = AttendanceRecord(
          name: 'A-leave',
          employee: tracked.name,
          employeeName: '',
          date: sat,
          status: 'On Leave',
          shift: '', // Leave Application rows carry no shift
          leaveType: 'Casual Leave');
      final r = day2(now: DateTime(2026, 9, 12, 15), ledgers: [onLeave]);
      expect(r.status, AttendanceStatus.onLeave);
    });

    test('buildMonthStrip agrees: the same On Leave row paints onLeave, not absent', () {
      final onLeave = AttendanceRecord(
          name: 'A-leave',
          employee: tracked.name,
          employeeName: '',
          date: sat,
          status: 'On Leave',
          shift: '',
          leaveType: 'Casual Leave');
      final s = buildMonthStrip(
        month: DateTime(2026, 9),
        ledger: [onLeave],
        holidays: const {},
        today: null,
        now: DateTime(2026, 9, 16, 9),
        shift: morning,
        employee: tracked,
        catalog: const {'Morning': morning, 'Afternoon': afternoon},
      );
      expect(s.days[11], AttendanceStatus.onLeave); // the 12th, index 11
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

    test('resolveShifts: an unresolved catalog name falls back to a single shift', () {
      final a = [
        ShiftAssignmentRow(
            employee: tracked.name, shiftType: 'Morning', startDate: DateTime(2026, 9, 12), endDate: DateTime(2026, 9, 12)),
        ShiftAssignmentRow(
            employee: tracked.name, shiftType: 'Afternoon', startDate: DateTime(2026, 9, 12), endDate: DateTime(2026, 9, 12)),
      ];
      // Afternoon is missing from the catalog (a transient fetchShiftTypes
      // failure, or a renamed/deleted Shift Type).
      final names = resolveShifts(
        employee: tracked,
        day: sat,
        assignments: a,
        catalog: const {'Morning': morning},
      ).map((s) => s.name).toList();
      expect(names, ['General']); // single fallback shift, not two overlapping guesses
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

  // The clocked-hours model from 2026-11-30 (design 3.2–3.4). The worked
  // examples are the same as clocked-hours/test-attendance-stamp.py, which
  // checks the Server Script that stamps the Attendance rows.
  group('clocked hours', () {
    // As the Shift Types come back from Frappe (Time fields as strings,
    // empty Friday expected hours = same as the other days).
    final standard = ShiftRules.fromJson({
      'name': 'Standard', 'start_time': '8:00:00', 'end_time': '20:00:00',
      'late_entry_grace_period': 15, 'begin_check_in_before_shift_start_time': 120,
      'allow_check_out_after_shift_end_time': 120, 'holiday_list': '',
      'custom_expected_hours': 10, 'custom_expected_hours_friday': null,
      'custom_break_start': '12:15:00', 'custom_break_end': '13:30:00',
      'custom_break_start_friday': '12:00:00', 'custom_break_end_friday': '14:30:00',
    });
    final lateStart = ShiftRules.fromJson({
      'name': 'Late Start', 'start_time': '10:00:00', 'end_time': '18:00:00',
      'late_entry_grace_period': 15, 'begin_check_in_before_shift_start_time': 240,
      'allow_check_out_after_shift_end_time': 240,
      'custom_expected_hours': 8, 'custom_expected_hours_friday': 0,
      'custom_break_start': null, 'custom_break_end': '',
      'custom_break_start_friday': '12:00:00', 'custom_break_end_friday': '14:30:00',
    });
    final earlyFinish = ShiftRules.fromJson({
      'name': 'Early Finish', 'start_time': '08:00:00', 'end_time': '19:00:00',
      'late_entry_grace_period': 15, 'begin_check_in_before_shift_start_time': 120,
      'allow_check_out_after_shift_end_time': 180,
      'custom_expected_hours': 8.0,
      'custom_break_start': '12:15:00', 'custom_break_end': '13:30:00',
      'custom_break_start_friday': '12:00:00', 'custom_break_end_friday': '14:30:00',
    });
    final mon = DateTime(2026, 11, 30), fri = DateTime(2026, 12, 4);

    List<EmployeeCheckin> taps(DateTime d, List<String> hms) => [
          for (final t in hms)
            EmployeeCheckin(
              name: t,
              employee: tracked.name,
              time: d.add(Duration(
                  hours: int.parse(t.split(':')[0]), minutes: int.parse(t.split(':')[1]))),
            ),
        ];

    // pattern, day, taps, net, shortfall, missing punch — design 3.4 tables.
    final cases = <(ShiftRules, DateTime, List<String>, double, double, bool)>[
      (standard, mon, ['08:00', '12:15', '13:30', '20:00'], 10.75, 0, false),
      (standard, mon, ['08:00', '20:00'], 10.75, 0, false),
      (standard, mon, ['08:00', '12:40', '13:10', '20:00'], 10.75, 0, false),
      (standard, mon, ['08:20', '12:15', '13:30', '20:00'], 10.42, 0, false),
      (standard, mon, ['08:00', '12:15', '13:30', '18:00'], 8.75, 1.25, false),
      (standard, mon, ['08:00', '13:30', '20:00'], 4.25, 5.75, true),
      (standard, mon, ['08:00'], 0, 10, true),
      (standard, fri, ['08:00', '12:00', '14:30', '20:00'], 9.5, 0.5, false),
      (standard, fri, ['08:00', '20:00'], 9.5, 0.5, false),
      (lateStart, mon, ['10:00', '18:00'], 8, 0, false),
      (lateStart, mon, ['08:02', '18:02'], 10, 0, false),
      (lateStart, fri, ['10:00', '18:00'], 5.5, 2.5, false),
      (lateStart, fri, ['10:00', '12:00', '14:30', '18:00'], 5.5, 2.5, false),
      (earlyFinish, mon, ['08:00', '12:15', '13:30', '19:00'], 9.75, 0, false),
      (earlyFinish, fri, ['08:00', '12:00', '14:30', '19:00'], 8.5, 0, false),
    ];

    for (final (shift, d, hms, net, short, missing) in cases) {
      test('${shift.name} ${d.weekday == DateTime.friday ? 'Fri' : 'Mon'} ${hms.join(', ')} '
          '→ net $net, short $short', () {
        final c = clockedDay(taps(d, hms), shift, d);
        expect(c.netHours, closeTo(net, 1e-9));
        expect(c.punchCount, hms.length);
        expect(c.oddTaps, missing);
        expect(c.expectedHours, shift.expectedHours);

        // The same day derived the next morning, before HRMS has a row.
        final r = deriveDayStatus(
          employee: tracked,
          day: d,
          now: d.add(const Duration(days: 1, hours: 7)),
          shift: shift,
          isHoliday: false,
          punches: taps(d, hms).reversed.toList(), // unsorted on purpose
        );
        expect(r.isClocked, isTrue);
        expect(r.netHours, closeTo(net, 1e-9));
        expect(r.expectedHours, shift.expectedHours);
        expect(r.shortfallHours, closeTo(short, 1e-9));
        expect(r.missingPunch, missing);
        expect(r.status == AttendanceStatus.missingPunch, missing);
        expect(r.rules, same(shift));
      });
    }

    test('Late Start: 10:20 is 5 min late (cut-off 10:15)', () {
      final r = deriveDayStatus(
        employee: tracked, day: mon, now: DateTime(2026, 11, 30, 11), shift: lateStart,
        isHoliday: false, punches: taps(mon, ['10:20']),
      );
      expect(r.status, AttendanceStatus.late);
      expect(r.lateBy, const Duration(minutes: 5));
    });

    test('today, still running: an odd count is just "in", no shortfall yet', () {
      final now = DateTime(2026, 11, 30, 15);
      final r = deriveDayStatus(
        employee: tracked, day: mon, now: now, shift: standard, isHoliday: false,
        punches: taps(mon, ['08:00', '12:15', '13:30']),
      );
      expect(r.status, AttendanceStatus.present);
      expect(r.missingPunch, isFalse);
      expect(r.netHours, closeTo(4.25, 1e-9)); // the open 13:30 tap adds nothing yet
      expect(r.shortfallHours, isNull);
      expect(r.hoursLabel, '4h 15m of 10h');
      expect(r.shortfallLabel, isNull);
      expect(r.outTime, isNull);
      expect(myAttendanceHeadline(r, standard, now), ('In · 08:00', 'On time · 4h 15m of 10h'));
    });

    test('today after the window closes (22:00): odd taps become Missing punch', () {
      final r = deriveDayStatus(
        employee: tracked, day: mon, now: DateTime(2026, 11, 30, 22, 1), shift: standard,
        isHoliday: false, punches: taps(mon, ['08:20', '13:30', '20:00']),
      );
      expect(r.status, AttendanceStatus.missingPunch);
      expect(r.flag, '5 min late'); // the pill says Missing punch; the flag keeps the minutes
      expect(r.flagIsWarning, isTrue);
      expect(r.shortfallLabel, 'Short 6h 05m'); // 08:20–13:30 less the 12:15–13:30 break = 3.92 h
      expect(r.status.severity, AttendanceStatus.noCheckOut.severity);
    });

    test('taps outside the 06:00–22:00 window are shown but not counted', () {
      final c = clockedDay(taps(mon, ['05:30', '08:00', '20:00', '22:30']), standard, mon);
      expect(c.punchCount, 2);
      expect(c.netHours, closeTo(10.75, 1e-9));
    });

    test('no taps: Absent with expected hours and no shortfall (design 3.4)', () {
      final r = deriveDayStatus(
        employee: tracked, day: mon, now: DateTime(2026, 12, 1, 7), shift: standard,
        isHoliday: false,
      );
      expect(r.status, AttendanceStatus.absent);
      expect((r.netHours, r.expectedHours, r.shortfallHours), (0.0, 10.0, 0.0));
    });

    test('Friday: own break when both fields are set, else the weekday break', () {
      expect(standard.breakLabelOn(fri), '12:00–14:30');
      expect(standard.breakLabelOn(mon), '12:15–13:30');
      expect(lateStart.breakOn(mon), isNull);
      final noFridayBreak = ShiftRules.fromJson({
        'name': 'X', 'start_time': '08:00:00', 'end_time': '20:00:00',
        'custom_expected_hours': 10,
        'custom_break_start': '12:15:00', 'custom_break_end': '13:30:00',
        'custom_break_start_friday': '12:00:00', // end missing: weekday break applies
      });
      expect(noFridayBreak.breakLabelOn(fri), '12:15–13:30');
    });

    test('Friday expected hours: their own figure when set, else the weekday one', () {
      expect(standard.expectedHoursOn(fri), 10);
      final withFriday = ShiftRules.fromJson({
        'name': 'X', 'start_time': '08:00:00', 'end_time': '20:00:00',
        'custom_expected_hours': '10', 'custom_expected_hours_friday': '9.5',
        'custom_break_start_friday': '12:00:00', 'custom_break_end_friday': '14:30:00',
      });
      expect(withFriday.expectedHoursOn(fri), 9.5);
      expect(withFriday.expectedHoursOn(mon), 10);
      final c = clockedDay(taps(fri, ['08:00', '20:00']), withFriday, fri);
      expect(c.shortfallFor(AttendanceStatus.present), 0);
    });

    AttendanceRecord stamped(String status,
            {bool late = false, bool missing = false, double net = 10.75, double short = 0}) =>
        AttendanceRecord(
          name: 'ATT-1', employee: tracked.name, employeeName: '', date: mon, status: status,
          shift: 'Standard', lateEntry: late, workingHours: 12,
          inTime: DateTime(2026, 11, 30, 8, 20), outTime: DateTime(2026, 11, 30, 20),
          punchCount: missing ? 3 : 4, missingPunch: missing, netHours: net,
          expectedHours: 10, shortfallHours: short,
        );

    test('past day: net, expected, shortfall and missing punch come from the record', () {
      final r = deriveDayStatus(
        employee: tracked, day: mon, now: DateTime(2026, 12, 3), shift: standard,
        isHoliday: false,
        // The day's punches disagree on purpose: the stamped row wins.
        punches: taps(mon, ['08:00', '20:00']),
        ledger: stamped('Present', late: true, missing: true, net: 4.25, short: 5.75),
      );
      expect(r.status, AttendanceStatus.missingPunch);
      expect(r.flag, '5 min late');
      expect((r.netHours, r.expectedHours, r.shortfallHours), (4.25, 10.0, 5.75));
      expect(r.punchCount, 3);
      expect(r.workingHours, 12); // HRMS's own paired hours stay available
      expect(r.hoursLabel, '4h 15m of 10h');
    });

    test('past day, complete: Present with its figures, no flag', () {
      final r = deriveDayStatus(
        employee: tracked, day: mon, now: DateTime(2026, 12, 3), shift: standard,
        isHoliday: false, ledger: stamped('Present'),
      );
      expect(r.status, AttendanceStatus.present);
      expect(r.flag, isNull);
      expect(r.shortfallLabel, isNull);
    });

    test('fields absent on the site: rows and shift types read as before', () {
      // No custom_* keys in the JSON, as when the fields do not exist yet.
      final rules = ShiftRules.fromJson({
        'name': 'General', 'start_time': '08:00:00', 'end_time': '20:00:00',
        'late_entry_grace_period': 15, 'begin_check_in_before_shift_start_time': 120,
        'allow_check_out_after_shift_end_time': 120,
      });
      final rec = AttendanceRecord.fromJson({
        'name': 'ATT-2', 'employee': tracked.name, 'attendance_date': '2026-11-30',
        'status': 'Present', 'working_hours': 11.5, 'in_time': '2026-11-30 08:00:00',
      });
      expect(rules.isClocked, isFalse);
      expect(rules.breakOn(mon), isNull);
      expect(rec.isClocked, isFalse);
      expect((rec.netHours, rec.expectedHours, rec.missingPunch), (null, null, false));

      final today = deriveDayStatus(
        employee: tracked, day: mon, now: DateTime(2026, 11, 30, 23), shift: rules,
        isHoliday: false, punches: taps(mon, ['08:00', '12:00', '13:00']),
      );
      expect(today.status, AttendanceStatus.present); // never Missing punch
      expect(today.isClocked, isFalse);
      expect(today.hoursLabel, isNull);
      expect(today.workingHours, 0);

      final past = deriveDayStatus(
        employee: tracked, day: mon, now: DateTime(2026, 12, 3), shift: rules,
        isHoliday: false, ledger: rec,
      );
      expect(past.status, AttendanceStatus.present);
      expect(past.isClocked, isFalse);
      expect(past.workingHours, 11.5);
    });

    test('an unstamped row (old Shift Type) is not clocked even with the fields present', () {
      final rec = AttendanceRecord.fromJson({
        'name': 'ATT-3', 'employee': tracked.name, 'attendance_date': '2026-11-20',
        'status': 'Present', 'shift': 'Morning', 'custom_punch_count': 0,
        'custom_missing_punch': 0, 'custom_net_hours': 0, 'custom_expected_hours': 0,
        'custom_shortfall_hours': 0,
      });
      expect(rec.isClocked, isFalse);
    });

    test('stamped row parsing: Check, Int and Float fields', () {
      final rec = AttendanceRecord.fromJson({
        'name': 'ATT-4', 'employee': tracked.name, 'attendance_date': '2026-11-30',
        'status': 'Present', 'custom_punch_count': 3, 'custom_missing_punch': 1,
        'custom_net_hours': 4.25, 'custom_expected_hours': 10, 'custom_shortfall_hours': '5.75',
      });
      expect(rec.isClocked, isTrue);
      expect((rec.punchCount, rec.missingPunch, rec.netHours, rec.shortfallHours),
          (3, true, 4.25, 5.75));
    });

    test('counts, filters and the month strip know Missing punch', () {
      EmployeeDayStatus row(String id, AttendanceStatus st) => EmployeeDayStatus(
          employee: TrackedEmployee(name: id, employeeName: id, deviceId: '1'), status: st);
      final rows = [
        row('a', AttendanceStatus.present),
        row('b', AttendanceStatus.missingPunch),
        row('c', AttendanceStatus.absent),
      ];
      final c = AttendanceCounts.of(rows);
      expect((c.present, c.missing, c.absent, c.tracked), (2, 1, 1, 3));
      expect(filterRows(rows, statusKey: 'Missing punch').map((r) => r.employee.name), ['b']);
      expect(filterRows(rows, statusKey: 'Present').map((r) => r.employee.name), ['a', 'b']);

      final s = buildMonthStrip(
        month: DateTime(2026, 12),
        ledger: [
          AttendanceRecord(
            name: 'M1', employee: tracked.name, employeeName: '', date: DateTime(2026, 12, 1),
            status: 'Present', shift: 'Standard', missingPunch: true, netHours: 4,
            expectedHours: 10, shortfallHours: 6,
          ),
          AttendanceRecord(
            name: 'M2', employee: tracked.name, employeeName: '', date: DateTime(2026, 12, 2),
            status: 'Present', shift: 'Standard', netHours: 10.75, expectedHours: 10,
            shortfallHours: 0,
          ),
        ],
        holidays: const {},
        today: null,
        now: DateTime(2026, 12, 3, 9),
        shift: standard,
        employee: tracked,
        catalog: {'Standard': standard},
      );
      expect(s.days[0], AttendanceStatus.missingPunch);
      expect(s.days[1], AttendanceStatus.present);
      expect(s.tallyLabel, 'December · 1 present · 0 late · 0 absent · 1 missing punch');
    });

    test('formatHours', () {
      expect(formatHours(10.75), '10h 45m');
      expect(formatHours(8), '8h');
      expect(formatHours(0.42), '25m');
      expect(formatHours(0), '0h');
      expect(formatHours(10.42), '10h 25m');
    });

    test('the whole catalogue: every default_shift once; company for holidays', () {
      const emps = [
        TrackedEmployee(name: '1', employeeName: 'a', defaultShift: 'Standard'),
        TrackedEmployee(name: '2', employeeName: 'b', defaultShift: 'Late Start', company: 'Multimax'),
        TrackedEmployee(name: '3', employeeName: 'c', defaultShift: 'Standard'),
        TrackedEmployee(name: '4', employeeName: 'd', defaultShift: ' '),
        TrackedEmployee(name: '5', employeeName: 'e', defaultShift: 'Early Finish'),
      ];
      expect(defaultShiftNames(emps), {'Standard', 'Late Start', 'Early Finish'});
      expect(companyOf(emps), 'Multimax');
      expect(companyOf(const []), '');
      // With the whole catalogue loaded, each person gets their own pattern.
      final cat = {'Standard': standard, 'Late Start': lateStart, 'Early Finish': earlyFinish};
      expect(
          resolveShifts(employee: emps[1], day: mon, assignments: const [], catalog: cat).single,
          same(lateStart));
    });
  });
}
