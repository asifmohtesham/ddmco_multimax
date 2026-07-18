# Digest Alarm Alerting, iOS Reminders & Manager Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the shipped digest feature with a per-user alarm/standard alert toggle (two Android channels), iOS static scheduled reminders (generic text, no live counts), and a Manager-role-only gate.

**Architecture:** Android keeps WorkManager background-fetch with live counts but now posts on one of two new high-importance channels (insistent-alarm vs standard) chosen by a per-user pref. iOS, which cannot run code at fire time, uses pre-scheduled weekly `zonedSchedule` local notifications with generic text. `DigestScheduler.rearm()` gains a Manager gate and a platform branch (Android → WorkManager; iOS → reminder set). The whole feature is gated to users holding any `*Manager` role.

**Tech Stack:** Flutter 3.44 / Dart 3.12, GetX, `flutter_local_notifications ^22.0.1`, `workmanager ^0.9.0+3`, `timezone ^0.11.1`, `flutter_timezone ^5.1.0`.

## Global Constraints

- **Base:** `origin/release/play-store` @ `ee930539` (v2.12.2+53). Spec: `docs/superpowers/specs/2026-07-18-digest-alarm-alert-ios-manager-design.md`.
- **Manager rule (exact):** `roles.any((r) => r.toLowerCase().contains('manager'))` — mirrors `home_controller.dart` `showTasksFirst`.
- **Alert-style pref:** key `notif_digest_alarm_style::<user>`, values `'alarm'` | `'standard'`, **default `'standard'`**.
- **Android channels:** `pending_documents_alarm` (`Importance.max`, `AudioAttributesUsage.alarm`, strong vibration, FLAG_INSISTENT `additionalFlags: Int32List.fromList(<int>[4])`) and `pending_documents_alert` (`Importance.high`, notification audio, single vibration). Delete old `pending_documents`. Keep `kDigestNotificationId = 1001`.
- **iOS reminders:** `zonedSchedule` (v22 fully-named: `id:`, `scheduledDate:`, `notificationDetails:`, `androidScheduleMode:` required, `title:`, `body:`, `matchDateTimeComponents:`), `DateTimeComponents.dayOfWeekAndTime`, generic text `title: 'Pending documents'` / `body: 'You have documents to review — open Multimax'`, `InterruptionLevel.timeSensitive` for `alarm` else `InterruptionLevel.active`. Reserved id range base `2000`.
- **API exactness:** `deleteNotificationChannel(channelId: ...)` is NAMED. `flutter_timezone` returns `TimezoneInfo`; read `.identifier`. `IOSFlutterLocalNotificationsPlugin.requestPermissions(alert: true, badge: true, sound: true)`.
- **Platform detection:** UI gates use `defaultTargetPlatform` (override-able in widget tests). Non-UI code uses `dart:io Platform`; `DigestScheduler` takes an injected `bool? isIos` (defaults to `!kIsWeb && Platform.isIOS`) so unit tests can force the branch — the desktop test host reports neither Android nor iOS.
- **iOS native limits:** this repo builds on Windows; iOS-native config (`Runner.entitlements`, Xcode capability) is written as files but **cannot be built or smoke-tested here** — that is deferred to the user's Mac. iOS Dart logic IS analyzed + unit-tested on Windows.
- **Test doubles:** hand-written fakes (no mockito); `StorageService.withStorage(fake as dynamic)`; seeded user via GetStorage `'currentUser'` map. `flutter analyze` in this repo reports ~388 pre-existing infos / 0 errors (never "No issues found!"); invariant per task = 0 new errors + no new issues in changed files. Full-suite baseline ≈ the released count with 24 pre-existing failures — add zero new failures.
- **Branch:** `claude/scheduled-notifications-draft-docs-18a178` (reset to `ee930539`). Run `git branch --show-current` before every commit.
- **Versioning:** MINOR at release time; do NOT bump here.

---

### Task 1: Dependencies, timezone init, Android VIBRATE

**Files:**
- Modify: `pubspec.yaml` (dependencies)
- Modify: `lib/main.dart` (imports + tz init)
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: nothing.
- Produces: `package:timezone/timezone.dart`, `package:timezone/data/latest_all.dart`, `package:flutter_timezone/flutter_timezone.dart` importable; `tz.local` set at startup.

- [ ] **Step 1: Add deps to pubspec.yaml**

In `pubspec.yaml`, after the line `  flutter_local_notifications: ^22.0.1` add:

```yaml
  # iOS scheduled digest reminders need an explicit timezone for zonedSchedule.
  timezone: ^0.11.1
  flutter_timezone: ^5.1.0
```

- [ ] **Step 2: pub get**

Run: `flutter pub get`
Expected: `Got dependencies!` with `flutter_timezone 5.1.0` and `timezone 0.11.1` resolved.

- [ ] **Step 3: Initialize timezone in main.dart**

In `lib/main.dart` add imports (with the existing imports):

```dart
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
```

Immediately after `await GetStorage.init();` (line 34) add:

```dart
  // Timezone DB for iOS scheduled digest reminders (zonedSchedule throws
  // without tz.local set). iOS-only — Android uses WorkManager, not
  // zonedSchedule. Best-effort — a failure here must never block startup.
  if (!kIsWeb && Platform.isIOS) {
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Leaves tz.local unset; iOS reminder scheduling will no-op on failure.
    }
  }
```

- [ ] **Step 4: Add VIBRATE to the manifest**

In `android/app/src/main/AndroidManifest.xml`, after the `POST_NOTIFICATIONS` line add:

```xml
    <!-- Alarm-style digest alert vibration. (Also merged from the plugin;
         declared explicitly for self-documentation.) -->
    <uses-permission android:name="android.permission.VIBRATE"/>
```

- [ ] **Step 5: Analyze + Android build**

Run: `flutter analyze`
Expected: 0 new errors on `lib/main.dart`.
Run: `flutter build apk --debug`
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk` (proves flutter_timezone's Android side links).

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add pubspec.yaml pubspec.lock lib/main.dart android/app/src/main/AndroidManifest.xml
git commit -m "feat(notifications): add timezone deps + tz init + VIBRATE for alarm/iOS digest"
```

---

### Task 2: `User.isManager`

**Files:**
- Modify: `lib/app/data/models/user_model.dart` (after `hasRole`, line 91)
- Test: `test/unit/user_is_manager_test.dart`

**Interfaces:**
- Produces: `bool get isManager` on `User` (used by Tasks 7, 10).

- [ ] **Step 1: Write the failing test**

Create `test/unit/user_is_manager_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/user_model.dart';

User _u(List<String> roles) =>
    User(id: 'a@b.c', name: 'A', email: 'a@b.c', roles: roles);

void main() {
  group('User.isManager', () {
    test('true for any *Manager role (case-insensitive)', () {
      expect(_u(['Stock Manager']).isManager, isTrue);
      expect(_u(['System Manager']).isManager, isTrue);
      expect(_u(['Purchase Manager']).isManager, isTrue);
      expect(_u(['sales manager']).isManager, isTrue);
      expect(_u(['Stock User', 'Manufacturing Manager']).isManager, isTrue);
    });
    test('false when no role contains manager', () {
      expect(_u(['Stock User']).isManager, isFalse);
      expect(_u(['Employee', 'Sales User']).isManager, isFalse);
      expect(_u(const <String>[]).isManager, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/user_is_manager_test.dart`
Expected: FAIL — `The getter 'isManager' isn't defined for the type 'User'`.

- [ ] **Step 3: Implement the getter**

In `lib/app/data/models/user_model.dart`, replace the closing of the class (line 91):

```dart
  bool hasRole(String role) => roles.contains(role);
}
```

with:

```dart
  bool hasRole(String role) => roles.contains(role);

  /// True when the user holds any "*manager" role (case-insensitive) — System
  /// Manager, Stock/Purchase/Manufacturing/Sales Manager, or any custom
  /// "* Manager". Mirrors the dashboard persona rule
  /// (HomeController.showTasksFirst).
  bool get isManager =>
      roles.any((r) => r.toLowerCase().contains('manager'));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/user_is_manager_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/models/user_model.dart test/unit/user_is_manager_test.dart
git commit -m "feat(notifications): User.isManager helper for the digest manager gate"
```

---

### Task 3: Alarm-style preference on StorageService

**Files:**
- Modify: `lib/app/data/services/storage_service.dart` (key at line 45; methods after line 201)
- Test: `test/unit/storage_digest_alarm_style_test.dart`

**Interfaces:**
- Produces: `Future<void> saveDigestAlarmStyle(String user, String style)` and `String getDigestAlarmStyle(String user)` (default `'standard'`). Used by Tasks 4, 7, 8.

- [ ] **Step 1: Write the failing test**

Create `test/unit/storage_digest_alarm_style_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class _FakeGetStorage {
  final Map<String, dynamic> _data = {};
  Future<void> write(String key, dynamic value) async => _data[key] = value;
  Future<void> remove(String key) async => _data.remove(key);
  T? read<T>(String key) => _data[key] as T?;
  bool hasData(String key) => _data.containsKey(key);
  Map<String, dynamic> get raw => _data;
}

void main() {
  late StorageService service;
  late _FakeGetStorage box;
  const user = 'asif@example.com';

  setUp(() {
    box = _FakeGetStorage();
    service = StorageService.withStorage(box as dynamic);
  });

  test('defaults to standard', () {
    expect(service.getDigestAlarmStyle(user), 'standard');
  });

  test('round-trips per user', () async {
    await service.saveDigestAlarmStyle(user, 'alarm');
    expect(service.getDigestAlarmStyle(user), 'alarm');
    expect(service.getDigestAlarmStyle('other@x.com'), 'standard');
    expect(box.raw.containsKey('notif_digest_alarm_style::$user'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/storage_digest_alarm_style_test.dart`
Expected: FAIL — `getDigestAlarmStyle` not defined.

- [ ] **Step 3: Implement the pref**

In `lib/app/data/services/storage_service.dart`, after the key `_digestDoctypesKey` (line 45) add:

```dart
  static const String _digestAlarmStyleKey = 'notif_digest_alarm_style';
```

and after `getDigestDoctypes` (after line 201) add:

```dart
  Future<void> saveDigestAlarmStyle(String user, String style) async =>
      _box.write('$_digestAlarmStyleKey::$user', style);

  /// 'alarm' (insistent) or 'standard' (single sound + vibration). Default
  /// 'standard' — least-surprising for existing enabled managers.
  String getDigestAlarmStyle(String user) =>
      _box.read<String>('$_digestAlarmStyleKey::$user') ?? 'standard';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/storage_digest_alarm_style_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/storage_service.dart test/unit/storage_digest_alarm_style_test.dart
git commit -m "feat(notifications): per-user digest alarm-style pref (default standard)"
```

---

### Task 4: Android two-channel alarm/standard posting

**Files:**
- Modify: `lib/app/data/services/digest_worker.dart`
- Test: none new (untestable plugin glue — the decision logic is a pref read tested in Task 3; verified by analyze + on-device smoke)

**Interfaces:**
- Consumes: `StorageService.getDigestAlarmStyle` (Task 3), `User.isManager` (Task 2).
- Produces: constants `kDigestAlarmChannelId = 'pending_documents_alarm'`, `kDigestAlertChannelId = 'pending_documents_alert'` (referenced by no other task; internal).

- [ ] **Step 0: Add the worker manager gate**

In `runDigestTask` (lines 42–44), after the null-user early return add a manager early-return so a task queued before the user lost the role does not fire:

```dart
  final user = storage.getUser();
  if (user == null) return; // logged out since scheduling — do nothing
  if (!user.isManager) return; // role revoked since scheduling
  if (!storage.getDigestEnabled(user.id)) return;
```

- [ ] **Step 1: Add the typed_data import + channel constants**

In `lib/app/data/services/digest_worker.dart`, add at the top of the imports (after line 8 `library;`, before line 9):

```dart
import 'dart:typed_data';
```

Replace the constants block (lines 18–22):

```dart
const int kDigestNotificationId = 1001;
const String kDigestChannelId = 'pending_documents';
const String _kChannelName = 'Pending documents';
const String _kChannelDescription =
    'Scheduled digest of documents needing action';
```

with:

```dart
const int kDigestNotificationId = 1001;
// The released default-importance channel — deleted so it doesn't linger as a
// stale, silent entry once the two new channels exist.
const String _kOldChannelId = 'pending_documents';
const String kDigestAlarmChannelId = 'pending_documents_alarm';
const String kDigestAlertChannelId = 'pending_documents_alert';
const String _kAlarmChannelName = 'Pending documents (alarm)';
const String _kAlertChannelName = 'Pending documents';
const String _kChannelDescription =
    'Scheduled digest of documents needing action';
```

- [ ] **Step 2: Replace the notify block with style-driven channels**

In `runDigestTask`, replace the whole `if (plan.show) { ... }` block (lines 63–90) with:

```dart
    if (plan.show) {
      final isAlarm = storage.getDigestAlarmStyle(user.id) == 'alarm';
      final fln = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await fln.initialize(
          settings: const InitializationSettings(android: androidInit));
      final android = fln.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Retire the old default-importance channel and (idempotently) create the
      // two new ones. Channel sound/importance is immutable after creation, so
      // each alert style gets its own pre-configured channel.
      await android?.deleteNotificationChannel(channelId: _kOldChannelId);
      await android?.createNotificationChannel(AndroidNotificationChannel(
        kDigestAlarmChannelId,
        _kAlarmChannelName,
        description: _kChannelDescription,
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern:
            Int64List.fromList(<int>[0, 500, 250, 500, 250, 500]),
      ));
      await android?.createNotificationChannel(AndroidNotificationChannel(
        kDigestAlertChannelId,
        _kAlertChannelName,
        description: _kChannelDescription,
        importance: Importance.high,
        enableVibration: true,
        vibrationPattern: Int64List.fromList(<int>[0, 400]),
      ));

      final channelId = isAlarm ? kDigestAlarmChannelId : kDigestAlertChannelId;
      final channelName = isAlarm ? _kAlarmChannelName : _kAlertChannelName;
      await fln.show(
        id: kDigestNotificationId, // fixed id: new digest replaces the old one
        title: plan.title,
        body: plan.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: _kChannelDescription,
            importance: isAlarm ? Importance.max : Importance.high,
            priority: isAlarm ? Priority.max : Priority.high,
            category:
                isAlarm ? AndroidNotificationCategory.alarm : null,
            audioAttributesUsage: isAlarm
                ? AudioAttributesUsage.alarm
                : AudioAttributesUsage.notification,
            styleInformation: BigTextStyleInformation(plan.body ?? ''),
            // FLAG_INSISTENT (4): loops the sound until dismissed/opened.
            additionalFlags:
                isAlarm ? Int32List.fromList(<int>[4]) : null,
          ),
        ),
      );
    }
```

- [ ] **Step 3: Update cancelDigestOnLogout to clear the notification (no channel refs)**

`cancelDigestOnLogout` (lines 99–110) references no channel constants — it only calls `fln.cancel(id: kDigestNotificationId)`. Leave it unchanged. Verify it still compiles (it does — it uses only `kDigestNotificationId` and `kDigestUniqueName`).

- [ ] **Step 4: Analyze + full suite (regression)**

Run: `flutter analyze`
Expected: 0 new errors on `digest_worker.dart` (in particular the v22 named `deleteNotificationChannel(channelId:)`, `Int64List`/`Int32List`, `AudioAttributesUsage.alarm`, `AndroidNotificationCategory.alarm`, `Priority.max` all resolve).
Run: `flutter test`
Expected: baseline unchanged (no new failures).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/digest_worker.dart
git commit -m "feat(notifications): alarm/standard Android digest channels driven by style pref"
```

---

### Task 5: iOS reminder specs (pure)

**Files:**
- Create: `lib/app/data/services/reminder_scheduler.dart` (pure part only in this task)
- Test: `test/unit/reminder_specs_test.dart`

**Interfaces:**
- Produces (used by Tasks 6, 7):
  - `const int kIosReminderIdBase = 2000;`
  - `class ReminderSpec { final int id; final int weekday; final int hour; final int minute; }`
  - `List<ReminderSpec> buildReminderSpecs({required List<String> times, required Set<int> weekdays})` — deterministic id/weekday/time set, invalid times skipped, empty inputs → empty.
  - `List<int> reservedIosReminderIds()` — the full id range to cancel.

- [ ] **Step 1: Write the failing test**

Create `test/unit/reminder_specs_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/reminder_scheduler.dart';

void main() {
  group('buildReminderSpecs', () {
    test('one spec per weekday x time, sorted, correct ids', () {
      final specs = buildReminderSpecs(
          times: ['16:00', '09:00'], weekdays: {3, 1});
      // weekdays sorted [1,3]; times sorted [09:00(idx0), 16:00(idx1)].
      expect(specs.map((s) => (s.weekday, s.hour, s.minute)).toList(), [
        (1, 9, 0),
        (1, 16, 0),
        (3, 9, 0),
        (3, 16, 0),
      ]);
      // id = base + (weekday-1)*8 + timeIndex
      expect(specs.map((s) => s.id).toList(), [
        kIosReminderIdBase + 0 * 8 + 0,
        kIosReminderIdBase + 0 * 8 + 1,
        kIosReminderIdBase + 2 * 8 + 0,
        kIosReminderIdBase + 2 * 8 + 1,
      ]);
      // ids are unique
      expect(specs.map((s) => s.id).toSet().length, specs.length);
    });

    test('invalid time strings are skipped', () {
      final specs =
          buildReminderSpecs(times: ['9am', '09:00'], weekdays: {1});
      expect(specs.length, 1);
      expect(specs.single.hour, 9);
    });

    test('empty times or weekdays -> empty', () {
      expect(buildReminderSpecs(times: [], weekdays: {1}), isEmpty);
      expect(buildReminderSpecs(times: ['09:00'], weekdays: {}), isEmpty);
    });

    test('out-of-range weekdays skipped', () {
      final specs = buildReminderSpecs(times: ['09:00'], weekdays: {0, 8, 5});
      expect(specs.map((s) => s.weekday).toList(), [5]);
    });
  });

  group('reservedIosReminderIds', () {
    test('covers every possible spec id and is distinct from 1001', () {
      final ids = reservedIosReminderIds();
      expect(ids, contains(kIosReminderIdBase));
      expect(ids.contains(1001), isFalse);
      // every buildable id is inside the reserved set
      final built = buildReminderSpecs(
              times: ['00:00', '06:00', '12:00', '18:00'],
              weekdays: {1, 2, 3, 4, 5, 6, 7})
          .map((s) => s.id);
      expect(built.every(ids.contains), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/reminder_specs_test.dart`
Expected: FAIL — file/symbols not found.

- [ ] **Step 3: Create the pure part of reminder_scheduler.dart**

Create `lib/app/data/services/reminder_scheduler.dart`:

```dart
/// iOS scheduled digest reminders — pure spec computation plus a plugin seam.
///
/// GetX-free. The spec computation is pure (no plugin, no timezone) so it is
/// unit-tested; the actual zonedSchedule calls live in [FlnReminderScheduler].
library;

/// First id of the reserved range for iOS digest reminders (distinct from the
/// Android digest notification id 1001).
const int kIosReminderIdBase = 2000;

/// 8 id slots per weekday leaves headroom above the 4-times cap while keeping
/// the whole reserved range (7 x 8 = 56 ids) well under iOS's 64-pending limit.
const int _slotsPerDay = 8;

/// One scheduled weekly reminder: fire on [weekday] (1=Mon..7=Sun) at
/// [hour]:[minute], under notification id [id].
class ReminderSpec {
  final int id;
  final int weekday;
  final int hour;
  final int minute;
  const ReminderSpec({
    required this.id,
    required this.weekday,
    required this.hour,
    required this.minute,
  });
}

/// Deterministic (weekday x time) reminder set. Times are parsed/validated and
/// sorted; invalid `HH:mm` strings and out-of-range weekdays are skipped.
List<ReminderSpec> buildReminderSpecs({
  required List<String> times,
  required Set<int> weekdays,
}) {
  final parsed = <(int, int)>[];
  for (final t in times) {
    final parts = t.split(':');
    if (parts.length != 2) continue;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) continue;
    parsed.add((h, m));
  }
  parsed.sort((a, b) => (a.$1 * 60 + a.$2).compareTo(b.$1 * 60 + b.$2));

  final days = weekdays.where((d) => d >= 1 && d <= 7).toList()..sort();

  final specs = <ReminderSpec>[];
  for (final wd in days) {
    for (var i = 0; i < parsed.length; i++) {
      specs.add(ReminderSpec(
        id: kIosReminderIdBase + (wd - 1) * _slotsPerDay + i,
        weekday: wd,
        hour: parsed[i].$1,
        minute: parsed[i].$2,
      ));
    }
  }
  return specs;
}

/// Every id the reminder set could ever occupy — cancel these to fully clear a
/// prior schedule before rescheduling (or on logout).
List<int> reservedIosReminderIds() =>
    [for (var i = 0; i < 7 * _slotsPerDay; i++) kIosReminderIdBase + i];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/reminder_specs_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/reminder_scheduler.dart test/unit/reminder_specs_test.dart
git commit -m "feat(notifications): pure iOS reminder-spec computation"
```

---

### Task 6: ReminderScheduler seam + zonedSchedule glue

**Files:**
- Modify: `lib/app/data/services/reminder_scheduler.dart` (append)
- Test: none new (plugin + timezone glue — the spec math is tested in Task 5; verified by analyze + iOS on-device smoke)

**Interfaces:**
- Consumes: `ReminderSpec`, `buildReminderSpecs`, `reservedIosReminderIds` (Task 5).
- Produces (used by Task 7 / Task 11):
  - `abstract class ReminderScheduler { Future<void> reschedule(List<ReminderSpec> specs, {required bool timeSensitive}); Future<void> cancelAll(); }`
  - `class FlnReminderScheduler implements ReminderScheduler`
  - `Future<void> cancelIosDigestReminders()` (logout teardown)

- [ ] **Step 1: Append the seam + implementation**

At the top of `lib/app/data/services/reminder_scheduler.dart` add imports (below `library;`):

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
```

At the end of the file append:

```dart
/// Seam over flutter_local_notifications so DigestScheduler stays testable.
abstract class ReminderScheduler {
  /// Cancel any prior reminders and (re)schedule the given weekly set.
  Future<void> reschedule(List<ReminderSpec> specs,
      {required bool timeSensitive});

  /// Cancel the whole reserved reminder range.
  Future<void> cancelAll();
}

class FlnReminderScheduler implements ReminderScheduler {
  static const String _title = 'Pending documents';
  static const String _body = 'You have documents to review — open Multimax';

  Future<FlutterLocalNotificationsPlugin> _plugin() async {
    final fln = FlutterLocalNotificationsPlugin();
    await fln.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    return fln;
  }

  @override
  Future<void> reschedule(List<ReminderSpec> specs,
      {required bool timeSensitive}) async {
    final fln = await _plugin();
    for (final id in reservedIosReminderIds()) {
      await fln.cancel(id: id);
    }
    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: timeSensitive
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );
    for (final s in specs) {
      await fln.zonedSchedule(
        id: s.id,
        title: _title,
        body: _body,
        scheduledDate: _nextInstanceOf(s.weekday, s.hour, s.minute),
        notificationDetails: details,
        // Required by the signature; irrelevant on iOS (this path is iOS-only).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    final fln = await _plugin();
    for (final id in reservedIosReminderIds()) {
      await fln.cancel(id: id);
    }
  }

  tz.TZDateTime _nextInstanceOf(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

/// Logout teardown for iOS: cancel every scheduled digest reminder. Best-effort.
Future<void> cancelIosDigestReminders() async {
  try {
    final fln = FlutterLocalNotificationsPlugin();
    await fln.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    for (final id in reservedIosReminderIds()) {
      await fln.cancel(id: id);
    }
  } catch (_) {
    // Never block logout on notification plumbing.
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 new errors on `reminder_scheduler.dart` — in particular the v22 fully-named `zonedSchedule` (required `androidScheduleMode:`), `DarwinNotificationDetails`, `InterruptionLevel.timeSensitive`, `DateTimeComponents.dayOfWeekAndTime`, `AndroidScheduleMode.inexactAllowWhileIdle` resolve.

- [ ] **Step 3: Full suite (regression)**

Run: `flutter test`
Expected: baseline unchanged (Task 5's specs test still green).

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add lib/app/data/services/reminder_scheduler.dart
git commit -m "feat(notifications): iOS zonedSchedule reminder scheduler + logout teardown"
```

---

### Task 7: DigestScheduler — manager gate + platform branch

**Files:**
- Modify: `lib/app/data/services/digest_scheduler.dart`
- Modify: `test/unit/digest_scheduler_test.dart` (seed a manager role; add fake ReminderScheduler + new cases)

**Interfaces:**
- Consumes: `User.isManager` (Task 2), `ReminderScheduler`/`FlnReminderScheduler`/`buildReminderSpecs` (Tasks 5/6), `StorageService.getDigestAlarmStyle` (Task 3).
- Produces: `DigestScheduler({StorageService? storage, WorkScheduler? work, ReminderScheduler? reminders, DateTime Function()? now, bool? isIos})` with a Manager-gated, platform-branching `rearm()`. Used by controller (Task 8), main.dart (Task 11), worker (unchanged call).

- [ ] **Step 1: Write the failing tests**

Replace the helper block and add cases in `test/unit/digest_scheduler_test.dart`. First, update the `userJson` used by the seed to include a manager role, and add a fake ReminderScheduler. Add these helpers near the top (after the existing `_FakeWork`, before `main()`):

```dart
class _FakeReminders implements ReminderScheduler {
  final rescheduled = <List<ReminderSpec>>[];
  bool? lastTimeSensitive;
  int cancelAllCount = 0;

  @override
  Future<void> reschedule(List<ReminderSpec> specs,
      {required bool timeSensitive}) async {
    rescheduled.add(specs);
    lastTimeSensitive = timeSensitive;
  }

  @override
  Future<void> cancelAll() async => cancelAllCount++;
}
```

Add this import at the top of the test:

```dart
import 'package:multimax/app/data/services/reminder_scheduler.dart';
```

In the existing test body, the seeded user map must now carry a manager role. Wherever the test seeds `currentUser` (e.g. `box._data['currentUser'] = userJson`), ensure `userJson` is:

```dart
  const userJson = {
    'name': 'asif@example.com',
    'full_name': 'Asif',
    'email': 'asif@example.com',
    'roles': [
      {'role': 'Stock Manager'}
    ],
  };
```

Then add these new tests inside `main()`:

```dart
  test('non-manager user -> cancel, never arms (Android path)', () async {
    box._data['currentUser'] = {
      'name': 'op@example.com',
      'full_name': 'Op',
      'email': 'op@example.com',
      'roles': [
        {'role': 'Stock User'}
      ],
    };
    await storage.saveDigestEnabled('op@example.com', true);
    final work = _FakeWork();
    final scheduler = DigestScheduler(
        storage: storage, work: work, now: () => now, isIos: false);
    await scheduler.rearm();
    expect(work.registered, isEmpty);
    expect(work.cancelled, [kDigestUniqueName]);
  });

  test('iOS manager -> reschedules the reminder set, timeSensitive from style',
      () async {
    box._data['currentUser'] = userJson; // manager
    await storage.saveDigestEnabled('asif@example.com', true);
    await storage.saveDigestTimes('asif@example.com', ['09:00']);
    await storage.saveDigestDays('asif@example.com', [1, 2]);
    await storage.saveDigestAlarmStyle('asif@example.com', 'alarm');
    final reminders = _FakeReminders();
    final scheduler = DigestScheduler(
        storage: storage, reminders: reminders, now: () => now, isIos: true);
    await scheduler.rearm();
    expect(reminders.rescheduled.single.map((s) => (s.weekday, s.hour)).toList(),
        [(1, 9), (2, 9)]);
    expect(reminders.lastTimeSensitive, isTrue);
  });

  test('iOS non-manager -> cancelAll reminders, no reschedule', () async {
    box._data['currentUser'] = {
      'name': 'op@example.com',
      'full_name': 'Op',
      'email': 'op@example.com',
      'roles': [
        {'role': 'Sales User'}
      ],
    };
    await storage.saveDigestEnabled('op@example.com', true);
    final reminders = _FakeReminders();
    final scheduler = DigestScheduler(
        storage: storage, reminders: reminders, now: () => now, isIos: true);
    await scheduler.rearm();
    expect(reminders.rescheduled, isEmpty);
    expect(reminders.cancelAllCount, greaterThan(0));
  });
```

(Existing arm/cancel tests keep working once the seeded user carries the `Stock Manager` role and the schedulers they build pass `isIos: false`. Update each existing `DigestScheduler(...)` construction in this file to pass `isIos: false` so they deterministically take the Android path on the desktop test host.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/digest_scheduler_test.dart`
Expected: FAIL — `isIos` / `reminders` params and the manager gate don't exist yet (and non-manager cases fail).

- [ ] **Step 3: Implement the gate + branch**

In `lib/app/data/services/digest_scheduler.dart`, add imports (after line 7):

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:multimax/app/data/services/reminder_scheduler.dart';
```

Replace the whole `DigestScheduler` class (lines 84–126) with:

```dart
class DigestScheduler {
  final StorageService _storage;
  final WorkScheduler _work;
  final ReminderScheduler _reminders;
  final DateTime Function() _now;
  final bool _isIos;

  DigestScheduler({
    StorageService? storage,
    WorkScheduler? work,
    ReminderScheduler? reminders,
    DateTime Function()? now,
    bool? isIos,
  })  : _storage = storage ?? StorageService(),
        _work = work ?? WorkmanagerScheduler(),
        _reminders = reminders ?? FlnReminderScheduler(),
        _now = now ?? DateTime.now,
        _isIos = isIos ?? (!kIsWeb && Platform.isIOS);

  Future<void> rearm() async {
    final user = _storage.getUser();
    // Manager-only, enabled, and at least one doctype selected — otherwise the
    // schedule is dead and everything is cancelled.
    final live = user != null &&
        user.isManager &&
        _storage.getDigestEnabled(user.id) &&
        _storage.getDigestDoctypes(user.id).isNotEmpty;
    if (!live) {
      await _cancelAll();
      return;
    }

    final times = _storage.getDigestTimes(user!.id);
    final weekdays = _storage.getDigestDays(user.id).toSet();

    if (_isIos) {
      final specs = buildReminderSpecs(times: times, weekdays: weekdays);
      if (specs.isEmpty) {
        await _cancelAll();
        return;
      }
      final timeSensitive = _storage.getDigestAlarmStyle(user.id) == 'alarm';
      await _reminders.reschedule(specs, timeSensitive: timeSensitive);
      return;
    }

    final now = _now();
    final next =
        nextDigestOccurrence(after: now, times: times, weekdays: weekdays);
    if (next == null) {
      await _cancelAll();
      return;
    }
    await _work.registerOneOff(
      uniqueName: kDigestUniqueName,
      taskName: kDigestTaskName,
      initialDelay: next.difference(now),
    );
  }

  Future<void> _cancelAll() async {
    if (_isIos) {
      await _reminders.cancelAll();
    } else {
      await _work.cancel(kDigestUniqueName);
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/digest_scheduler_test.dart`
Expected: PASS (existing arm/cancel cases + the 3 new ones).

- [ ] **Step 5: Full suite (regression)**

Run: `flutter test`
Expected: baseline unchanged (the worker's unchanged `DigestScheduler(storage: storage).rearm()` call still compiles — `isIos` defaults, and on a real Android device it resolves to the Android path).

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add lib/app/data/services/digest_scheduler.dart test/unit/digest_scheduler_test.dart
git commit -m "feat(notifications): manager gate + iOS/Android branch in DigestScheduler"
```

---

### Task 8: Controller — alarm style + iOS permission

**Files:**
- Modify: `lib/app/modules/notification_settings/notification_settings_controller.dart`
- Modify: `test/unit/notification_settings_controller_test.dart`

**Interfaces:**
- Consumes: `StorageService.getDigestAlarmStyle`/`saveDigestAlarmStyle` (Task 3), `DigestScheduler.rearm` (Task 7).
- Produces: `RxString`-like `alarmStyle` observable + `Future<void> setAlarmStyle(String)`; a platform-branching `requestNotificationsPermission()`. Used by the screen (Task 9).

- [ ] **Step 1: Write the failing tests**

In `test/unit/notification_settings_controller_test.dart`, add (inside `main()`, reusing the existing fakes/setup):

```dart
  test('loads alarm style default standard on init', () {
    final c = build()..onInit();
    expect(c.alarmStyle.value, 'standard');
  });

  test('setAlarmStyle persists and re-arms', () async {
    final c = build()..onInit();
    await c.setAlarmStyle('alarm');
    expect(c.alarmStyle.value, 'alarm');
    expect(storage.getDigestAlarmStyle(user), 'alarm');
    expect(scheduler.rearms, greaterThan(0));
  });
```

(`build()`, `storage`, `scheduler`, `user` are the existing test's helpers — `scheduler` is the `_CountingScheduler`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/notification_settings_controller_test.dart`
Expected: FAIL — `alarmStyle` / `setAlarmStyle` not defined.

- [ ] **Step 3: Implement alarm style + iOS permission branch**

In `lib/app/modules/notification_settings/notification_settings_controller.dart`, add imports (after line 1):

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
```

Replace the `requestNotificationsPermission` free function (lines 10–15) with:

```dart
/// Requests the platform notification permission. Kept as a free function so
/// the controller can take a test seam instead of touching the plugin.
Future<bool> requestNotificationsPermission() async {
  final plugin = FlutterLocalNotificationsPlugin();
  if (!kIsWeb && Platform.isIOS) {
    final ios = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
            alert: true, badge: true, sound: true) ??
        false;
  }
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? false;
}
```

Add the observable (after `doctypeKeys`, line 35):

```dart
  final alarmStyle = 'standard'.obs;
```

In `onInit` (after line 45 `doctypeKeys.assignAll(...)`) add:

```dart
    alarmStyle.value = _storage.getDigestAlarmStyle(_user);
```

Add the setter (after `_persistTimes`, before the closing brace):

```dart
  /// 'standard' | 'alarm'. Re-arms because on iOS the interruption level is
  /// baked into the scheduled reminders (Android reads it at post time, where
  /// a re-arm is a harmless no-op).
  Future<void> setAlarmStyle(String style) async {
    alarmStyle.value = style;
    await _storage.saveDigestAlarmStyle(_user, style);
    await _scheduler.rearm();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/notification_settings_controller_test.dart`
Expected: PASS (new + existing).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/notification_settings/notification_settings_controller.dart test/unit/notification_settings_controller_test.dart
git commit -m "feat(notifications): alarm-style setting + iOS permission request in controller"
```

---

### Task 9: Settings screen — alert-style control + iOS Documents hide

**Files:**
- Modify: `lib/app/modules/notification_settings/notification_settings_screen.dart`
- Modify: `test/widget/notification_settings_screen_test.dart`

**Interfaces:**
- Consumes: `controller.alarmStyle` / `controller.setAlarmStyle` (Task 8), `SettingsSegmented`/`SegmentOption` (existing).
- Produces: UI only.

- [ ] **Step 1: Write the failing widget tests**

In `test/widget/notification_settings_screen_test.dart`: at the top of `main()` capture and restore the platform override, and add cases. Add these inside `main()`:

```dart
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Android: shows Documents + alert-style segments', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pump(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('DOCUMENTS'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('ALERT STYLE'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Alarm'), findsOneWidget);
  });

  testWidgets('iOS: hides Documents, keeps alert-style', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('DOCUMENTS'), findsNothing);
    expect(find.text('ALERT STYLE'), findsOneWidget);
  });
```

Add `import 'package:flutter/foundation.dart';` to the test if not present (for `debugDefaultTargetPlatformOverride` / `TargetPlatform`). If an existing test asserts the Documents section, wrap its setup with `debugDefaultTargetPlatformOverride = TargetPlatform.android;` so it keeps seeing Documents.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/notification_settings_screen_test.dart`
Expected: FAIL — no ALERT STYLE section; Documents shown regardless of platform.

- [ ] **Step 3: Implement the screen changes**

In `lib/app/modules/notification_settings/notification_settings_screen.dart` add the import (after line 2):

```dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
```

In the `if (controller.enabled.value) ...[` block, replace the `Documents` `SettingsGroup` (lines 59–70) with an **Alert style** group followed by the platform-gated Documents group:

```dart
                const SizedBox(height: AppSpace.s4),
                SettingsGroup(
                  label: 'Alert style',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.s3),
                      child: SettingsSegmented<String>(
                        value: controller.alarmStyle.value,
                        onChanged: controller.setAlarmStyle,
                        options: const [
                          SegmentOption(
                              value: 'standard',
                              label: 'Standard',
                              icon: Icons.notifications_active_outlined),
                          SegmentOption(
                              value: 'alarm',
                              label: 'Alarm',
                              icon: Icons.alarm),
                        ],
                      ),
                    ),
                  ],
                ),
                // iOS reminders are generic text (no per-doctype counts), so
                // the Documents selector only applies on Android.
                if (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android) ...[
                  const SizedBox(height: AppSpace.s4),
                  SettingsGroup(
                    label: 'Documents',
                    children: [
                      for (final d in kDigestDoctypes)
                        SettingsSwitchRow(
                          title: d.doctype,
                          value: controller.doctypeKeys.contains(d.key),
                          onChanged: (_) => controller.toggleDoctype(d.key),
                        ),
                    ],
                  ),
                ],
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/notification_settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `flutter analyze`
Expected: 0 new errors on the screen.

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add lib/app/modules/notification_settings/notification_settings_screen.dart test/widget/notification_settings_screen_test.dart
git commit -m "feat(notifications): alert-style segmented control; hide Documents on iOS"
```

---

### Task 10: User Area entry — manager + iOS gate

**Files:**
- Modify: `lib/app/modules/user_area/user_area_screen.dart`
- Test: `test/widget/user_area_notifications_entry_test.dart`

**Interfaces:**
- Consumes: `User.isManager` (Task 2); `controller.user.value` (existing — the profile card reads `controller.user.value`).
- Produces: UI only.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/user_area_notifications_entry_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/user_area/user_area_controller.dart';
import 'package:multimax/app/modules/user_area/user_area_screen.dart';

class _FakeUserAreaController extends UserAreaController {
  final User? seed;
  _FakeUserAreaController(this.seed);
  @override
  void onInit() {} // skip real service wiring
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    Get.deleteAll(force: true);
  });

  Future<void> pumpWith(WidgetTester tester, User? user) async {
    final c = _FakeUserAreaController(user);
    c.user.value = user;
    Get.put<UserAreaController>(c);
    await tester.pumpWidget(const GetMaterialApp(home: UserAreaScreen()));
    await tester.pumpAndSettle();
  }

  User _mgr() => User(
      id: 'a', name: 'A', email: 'a', roles: const ['Stock Manager']);
  User _op() =>
      User(id: 'b', name: 'B', email: 'b', roles: const ['Stock User']);

  testWidgets('Android manager sees Notifications entry', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpWith(tester, _mgr());
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('Android non-manager does not', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpWith(tester, _op());
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('iOS manager sees it too', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpWith(tester, _mgr());
    expect(find.text('Notifications'), findsOneWidget);
  });
}
```

Note: if `UserAreaController` cannot be subclassed cleanly (e.g. required constructor args or a non-virtual `onInit`), fall back to constructing the real controller with its test-friendly path and setting `controller.user.value`; adapt the fake to the real controller's shape and report the adaptation.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/user_area_notifications_entry_test.dart`
Expected: FAIL — the entry is currently gated `if (!kIsWeb && Platform.isAndroid)` with no manager check (non-manager test fails; iOS test fails).

- [ ] **Step 3: Implement the gate**

In `lib/app/modules/user_area/user_area_screen.dart`, replace the `dart:io` import (line 1) with a foundation import (the file already imports `kIsWeb` on line 3):

```dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
```

(Remove `import 'dart:io' show Platform;` on line 1 — `Platform` is no longer used here. If `Platform` is used elsewhere in the file, keep both imports.)

Replace the Notifications `SettingsRow` gate (lines 47–53):

```dart
                if (!kIsWeb && Platform.isAndroid)
                  SettingsRow(
                    icon: Icons.notifications_outlined,
                    iconTint: AppColors.orange500,
                    title: 'Notifications',
                    onTap: () => Get.toNamed(AppRoutes.NOTIFICATION_SETTINGS),
                  ),
```

with:

```dart
                Obx(() {
                  final isMobile = !kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.android ||
                          defaultTargetPlatform == TargetPlatform.iOS);
                  final isManager =
                      controller.user.value?.isManager ?? false;
                  if (!isMobile || !isManager) return const SizedBox.shrink();
                  return SettingsRow(
                    icon: Icons.notifications_outlined,
                    iconTint: AppColors.orange500,
                    title: 'Notifications',
                    onTap: () => Get.toNamed(AppRoutes.NOTIFICATION_SETTINGS),
                  );
                }),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/user_area_notifications_entry_test.dart`
Expected: PASS. If the fake-controller approach needed adaptation, note it in the report.

- [ ] **Step 5: Analyze + full suite**

Run: `flutter analyze`
Expected: 0 new errors; no unused `dart:io`/`Platform` import warning in `user_area_screen.dart`.
Run: `flutter test`
Expected: baseline unchanged.

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add lib/app/modules/user_area/user_area_screen.dart test/widget/user_area_notifications_entry_test.dart
git commit -m "feat(notifications): gate Notifications entry to managers on Android + iOS"
```

---

### Task 11: App wiring — iOS launch/login re-arm + logout teardown

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app/modules/auth/authentication_controller.dart`

**Interfaces:**
- Consumes: `DigestScheduler.rearm` (Task 7), `cancelIosDigestReminders` (Task 6), `cancelDigestOnLogout` (existing).
- Produces: iOS reminders armed on launch/login, cancelled on logout.

- [ ] **Step 1: Broaden the launch re-arm in main.dart**

In `lib/main.dart`, replace the launch re-arm block (lines 91–95):

```dart
  // Self-heal a broken digest chain (crash/force-stop) on every launch.
  // Fire-and-forget: startup must never block on WorkManager.
  if (!kIsWeb && Platform.isAndroid && authController.isAuthenticated.value) {
    unawaited(DigestScheduler().rearm().catchError((_) {}));
  }
```

with:

```dart
  // Self-heal the digest schedule on every launch (Android: WorkManager chain;
  // iOS: the weekly reminder set). Fire-and-forget — startup never blocks.
  if (!kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      authController.isAuthenticated.value) {
    unawaited(DigestScheduler().rearm().catchError((_) {}));
  }
```

(The Android-only `Workmanager().initialize(...)` block at lines 38–40 stays Android-only — iOS uses no background isolate.)

- [ ] **Step 2: Broaden login re-arm + add iOS logout teardown in authentication_controller.dart**

In `lib/app/modules/auth/authentication_controller.dart`:

- Add import: `import 'package:multimax/app/data/services/reminder_scheduler.dart';` (keep the existing `digest_worker`/`digest_scheduler` imports).
- Find the post-login re-arm block (the `if (!kIsWeb && Platform.isAndroid) { unawaited(DigestScheduler().rearm()...); }` added by the shipped feature in `fetchUserDetails`) and change its condition to:

```dart
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
            unawaited(DigestScheduler().rearm().catchError((_) {}));
          }
```

- Find the logout teardown in `_clearSessionAndLocalData` (the `if (!kIsWeb && Platform.isAndroid) { await cancelDigestOnLogout(); }` block) and change it to:

```dart
    if (!kIsWeb && Platform.isAndroid) {
      await cancelDigestOnLogout();
    }
    if (!kIsWeb && Platform.isIOS) {
      await cancelIosDigestReminders();
    }
```

READ the file first to match the exact surrounding lines; adapt if they differ and note it.

- [ ] **Step 3: Analyze + affected tests + full suite**

Run: `flutter analyze`
Expected: 0 new errors.
Run: `flutter test test/unit/user_area_controller_test.dart test/unit/user_profile_logout_removed_test.dart test/unit/connect_to_instance_controller_test.dart`
Expected: pass (the new iOS-gated calls are inert on the desktop test host — `Platform.isIOS` is false there).
Run: `flutter test`
Expected: baseline unchanged.

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add lib/main.dart lib/app/modules/auth/authentication_controller.dart
git commit -m "feat(notifications): arm/cancel iOS digest reminders on launch, login, logout"
```

---

### Task 12: iOS native config + final verification

**Files:**
- Create: `ios/Runner/Runner.entitlements`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: everything above.
- Produces: verified branch; iOS entitlement artifact for the Mac build.

- [ ] **Step 1: Create the iOS entitlements file**

Create `ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.usernotifications.time-sensitive</key>
	<true/>
</dict>
</plist>
```

Note in the report: on the Mac, this must be wired into the Xcode project — open `ios/Runner.xcworkspace` → Runner target → Signing & Capabilities → **+ Capability → Time Sensitive Notifications** (this sets `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` for both Debug and Release, and enables the capability on the App ID). Without this wiring, `InterruptionLevel.timeSensitive` silently downgrades. This step cannot be performed or verified on Windows.

- [ ] **Step 2: Full analyze + suite**

Run: `flutter analyze`
Expected: 0 errors (record the info/warning count; compare to the ~388 pre-existing baseline — no new issues in changed files).
Run: `flutter test`
Expected: no failures beyond the pre-existing ~24 (record counts; the feature's new unit/widget tests all pass).

- [ ] **Step 3: Android debug build**

Run: `flutter build apk --debug`
Expected: builds clean (proves the alarm channel APIs + flutter_timezone Android side link).

- [ ] **Step 4: CHANGELOG entry**

Prepend to `CHANGELOG.md`, matching the file's `## [Unreleased] — <Title>` heading convention:

```markdown
## [Unreleased] — Digest Alerts: Alarm Style, iOS Reminders, Manager Gate

- Scheduled digest notifications are now available only to **Manager** roles
  (any "* Manager" role), on both Android and iOS.
- New **Alert style** toggle: *Standard* (single sound + vibration) or *Alarm*
  (insistent, alarm-volume, loops until dismissed) — default Standard.
- **iOS support**: the digest now delivers as reliable scheduled reminders at
  the chosen times (generic text — iOS cannot query live counts in the
  background; the per-document selector is Android-only). Time-Sensitive when
  Alarm style is selected.
```

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add ios/Runner/Runner.entitlements CHANGELOG.md
git commit -m "feat(notifications): iOS time-sensitive entitlement + changelog"
```

- [ ] **Step 6: Manual smoke checklist (report to the user — the release gate)**

**Android** (Zebra/Android device):
1. Sign in as a **manager** → Account shows the Notifications entry; sign in as a non-manager → it's absent.
2. Enable digest, style = **Alarm**, add a near-term time with drafts present → the notification loops sound at alarm volume + vibrates until dismissed/opened.
3. Switch to **Standard** → next tick plays a single sound + vibration, no loop.
4. Non-manager who was previously scheduled: after a relaunch, no digest fires (scheduler cancels).

**iOS** (Mac build on a real device, after wiring the entitlement in Xcode):
1. Manager enables digest → grant the notification permission prompt.
2. A scheduled reminder fires at the chosen time **with the app closed**, generic text; Time-Sensitive breaks through Focus when style = Alarm.
3. The **Documents** section is absent on iOS.
4. Log out → scheduled reminders are cancelled.

Version note: this is a `feat` → **MINOR** bump at release time per `docs/versioning_conventions.md` (do not bump here).
