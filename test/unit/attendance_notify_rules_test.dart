import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/services/attendance_notify_rules.dart';

const morning = ShiftRules(
    name: 'Morning', start: Duration(hours: 8), end: Duration(hours: 12, minutes: 15),
    graceMinutes: 15, checkInBeforeMinutes: 120, checkOutAfterMinutes: 45);
const afternoon = ShiftRules(
    name: 'Afternoon', start: Duration(hours: 13, minutes: 30), end: Duration(hours: 20),
    graceMinutes: 15, checkInBeforeMinutes: 30, checkOutAfterMinutes: 120);
const morningFri = ShiftRules(
    name: 'Morning (Fri)', start: Duration(hours: 8), end: Duration(hours: 12),
    graceMinutes: 15, checkInBeforeMinutes: 120, checkOutAfterMinutes: 75);
const afternoonFri = ShiftRules(
    name: 'Afternoon (Fri)', start: Duration(hours: 14, minutes: 30), end: Duration(hours: 20),
    graceMinutes: 15, checkInBeforeMinutes: 75, checkOutAfterMinutes: 120);
const catalog = {
  'Morning': morning, 'Afternoon': afternoon,
  'Morning (Fri)': morningFri, 'Afternoon (Fri)': afternoonFri,
};

final sat = DateTime(2026, 9, 12);
DateTime at(DateTime d, int h, int m) => DateTime(d.year, d.month, d.day, h, m);
EmployeeCheckin punch(DateTime t) => EmployeeCheckin(name: 'p${t.hour}${t.minute}', employee: 'E1', time: t);
AttendanceRecord row(DateTime d, String shift,
        {String status = 'Present', bool late = false, bool early = false,
        DateTime? inTime, DateTime? outTime}) =>
    AttendanceRecord(
        name: 'a-$shift-${d.day}', employee: 'E1', employeeName: 'E', date: d, status: status,
        lateEntry: late, earlyExit: early, shift: shift, inTime: inTime, outTime: outTime);

const both = [morning, afternoon];
const morningDone = {'Morning|headsUp', 'Morning|missedIn', 'Morning|checkOut'};

void main() {
  group('reminderShifts', () {
    test('from own assignments covering the day, sorted by start', () {
      final a = [
        ShiftAssignmentRow(employee: 'E1', shiftType: 'Afternoon', startDate: sat),
        ShiftAssignmentRow(employee: 'E1', shiftType: 'Morning', startDate: sat),
        ShiftAssignmentRow(employee: 'E2', shiftType: 'Morning', startDate: sat),
      ];
      expect(reminderShifts(employee: 'E1', day: sat, assignments: a, ledger: const [], catalog: catalog)
          .map((s) => s.name), ['Morning', 'Afternoon']);
    });
    test('from own Attendance rows when no assignment covers the day', () {
      expect(reminderShifts(employee: 'E1', day: sat, assignments: const [],
          ledger: [row(sat, 'Afternoon')], catalog: catalog).map((s) => s.name), ['Afternoon']);
    });
    test('never the fallback: no names, blank names or unknown Shift Types give no shifts', () {
      expect(reminderShifts(employee: 'E1', day: sat, assignments: const [], ledger: const [], catalog: catalog), isEmpty);
      expect(reminderShifts(employee: 'E1', day: sat, assignments: const [],
          ledger: [row(sat, '', status: 'On Leave')], catalog: catalog), isEmpty);
      expect(reminderShifts(employee: 'E1', day: sat,
          assignments: [ShiftAssignmentRow(employee: 'E1', shiftType: 'Night', startDate: sat)],
          ledger: const [], catalog: catalog), isEmpty);
    });
  });

  group('decideReminders', () {
    ReminderOutcome run(DateTime now,
            {List<EmployeeCheckin> punches = const [], List<AttendanceRecord> ledger = const [],
            bool holiday = false, bool onLeave = false, bool syncing = true,
            Set<String> handled = const {}, Set<String> posted = const {}, List<ShiftRules> shifts = both}) =>
        decideReminders(
          now: now,
          facts: EmployeeDayFacts(shifts: shifts, punches: punches, ledger: ledger,
              holiday: holiday, onLeave: onLeave, syncing: syncing),
          handled: handled,
          posted: posted,
        );

    test('no shifts: nothing', () {
      final o = run(at(sat, 8, 15), shifts: const []);
      expect(o.post, isEmpty);
      expect(o.handled, isEmpty);
    });

    test('heads-up at 08:05 with no punch', () {
      final o = run(at(sat, 8, 5));
      expect(o.post.single.id, 3000);
      expect(o.post.single.title, 'Check in for the Morning shift');
      expect(o.post.single.body, 'Punch before 08:15 to be on time.');
      expect(o.post.single.terminal, isFalse);
      expect(o.handled, {'Morning|headsUp'});
      expect(o.posted, {'Morning|headsUp'});
    });

    test('heads-up is not needed once punched', () {
      final o = run(at(sat, 8, 5), punches: [punch(at(sat, 7, 50))]);
      expect(o.post, isEmpty);
      expect(o.handled, {'Morning|headsUp'});
    });

    test('missed check-in at the cut-off; the late heads-up is dropped', () {
      final o = run(at(sat, 8, 15));
      expect(o.post.single.title, 'No check-in for the Morning shift');
      expect(o.post.single.body, 'Nothing recorded since 08:00. Punch now; this shift will show late.');
      expect(o.handled, {'Morning|headsUp', 'Morning|missedIn'});
      expect(o.posted, {'Morning|missedIn'});
    });

    test('terminal not syncing: held back and retried later, never marked handled', () {
      final o = run(at(sat, 8, 15), syncing: false);
      expect(o.post, isEmpty);
      expect(o.handled, {'Morning|headsUp'}); // dropped: its cut-off passed
      expect(o.handled.contains('Morning|missedIn'), isFalse);
    });

    test('a late run catches up once and never repeats', () {
      final first = run(at(sat, 10, 0));
      expect(first.post.map((m) => m.title), ['No check-in for the Morning shift']);
      final second = run(at(sat, 10, 30), handled: first.handled, posted: first.posted);
      expect(second.post, isEmpty);
    });

    test('missed check-in is dropped after the shift ends', () {
      final o = run(at(sat, 12, 20));
      expect(o.post, isEmpty);
      expect(o.handled, containsAll(['Morning|headsUp', 'Morning|missedIn']));
    });

    test('check-out 10 min after the shift ends, only without an OUT', () {
      final o = run(at(sat, 12, 25), punches: [punch(at(sat, 7, 58))]);
      expect(o.post.single.id, 3000);
      expect(o.post.single.title, 'Check out of the Morning shift');
      expect(o.post.single.body, 'In at 07:58, no check-out yet. Punch before 13:00.');
      final out = run(at(sat, 12, 25), punches: [punch(at(sat, 7, 58)), punch(at(sat, 12, 16))]);
      expect(out.post, isEmpty);
    });

    test('check-out is dropped once the window has closed', () {
      final o = run(at(sat, 13, 5), punches: [punch(at(sat, 7, 58))], handled: {'Morning|headsUp', 'Morning|missedIn'});
      expect(o.post.where((m) => m.id == 3000), isEmpty);
      expect(o.handled, contains('Morning|checkOut'));
    });

    test('the Afternoon shift uses id 3001 and its own times', () {
      final o = run(at(sat, 13, 45),
          punches: [punch(at(sat, 7, 58)), punch(at(sat, 12, 16))], handled: morningDone);
      expect(o.post.single.id, 3001);
      expect(o.post.single.title, 'No check-in for the Afternoon shift');
      expect(o.post.single.body, 'Nothing recorded since 13:30. Punch now; this shift will show late.');
    });

    test('holiday, approved leave or an On Leave row: nothing, and the moments are handled', () {
      for (final o in [
        run(at(sat, 8, 15), holiday: true),
        run(at(sat, 8, 15), onLeave: true),
        run(at(sat, 8, 15), ledger: [row(sat, '', status: 'On Leave')]),
      ]) {
        expect(o.post, isEmpty);
        expect(o.handled, {'Morning|headsUp', 'Morning|missedIn'});
      }
    });

    test('a stale heads-up is cancelled once the person has punched', () {
      final o = run(at(sat, 8, 15), punches: [punch(at(sat, 8, 10))],
          handled: {'Morning|headsUp'}, posted: {'Morning|headsUp'});
      expect(o.post, isEmpty);
      expect(o.cancel, [3000]);
    });
  });

  group('decideRecap', () {
    final now = at(sat, 7, 30);
    final fri = DateTime(2026, 9, 11);
    final thu = DateTime(2026, 9, 10);

    test("yesterday's problems, in shift order, with late minutes", () {
      final o = decideRecap(now: now, catalog: catalog, rows: [
        row(fri, 'Afternoon (Fri)', inTime: at(fri, 14, 20)),
        row(fri, 'Morning (Fri)', late: true, inTime: at(fri, 8, 27), outTime: at(fri, 12, 2)),
      ]);
      expect(o.recapped, '2026-09-11');
      expect(o.message!.id, 3010);
      expect(o.message!.title, "Yesterday's attendance");
      expect(o.message!.body, 'Morning: late 12 min · Afternoon: no check-out.');
    });

    test('a clean day is recapped silently', () {
      final o = decideRecap(now: now, catalog: catalog,
          rows: [row(fri, 'Morning (Fri)', inTime: at(fri, 7, 58), outTime: at(fri, 12, 1))]);
      expect(o.recapped, '2026-09-11');
      expect(o.message, isNull);
    });

    test('not yesterday: the title names the day; leave is never a problem', () {
      final o = decideRecap(now: now, catalog: catalog, rows: [
        row(thu, 'Morning', status: 'Absent'),
        row(thu, '', status: 'On Leave'),
      ]);
      expect(o.recapped, '2026-09-10');
      expect(o.message!.title, 'Attendance on Thu 10 Sep');
      expect(o.message!.body, 'Morning: absent.');
    });

    test('already recapped, or older than 3 days: nothing', () {
      expect(decideRecap(now: now, catalog: catalog, lastRecapped: '2026-09-11',
          rows: [row(thu, 'Morning', status: 'Absent')]).recapped, isNull);
      final old = decideRecap(now: now, catalog: catalog,
          rows: [row(DateTime(2026, 9, 8), 'Morning', status: 'Absent')]);
      expect(old.recapped, isNull);
      expect(old.message, isNull);
    });
  });

  group('decideTerminal', () {
    SyncStatus s(DateTime seen, DateTime run) =>
        SyncStatus(terminalOnline: true, terminalLastSeen: seen, agentLastRun: run);

    test('first run while syncing: nothing', () {
      final o = decideTerminal(now: at(sat, 9, 30), status: s(at(sat, 9, 20), at(sat, 9, 25)));
      expect(o.quiet, isFalse);
      expect(o.message, isNull);
    });
    test('goes quiet: alert with the older heartbeat time', () {
      final o = decideTerminal(now: at(sat, 10, 0), status: s(at(sat, 9, 15), at(sat, 9, 12)), wasQuiet: false);
      expect(o.quiet, isTrue);
      expect(o.message!.id, 3020);
      expect(o.message!.terminal, isTrue);
      expect(o.message!.title, 'Attendance terminal quiet');
      expect(o.message!.body, 'No sync since 09:12. Check-ins may not be arriving; staff reminders are paused.');
    });
    test('recovers: back alert', () {
      final o = decideTerminal(now: at(sat, 9, 47), status: s(at(sat, 9, 46), at(sat, 9, 46)), wasQuiet: true);
      expect(o.quiet, isFalse);
      expect(o.message!.title, 'Attendance terminal back');
      expect(o.message!.body, 'Syncing again since 09:47.');
    });
    test('no change: nothing', () {
      expect(decideTerminal(now: at(sat, 10, 30), status: null, wasQuiet: true).message, isNull);
    });
    test('unreadable status counts as quiet', () {
      final o = decideTerminal(now: at(sat, 10, 0), status: null, wasQuiet: false);
      expect(o.quiet, isTrue);
      expect(o.message!.body,
          "The sync status can't be read. Check-ins may not be arriving; staff reminders are paused.");
    });
  });
}
