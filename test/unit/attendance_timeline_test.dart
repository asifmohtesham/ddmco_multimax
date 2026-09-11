import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/services/attendance_timeline.dart';

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

final sat = DateTime(2026, 9, 12);
final fri = DateTime(2026, 9, 18);
DateTime at(DateTime d, int h, int m) => DateTime(d.year, d.month, d.day, h, m);

void main() {
  group('shiftMoments', () {
    test('Saturday: heads-up, missed check-in and check-out per shift, in time order', () {
      final m = shiftMoments(const [afternoon, morning], sat);
      expect([for (final x in m) (x.shift.name, x.kind, x.at)], [
        ('Morning', ReminderKind.headsUp, at(sat, 8, 5)),
        ('Morning', ReminderKind.missedIn, at(sat, 8, 15)),
        ('Morning', ReminderKind.checkOut, at(sat, 12, 25)),
        ('Afternoon', ReminderKind.headsUp, at(sat, 13, 35)),
        ('Afternoon', ReminderKind.missedIn, at(sat, 13, 45)),
        ('Afternoon', ReminderKind.checkOut, at(sat, 20, 10)),
      ]);
      expect(m.first.shiftIndex, 0);
      expect(m.last.shiftIndex, 1);
      expect(m.first.key, 'Morning|headsUp');
    });

    test('Friday uses the Friday shifts', () {
      final m = shiftMoments(const [morningFri, afternoonFri], fri);
      expect(m[2].at, at(fri, 12, 10)); // Morning (Fri) check-out
      expect(m[3].at, at(fri, 14, 35)); // Afternoon (Fri) heads-up
      expect(m[4].at, at(fri, 14, 45)); // Afternoon (Fri) cut-off
    });

    test('no shifts: no moments', () {
      expect(shiftMoments(const [], sat), isEmpty);
    });
  });

  group('nextAttendanceWake', () {
    final moments = shiftMoments(const [morning, afternoon], sat);
    DateTime next(DateTime now, {bool working = true, bool recap = true, bool watch = false,
            List<ShiftMoment>? ms}) =>
        nextAttendanceWake(
            now: now, moments: ms ?? moments, workingDay: working, recap: recap, terminalWatch: watch);

    test('recap at 07:30 comes before the 08:05 heads-up', () {
      expect(next(at(sat, 7, 0)), at(sat, 7, 30));
      expect(next(at(sat, 7, 0), recap: false), at(sat, 8, 5));
    });
    test('between shifts: the Afternoon heads-up', () {
      expect(next(at(sat, 12, 30)), at(sat, 13, 35));
    });
    test('after the last moment: planning run at 05:55 tomorrow', () {
      expect(next(at(sat, 20, 15)), DateTime(2026, 9, 13, 5, 55));
    });
    test('System Manager watch every 30 min until 22:00', () {
      expect(next(at(sat, 20, 15), watch: true), at(sat, 20, 30));
      expect(next(at(sat, 21, 45), watch: true), at(sat, 22, 0));
      expect(next(at(sat, 22, 5), watch: true), DateTime(2026, 9, 13, 5, 55));
      expect(next(at(sat, 6, 10), watch: true, ms: const [], recap: false), at(sat, 6, 30));
    });
    test('holiday: no moments, no watch, planning run tomorrow', () {
      expect(next(at(sat, 10, 0), working: false, watch: true, ms: const []),
          DateTime(2026, 9, 13, 5, 55));
    });
    test('before 05:55 the planning run is today', () {
      expect(planningRunAfter(at(sat, 5, 0)), at(sat, 5, 55));
      expect(planningRunAfter(at(sat, 5, 55)), DateTime(2026, 9, 13, 5, 55));
    });
    test('watch hours are 06:00 to 22:00 inclusive', () {
      expect(inWatchHours(at(sat, 5, 59)), isFalse);
      expect(inWatchHours(at(sat, 6, 0)), isTrue);
      expect(inWatchHours(at(sat, 22, 0)), isTrue);
      expect(inWatchHours(at(sat, 22, 1)), isFalse);
    });
  });

  group('isSyncing (spec #0 §5)', () {
    final now = at(sat, 10, 0);
    SyncStatus s({bool online = true, DateTime? seen, DateTime? run}) =>
        SyncStatus(terminalOnline: online, terminalLastSeen: seen, agentLastRun: run);

    test('fresh agent and terminal within 20 min: syncing', () {
      expect(isSyncing(s(seen: at(sat, 9, 40), run: at(sat, 9, 40)), now), isTrue);
    });
    test('21 minutes old: not syncing', () {
      expect(isSyncing(s(seen: at(sat, 9, 39), run: at(sat, 9, 50)), now), isFalse);
      expect(isSyncing(s(seen: at(sat, 9, 50), run: at(sat, 9, 39)), now), isFalse);
    });
    test('terminal offline, missing times or unreadable: not syncing', () {
      expect(isSyncing(s(online: false, seen: at(sat, 9, 59), run: at(sat, 9, 59)), now), isFalse);
      expect(isSyncing(s(run: at(sat, 9, 59)), now), isFalse);
      expect(isSyncing(null, now), isFalse);
    });
    test('quietSince is the older of the two times', () {
      expect(quietSince(s(seen: at(sat, 9, 15), run: at(sat, 9, 12))), at(sat, 9, 12));
      expect(quietSince(s(seen: at(sat, 9, 15))), at(sat, 9, 15));
      expect(quietSince(null), isNull);
    });
    test('SyncStatus parses the Single DocType', () {
      final p = SyncStatus.fromJson({
        'terminal_online': 1,
        'terminal_last_seen': '2026-09-12 09:15:00',
        'agent_last_run': '2026-09-12 09:16:30',
      });
      expect(p.terminalOnline, isTrue);
      expect(p.terminalLastSeen, DateTime(2026, 9, 12, 9, 15));
      expect(p.agentLastRun, DateTime(2026, 9, 12, 9, 16, 30));
      expect(SyncStatus.fromJson({'terminal_online': 0}).terminalOnline, isFalse);
    });
  });
}
