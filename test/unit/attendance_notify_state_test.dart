import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/attendance_notify_state.dart';

void main() {
  test('no stored state: fresh for this user and day', () {
    final s = AttendanceNotifyState.fromMap(null, user: 'a', today: '2026-09-12');
    expect(s.user, 'a');
    expect(s.day, '2026-09-12');
    expect(s.handled, isEmpty);
    expect(s.posted, isEmpty);
    expect(s.terminalQuiet, isNull);
    expect(s.lastRecapped, isNull);
  });

  test("another user's state is discarded", () {
    final s = AttendanceNotifyState.fromMap({
      'user': 'b', 'day': '2026-09-12', 'handled': ['Morning|headsUp'],
      'lastRecapped': '2026-09-11', 'terminalQuiet': true,
    }, user: 'a', today: '2026-09-12');
    expect(s.handled, isEmpty);
    expect(s.lastRecapped, isNull);
    expect(s.terminalQuiet, isNull);
  });

  test('a new day drops handled/posted but keeps recap, terminal and auth state', () {
    final s = AttendanceNotifyState.fromMap({
      'user': 'a', 'day': '2026-09-11',
      'handled': ['Morning|headsUp'], 'posted': ['Morning|headsUp'],
      'lastRecapped': '2026-09-10', 'recapRunDay': '2026-09-11',
      'terminalQuiet': true, 'lastAuthNotice': '2026-09-11',
    }, user: 'a', today: '2026-09-12');
    expect(s.day, '2026-09-12');
    expect(s.handled, isEmpty);
    expect(s.posted, isEmpty);
    expect(s.lastRecapped, '2026-09-10');
    expect(s.recapRunDay, '2026-09-11');
    expect(s.terminalQuiet, isTrue);
    expect(s.lastAuthNotice, '2026-09-11');
  });

  test('round-trips through toMap on the same day', () {
    final s = const AttendanceNotifyState(user: 'a', day: '2026-09-12')
        .copyWith(handled: {'Morning|missedIn'}, posted: {'Morning|missedIn'}, terminalQuiet: false);
    final back = AttendanceNotifyState.fromMap(s.toMap(), user: 'a', today: '2026-09-12');
    expect(back.handled, {'Morning|missedIn'});
    expect(back.posted, {'Morning|missedIn'});
    expect(back.terminalQuiet, isFalse);
  });

  test('malformed stored values degrade instead of throwing', () {
    final s = AttendanceNotifyState.fromMap({
      'user': 'a', 'day': '2026-09-12', 'handled': 'not-a-list', 'posted': 7,
      'lastRecapped': 3, 'recapRunDay': false, 'terminalQuiet': 'yes', 'lastAuthNotice': [],
    }, user: 'a', today: '2026-09-12');
    expect(s.handled, isEmpty);
    expect(s.posted, isEmpty);
    expect(s.lastRecapped, isNull);
    expect(s.recapRunDay, isNull);
    expect(s.terminalQuiet, isNull);
    expect(s.lastAuthNotice, isNull);
  });
}
