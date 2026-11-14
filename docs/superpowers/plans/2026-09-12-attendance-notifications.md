# Attendance Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android background notifications for attendance: per-shift check-in heads-up and missed check-in, a check-out reminder, a problem-only morning recap for employees, and a quiet/back terminal alert for System Managers.

**Architecture:** A second WorkManager one-off chain (`attendance-notification`) shares the app's single dispatcher with the documents digest. Each run fetches the user's own data over the persisted session cookie (isolate-safe service), decides with pure functions (timeline, rules), posts on two new channels, saves worker-only state in a separate GetStorage container, and schedules the next wake.

**Tech Stack:** Flutter, GetX 4.7.2, workmanager ^0.9.0+3, flutter_local_notifications ^22.0.1, get_storage, Dio + PersistCookieJar, Frappe/ERPNext 15 + HRMS 15 REST.

**Spec:** `docs/superpowers/specs/2026-09-12-attendance-notifications-design.md`

## Global Constraints

- Android only. iOS behaviour and the documents digest (manager-only, `digest-notification` / `digestTask`) must be unchanged.
- The background isolate must NEVER write the main GetStorage box. Worker state lives only in the container `attendance_notify`.
- Employee reminders fire only for shifts from the employee's own Shift Assignment or Attendance row — never for `General` / `ShiftRules.fallback` — and only when the heartbeat says syncing: `now − agent_last_run ≤ 20 min` AND `terminal_online` AND `now − terminal_last_seen ≤ 20 min`.
- Times: heads-up = cut-off − 10 min; missed check-in = cut-off; check-out = shift end + 10 min; recap 07:30; terminal watch every 30 min 06:00–22:00 on working days; planning run 05:55.
- Notification ids: `3000 + shift index`, `3010` recap, `3020` terminal, `3030` session expired. Channels `attendance_reminders` ("Attendance reminders") and `attendance_terminal` ("Attendance terminal"), both Importance.high.
- Copy never blames the person ("No check-in recorded", never "you forgot"). Exact strings are in the tasks and must be used verbatim.
- Preferences (main box, per user `key::user`): `notif_att_enabled` (absent ⇒ on), `notif_att_terminal` (absent ⇒ on), `notif_att_prompted`.
- Hand-edit only; NEVER `dart format` whole files. Never `git stash`. Never run `flutter analyze` and `flutter test` concurrently. Colours only via `context.scheme` / `AppColors`; new text maxLines + ellipsis where it can overflow.
- Verify `git branch --show-current` is `claude/attendance-notifications` before every commit; commit trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Whole-repo `flutter analyze` has ~397 pre-existing issues; files you touch must have none new.
- Release: MINOR **2.18.0+61**, only with the user's explicit approval (Task 7).

## File Structure

| File | Responsibility |
|---|---|
| `lib/app/data/services/attendance_notify_state.dart` (new) | Worker-only state model + box names |
| `lib/app/data/services/storage_service.dart` | Attendance notification prefs |
| `lib/app/data/models/attendance_models.dart` | `SyncStatus` (heartbeat document) |
| `lib/app/data/services/attendance_timeline.dart` (new) | Pure: moments, next wake, heartbeat rule |
| `lib/app/data/services/attendance_notify_rules.dart` (new) | Pure: reminder / recap / terminal decisions + wording |
| `lib/app/data/services/attendance_notify_service.dart` (new) | Isolate-safe reads over the session cookie |
| `lib/app/data/services/attendance_notify_scheduler.dart` (new) | Arms / re-arms / cancels the WorkManager chain |
| `lib/app/data/services/attendance_notify_worker.dart` (new) | Background run: fetch → decide → post → save → next |
| `lib/app/data/services/digest_worker.dart` | Shared dispatcher routes by task name |
| `lib/main.dart`, `lib/app/modules/auth/authentication_controller.dart` | Rearm at start/login, cancel at logout |
| `lib/app/modules/user_area/user_area_screen.dart` | Notifications entry gate |
| `lib/app/modules/notification_settings/notification_settings_{controller,screen}.dart` | Attendance section, terminal switch, blocked hint |
| `lib/app/modules/home/home_controller.dart` | One-time permission prompt |

Run everything from the worktree root `C:\Users\asifm\StudioProjects\ddmco_multimax\.claude\worktrees\attendance-terminal-ux-4863b9`.

---

### Task 1: Preferences and worker state

**Files:**
- Modify: `lib/app/data/services/storage_service.dart` (keys block ~l.40-46; methods after the digest block ~l.210)
- Create: `lib/app/data/services/attendance_notify_state.dart`
- Test: `test/unit/storage_attendance_prefs_test.dart`, `test/unit/attendance_notify_state_test.dart`

**Interfaces:**
- Produces: `StorageService.getAttendanceRemindersEnabled(user) → bool` (default true), `saveAttendanceRemindersEnabled(user, bool)`, `getAttendanceTerminalAlerts(user) → bool` (default true), `saveAttendanceTerminalAlerts(user, bool)`, `getAttendancePermissionPrompted(user) → bool` (default false), `saveAttendancePermissionPrompted(user)`.
- Produces: `const kAttendanceStateBox = 'attendance_notify'`, `const kAttendanceStateKey = 'state'`, `class AttendanceNotifyState { user, day, handled, posted, lastRecapped, recapRunDay, terminalQuiet, lastAuthNotice; factory fromMap(Object? raw, {required String user, required String today}); Map<String, dynamic> toMap(); copyWith(...) }`.

- [ ] **Step 1: Write the failing tests**

`test/unit/storage_attendance_prefs_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class _FakeGetStorage {
  final Map<String, dynamic> data = {};
  Future<void> write(String key, dynamic value) async => data[key] = value;
  Future<void> remove(String key) async => data.remove(key);
  T? read<T>(String key) => data[key] as T?;
  bool hasData(String key) => data.containsKey(key);
}

void main() {
  late _FakeGetStorage box;
  late StorageService storage;

  setUp(() {
    box = _FakeGetStorage();
    storage = StorageService.withStorage(box as dynamic);
  });

  test('attendance reminders and terminal alerts default on, prompt not yet shown', () {
    expect(storage.getAttendanceRemindersEnabled('u'), isTrue);
    expect(storage.getAttendanceTerminalAlerts('u'), isTrue);
    expect(storage.getAttendancePermissionPrompted('u'), isFalse);
  });

  test('saved per user under key::user', () async {
    await storage.saveAttendanceRemindersEnabled('u', false);
    await storage.saveAttendanceTerminalAlerts('u', false);
    await storage.saveAttendancePermissionPrompted('u');
    expect(box.data['notif_att_enabled::u'], isFalse);
    expect(box.data['notif_att_terminal::u'], isFalse);
    expect(box.data['notif_att_prompted::u'], isTrue);
    expect(storage.getAttendanceRemindersEnabled('u'), isFalse);
    expect(storage.getAttendanceRemindersEnabled('other'), isTrue);
    expect(storage.getAttendancePermissionPrompted('u'), isTrue);
  });
}
```

`test/unit/attendance_notify_state_test.dart`:

```dart
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
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/storage_attendance_prefs_test.dart test/unit/attendance_notify_state_test.dart`
Expected: FAIL — methods / file not defined.

- [ ] **Step 3: Implement**

In `storage_service.dart`, after the digest keys:

```dart
  // Attendance notification preferences (#2b), per user. Absent = on.
  static const String _attEnabledKey = 'notif_att_enabled';
  static const String _attTerminalKey = 'notif_att_terminal';
  static const String _attPromptedKey = 'notif_att_prompted';
```

After `getDigestAlarmStyle`:

```dart
  // --- Attendance notification preferences ---
  Future<void> saveAttendanceRemindersEnabled(String user, bool value) async =>
      _box.write('$_attEnabledKey::$user', value);

  /// Attendance reminders are on by default for linked employees.
  bool getAttendanceRemindersEnabled(String user) =>
      _box.read<bool>('$_attEnabledKey::$user') ?? true;

  Future<void> saveAttendanceTerminalAlerts(String user, bool value) async =>
      _box.write('$_attTerminalKey::$user', value);

  /// Terminal quiet/back alerts are on by default for System Managers.
  bool getAttendanceTerminalAlerts(String user) =>
      _box.read<bool>('$_attTerminalKey::$user') ?? true;

  /// Written by the main isolate once the Dashboard has asked for
  /// notification permission, so the prompt never repeats.
  Future<void> saveAttendancePermissionPrompted(String user) async =>
      _box.write('$_attPromptedKey::$user', true);

  bool getAttendancePermissionPrompted(String user) =>
      _box.read<bool>('$_attPromptedKey::$user') ?? false;
```

Create `lib/app/data/services/attendance_notify_state.dart`:

```dart
/// What the attendance worker remembers between runs. Kept in its own
/// GetStorage container ([kAttendanceStateBox]) that ONLY the background
/// worker writes — the main isolate never touches it, so there is no
/// cross-isolate last-writer-wins on the main box (see digest_worker.dart).
library;

const String kAttendanceStateBox = 'attendance_notify';
const String kAttendanceStateKey = 'state';

class AttendanceNotifyState {
  final String user;

  /// yyyy-MM-dd the [handled] / [posted] keys belong to.
  final String day;

  /// `<shift>|<kind>` moments already decided today (posted or not needed).
  final Set<String> handled;

  /// `<shift>|<kind>` moments actually posted today.
  final Set<String> posted;

  /// Last day a recap decision covered (yyyy-MM-dd).
  final String? lastRecapped;

  /// Day the recap was last evaluated (it runs once per day).
  final String? recapRunDay;

  /// Terminal state at the last watch; null before the first watch.
  final bool? terminalQuiet;

  /// Day the "session expired" notice was last posted.
  final String? lastAuthNotice;

  const AttendanceNotifyState({
    required this.user,
    required this.day,
    this.handled = const {},
    this.posted = const {},
    this.lastRecapped,
    this.recapRunDay,
    this.terminalQuiet,
    this.lastAuthNotice,
  });

  /// Reads [raw] for [user] on [today]: another user's state is discarded; a
  /// previous day's handled/posted keys are dropped and the rest kept.
  factory AttendanceNotifyState.fromMap(Object? raw,
      {required String user, required String today}) {
    if (raw is! Map || raw['user'] != user) {
      return AttendanceNotifyState(user: user, day: today);
    }
    Set<String> set(Object? v) => v is List ? v.map((e) => '$e').toSet() : <String>{};
    final sameDay = raw['day'] == today;
    return AttendanceNotifyState(
      user: user,
      day: today,
      handled: sameDay ? set(raw['handled']) : const {},
      posted: sameDay ? set(raw['posted']) : const {},
      lastRecapped: raw['lastRecapped'] as String?,
      recapRunDay: raw['recapRunDay'] as String?,
      terminalQuiet: raw['terminalQuiet'] as bool?,
      lastAuthNotice: raw['lastAuthNotice'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'user': user,
        'day': day,
        'handled': handled.toList()..sort(),
        'posted': posted.toList()..sort(),
        'lastRecapped': lastRecapped,
        'recapRunDay': recapRunDay,
        'terminalQuiet': terminalQuiet,
        'lastAuthNotice': lastAuthNotice,
      };

  AttendanceNotifyState copyWith({
    Set<String>? handled,
    Set<String>? posted,
    String? lastRecapped,
    String? recapRunDay,
    bool? terminalQuiet,
    String? lastAuthNotice,
  }) =>
      AttendanceNotifyState(
        user: user,
        day: day,
        handled: handled ?? this.handled,
        posted: posted ?? this.posted,
        lastRecapped: lastRecapped ?? this.lastRecapped,
        recapRunDay: recapRunDay ?? this.recapRunDay,
        terminalQuiet: terminalQuiet ?? this.terminalQuiet,
        lastAuthNotice: lastAuthNotice ?? this.lastAuthNotice,
      );
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/unit/storage_attendance_prefs_test.dart test/unit/attendance_notify_state_test.dart test/unit/storage_digest_prefs_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current   # claude/attendance-notifications
git add lib/app/data/services/storage_service.dart lib/app/data/services/attendance_notify_state.dart test/unit/storage_attendance_prefs_test.dart test/unit/attendance_notify_state_test.dart
git commit -m "feat(attendance): notification preferences and worker state

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Timeline and heartbeat rule

**Files:**
- Modify: `lib/app/data/models/attendance_models.dart` (append `SyncStatus`)
- Create: `lib/app/data/services/attendance_timeline.dart`
- Test: `test/unit/attendance_timeline_test.dart`

**Interfaces:**
- Consumes: `ShiftRules` (`cutoffOn`, `endOn`, `windowEndOn`, `start`), `dateOnly` from `attendance_models.dart`.
- Produces: `class SyncStatus { bool terminalOnline; DateTime? terminalLastSeen; DateTime? agentLastRun; factory fromJson }`; `enum ReminderKind { headsUp, missedIn, checkOut }`; `class ShiftMoment { kind, shiftIndex, shift, at; String get key }` (key = `'<shift name>|<kind name>'`); `List<ShiftMoment> shiftMoments(List<ShiftRules> shifts, DateTime day)`; `DateTime recapTimeOn(DateTime day)`; `bool inWatchHours(DateTime now)`; `DateTime planningRunAfter(DateTime now)`; `DateTime nextAttendanceWake({required DateTime now, required List<ShiftMoment> moments, required bool workingDay, required bool recap, required bool terminalWatch})`; `bool isSyncing(SyncStatus? s, DateTime now)`; `DateTime? quietSince(SyncStatus? s)`.

- [ ] **Step 1: Write the failing test** — `test/unit/attendance_timeline_test.dart`:

```dart
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/attendance_timeline_test.dart`
Expected: FAIL — `attendance_timeline.dart` / `SyncStatus` not defined.

- [ ] **Step 3: Implement**

Append to `lib/app/data/models/attendance_models.dart`:

```dart
/// The Single DocType `Attendance Sync Status` the BioTime agent publishes
/// (sub-project #0). Times are naive site-local (Asia/Dubai).
class SyncStatus {
  final bool terminalOnline;
  final DateTime? terminalLastSeen;
  final DateTime? agentLastRun;

  const SyncStatus({required this.terminalOnline, this.terminalLastSeen, this.agentLastRun});

  factory SyncStatus.fromJson(Map<String, dynamic> j) => SyncStatus(
        terminalOnline:
            j['terminal_online'] == true || '${j['terminal_online'] ?? 0}' == '1',
        terminalLastSeen: _parseDt(j['terminal_last_seen']),
        agentLastRun: _parseDt(j['agent_last_run']),
      );
}
```

Create `lib/app/data/services/attendance_timeline.dart`:

```dart
/// When the attendance worker wakes (spec 2026-09-12 §4.2) and the heartbeat
/// rule (spec #0 §5). Pure and GetX-free — runs in the background isolate.
library;

import 'package:multimax/app/data/models/attendance_models.dart';

enum ReminderKind { headsUp, missedIn, checkOut }

const Duration kHeadsUpLead = Duration(minutes: 10);
const Duration kCheckOutLag = Duration(minutes: 10);
const Duration kSyncFreshness = Duration(minutes: 20);
const Duration kWatchStep = Duration(minutes: 30);

/// One reminder moment of one shift on one day.
class ShiftMoment {
  final ReminderKind kind;

  /// 0 = the day's first shift, 1 = the second (notification id offset).
  final int shiftIndex;
  final ShiftRules shift;
  final DateTime at;

  const ShiftMoment(
      {required this.kind, required this.shiftIndex, required this.shift, required this.at});

  /// `<shift>|<kind>` — the handled/posted key in the worker state.
  String get key => '${shift.name}|${kind.name}';
}

/// Heads-up (cut-off − 10), missed check-in (cut-off) and check-out
/// (end + 10) for each of [shifts] on [day], in time order.
List<ShiftMoment> shiftMoments(List<ShiftRules> shifts, DateTime day) {
  final ordered = [...shifts]..sort((a, b) => a.start.compareTo(b.start));
  final out = <ShiftMoment>[];
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    final cut = s.cutoffOn(day);
    out
      ..add(ShiftMoment(kind: ReminderKind.headsUp, shiftIndex: i, shift: s, at: cut.subtract(kHeadsUpLead)))
      ..add(ShiftMoment(kind: ReminderKind.missedIn, shiftIndex: i, shift: s, at: cut))
      ..add(ShiftMoment(kind: ReminderKind.checkOut, shiftIndex: i, shift: s, at: s.endOn(day).add(kCheckOutLag)));
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}

DateTime recapTimeOn(DateTime day) => DateTime(day.year, day.month, day.day, 7, 30);

/// 06:00–22:00 inclusive: when System Managers' terminal watch runs.
bool inWatchHours(DateTime now) {
  final d = dateOnly(now);
  return !now.isBefore(DateTime(d.year, d.month, d.day, 6)) &&
      !now.isAfter(DateTime(d.year, d.month, d.day, 22));
}

/// The 05:55 planning run: today if it is still ahead, else tomorrow.
DateTime planningRunAfter(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, 5, 55);
  return now.isBefore(today) ? today : DateTime(now.year, now.month, now.day + 1, 5, 55);
}

DateTime? _nextWatchSlot(DateTime now) {
  final d = dateOnly(now);
  final end = DateTime(d.year, d.month, d.day, 22);
  for (var t = DateTime(d.year, d.month, d.day, 6); !t.isAfter(end); t = t.add(kWatchStep)) {
    if (t.isAfter(now)) return t;
  }
  return null;
}

/// The next time after [now] the worker must run: the next shift moment,
/// the 07:30 recap ([recap], working days), the next terminal watch slot
/// ([terminalWatch], working days) — else the planning run.
DateTime nextAttendanceWake({
  required DateTime now,
  required List<ShiftMoment> moments,
  required bool workingDay,
  required bool recap,
  required bool terminalWatch,
}) {
  final day = dateOnly(now);
  final watch = workingDay && terminalWatch ? _nextWatchSlot(now) : null;
  final candidates = <DateTime>[
    for (final m in moments)
      if (m.at.isAfter(now)) m.at,
    if (workingDay && recap && recapTimeOn(day).isAfter(now)) recapTimeOn(day),
    if (watch != null) watch,
  ];
  if (candidates.isEmpty) return planningRunAfter(now);
  return candidates.reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Syncing ⇔ agent and terminal both seen within 20 min and the terminal is
/// online. Anything else — including an unreadable document — is unknown.
bool isSyncing(SyncStatus? s, DateTime now) =>
    s != null &&
    s.terminalOnline &&
    s.agentLastRun != null &&
    s.terminalLastSeen != null &&
    now.difference(s.agentLastRun!) <= kSyncFreshness &&
    now.difference(s.terminalLastSeen!) <= kSyncFreshness;

/// Since when the sync looks quiet: the older of the two heartbeat times.
DateTime? quietSince(SyncStatus? s) {
  final times = [
    if (s?.agentLastRun != null) s!.agentLastRun!,
    if (s?.terminalLastSeen != null) s!.terminalLastSeen!,
  ];
  if (times.isEmpty) return null;
  return times.reduce((a, b) => a.isBefore(b) ? a : b);
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/unit/attendance_timeline_test.dart test/unit/attendance_logic_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/models/attendance_models.dart lib/app/data/services/attendance_timeline.dart test/unit/attendance_timeline_test.dart
git commit -m "feat(attendance): notification timeline and heartbeat rule

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Decision rules and wording

**Files:**
- Create: `lib/app/data/services/attendance_notify_rules.dart`
- Test: `test/unit/attendance_notify_rules_test.dart`

**Interfaces:**
- Consumes: Task 2 (`ReminderKind`, `ShiftMoment`, `shiftMoments`, `isSyncing`, `quietSince`, `SyncStatus`); released `shiftForPunch`, `deriveShiftStatus` (`lib/app/modules/hr/attendance/attendance_logic.dart`); `ShiftRules.shortName/cutoffLabel/startLabel`, `kHHmm`, `kFrappeDate`, `ShiftAssignmentRow.covers`.
- Produces: ids `kShiftReminderIdBase = 3000`, `kRecapNotificationId = 3010`, `kTerminalNotificationId = 3020`, `kSessionNotificationId = 3030`, `kAttendanceNotificationIds`; `class NotifyMessage { id, title, body, terminal }`; `kSessionExpiredMessage`; `List<ShiftRules> reminderShifts({required String employee, required DateTime day, required List<ShiftAssignmentRow> assignments, required List<AttendanceRecord> ledger, required Map<String, ShiftRules> catalog})`; `class EmployeeDayFacts`; `class ReminderOutcome { post, cancel, handled, posted }`; `ReminderOutcome decideReminders({required DateTime now, required EmployeeDayFacts facts, Set<String> handled, Set<String> posted})`; `class RecapOutcome { recapped, message }`; `RecapOutcome decideRecap({required DateTime now, required List<AttendanceRecord> rows, required Map<String, ShiftRules> catalog, String? lastRecapped})`; `class TerminalOutcome { quiet, message }`; `TerminalOutcome decideTerminal({required DateTime now, required SyncStatus? status, bool? wasQuiet})`.

- [ ] **Step 1: Write the failing test** — `test/unit/attendance_notify_rules_test.dart`:

```dart
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/attendance_notify_rules_test.dart`
Expected: FAIL — `attendance_notify_rules.dart` not found.

- [ ] **Step 3: Implement** — create `lib/app/data/services/attendance_notify_rules.dart`:

```dart
/// Pure decisions for attendance notifications (spec 2026-09-12 §5): which
/// reminder, recap or terminal alert to post, and its exact wording.
/// GetX-free — runs in the background isolate.
library;

import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/services/attendance_timeline.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

const int kShiftReminderIdBase = 3000;
const int kRecapNotificationId = 3010;
const int kTerminalNotificationId = 3020;
const int kSessionNotificationId = 3030;
const List<int> kAttendanceNotificationIds = [
  kShiftReminderIdBase,
  kShiftReminderIdBase + 1,
  kRecapNotificationId,
  kTerminalNotificationId,
  kSessionNotificationId,
];

class NotifyMessage {
  final int id;
  final String title;
  final String body;

  /// Posted on the System Manager terminal channel instead of reminders.
  final bool terminal;

  const NotifyMessage({required this.id, required this.title, required this.body, this.terminal = false});
}

const NotifyMessage kSessionExpiredMessage = NotifyMessage(
  id: kSessionNotificationId,
  title: 'Attendance reminders paused',
  body: 'Open Multimax to keep attendance reminders working.',
);

String _short(String shiftName) => shiftName.replaceFirst(RegExp(r'\s*\(.*\)$'), '');

/// The shifts that may produce reminders for [employee] on [day]: their own
/// Shift Assignments covering the day, else the shifts their own Attendance
/// rows name. Never the General / fallback shift; a name missing from
/// [catalog] is left out (no reminder at unknown times).
List<ShiftRules> reminderShifts({
  required String employee,
  required DateTime day,
  required List<ShiftAssignmentRow> assignments,
  required List<AttendanceRecord> ledger,
  required Map<String, ShiftRules> catalog,
}) {
  final names = <String>{
    for (final a in assignments)
      if (a.employee == employee && a.covers(day)) a.shiftType,
  };
  if (names.isEmpty) {
    names.addAll(ledger.map((r) => r.shift).where((n) => n.trim().isNotEmpty));
  }
  return [
    for (final n in names)
      if (catalog[n] != null) catalog[n]!,
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// Everything [decideReminders] needs about the employee's day.
class EmployeeDayFacts {
  final List<ShiftRules> shifts;
  final List<EmployeeCheckin> punches;
  final List<AttendanceRecord> ledger;
  final bool holiday;
  final bool onLeave;
  final bool syncing;

  const EmployeeDayFacts({
    required this.shifts,
    this.punches = const [],
    this.ledger = const [],
    this.holiday = false,
    this.onLeave = false,
    this.syncing = true,
  });
}

class ReminderOutcome {
  final List<NotifyMessage> post;
  final List<int> cancel;
  final Set<String> handled;
  final Set<String> posted;

  const ReminderOutcome(
      {required this.post, required this.cancel, required this.handled, required this.posted});
}

NotifyMessage? _reminder(ShiftMoment m, ShiftDayStatus st, DateTime now) {
  final s = m.shift;
  final day = dateOnly(now);
  final id = kShiftReminderIdBase + m.shiftIndex;
  final hasIn = st.inTime != null;
  switch (m.kind) {
    case ReminderKind.headsUp:
      if (hasIn || !now.isBefore(s.cutoffOn(day))) return null;
      return NotifyMessage(
          id: id,
          title: 'Check in for the ${s.shortName} shift',
          body: 'Punch before ${s.cutoffLabel} to be on time.');
    case ReminderKind.missedIn:
      if (hasIn || !now.isBefore(s.endOn(day))) return null;
      return NotifyMessage(
          id: id,
          title: 'No check-in for the ${s.shortName} shift',
          body: 'Nothing recorded since ${s.startLabel}. Punch now; this shift will show late.');
    case ReminderKind.checkOut:
      if (!hasIn || st.outTime != null || !now.isBefore(s.windowEndOn(day))) return null;
      return NotifyMessage(
          id: id,
          title: 'Check out of the ${s.shortName} shift',
          body: 'In at ${kHHmm.format(st.inTime!)}, no check-out yet. '
              'Punch before ${kHHmm.format(s.windowEndOn(day))}.');
  }
}

/// Decides today's due moments (time ≤ [now], not yet [handled]) for every
/// shift. A moment that is no longer needed (punched, too late, holiday,
/// leave) is marked handled; one held back because the terminal isn't
/// syncing stays open so a later run can still post it. A posted
/// check-in reminder is cancelled once the person has punched in, and a
/// check-out reminder once they have punched out.
ReminderOutcome decideReminders({
  required DateTime now,
  required EmployeeDayFacts facts,
  Set<String> handled = const {},
  Set<String> posted = const {},
}) {
  final day = dateOnly(now);
  final ordered = [...facts.shifts]..sort((a, b) => a.start.compareTo(b.start));
  final doneKeys = {...handled};
  final postedKeys = {...posted};
  final post = <NotifyMessage>[];
  final cancel = <int>[];
  if (ordered.isEmpty) {
    return ReminderOutcome(post: post, cancel: cancel, handled: doneKeys, posted: postedKeys);
  }

  final silenced =
      facts.holiday || facts.onLeave || facts.ledger.any((r) => r.status == 'On Leave');
  final sorted = [...facts.punches]..sort((a, b) => a.time.compareTo(b.time));
  final byShift = {for (final s in ordered) s.name: <EmployeeCheckin>[]};
  for (final p in sorted) {
    byShift[shiftForPunch(p.time, ordered, day).name]!.add(p);
  }
  AttendanceRecord? ledgerFor(String name) {
    for (final r in facts.ledger) {
      if (r.shift == name) return r;
    }
    return null;
  }

  final moments = shiftMoments(ordered, day);
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    final st = deriveShiftStatus(
        shift: s, day: day, now: now, punches: byShift[s.name]!, ledger: ledgerFor(s.name));
    final id = kShiftReminderIdBase + i;
    final postedIn = postedKeys.contains('${s.name}|${ReminderKind.headsUp.name}') ||
        postedKeys.contains('${s.name}|${ReminderKind.missedIn.name}');
    final postedOut = postedKeys.contains('${s.name}|${ReminderKind.checkOut.name}');
    if ((st.inTime != null && postedIn && !postedOut) || (st.outTime != null && postedOut)) {
      cancel.add(id);
    }

    for (final m in moments) {
      if (m.shiftIndex != i || m.at.isAfter(now) || doneKeys.contains(m.key)) continue;
      if (silenced) {
        doneKeys.add(m.key);
        continue;
      }
      final msg = _reminder(m, st, now);
      if (msg == null) {
        doneKeys.add(m.key);
        continue;
      }
      if (!facts.syncing) continue; // held back: never blame a person for the terminal
      post.add(msg);
      doneKeys.add(m.key);
      postedKeys.add(m.key);
      cancel.remove(id);
    }
  }
  return ReminderOutcome(post: post, cancel: cancel, handled: doneKeys, posted: postedKeys);
}

class RecapOutcome {
  /// The day this decision covered (yyyy-MM-dd), or null when none was found.
  final String? recapped;
  final NotifyMessage? message;

  const RecapOutcome({this.recapped, this.message});
}

String? _problem(AttendanceRecord r, Map<String, ShiftRules> catalog) {
  final label = r.shift.trim().isEmpty ? 'Day' : _short(r.shift);
  if (r.status == 'Absent') return '$label: absent';
  if (r.status != 'Present') return null; // On Leave, Half Day, Work From Home
  final issues = <String>[];
  if (r.lateEntry) {
    final s = catalog[r.shift];
    final mins = s != null && r.inTime != null ? r.inTime!.difference(s.cutoffOn(r.date)).inMinutes : 0;
    issues.add(mins > 0 ? 'late $mins min' : 'late');
  }
  if (r.earlyExit) issues.add('early exit');
  if (r.outTime == null) issues.add('no check-out');
  return issues.isEmpty ? null : '$label: ${issues.join(', ')}';
}

/// The most recent of the last 3 days after [lastRecapped] that has rows. A
/// day with an Absent, Late, Early exit or No check-out row gets a message;
/// either way that day is recapped.
RecapOutcome decideRecap({
  required DateTime now,
  required List<AttendanceRecord> rows,
  required Map<String, ShiftRules> catalog,
  String? lastRecapped,
}) {
  final today = dateOnly(now);
  for (var back = 1; back <= 3; back++) {
    final d = DateTime(today.year, today.month, today.day - back);
    final key = kFrappeDate.format(d);
    if (lastRecapped != null && key.compareTo(lastRecapped) <= 0) break;
    final dayRows = rows.where((r) => kFrappeDate.format(r.date) == key).toList();
    if (dayRows.isEmpty) continue;
    Duration startOf(AttendanceRecord r) => catalog[r.shift]?.start ?? const Duration(hours: 24);
    dayRows.sort((a, b) => startOf(a).compareTo(startOf(b)));
    final parts = <String>[
      for (final r in dayRows)
        if (_problem(r, catalog) != null) _problem(r, catalog)!,
    ];
    if (parts.isEmpty) return RecapOutcome(recapped: key);
    final title =
        back == 1 ? "Yesterday's attendance" : 'Attendance on ${DateFormat('EEE d MMM').format(d)}';
    return RecapOutcome(
      recapped: key,
      message: NotifyMessage(id: kRecapNotificationId, title: title, body: '${parts.join(' · ')}.'),
    );
  }
  return const RecapOutcome();
}

class TerminalOutcome {
  final bool quiet;
  final NotifyMessage? message;

  const TerminalOutcome({required this.quiet, this.message});
}

/// Alerts System Managers only when the sync state changes. The first watch
/// of a session ([wasQuiet] null) alerts only if the sync is quiet.
TerminalOutcome decideTerminal({required DateTime now, required SyncStatus? status, bool? wasQuiet}) {
  final quiet = !isSyncing(status, now);
  if (quiet == wasQuiet) return TerminalOutcome(quiet: quiet);
  if (!quiet) {
    return TerminalOutcome(
      quiet: false,
      message: wasQuiet == null
          ? null
          : NotifyMessage(
              id: kTerminalNotificationId,
              title: 'Attendance terminal back',
              body: 'Syncing again since ${kHHmm.format(now)}.',
              terminal: true),
    );
  }
  final since = quietSince(status);
  return TerminalOutcome(
    quiet: true,
    message: NotifyMessage(
      id: kTerminalNotificationId,
      title: 'Attendance terminal quiet',
      body: since == null
          ? "The sync status can't be read. Check-ins may not be arriving; staff reminders are paused."
          : 'No sync since ${kHHmm.format(since)}. Check-ins may not be arriving; staff reminders are paused.',
      terminal: true,
    ),
  );
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/unit/attendance_notify_rules_test.dart test/unit/attendance_timeline_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/attendance_notify_rules.dart test/unit/attendance_notify_rules_test.dart
git commit -m "feat(attendance): notification rules and wording

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Isolate-safe data service

**Files:**
- Create: `lib/app/data/services/attendance_notify_service.dart`
- Test: `test/unit/attendance_notify_service_test.dart`

**Interfaces:**
- Consumes: `ShiftAssignmentRow.fromJson`, `ShiftRules.fromJson`, `EmployeeCheckin.fromJson`, `AttendanceRecord.fromJson`, `SyncStatus.fromJson`, `kFrappeDate`, `kFrappeDateTime`, `dateOnly`.
- Produces: `class AttendanceNotifyData { authExpired, tracked, assignments, catalog, punches, ledger (day−3..day), holiday, onLeave, sync; static const expired; List<AttendanceRecord> ledgerOn(DateTime day) }`; `class AttendanceNotifyService { AttendanceNotifyService({required String baseUrl, required String cookieDir}); Future<Response> callGet(String path, Map<String, dynamic> query); Future<AttendanceNotifyData?> fetch({required String employee, required DateTime day}) }` — `fetch` returns `expired` on Guest/401/403 at the session probe, `null` on any other failure of a required read; Leave Application, holiday and heartbeat reads are tolerant (false / false / null).

Endpoints (same shapes as `ApiProvider.getDocumentList`, full `[doctype, field, op, value]` tuples):
- `/api/method/frappe.auth.get_logged_user`
- `/api/resource/Employee/<employee>` → `attendance_device_id` (403/404 ⇒ not tracked)
- `/api/resource/Shift Assignment` — employee, docstatus 1, status Active, `start_date <= day`; `or_filters` `end_date >= day` / `end_date is not set`
- `/api/resource/Attendance` — employee, docstatus 1, `attendance_date between [day−3, day]`
- `/api/resource/Shift Type` — `name in` the assignment + ledger shift names (skipped when none)
- `/api/resource/Employee Checkin` — employee, `time between [day 00:00:00, day 23:59:59]`
- `/api/resource/Leave Application` — employee, status Approved, docstatus 1, `from_date <= day`, `to_date >= day`
- holiday: employee ⇒ `/api/method/hrms.api.get_attendance_calendar_events` (`from_date`=`to_date`=day, message[day] == 'Holiday'); no employee (System Manager only) ⇒ first non-empty `holiday_list` of `/api/resource/Shift Type`, then `/api/resource/Holiday List/<name>` holidays
- `/api/resource/Attendance Sync Status/Attendance Sync Status`

- [ ] **Step 1: Write the failing test** — `test/unit/attendance_notify_service_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/attendance_notify_service.dart';

/// Hand-written fake (repo convention): overrides the single HTTP seam.
class _FakeService extends AttendanceNotifyService {
  _FakeService() : super(baseUrl: 'https://erp.test', cookieDir: '/x/');

  String? loggedUser = 'e1@x.com';
  DioException? probeError;

  /// path → response data (List for resource lists, Map for docs / method
  /// messages) or a DioException to throw.
  final Map<String, Object> responses = {};
  final List<String> paths = [];

  static DioException err(int? code) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: code == null ? null : Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
        type: code == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
      );

  Response _ok(Object data) => Response(requestOptions: RequestOptions(path: '/x'), statusCode: 200, data: data);

  @override
  Future<Response> callGet(String path, Map<String, dynamic> query) async {
    paths.add(path);
    if (path == '/api/method/frappe.auth.get_logged_user') {
      if (probeError != null) throw probeError!;
      return _ok({'message': loggedUser});
    }
    final r = responses[path];
    if (r is DioException) throw r;
    if (path.startsWith('/api/method/')) return _ok({'message': r ?? const {}});
    return _ok({'data': r ?? const []});
  }
}

final day = DateTime(2026, 9, 12);

void seedEmployee(_FakeService f) {
  f.responses['/api/resource/Employee/E1'] = {'name': 'E1', 'attendance_device_id': '7'};
  f.responses['/api/resource/Shift Assignment'] = [
    {'employee': 'E1', 'shift_type': 'Morning', 'start_date': '2026-09-12', 'end_date': '2026-09-17'},
    {'employee': 'E1', 'shift_type': 'Afternoon', 'start_date': '2026-09-12', 'end_date': '2026-09-17'},
  ];
  f.responses['/api/resource/Shift Type'] = [
    {'name': 'Morning', 'start_time': '8:00:00', 'end_time': '12:15:00', 'late_entry_grace_period': 15},
    {'name': 'Afternoon', 'start_time': '13:30:00', 'end_time': '20:00:00', 'late_entry_grace_period': 15},
  ];
  f.responses['/api/resource/Employee Checkin'] = [
    {'name': 'c1', 'employee': 'E1', 'time': '2026-09-12 07:58:00', 'log_type': 'IN'},
  ];
  f.responses['/api/resource/Attendance Sync Status/Attendance Sync Status'] = {
    'terminal_online': 1,
    'terminal_last_seen': '2026-09-12 07:59:00',
    'agent_last_run': '2026-09-12 08:00:00',
  };
}

void main() {
  test('Guest or 401 at the probe: session expired', () async {
    final f = _FakeService()..loggedUser = 'Guest';
    expect((await f.fetch(employee: 'E1', day: day))!.authExpired, isTrue);
    final g = _FakeService()..probeError = _FakeService.err(401);
    expect((await g.fetch(employee: 'E1', day: day))!.authExpired, isTrue);
  });

  test('network error at the probe: null (post nothing)', () async {
    final f = _FakeService()..probeError = _FakeService.err(null);
    expect(await f.fetch(employee: 'E1', day: day), isNull);
  });

  test('tracked employee: assignments, catalog, punches, heartbeat', () async {
    final f = _FakeService();
    seedEmployee(f);
    final d = (await f.fetch(employee: 'E1', day: day))!;
    expect(d.authExpired, isFalse);
    expect(d.tracked, isTrue);
    expect(d.assignments.map((a) => a.shiftType), ['Morning', 'Afternoon']);
    expect(d.catalog.keys.toSet(), {'Morning', 'Afternoon'});
    expect(d.punches.single.time, DateTime(2026, 9, 12, 7, 58));
    expect(d.holiday, isFalse);
    expect(d.onLeave, isFalse);
    expect(d.sync!.terminalOnline, isTrue);
  });

  test('untracked employee: no shift reads', () async {
    final f = _FakeService();
    seedEmployee(f);
    f.responses['/api/resource/Employee/E1'] = {'name': 'E1', 'attendance_device_id': ''};
    final d = (await f.fetch(employee: 'E1', day: day))!;
    expect(d.tracked, isFalse);
    expect(f.paths, isNot(contains('/api/resource/Shift Assignment')));
  });

  test('approved leave, holiday and an unreadable heartbeat', () async {
    final f = _FakeService();
    seedEmployee(f);
    f.responses['/api/resource/Leave Application'] = [
      {'name': 'HR-LAP-0001'},
    ];
    f.responses['/api/method/hrms.api.get_attendance_calendar_events'] = {'2026-09-12': 'Holiday'};
    f.responses['/api/resource/Attendance Sync Status/Attendance Sync Status'] = _FakeService.err(403);
    final d = (await f.fetch(employee: 'E1', day: day))!;
    expect(d.onLeave, isTrue);
    expect(d.holiday, isTrue);
    expect(d.sync, isNull);
  });

  test('Leave Application 403 is tolerated', () async {
    final f = _FakeService();
    seedEmployee(f);
    f.responses['/api/resource/Leave Application'] = _FakeService.err(403);
    final d = await f.fetch(employee: 'E1', day: day);
    expect(d, isNotNull);
    expect(d!.onLeave, isFalse);
  });

  test('a failed required read: null', () async {
    final f = _FakeService();
    seedEmployee(f);
    f.responses['/api/resource/Shift Assignment'] = _FakeService.err(500);
    expect(await f.fetch(employee: 'E1', day: day), isNull);
  });

  test('System Manager without an employee: holiday from the shift holiday list', () async {
    final f = _FakeService();
    f.responses['/api/resource/Shift Type'] = [
      {'name': 'Morning', 'holiday_list': 'Multimax 2026'},
    ];
    f.responses['/api/resource/Holiday List/Multimax 2026'] = {
      'holidays': [
        {'holiday_date': '2026-09-13'},
      ],
    };
    f.responses['/api/resource/Attendance Sync Status/Attendance Sync Status'] = {'terminal_online': 0};
    final d = (await f.fetch(employee: '', day: DateTime(2026, 9, 13)))!;
    expect(d.tracked, isFalse);
    expect(d.holiday, isTrue);
    expect(d.sync!.terminalOnline, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/attendance_notify_service_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Implement** — create `lib/app/data/services/attendance_notify_service.dart`:

```dart
/// Reads everything one attendance-notification run needs, as the logged-in
/// user, over the app's persisted session cookies (same jar as ApiProvider,
/// like DigestService). Safe to construct in any isolate.
library;

import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:multimax/app/data/models/attendance_models.dart';

class AttendanceNotifyData {
  final bool authExpired;
  final bool tracked;
  final List<ShiftAssignmentRow> assignments;
  final Map<String, ShiftRules> catalog;
  final List<EmployeeCheckin> punches;

  /// Own Attendance rows from day − 3 to day (recap window + today).
  final List<AttendanceRecord> ledger;
  final bool holiday;
  final bool onLeave;

  /// Null when the heartbeat document could not be read.
  final SyncStatus? sync;

  const AttendanceNotifyData({
    this.authExpired = false,
    this.tracked = false,
    this.assignments = const [],
    this.catalog = const {},
    this.punches = const [],
    this.ledger = const [],
    this.holiday = false,
    this.onLeave = false,
    this.sync,
  });

  static const AttendanceNotifyData expired = AttendanceNotifyData(authExpired: true);

  List<AttendanceRecord> ledgerOn(DateTime day) {
    final key = kFrappeDate.format(day);
    return [for (final r in ledger) if (kFrappeDate.format(r.date) == key) r];
  }
}

class AttendanceNotifyService {
  final String baseUrl;

  /// Directory of the app's PersistCookieJar (`<appSupportDir>/.cookies/`).
  final String cookieDir;

  Dio? _dio;

  AttendanceNotifyService({required this.baseUrl, required this.cookieDir});

  Dio _client() {
    if (_dio != null) return _dio!;
    final jar = PersistCookieJar(ignoreExpires: true, storage: FileStorage(cookieDir));
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ))
      ..interceptors.add(CookieManager(jar));
    return _dio!;
  }

  /// Single HTTP seam — tests subclass and override this.
  Future<Response> callGet(String path, Map<String, dynamic> query) =>
      _client().get(path, queryParameters: query);

  Future<List<Map<String, dynamic>>> _list(
    String doctype, {
    required List<String> fields,
    List<List<dynamic>> filters = const [],
    List<List<dynamic>> orFilters = const [],
    String orderBy = 'modified desc',
  }) async {
    final res = await callGet('/api/resource/$doctype', {
      'fields': jsonEncode(fields),
      'filters': jsonEncode(filters),
      if (orFilters.isNotEmpty) 'or_filters': jsonEncode(orFilters),
      'order_by': orderBy,
      'limit_page_length': 0,
    });
    final data = res.data is Map ? res.data['data'] : null;
    return (data is List ? data : const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// One document, or null when it can't be read (403 / 404 / network).
  Future<Map<String, dynamic>?> _doc(String doctype, String name) async {
    try {
      final res = await callGet('/api/resource/$doctype/$name', const {});
      final data = res.data is Map ? res.data['data'] : null;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on DioException {
      return null;
    }
  }

  /// Everything for [employee] (empty for a System Manager without one) on
  /// [day]. `expired` when the session probe says so; null when a required
  /// read fails — the worker then posts nothing and retries soon.
  Future<AttendanceNotifyData?> fetch({required String employee, required DateTime day}) async {
    try {
      final res = await callGet('/api/method/frappe.auth.get_logged_user', const {});
      final who = res.data is Map ? res.data['message'] : null;
      if (who == null || who == 'Guest') return AttendanceNotifyData.expired;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return AttendanceNotifyData.expired;
      return null;
    } catch (_) {
      return null;
    }

    try {
      final d = kFrappeDate.format(day);
      final from = kFrappeDate.format(dateOnly(day).subtract(const Duration(days: 3)));
      var tracked = false;
      var assignments = <ShiftAssignmentRow>[];
      var ledger = <AttendanceRecord>[];
      var punches = <EmployeeCheckin>[];
      var onLeave = false;

      if (employee.isNotEmpty) {
        final emp = await _doc('Employee', employee);
        tracked = '${emp?['attendance_device_id'] ?? ''}'.trim().isNotEmpty;
      }
      if (tracked) {
        assignments = (await _list('Shift Assignment',
                fields: ['employee', 'shift_type', 'start_date', 'end_date'],
                filters: [
                  ['Shift Assignment', 'employee', '=', employee],
                  ['Shift Assignment', 'docstatus', '=', 1],
                  ['Shift Assignment', 'status', '=', 'Active'],
                  ['Shift Assignment', 'start_date', '<=', d],
                ],
                orFilters: [
                  ['Shift Assignment', 'end_date', '>=', d],
                  ['Shift Assignment', 'end_date', 'is', 'not set'],
                ],
                orderBy: 'start_date asc'))
            .map(ShiftAssignmentRow.fromJson)
            .toList();
        ledger = (await _list('Attendance',
                fields: [
                  'name', 'employee', 'employee_name', 'attendance_date', 'status',
                  'working_hours', 'in_time', 'out_time', 'late_entry', 'early_exit',
                  'shift', 'leave_type',
                ],
                filters: [
                  ['Attendance', 'employee', '=', employee],
                  ['Attendance', 'docstatus', '=', 1],
                  ['Attendance', 'attendance_date', 'between', [from, d]],
                ],
                orderBy: 'attendance_date desc'))
            .map(AttendanceRecord.fromJson)
            .toList();
        punches = (await _list('Employee Checkin',
                fields: ['name', 'employee', 'time', 'log_type', 'device_id', 'shift'],
                filters: [
                  ['Employee Checkin', 'employee', '=', employee],
                  ['Employee Checkin', 'time', 'between', ['$d 00:00:00', '$d 23:59:59']],
                ],
                orderBy: 'time asc'))
            .map(EmployeeCheckin.fromJson)
            .toList();
        onLeave = await _onLeave(employee, d);
      }

      final names = <String>{
        for (final a in assignments) a.shiftType,
        for (final r in ledger)
          if (r.shift.trim().isNotEmpty) r.shift,
      };
      final catalog = <String, ShiftRules>{};
      if (names.isNotEmpty) {
        final rows = await _list('Shift Type',
            fields: [
              'name', 'start_time', 'end_time', 'late_entry_grace_period',
              'early_exit_grace_period', 'begin_check_in_before_shift_start_time',
              'allow_check_out_after_shift_end_time', 'holiday_list',
            ],
            filters: [
              ['Shift Type', 'name', 'in', names.toList()],
            ]);
        for (final j in rows) {
          catalog['${j['name'] ?? ''}'] = ShiftRules.fromJson(j);
        }
      }

      final holiday = await _isHoliday(d, employee: tracked ? employee : '', catalog: catalog);
      final syncDoc = await _doc('Attendance Sync Status', 'Attendance Sync Status');
      return AttendanceNotifyData(
        tracked: tracked,
        assignments: assignments,
        catalog: catalog,
        punches: punches,
        ledger: ledger,
        holiday: holiday,
        onLeave: onLeave,
        sync: syncDoc == null ? null : SyncStatus.fromJson(syncDoc),
      );
    } catch (_) {
      return null;
    }
  }

  /// An approved Leave Application covering [d]. Unreadable (e.g. 403 for the
  /// Employee role) ⇒ false; the Attendance row's On Leave still silences.
  Future<bool> _onLeave(String employee, String d) async {
    try {
      final rows = await _list('Leave Application', fields: ['name'], filters: [
        ['Leave Application', 'employee', '=', employee],
        ['Leave Application', 'status', '=', 'Approved'],
        ['Leave Application', 'docstatus', '=', 1],
        ['Leave Application', 'from_date', '<=', d],
        ['Leave Application', 'to_date', '>=', d],
      ]);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Employees read HRMS's own calendar (Holiday List is 403 for them); a
  /// System Manager without an employee reads the shifts' Holiday List.
  /// Unreadable ⇒ a working day.
  Future<bool> _isHoliday(String d,
      {required String employee, required Map<String, ShiftRules> catalog}) async {
    try {
      if (employee.isNotEmpty) {
        final res = await callGet('/api/method/hrms.api.get_attendance_calendar_events',
            {'from_date': d, 'to_date': d});
        final msg = res.data is Map ? res.data['message'] : null;
        return msg is Map && msg[d] == 'Holiday';
      }
      var list = '';
      for (final s in catalog.values) {
        if (s.holidayList.trim().isNotEmpty) list = s.holidayList;
      }
      if (list.isEmpty) {
        final rows = await _list('Shift Type', fields: ['name', 'holiday_list']);
        for (final j in rows) {
          final h = '${j['holiday_list'] ?? ''}'.trim();
          if (h.isNotEmpty) {
            list = h;
            break;
          }
        }
      }
      if (list.isEmpty) return false;
      final doc = await _doc('Holiday List', list);
      final holidays = doc?['holidays'];
      return holidays is List &&
          holidays.whereType<Map>().any((h) => '${h['holiday_date'] ?? ''}'.startsWith(d));
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/unit/attendance_notify_service_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/attendance_notify_service.dart test/unit/attendance_notify_service_test.dart
git commit -m "feat(attendance): isolate-safe reads for attendance notifications

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Scheduler, worker, shared dispatcher and app wiring

**Files:**
- Create: `lib/app/data/services/attendance_notify_scheduler.dart`, `lib/app/data/services/attendance_notify_worker.dart`
- Modify: `lib/app/data/services/digest_worker.dart` (dispatcher routing), `lib/main.dart:109-115`, `lib/app/modules/auth/authentication_controller.dart:102-105` and `:217-225`
- Test: `test/unit/attendance_notify_scheduler_test.dart`

**Interfaces:**
- Consumes: `WorkScheduler` / `WorkmanagerScheduler` (`digest_scheduler.dart:55-83`), Tasks 1–4, `ApiProvider.defaultBaseUrl`, `getApplicationSupportDirectory`.
- Produces: `const kAttendanceTaskName = 'attendanceTask'`, `const kAttendanceUniqueName = 'attendance-notification'`; `class AttendanceNotifyScheduler { AttendanceNotifyScheduler({StorageService? storage, WorkScheduler? work, DateTime Function()? now, bool? isAndroid}); bool wants(User? user); Future<void> rearm(); Future<void> scheduleNext(DateTime wake); Future<void> cancel(); }`; `Future<void> runAttendanceTask()`, `Future<void> showAttendanceNotifications({required List<NotifyMessage> post, required List<int> cancel})`, `Future<void> cancelAttendanceOnLogout()`, channel ids `kAttendanceReminderChannelId` / `kAttendanceTerminalChannelId`; `Future<void> runBackgroundTask(String taskName, {Future<void> Function()? digest, Future<void> Function()? attendance})` in `digest_worker.dart`.

- [ ] **Step 1: Write the failing test** — `test/unit/attendance_notify_scheduler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_worker.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class _FakeGetStorage {
  final Map<String, dynamic> data = {};
  Future<void> write(String key, dynamic value) async => data[key] = value;
  Future<void> remove(String key) async => data.remove(key);
  T? read<T>(String key) => data[key] as T?;
  bool hasData(String key) => data.containsKey(key);
}

class _FakeWork implements WorkScheduler {
  final registered = <({String uniqueName, String taskName, Duration delay})>[];
  final cancelled = <String>[];

  @override
  Future<void> registerOneOff(
          {required String uniqueName, required String taskName, required Duration initialDelay}) async =>
      registered.add((uniqueName: uniqueName, taskName: taskName, delay: initialDelay));

  @override
  Future<void> cancel(String uniqueName) async => cancelled.add(uniqueName);
}

const employeeUser = {
  'name': 'e1@x.com', 'full_name': 'E', 'email': 'e1@x.com',
  'employee_id': 'HR-EMP-00001',
  'roles': [
    {'role': 'Employee'}
  ],
};
const managerUser = {
  'name': 'sm@x.com', 'full_name': 'SM', 'email': 'sm@x.com',
  'roles': [
    {'role': 'System Manager'}
  ],
};

void main() {
  final now = DateTime(2026, 9, 12, 10, 0);
  late _FakeGetStorage box;
  late StorageService storage;
  late _FakeWork work;
  late AttendanceNotifyScheduler scheduler;

  setUp(() {
    box = _FakeGetStorage();
    storage = StorageService.withStorage(box as dynamic);
    work = _FakeWork();
    scheduler = AttendanceNotifyScheduler(
        storage: storage, work: work, now: () => now, isAndroid: true);
  });

  test('no logged-in user: cancel', () async {
    await scheduler.rearm();
    expect(work.cancelled, [kAttendanceUniqueName]);
    expect(work.registered, isEmpty);
  });

  test('linked employee, reminders on by default: planning run in 1 minute', () async {
    box.data['currentUser'] = employeeUser;
    await scheduler.rearm();
    expect(work.registered.single.uniqueName, kAttendanceUniqueName);
    expect(work.registered.single.taskName, kAttendanceTaskName);
    expect(work.registered.single.delay, const Duration(minutes: 1));
    expect(work.cancelled, isEmpty);
  });

  test('reminders off and not a System Manager: cancel', () async {
    box.data['currentUser'] = employeeUser;
    await storage.saveAttendanceRemindersEnabled('e1@x.com', false);
    await scheduler.rearm();
    expect(work.registered, isEmpty);
    expect(work.cancelled, [kAttendanceUniqueName]);
  });

  test('System Manager without an employee: armed for terminal alerts only', () async {
    box.data['currentUser'] = managerUser;
    await scheduler.rearm();
    expect(work.registered, hasLength(1));
    await storage.saveAttendanceTerminalAlerts('sm@x.com', false);
    final w2 = _FakeWork();
    await AttendanceNotifyScheduler(storage: storage, work: w2, now: () => now, isAndroid: true).rearm();
    expect(w2.registered, isEmpty);
    expect(w2.cancelled, [kAttendanceUniqueName]);
  });

  test('not Android: never touches WorkManager', () async {
    box.data['currentUser'] = employeeUser;
    final w2 = _FakeWork();
    await AttendanceNotifyScheduler(storage: storage, work: w2, now: () => now, isAndroid: false).rearm();
    expect(w2.registered, isEmpty);
    expect(w2.cancelled, isEmpty);
  });

  test('scheduleNext uses the wake delay, clamped at zero', () async {
    await scheduler.scheduleNext(now.add(const Duration(hours: 2)));
    expect(work.registered.single.delay, const Duration(hours: 2));
    await scheduler.scheduleNext(now.subtract(const Duration(minutes: 5)));
    expect(work.registered.last.delay, Duration.zero);
  });

  test('never touches the digest chain', () async {
    box.data['currentUser'] = employeeUser;
    await scheduler.rearm();
    await scheduler.cancel();
    expect(work.registered.map((r) => r.uniqueName), everyElement(kAttendanceUniqueName));
    expect(work.cancelled, everyElement(kAttendanceUniqueName));
  });

  group('shared dispatcher', () {
    test('routes by task name; an unknown name falls back to the digest', () async {
      final calls = <String>[];
      Future<void> digest() async => calls.add('digest');
      Future<void> attendance() async => calls.add('attendance');
      await runBackgroundTask(kAttendanceTaskName, digest: digest, attendance: attendance);
      await runBackgroundTask(kDigestTaskName, digest: digest, attendance: attendance);
      await runBackgroundTask('somethingElse', digest: digest, attendance: attendance);
      expect(calls, ['attendance', 'digest', 'digest']);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/attendance_notify_scheduler_test.dart`
Expected: FAIL — scheduler file and `runBackgroundTask` not defined.

- [ ] **Step 3: Create the scheduler** — `lib/app/data/services/attendance_notify_scheduler.dart`:

```dart
/// Arms the attendance notification chain: its own WorkManager one-off work,
/// separate from the digest's. GetX-free — also called from the worker.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart' show WorkScheduler, WorkmanagerScheduler;
import 'package:multimax/app/data/services/storage_service.dart';

const String kAttendanceTaskName = 'attendanceTask';
const String kAttendanceUniqueName = 'attendance-notification';

class AttendanceNotifyScheduler {
  final StorageService _storage;
  final WorkScheduler _work;
  final DateTime Function() _now;
  final bool _isAndroid;

  AttendanceNotifyScheduler({
    StorageService? storage,
    WorkScheduler? work,
    DateTime Function()? now,
    bool? isAndroid,
  })  : _storage = storage ?? StorageService(),
        _work = work ?? WorkmanagerScheduler(),
        _now = now ?? DateTime.now,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// True when [user] gets attendance reminders (a linked employee with them
  /// on) or terminal alerts (a System Manager with them on).
  bool wants(User? user) {
    if (user == null) return false;
    final reminders = (user.employeeId ?? '').trim().isNotEmpty &&
        _storage.getAttendanceRemindersEnabled(user.id);
    final terminal =
        user.hasRole('System Manager') && _storage.getAttendanceTerminalAlerts(user.id);
    return reminders || terminal;
  }

  /// App start / login / settings change: the main isolate doesn't know the
  /// day's shifts, so it schedules a planning run that works them out.
  Future<void> rearm() async {
    if (!_isAndroid) return;
    if (!wants(_storage.getUser())) {
      await _work.cancel(kAttendanceUniqueName);
      return;
    }
    await _work.registerOneOff(
      uniqueName: kAttendanceUniqueName,
      taskName: kAttendanceTaskName,
      initialDelay: const Duration(minutes: 1),
    );
  }

  /// Called by the worker with the next moment from the timeline.
  Future<void> scheduleNext(DateTime wake) async {
    if (!_isAndroid) return;
    final delay = wake.difference(_now());
    await _work.registerOneOff(
      uniqueName: kAttendanceUniqueName,
      taskName: kAttendanceTaskName,
      initialDelay: delay.isNegative ? Duration.zero : delay,
    );
  }

  Future<void> cancel() => _work.cancel(kAttendanceUniqueName);
}
```

- [ ] **Step 4: Create the worker** — `lib/app/data/services/attendance_notify_worker.dart`:

```dart
/// One attendance notification run, in the WorkManager background isolate:
/// fetch → decide (pure) → post → save worker state → schedule the next
/// moment. No GetX. The main GetStorage box is read-only here; worker state
/// lives in the separate [kAttendanceStateBox] container.
library;

import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/attendance_notify_rules.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
import 'package:multimax/app/data/services/attendance_notify_service.dart';
import 'package:multimax/app/data/services/attendance_notify_state.dart';
import 'package:multimax/app/data/services/attendance_timeline.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

const String kAttendanceReminderChannelId = 'attendance_reminders';
const String kAttendanceTerminalChannelId = 'attendance_terminal';
const String _kReminderChannelName = 'Attendance reminders';
const String _kTerminalChannelName = 'Attendance terminal';

/// A failed fetch is retried soon rather than waiting for the next moment.
const Duration kAttendanceRetry = Duration(minutes: 15);

Future<void> runAttendanceTask() async {
  await GetStorage.init();
  await GetStorage.init(kAttendanceStateBox);
  final storage = StorageService();
  final scheduler = AttendanceNotifyScheduler(storage: storage);
  final user = storage.getUser();
  if (user == null) return; // logged out since scheduling

  final employee = (user.employeeId ?? '').trim();
  final reminders = employee.isNotEmpty && storage.getAttendanceRemindersEnabled(user.id);
  final terminal =
      user.hasRole('System Manager') && storage.getAttendanceTerminalAlerts(user.id);
  if (!reminders && !terminal) {
    await scheduler.cancel(); // switched off or role revoked since scheduling
    return;
  }

  final now = DateTime.now();
  final today = dateOnly(now);
  final todayKey = kFrappeDate.format(today);
  final box = GetStorage(kAttendanceStateBox);
  var state =
      AttendanceNotifyState.fromMap(box.read(kAttendanceStateKey), user: user.id, today: todayKey);
  var wake = planningRunAfter(now);

  try {
    final supportDir = await getApplicationSupportDirectory();
    final service = AttendanceNotifyService(
      baseUrl: storage.getBaseUrl() ?? ApiProvider.defaultBaseUrl,
      cookieDir: '${supportDir.path}/.cookies/',
    );
    final data = await service.fetch(employee: reminders ? employee : '', day: today);
    final post = <NotifyMessage>[];
    final cancel = <int>[];

    if (data == null) {
      wake = now.add(kAttendanceRetry); // transient failure: try again soon
    } else if (data.authExpired) {
      if (state.lastAuthNotice != todayKey) {
        post.add(kSessionExpiredMessage);
        state = state.copyWith(lastAuthNotice: todayKey);
      }
    } else {
      final workingDay = !data.holiday;
      final canRemind = reminders && data.tracked;
      var moments = const <ShiftMoment>[];

      if (canRemind) {
        final shifts = reminderShifts(
          employee: employee,
          day: today,
          assignments: data.assignments,
          ledger: data.ledgerOn(today),
          catalog: data.catalog,
        );
        final out = decideReminders(
          now: now,
          facts: EmployeeDayFacts(
            shifts: shifts,
            punches: data.punches,
            ledger: data.ledgerOn(today),
            holiday: data.holiday,
            onLeave: data.onLeave,
            syncing: isSyncing(data.sync, now),
          ),
          handled: state.handled,
          posted: state.posted,
        );
        post.addAll(out.post);
        cancel.addAll(out.cancel);
        state = state.copyWith(handled: out.handled, posted: out.posted);
        moments = shiftMoments(shifts, today);

        if (workingDay &&
            !now.isBefore(recapTimeOn(today)) &&
            state.recapRunDay != todayKey) {
          final recap = decideRecap(
            now: now,
            rows: data.ledger,
            catalog: data.catalog,
            lastRecapped: state.lastRecapped,
          );
          if (recap.message != null) post.add(recap.message!);
          state = state.copyWith(recapRunDay: todayKey, lastRecapped: recap.recapped);
        }
      }

      if (terminal && workingDay && inWatchHours(now)) {
        final t = decideTerminal(now: now, status: data.sync, wasQuiet: state.terminalQuiet);
        if (t.message != null) post.add(t.message!);
        state = state.copyWith(terminalQuiet: t.quiet);
      }

      wake = nextAttendanceWake(
        now: now,
        moments: moments,
        workingDay: workingDay,
        recap: canRemind && state.recapRunDay != todayKey,
        terminalWatch: terminal,
      );
    }

    await showAttendanceNotifications(post: post, cancel: cancel);
    await box.write(kAttendanceStateKey, state.toMap());
  } finally {
    // Always chain the next run — one failure must never end the chain.
    await scheduler.scheduleNext(wake);
  }
}

/// Posts [post] and clears [cancel] on the two attendance channels.
Future<void> showAttendanceNotifications({
  required List<NotifyMessage> post,
  required List<int> cancel,
}) async {
  if (post.isEmpty && cancel.isEmpty) return;
  final fln = FlutterLocalNotificationsPlugin();
  await fln.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  final android =
      fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(AndroidNotificationChannel(
    kAttendanceReminderChannelId,
    _kReminderChannelName,
    description: 'Check-in and check-out reminders for your shifts',
    importance: Importance.high,
    enableVibration: true,
    vibrationPattern: Int64List.fromList(<int>[0, 400]),
  ));
  await android?.createNotificationChannel(const AndroidNotificationChannel(
    kAttendanceTerminalChannelId,
    _kTerminalChannelName,
    description: 'Alerts when the attendance terminal or its sync goes quiet',
    importance: Importance.high,
  ));

  for (final id in cancel) {
    await fln.cancel(id: id);
  }
  for (final m in post) {
    final channelId = m.terminal ? kAttendanceTerminalChannelId : kAttendanceReminderChannelId;
    final channelName = m.terminal ? _kTerminalChannelName : _kReminderChannelName;
    await fln.show(
      id: m.id,
      title: m.title,
      body: m.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(m.body),
        ),
      ),
    );
  }
}

/// Logout: drop pending work and clear posted attendance notifications so the
/// next user never sees the previous one's shifts.
Future<void> cancelAttendanceOnLogout() async {
  try {
    await Workmanager().cancelByUniqueName(kAttendanceUniqueName);
    final fln = FlutterLocalNotificationsPlugin();
    await fln.initialize(
        settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    for (final id in kAttendanceNotificationIds) {
      await fln.cancel(id: id);
    }
  } catch (_) {
    // Best-effort cleanup; never block logout on notification plumbing.
  }
}
```

- [ ] **Step 5: Route the shared dispatcher** — in `digest_worker.dart`, add the import
`import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';`,
`import 'package:multimax/app/data/services/attendance_notify_worker.dart';`, and replace
`digestCallbackDispatcher` with:

```dart
@pragma('vm:entry-point')
void digestCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await runBackgroundTask(taskName);
    } catch (_) {
      // Neither feature may nag about its own failures, and returning false
      // would trigger WorkManager backoff retries — the next scheduled tick
      // is the retry.
    }
    return true;
  });
}

/// WorkManager allows one dispatcher per app, so both chains arrive here and
/// are routed by task name. Runners are injectable for tests.
Future<void> runBackgroundTask(
  String taskName, {
  Future<void> Function()? digest,
  Future<void> Function()? attendance,
}) async {
  if (taskName == kAttendanceTaskName) {
    return (attendance ?? runAttendanceTask)();
  }
  return (digest ?? runDigestTask)();
}
```

- [ ] **Step 6: Wire start, login and logout**

`lib/main.dart`, inside the existing authenticated block (`:111-115`), after the digest rearm:

```dart
    if (Platform.isAndroid) {
      unawaited(AttendanceNotifyScheduler().rearm().catchError((_) {}));
    }
```

`authentication_controller.dart`, after the digest rearm in `fetchUserDetails` (`:102-105`):

```dart
          // Arm attendance notifications for the user who just signed in
          // (Android only — iOS cannot check punches at fire time).
          if (!kIsWeb && Platform.isAndroid) {
            unawaited(AttendanceNotifyScheduler().rearm().catchError((_) {}));
          }
```

and in `_clearSessionAndLocalData`, inside the existing Android branch next to `cancelDigestOnLogout()`:

```dart
      await cancelAttendanceOnLogout();
```

Add the two imports (`attendance_notify_scheduler.dart`, `attendance_notify_worker.dart`) to both files as needed.

- [ ] **Step 7: Analyze, then test (sequentially)**

Run: `flutter analyze lib/app/data/services/attendance_notify_scheduler.dart lib/app/data/services/attendance_notify_worker.dart lib/app/data/services/digest_worker.dart lib/main.dart lib/app/modules/auth/authentication_controller.dart test/unit/attendance_notify_scheduler_test.dart`
Expected: no new issues in these files.
Then run: `flutter test test/unit`
Expected: PASS, including the existing digest tests.

- [ ] **Step 8: Commit**

```bash
git branch --show-current
git add lib/app/data/services/attendance_notify_scheduler.dart lib/app/data/services/attendance_notify_worker.dart lib/app/data/services/digest_worker.dart lib/main.dart lib/app/modules/auth/authentication_controller.dart test/unit/attendance_notify_scheduler_test.dart
git commit -m "feat(attendance): background attendance notification worker

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Settings, entry gate and the one-time permission prompt

**Files:**
- Modify: `lib/app/modules/user_area/user_area_screen.dart:14-24` (`showNotificationsEntry`)
- Modify: `lib/app/modules/notification_settings/notification_settings_controller.dart`, `notification_settings_screen.dart`
- Modify: `lib/app/modules/home/home_controller.dart` (`onInit` ~l.453)
- Test: `test/unit/notifications_entry_test.dart` (new), `test/widget/notification_settings_screen_test.dart` (extend)

**Interfaces:**
- Consumes: Task 1 prefs, Task 5 `AttendanceNotifyScheduler`.
- Produces: `showNotificationsEntry` also true for an Android user linked to an Employee; `NotificationSettingsController` gains `attendanceEnabled`, `terminalEnabled`, `notificationsBlocked`, `showDigest`, `showAttendance`, `showTerminal`, `setAttendanceEnabled(bool)`, `setTerminalEnabled(bool)` and the constructor params `attendanceScheduler`, `isAndroid`, `notificationsAllowed`; free functions `Future<bool> notificationsAllowed()` and `bool shouldPromptAttendancePermission({required User? user, required bool isAndroid, required StorageService storage})`.

- [ ] **Step 1: Write the failing tests** — create `test/unit/notifications_entry_test.dart`:

```dart
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_controller.dart';
import 'package:multimax/app/modules/user_area/user_area_screen.dart';

class _FakeGetStorage {
  final Map<String, dynamic> data = {};
  Future<void> write(String key, dynamic value) async => data[key] = value;
  Future<void> remove(String key) async => data.remove(key);
  T? read<T>(String key) => data[key] as T?;
  bool hasData(String key) => data.containsKey(key);
}

User user({String id = 'u@x.com', String? employeeId, List<String> roles = const []}) =>
    User(id: id, name: 'U', email: id, employeeId: employeeId, roles: roles);

void main() {
  group('showNotificationsEntry', () {
    bool show(User? u, TargetPlatform p) => showNotificationsEntry(user: u, platform: p, isWeb: false);

    test('managers keep it on Android and iOS', () {
      final m = user(roles: ['Stock Manager']);
      expect(show(m, TargetPlatform.android), isTrue);
      expect(show(m, TargetPlatform.iOS), isTrue);
    });
    test('a linked employee sees it on Android only', () {
      final e = user(employeeId: 'HR-EMP-00001', roles: ['Employee']);
      expect(show(e, TargetPlatform.android), isTrue);
      expect(show(e, TargetPlatform.iOS), isFalse);
    });
    test('neither manager nor linked employee, or web: hidden', () {
      expect(show(user(roles: ['Employee']), TargetPlatform.android), isFalse);
      expect(show(null, TargetPlatform.android), isFalse);
      expect(
          showNotificationsEntry(
              user: user(roles: ['Stock Manager']), platform: TargetPlatform.android, isWeb: true),
          isFalse);
    });
  });

  group('shouldPromptAttendancePermission', () {
    late StorageService storage;
    setUp(() => storage = StorageService.withStorage(_FakeGetStorage() as dynamic));

    test('once for a linked employee on Android with reminders on', () async {
      final e = user(employeeId: 'HR-EMP-00001');
      expect(shouldPromptAttendancePermission(user: e, isAndroid: true, storage: storage), isTrue);
      await storage.saveAttendancePermissionPrompted(e.id);
      expect(shouldPromptAttendancePermission(user: e, isAndroid: true, storage: storage), isFalse);
    });
    test('never off Android, unlinked, or with reminders switched off', () async {
      final e = user(employeeId: 'HR-EMP-00001');
      expect(shouldPromptAttendancePermission(user: e, isAndroid: false, storage: storage), isFalse);
      expect(shouldPromptAttendancePermission(user: user(), isAndroid: true, storage: storage), isFalse);
      expect(shouldPromptAttendancePermission(user: null, isAndroid: true, storage: storage), isFalse);
      await storage.saveAttendanceRemindersEnabled(e.id, false);
      expect(shouldPromptAttendancePermission(user: e, isAndroid: true, storage: storage), isFalse);
    });
  });
}
```

In `test/widget/notification_settings_screen_test.dart`: the fixture user now needs a manager role for the digest section (the gate is new), and the controller takes the new seams. Replace the `setUp` body's user map and controller construction with:

```dart
    box.data['currentUser'] = {
      'name': 'a@b.c',
      'full_name': 'A',
      'email': 'a@b.c',
      'roles': [
        {'role': 'Stock Manager'}
      ],
    };
    storage = StorageService.withStorage(box as dynamic);
    Get.put<NotificationSettingsController>(NotificationSettingsController(
      storage: storage,
      scheduler: DigestScheduler(storage: storage, work: _FakeWork()),
      attendanceScheduler:
          AttendanceNotifyScheduler(storage: storage, work: _FakeWork(), isAndroid: true),
      isAndroid: false,
      requestPermission: () async => true,
      notificationsAllowed: () async => true,
    ));
```

(keep the existing `_FakeGetStorage` / `_FakeWork` helpers and `box` variable; add the
`attendance_notify_scheduler.dart` import). Then append these tests:

```dart
  testWidgets('a linked employee sees Attendance reminders and no digest', (tester) async {
    Get.deleteAll(force: true);
    final box = _FakeGetStorage();
    box.data['currentUser'] = {
      'name': 'e@x.com', 'full_name': 'E', 'email': 'e@x.com',
      'employee_id': 'HR-EMP-00001',
      'roles': [
        {'role': 'Employee'}
      ],
    };
    final s = StorageService.withStorage(box as dynamic);
    Get.put<NotificationSettingsController>(NotificationSettingsController(
      storage: s,
      scheduler: DigestScheduler(storage: s, work: _FakeWork()),
      attendanceScheduler: AttendanceNotifyScheduler(storage: s, work: _FakeWork(), isAndroid: true),
      isAndroid: true,
      requestPermission: () async => true,
      notificationsAllowed: () async => true,
    ));
    await pump(tester);
    expect(find.text('Attendance reminders'), findsOneWidget);
    expect(find.text('Scheduled digest'), findsNothing);
    expect(find.text('Terminal alerts'), findsNothing);
    final sw = tester.widget<Switch>(find.byType(Switch).first);
    expect(sw.value, isTrue); // on by default
  });

  testWidgets('a System Manager sees the digest, reminders and terminal alerts',
      (tester) async {
    Get.deleteAll(force: true);
    final box = _FakeGetStorage();
    box.data['currentUser'] = {
      'name': 'sm@x.com', 'full_name': 'SM', 'email': 'sm@x.com',
      'employee_id': 'HR-EMP-00002',
      'roles': [
        {'role': 'System Manager'}
      ],
    };
    final s = StorageService.withStorage(box as dynamic);
    Get.put<NotificationSettingsController>(NotificationSettingsController(
      storage: s,
      scheduler: DigestScheduler(storage: s, work: _FakeWork()),
      attendanceScheduler: AttendanceNotifyScheduler(storage: s, work: _FakeWork(), isAndroid: true),
      isAndroid: true,
      requestPermission: () async => true,
      notificationsAllowed: () async => false, // notifications blocked in Android settings
    ));
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('Scheduled digest'), findsOneWidget);
    expect(find.text('Attendance reminders'), findsOneWidget);
    expect(find.text('Terminal alerts'), findsOneWidget);
    expect(find.textContaining('Allow them in Android settings'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/notifications_entry_test.dart test/widget/notification_settings_screen_test.dart`
Expected: FAIL — `shouldPromptAttendancePermission` undefined, no `attendanceScheduler` parameter, Attendance rows missing.

- [ ] **Step 3: Widen the entry gate** — in `user_area_screen.dart` replace `showNotificationsEntry`:

```dart
/// The Notifications entry: managers on Android/iOS (documents digest), and
/// Android users linked to an Employee (attendance reminders).
bool showNotificationsEntry({
  required User? user,
  required TargetPlatform platform,
  required bool isWeb,
}) {
  if (isWeb || user == null) return false;
  final isMobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  if (isMobile && user.isManager) return true;
  return platform == TargetPlatform.android && (user.employeeId ?? '').trim().isNotEmpty;
}
```

- [ ] **Step 4: Extend the settings controller** — in `notification_settings_controller.dart`:

Add imports (`dart:io` Platform and `kIsWeb` are already there via the permission helper; add
`package:multimax/app/data/models/user_model.dart` and
`package:multimax/app/data/services/attendance_notify_scheduler.dart`), then after
`requestNotificationsPermission()`:

```dart
/// Whether the OS currently lets the app post notifications (Android 13+
/// users can revoke it after the first prompt). Named apart from the
/// constructor's `notificationsAllowed` seam so neither shadows the other.
Future<bool> notificationsAllowedNow() async {
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.areNotificationsEnabled() ?? true;
}

/// Attendance reminders are on by default, so the Dashboard asks for
/// notification permission once per linked employee on Android.
bool shouldPromptAttendancePermission({
  required User? user,
  required bool isAndroid,
  required StorageService storage,
}) =>
    isAndroid &&
    user != null &&
    (user.employeeId ?? '').trim().isNotEmpty &&
    storage.getAttendanceRemindersEnabled(user.id) &&
    !storage.getAttendancePermissionPrompted(user.id);
```

In the class, add the fields and constructor params:

```dart
  final AttendanceNotifyScheduler _attendanceScheduler;
  final Future<bool> Function() _notificationsAllowed;
  final bool _isAndroid;

  NotificationSettingsController({
    StorageService? storage,
    DigestScheduler? scheduler,
    AttendanceNotifyScheduler? attendanceScheduler,
    Future<bool> Function()? requestPermission,
    Future<bool> Function()? notificationsAllowed,
    bool? isAndroid,
  })  : _storage = storage ?? Get.find<StorageService>(),
        _scheduler = scheduler ?? DigestScheduler(),
        _attendanceScheduler = attendanceScheduler ?? AttendanceNotifyScheduler(),
        _requestPermission = requestPermission ?? requestNotificationsPermission,
        _notificationsAllowed = notificationsAllowed ?? notificationsAllowedNow,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  final attendanceEnabled = true.obs;
  final terminalEnabled = true.obs;

  /// The OS switch is off: the sections explain it instead of silently never
  /// notifying.
  final notificationsBlocked = false.obs;

  User? get _account => _storage.getUser();
  bool get showDigest => _account?.isManager ?? false;
  bool get showAttendance => _isAndroid && (_account?.employeeId ?? '').trim().isNotEmpty;
  bool get showTerminal => _isAndroid && (_account?.hasRole('System Manager') ?? false);
```

In `onInit`, after the digest reads:

```dart
    attendanceEnabled.value = _storage.getAttendanceRemindersEnabled(_user);
    terminalEnabled.value = _storage.getAttendanceTerminalAlerts(_user);
    if (showAttendance || showTerminal) unawaited(_refreshBlocked());
```

and add:

```dart
  Future<void> _refreshBlocked() async {
    try {
      notificationsBlocked.value = !await _notificationsAllowed();
    } catch (_) {
      // Plugin unavailable (tests, desktop) — assume allowed.
    }
  }

  Future<void> setAttendanceEnabled(bool value) async {
    if (value) notificationsBlocked.value = !await _requestPermission();
    attendanceEnabled.value = value;
    await _storage.saveAttendanceRemindersEnabled(_user, value);
    await _attendanceScheduler.rearm();
  }

  Future<void> setTerminalEnabled(bool value) async {
    if (value) notificationsBlocked.value = !await _requestPermission();
    terminalEnabled.value = value;
    await _storage.saveAttendanceTerminalAlerts(_user, value);
    await _attendanceScheduler.rearm();
  }
```

Add `import 'dart:async';` for `unawaited` if it isn't imported.

- [ ] **Step 5: Extend the settings screen** — in `notification_settings_screen.dart`, wrap the
existing digest `SettingsGroup` and its dependent sections in `if (controller.showDigest) ...[ ... ]`,
and add before them:

```dart
              if (controller.showAttendance || controller.showTerminal) ...[
                SettingsGroup(
                  label: 'Attendance',
                  children: [
                    if (controller.showAttendance)
                      SettingsSwitchRow(
                        title: 'Attendance reminders',
                        subtitle: 'Check-in and check-out reminders for your shifts, '
                            'and a morning recap when something was missed',
                        value: controller.attendanceEnabled.value,
                        onChanged: controller.setAttendanceEnabled,
                      ),
                    if (controller.showTerminal)
                      SettingsSwitchRow(
                        title: 'Terminal alerts',
                        subtitle: 'Tell me when the attendance terminal or its sync goes quiet',
                        value: controller.terminalEnabled.value,
                        onChanged: controller.setTerminalEnabled,
                      ),
                  ],
                ),
                if (controller.notificationsBlocked.value)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.s3, AppSpace.s2, AppSpace.s3, 0),
                    child: Text(
                      'Notifications are turned off for Multimax. Allow them in Android settings '
                      'to get these reminders.',
                      style: TextStyle(fontSize: 12.5, color: context.scheme.textMuted),
                    ),
                  ),
                const SizedBox(height: AppSpace.s4),
              ],
```

- [ ] **Step 6: Prompt once from the Dashboard** — in `home_controller.dart`, after `_initDashboard();`
in `onInit`, add `unawaited(_maybePromptAttendancePermission());` and the method:

```dart
  /// Attendance reminders are on by default, so ask for notification
  /// permission the first time a linked employee opens the Dashboard. The
  /// answer is remembered either way; Notifications settings explains how to
  /// turn it on later.
  Future<void> _maybePromptAttendancePermission() async {
    final user = _authController.currentUser.value;
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!shouldPromptAttendancePermission(
        user: user, isAndroid: isAndroid, storage: _storageService)) {
      return;
    }
    await _storageService.saveAttendancePermissionPrompted(user!.id);
    try {
      await requestNotificationsPermission();
    } catch (_) {
      // Plugin failure must never break the Dashboard.
    }
  }
```

Add the imports it needs if missing: `dart:async` (`unawaited`), `package:flutter/foundation.dart`
(`defaultTargetPlatform`, `kIsWeb`, `TargetPlatform`) and the notification settings controller.

- [ ] **Step 7: Analyze, then test (sequentially)**

Run: `flutter analyze lib/app/modules/user_area/user_area_screen.dart lib/app/modules/notification_settings/notification_settings_controller.dart lib/app/modules/notification_settings/notification_settings_screen.dart lib/app/modules/home/home_controller.dart test/unit/notifications_entry_test.dart test/widget/notification_settings_screen_test.dart`
Expected: no new issues in these files.
Then run: `flutter test test/unit test/widget`
Expected: PASS. If a pre-existing test asserted the old manager-only entry gate, update that
expectation and say which in your report.

- [ ] **Step 8: Commit**

```bash
git branch --show-current
git add lib/app/modules/user_area/user_area_screen.dart lib/app/modules/notification_settings lib/app/modules/home/home_controller.dart test/unit/notifications_entry_test.dart test/widget/notification_settings_screen_test.dart
git commit -m "feat(attendance): notification settings and the one-time permission prompt

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Whole-feature verification and release

**Files:** `pubspec.yaml`, `whatsnew/whatsnew-en-GB` (bump commit); the spec gains a release record.

- [ ] **Step 1: Whole suite, sequentially**

Run: `flutter analyze`
Expected: no issues in any file this plan touched (the repo carries ~397 pre-existing ones elsewhere).
Then run: `flutter test`
Expected: all pass (baseline before this plan: 1314).

- [ ] **Step 2: Final code review** — dispatch one reviewer over `git diff 862e61cd..HEAD` against the
spec, with these risks called out: the worker never writes the main GetStorage box; the digest chain
and its manager-only gate are untouched; reminders never fire for the fallback shift or while the
heartbeat is quiet; no reminder repeats across runs (handled/posted keys) and none is lost on a late
run; the chain always re-arms (`finally`), including after a failed fetch; logout cancels work and
clears ids. Fix confirmed findings with `fix(attendance): …` commits and re-run Step 1.

- [ ] **Step 3: On-device smoke (Android, with the user)** — install the build and check:
  - a shift cut-off with the terminal syncing (reminder arrives) and with it quiet (no reminder, and a
    System Manager gets the terminal alert instead);
  - punching in after the heads-up clears it; the check-out reminder ~10 min after the shift ends;
  - the morning recap after a day with a late or missing check-out, and silence after a clean day;
  - Notifications settings: an employee sees Attendance reminders (on), a System Manager also sees
    Terminal alerts, a non-employee manager sees only the digest;
  - battery-saver timing: reminders still arrive, a few minutes late at worst.

- [ ] **Step 4: Release (only after the user approves)** — per `docs/versioning_conventions.md` and
the CI notes:

```bash
git fetch origin --tags
git log --oneline -1 origin/release/play-store   # expect 862e61cd unless someone released
dart run tool/bump_version.dart --minor          # dry-run; expect 2.18.0+61
dart run tool/bump_version.dart --minor --write
```

Set `whatsnew/whatsnew-en-GB` to one line: `Attendance reminders: your phone now reminds you to check
in before each shift's cut-off and to check out after it, tells you the next morning if a shift was
late or missed, and alerts System Managers when the attendance terminal goes quiet.` Commit
`chore(release): 2.18.0+61`, re-run `flutter test`, tag `git tag -a v2.18.0+61 -m "Release 2.18.0+61"`,
then `git push --atomic origin HEAD:release/play-store v2.18.0+61` and watch the "Release to Play
Store" run to success. Record the outcome in the spec as a release record, and update the local
`release/play-store` branch to the released commit.

⚠️ Merging, tagging and pushing need the user's explicit go-ahead (Global Constraints).
