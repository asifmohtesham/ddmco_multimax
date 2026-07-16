# Scheduled Draft-Document Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-user recurring OS-notification digest of draft PO/PR/DN/SE (`docstatus = 0`) and open POS Uploads (`status in [Pending, In Progress]`), fired by Android WorkManager at user-chosen times even when the app is closed.

**Architecture:** A GetX-free `DigestService` runs in a WorkManager background isolate, reuses the app's on-disk session cookies to run `frappe.client.get_count` per doctype, and posts one replaceable local notification. A `DigestScheduler` chains one-off WorkManager tasks (next occurrence computed from per-user prefs). A new Notifications settings screen (User Area → Preferences) edits prefs and re-arms. Spec: `docs/superpowers/specs/2026-07-16-scheduled-draft-notifications-design.md`.

**Tech Stack:** Flutter 3.44 / Dart 3.12 (repo `sdk: ^3.8.1`), GetX, Dio + cookie_jar, GetStorage, `workmanager ^0.9.0+3`, `flutter_local_notifications ^22.0.1`.

## Global Constraints

- Dependency pins: `workmanager: ^0.9.0+3`, `flutter_local_notifications: ^22.0.1`, `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`, Java compatibility `VERSION_17`.
- Android-only gating idiom (copy exactly): `if (!kIsWeb && Platform.isAndroid)`.
- The background isolate must **NEVER write GetStorage** (whole-file last-writer-wins across isolates); it may read.
- No `Get.find` / GetX DI in `digest_service.dart`, `digest_scheduler.dart`, `digest_worker.dart` (they run without bindings; constructing `StorageService()` directly is allowed).
- `flutter_local_notifications` v22 API uses NAMED parameters: `initialize(settings: …)`, `show(id: …)`, `cancel(id: …)`.
- The fln plugin must be initialized **inside the background isolate** before posting (main-isolate init does not carry over); icon is the resource string `'@mipmap/ic_launcher'`.
- Shared constants (define once in `digest_worker.dart`, import everywhere): `kDigestTaskName = 'digestTask'`, `kDigestUniqueName = 'digest-notification'`, `kDigestNotificationId = 1001`, `kDigestChannelId = 'pending_documents'`.
- Per-user pref keys use the existing `'$key::$user'` convention where `user` is `User.id`.
- Doctype filters (exact): PO/PR/DN/SE → `{'docstatus': 0}`; POS Upload → `{'status': ['in', ['Pending', 'In Progress']]}`.
- Notification copy (verbatim): title `Pending documents (<total>)`; session-expired title `Session expired`, body `Open Multimax to resume digests`; channel name `Pending documents`.
- UI: no hardcoded surface/ink colours — `context.scheme` tokens and `AppColors` ramps only (CLAUDE.md contrast rules). Reuse `SettingsGroup`/`SettingsRow`/`SettingsSwitchRow`/`SelectableFilterChip`.
- Worktree: `C:\Users\asifm\StudioProjects\ddmco_multimax\.claude\worktrees\scheduled-notifications-draft-docs-18a178`, branch `claude/scheduled-notifications-draft-docs-18a178`. Run `git branch --show-current` before every commit.
- Test doubles are hand-written fakes (no mockito); GetStorage is faked via `StorageService.withStorage(fake as dynamic)`.

---

### Task 1: Dependencies + Android platform config

**Files:**
- Modify: `pubspec.yaml` (dependencies block, after `speech_to_text: ^7.4.0`)
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: nothing.
- Produces: importable packages `package:workmanager/workmanager.dart`, `package:flutter_local_notifications/flutter_local_notifications.dart` for all later tasks; a debug APK that proves desugaring works.

- [ ] **Step 1: Add packages to pubspec.yaml**

In `pubspec.yaml`, after the line `  speech_to_text: ^7.4.0` add:

```yaml
  # Scheduled draft-document digest notifications (Android-only feature):
  # workmanager wakes the app in the background at the scheduled times,
  # flutter_local_notifications posts the OS notification.
  workmanager: ^0.9.0+3
  flutter_local_notifications: ^22.0.1
```

- [ ] **Step 2: Run pub get**

Run: `flutter pub get`
Expected: `Got dependencies!` with both packages resolving (workmanager 0.9.0+3, flutter_local_notifications 22.0.x). No resolution conflict.

- [ ] **Step 3: Enable core library desugaring + Java 17**

In `android/app/build.gradle.kts` replace:

```kotlin
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
```

with:

```kotlin
    compileOptions {
        // flutter_local_notifications requires core library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
```

and at the very bottom of the file (after the `flutter { … }` block) add:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

- [ ] **Step 4: Declare POST_NOTIFICATIONS**

In `android/app/src/main/AndroidManifest.xml`, after `<uses-permission android:name="android.permission.INTERNET"/>` add:

```xml
    <!-- Android 13+ runtime permission for the scheduled digest notification.
         (Also merged in by flutter_local_notifications; declared explicitly
         for self-documentation.) -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

No receivers are needed: workmanager does the scheduling and the plugin only calls `show()` (receivers are only for `zonedSchedule`).

- [ ] **Step 5: Verify the Android build**

Run: `flutter build apk --debug`
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk` — proves desugaring + Java 17 compile. If it fails on desugaring, re-check Step 3 (both the flag and the `dependencies` block).

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git branch --show-current   # must print claude/scheduled-notifications-draft-docs-18a178
git add pubspec.yaml pubspec.lock android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml
git commit -m "feat(notifications): add workmanager + flutter_local_notifications with Android desugaring"
```

---

### Task 2: Digest prefs on StorageService

**Files:**
- Modify: `lib/app/data/services/storage_service.dart` (append inside the class, after `getDashboardTasksFirst`)
- Test: `test/unit/storage_digest_prefs_test.dart`

**Interfaces:**
- Consumes: existing `StorageService` `_box` field and `withStorage` test seam.
- Produces (exact signatures, used by Tasks 6, 7, 9):
  - `Future<void> saveDigestEnabled(String user, bool value)` / `bool getDigestEnabled(String user)` — default `false`
  - `Future<void> saveDigestTimes(String user, List<String> times)` / `List<String> getDigestTimes(String user)` — default `['09:00']`
  - `Future<void> saveDigestDays(String user, List<int> days)` / `List<int> getDigestDays(String user)` — default `[1,2,3,4,5,6,7]`
  - `Future<void> saveDigestDoctypes(String user, List<String> keys)` / `List<String> getDigestDoctypes(String user)` — default all five keys `['purchase_order','purchase_receipt','delivery_note','stock_entry','pos_upload']`

- [ ] **Step 1: Write the failing test**

Create `test/unit/storage_digest_prefs_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

// Mirrors _FakeGetStorage in storage_service_auto_save_test.dart.
class _FakeGetStorage {
  final Map<String, dynamic> _data = {};
  Future<void> write(String key, dynamic value) async {
    _data[key] = value;
  }

  Future<void> remove(String key) async {
    _data.remove(key);
  }

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

  group('digest enabled', () {
    test('defaults to false', () {
      expect(service.getDigestEnabled(user), isFalse);
    });
    test('round-trips per user', () async {
      await service.saveDigestEnabled(user, true);
      expect(service.getDigestEnabled(user), isTrue);
      expect(service.getDigestEnabled('other@example.com'), isFalse);
      expect(box.raw.containsKey('notif_digest_enabled::$user'), isTrue);
    });
  });

  group('digest times', () {
    test('defaults to 09:00', () {
      expect(service.getDigestTimes(user), ['09:00']);
    });
    test('round-trips and survives List<dynamic> storage', () async {
      await service.saveDigestTimes(user, ['08:30', '16:00']);
      // GetStorage returns List<dynamic> after a JSON round-trip.
      box.raw['notif_digest_times::$user'] =
          List<dynamic>.from(box.raw['notif_digest_times::$user'] as List);
      expect(service.getDigestTimes(user), ['08:30', '16:00']);
    });
  });

  group('digest days', () {
    test('defaults to all seven weekdays', () {
      expect(service.getDigestDays(user), [1, 2, 3, 4, 5, 6, 7]);
    });
    test('round-trips', () async {
      await service.saveDigestDays(user, [1, 2, 3]);
      expect(service.getDigestDays(user), [1, 2, 3]);
    });
  });

  group('digest doctypes', () {
    test('defaults to all five', () {
      expect(service.getDigestDoctypes(user), [
        'purchase_order',
        'purchase_receipt',
        'delivery_note',
        'stock_entry',
        'pos_upload',
      ]);
    });
    test('round-trips', () async {
      await service.saveDigestDoctypes(user, ['stock_entry']);
      expect(service.getDigestDoctypes(user), ['stock_entry']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/storage_digest_prefs_test.dart`
Expected: FAIL — `The method 'getDigestEnabled' isn't defined for the type 'StorageService'`.

- [ ] **Step 3: Implement the prefs**

In `lib/app/data/services/storage_service.dart`, add to the Keys section (after `_dashboardTasksFirstKey`):

```dart
  // Scheduled digest notification preferences (per user, keyed key::user —
  // same convention as dashboard_tasks_first).
  static const String _digestEnabledKey = 'notif_digest_enabled';
  static const String _digestTimesKey = 'notif_digest_times';
  static const String _digestDaysKey = 'notif_digest_days';
  static const String _digestDoctypesKey = 'notif_digest_doctypes';
```

and at the end of the class (after `getDashboardTasksFirst`):

```dart
  // --- Scheduled digest notification preferences ---
  Future<void> saveDigestEnabled(String user, bool value) async =>
      _box.write('$_digestEnabledKey::$user', value);

  bool getDigestEnabled(String user) =>
      _box.read<bool>('$_digestEnabledKey::$user') ?? false;

  Future<void> saveDigestTimes(String user, List<String> times) async =>
      _box.write('$_digestTimesKey::$user', times);

  List<String> getDigestTimes(String user) {
    final raw = _box.read<List<dynamic>>('$_digestTimesKey::$user');
    return raw == null ? const ['09:00'] : raw.cast<String>();
  }

  Future<void> saveDigestDays(String user, List<int> days) async =>
      _box.write('$_digestDaysKey::$user', days);

  List<int> getDigestDays(String user) {
    final raw = _box.read<List<dynamic>>('$_digestDaysKey::$user');
    return raw == null ? const [1, 2, 3, 4, 5, 6, 7] : raw.cast<int>();
  }

  Future<void> saveDigestDoctypes(String user, List<String> keys) async =>
      _box.write('$_digestDoctypesKey::$user', keys);

  List<String> getDigestDoctypes(String user) {
    final raw = _box.read<List<dynamic>>('$_digestDoctypesKey::$user');
    return raw == null
        ? const [
            'purchase_order',
            'purchase_receipt',
            'delivery_note',
            'stock_entry',
            'pos_upload',
          ]
        : raw.cast<String>();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/storage_digest_prefs_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/storage_service.dart test/unit/storage_digest_prefs_test.dart
git commit -m "feat(notifications): per-user digest prefs on StorageService"
```

---

### Task 3: Digest registry, result model, and notification copy

**Files:**
- Create: `lib/app/data/services/digest_service.dart` (registry + models + copy only in this task; HTTP added in Task 5)
- Test: `test/unit/digest_message_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart).
- Produces (used by Tasks 5, 7):
  - `class DigestDoctype { final String key; final String doctype; final String singular; final String plural; final Map<String, dynamic> filters; }`
  - `const List<DigestDoctype> kDigestDoctypes` — five entries in order PO, PR, DN, SE, POS Upload
  - `enum DigestStatus { ok, authExpired, failed }`
  - `class DigestResult { final DigestStatus status; final Map<String, int> counts; int get total; }` with factories `DigestResult.ok(Map<String,int>)`, `DigestResult.authExpired()`, `DigestResult.failed()`
  - `class DigestNotificationPlan { final bool show; final String? title; final String? body; static DigestNotificationPlan forResult(DigestResult r); }`

- [ ] **Step 1: Write the failing test**

Create `test/unit/digest_message_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_service.dart';

void main() {
  group('kDigestDoctypes registry', () {
    test('has the five doctypes with the spec filters', () {
      expect(kDigestDoctypes.map((d) => d.key), [
        'purchase_order',
        'purchase_receipt',
        'delivery_note',
        'stock_entry',
        'pos_upload',
      ]);
      expect(kDigestDoctypes.map((d) => d.doctype), [
        'Purchase Order',
        'Purchase Receipt',
        'Delivery Note',
        'Stock Entry',
        'POS Upload',
      ]);
      for (final d in kDigestDoctypes.take(4)) {
        expect(d.filters, {'docstatus': 0});
      }
      expect(kDigestDoctypes.last.filters, {
        'status': ['in', ['Pending', 'In Progress']],
      });
    });
  });

  group('DigestNotificationPlan.forResult', () {
    test('ok with counts builds title + body in registry order, plurals', () {
      final plan = DigestNotificationPlan.forResult(DigestResult.ok({
        'stock_entry': 3,
        'purchase_order': 1,
        'pos_upload': 2,
      }));
      expect(plan.show, isTrue);
      expect(plan.title, 'Pending documents (6)');
      expect(plan.body,
          '1 draft Purchase Order · 3 draft Stock Entries · 2 POS Uploads to fulfil');
    });

    test('zero-count doctypes are suppressed from the body', () {
      final plan = DigestNotificationPlan.forResult(
          DigestResult.ok({'delivery_note': 0, 'purchase_receipt': 2}));
      expect(plan.title, 'Pending documents (2)');
      expect(plan.body, '2 draft Purchase Receipts');
    });

    test('all-zero → no notification', () {
      final plan = DigestNotificationPlan.forResult(
          DigestResult.ok({'purchase_order': 0}));
      expect(plan.show, isFalse);
    });

    test('empty counts → no notification', () {
      expect(DigestNotificationPlan.forResult(DigestResult.ok({})).show,
          isFalse);
    });

    test('authExpired → session-expired copy', () {
      final plan =
          DigestNotificationPlan.forResult(DigestResult.authExpired());
      expect(plan.show, isTrue);
      expect(plan.title, 'Session expired');
      expect(plan.body, 'Open Multimax to resume digests');
    });

    test('failed → silent', () {
      expect(DigestNotificationPlan.forResult(DigestResult.failed()).show,
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/digest_message_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'multimax/app/data/services/digest_service.dart'` (file missing).

- [ ] **Step 3: Create digest_service.dart with registry + models + copy**

Create `lib/app/data/services/digest_service.dart`:

```dart
/// Scheduled digest of documents needing action.
///
/// GetX-free by design: everything in this file also runs inside the
/// WorkManager background isolate (see digest_worker.dart) where no GetX
/// bindings exist.
library;

/// One doctype tracked by the digest.
class DigestDoctype {
  final String key; // pref key, e.g. 'purchase_order'
  final String doctype; // ERPNext DocType name
  final String singular; // copy after a count of 1
  final String plural; // copy after any other count
  final Map<String, dynamic> filters; // frappe.client.get_count filters

  const DigestDoctype({
    required this.key,
    required this.doctype,
    required this.singular,
    required this.plural,
    required this.filters,
  });
}

/// Registry order == notification body order.
const List<DigestDoctype> kDigestDoctypes = [
  DigestDoctype(
    key: 'purchase_order',
    doctype: 'Purchase Order',
    singular: 'draft Purchase Order',
    plural: 'draft Purchase Orders',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'purchase_receipt',
    doctype: 'Purchase Receipt',
    singular: 'draft Purchase Receipt',
    plural: 'draft Purchase Receipts',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'delivery_note',
    doctype: 'Delivery Note',
    singular: 'draft Delivery Note',
    plural: 'draft Delivery Notes',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'stock_entry',
    doctype: 'Stock Entry',
    singular: 'draft Stock Entry',
    plural: 'draft Stock Entries',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'pos_upload',
    doctype: 'POS Upload',
    singular: 'POS Upload to fulfil',
    plural: 'POS Uploads to fulfil',
    // The two statuses the app treats as open for fulfilment.
    filters: {
      'status': ['in', ['Pending', 'In Progress']],
    },
  ),
];

enum DigestStatus { ok, authExpired, failed }

class DigestResult {
  final DigestStatus status;

  /// key (from [DigestDoctype.key]) → server count. Only doctypes that were
  /// actually counted appear; permission-denied doctypes are absent.
  final Map<String, int> counts;

  DigestResult.ok(this.counts) : status = DigestStatus.ok;
  DigestResult.authExpired()
      : status = DigestStatus.authExpired,
        counts = const {};
  DigestResult.failed()
      : status = DigestStatus.failed,
        counts = const {};

  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// What (if anything) to put on screen for a [DigestResult]. Pure — unit
/// tested; the plugin glue in digest_worker.dart stays trivially thin.
class DigestNotificationPlan {
  final bool show;
  final String? title;
  final String? body;

  const DigestNotificationPlan._({required this.show, this.title, this.body});

  static const none = DigestNotificationPlan._(show: false);

  static DigestNotificationPlan forResult(DigestResult r) {
    switch (r.status) {
      case DigestStatus.failed:
        return none; // never nag about our own failures
      case DigestStatus.authExpired:
        return const DigestNotificationPlan._(
          show: true,
          title: 'Session expired',
          body: 'Open Multimax to resume digests',
        );
      case DigestStatus.ok:
        if (r.total == 0) return none; // silent tick
        final clauses = kDigestDoctypes
            .where((d) => (r.counts[d.key] ?? 0) > 0)
            .map((d) {
          final c = r.counts[d.key]!;
          return '$c ${c == 1 ? d.singular : d.plural}';
        }).join(' · ');
        return DigestNotificationPlan._(
          show: true,
          title: 'Pending documents (${r.total})',
          body: clauses,
        );
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/digest_message_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/digest_service.dart test/unit/digest_message_test.dart
git commit -m "feat(notifications): digest doctype registry, result model and notification copy"
```

---

### Task 4: Next-occurrence computation

**Files:**
- Create: `lib/app/data/services/digest_scheduler.dart` (pure function only in this task; scheduler class added in Task 6)
- Test: `test/unit/digest_next_occurrence_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart).
- Produces (used by Task 6): top-level
  `DateTime? nextDigestOccurrence({required DateTime after, required List<String> times, required Set<int> weekdays})`
  — earliest local `DateTime` strictly after `after` whose weekday is in `weekdays` (`DateTime.monday == 1` … `DateTime.sunday == 7`) and whose `HH:mm` is in `times`. Returns `null` when `times` or `weekdays` is empty or a time string is malformed.

- [ ] **Step 1: Write the failing test**

Create `test/unit/digest_next_occurrence_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';

void main() {
  // Wed 2026-07-15 10:00 local.
  final wed10 = DateTime(2026, 7, 15, 10, 0);

  test('same-day later time wins', () {
    expect(
      nextDigestOccurrence(
          after: wed10, times: ['09:00', '16:00'], weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 15, 16, 0),
    );
  });

  test('all of today consumed → earliest time tomorrow', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 15, 17, 0),
          times: ['09:00', '16:00'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 16, 9, 0),
    );
  });

  test('exact-boundary time is skipped (strictly after)', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 15, 9, 0),
          times: ['09:00'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 16, 9, 0),
    );
  });

  test('skips disabled weekdays', () {
    // Wed(3) 10:00; only Mon(1) enabled → next Monday 2026-07-20.
    expect(
      nextDigestOccurrence(after: wed10, times: ['09:00'], weekdays: {1}),
      DateTime(2026, 7, 20, 9, 0),
    );
  });

  test('unsorted times are handled', () {
    expect(
      nextDigestOccurrence(
          after: wed10,
          times: ['16:00', '11:30'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 15, 11, 30),
    );
  });

  test('same weekday next week when today is the only enabled day', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 15, 17, 0), times: ['09:00'], weekdays: {3}),
      DateTime(2026, 7, 22, 9, 0),
    );
  });

  test('month rollover via day arithmetic', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 31, 12, 0),
          times: ['09:00'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 8, 1, 9, 0),
    );
  });

  test('empty times or weekdays → null', () {
    expect(
        nextDigestOccurrence(
            after: wed10, times: [], weekdays: {1, 2, 3, 4, 5, 6, 7}),
        isNull);
    expect(nextDigestOccurrence(after: wed10, times: ['09:00'], weekdays: {}),
        isNull);
  });

  test('malformed time string → null', () {
    expect(
        nextDigestOccurrence(
            after: wed10, times: ['9am'], weekdays: {1, 2, 3, 4, 5, 6, 7}),
        isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/digest_next_occurrence_test.dart`
Expected: FAIL — package/file not found.

- [ ] **Step 3: Implement nextDigestOccurrence**

Create `lib/app/data/services/digest_scheduler.dart`:

```dart
/// Digest schedule computation + WorkManager arming.
///
/// GetX-free by design — also used from the background isolate.
library;

/// Earliest local instant strictly after [after] matching an enabled weekday
/// (`DateTime.monday == 1` … `DateTime.sunday == 7`) and an `HH:mm` entry of
/// [times]. Null when the schedule can never fire. Day stepping uses
/// component arithmetic (`DateTime(y, m, d + n)`), which Dart normalises
/// across month ends and DST shifts.
DateTime? nextDigestOccurrence({
  required DateTime after,
  required List<String> times,
  required Set<int> weekdays,
}) {
  if (times.isEmpty || weekdays.isEmpty) return null;

  final minutes = <(int, int)>[];
  for (final t in times) {
    final parts = t.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    minutes.add((h, m));
  }
  minutes.sort((a, b) => (a.$1 * 60 + a.$2).compareTo(b.$1 * 60 + b.$2));

  for (var day = 0; day <= 7; day++) {
    final date = DateTime(after.year, after.month, after.day + day);
    if (!weekdays.contains(date.weekday)) continue;
    for (final (h, m) in minutes) {
      final candidate = DateTime(date.year, date.month, date.day, h, m);
      if (candidate.isAfter(after)) return candidate;
    }
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/digest_next_occurrence_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/digest_scheduler.dart test/unit/digest_next_occurrence_test.dart
git commit -m "feat(notifications): next-occurrence computation for digest schedule"
```

---

### Task 5: DigestService — session probe + count queries

**Files:**
- Modify: `lib/app/data/services/digest_service.dart` (append the service class)
- Test: `test/unit/digest_service_test.dart`

**Interfaces:**
- Consumes: `kDigestDoctypes`, `DigestResult` (Task 3); `dio`, `cookie_jar`, `dio_cookie_manager` packages (already app dependencies).
- Produces (used by Task 7):
  - `class DigestService { DigestService({required String baseUrl, required String cookieDir}); Future<Response> callGet(String path, Map<String, dynamic> query); Future<DigestResult> fetchDigest(List<DigestDoctype> doctypes); }`
  - `callGet` is `@visibleForTesting`-style seam: tests subclass and override it (repo convention — hand-written fakes, no mockito).

- [ ] **Step 1: Write the failing test**

Create `test/unit/digest_service_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_service.dart';

/// Hand-written fake (repo convention): overrides the single HTTP seam.
class _FakeDigestService extends DigestService {
  _FakeDigestService() : super(baseUrl: 'https://erp.test', cookieDir: '/x/');

  /// message returned by the session probe; null → probe throws [probeError].
  String? loggedUser = 'asif@example.com';
  DioException? probeError;

  /// doctype name → count, DioException, or Exception.
  final Map<String, Object> countResults = {};
  final List<String> countedDoctypes = [];

  static DioException _dioError(int? statusCode) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: statusCode == null
            ? null
            : Response(
                requestOptions: RequestOptions(path: '/x'),
                statusCode: statusCode),
        type: statusCode == null
            ? DioExceptionType.connectionError
            : DioExceptionType.badResponse,
      );

  static DioException forbidden() => _dioError(403);
  static DioException unauthorized() => _dioError(401);
  static DioException network() => _dioError(null);

  @override
  Future<Response> callGet(String path, Map<String, dynamic> query) async {
    if (path == '/api/method/frappe.auth.get_logged_user') {
      if (probeError != null) throw probeError!;
      return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'message': loggedUser},
      );
    }
    // count call
    final doctype = query['doctype'] as String;
    countedDoctypes.add(doctype);
    final r = countResults[doctype];
    if (r is DioException) throw r;
    if (r is Exception) throw r;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'message': r ?? 0}, // int, or any raw value a test injects
    );
  }
}

void main() {
  late _FakeDigestService svc;

  setUp(() => svc = _FakeDigestService());

  test('happy path counts every requested doctype with its filters', () async {
    svc.countResults['Purchase Order'] = 2;
    svc.countResults['POS Upload'] = 5;
    final result = await svc
        .fetchDigest([kDigestDoctypes.first, kDigestDoctypes.last]);
    expect(result.status, DigestStatus.ok);
    expect(result.counts, {'purchase_order': 2, 'pos_upload': 5});
    expect(result.total, 7);
    expect(svc.countedDoctypes, ['Purchase Order', 'POS Upload']);
  });

  test('per-doctype 403 is a permission skip, not a failure', () async {
    svc.countResults['Purchase Order'] = _FakeDigestService.forbidden();
    svc.countResults['POS Upload'] = 3;
    final result =
        await svc.fetchDigest([kDigestDoctypes.first, kDigestDoctypes.last]);
    expect(result.status, DigestStatus.ok);
    expect(result.counts, {'pos_upload': 3});
  });

  test('probe returning Guest → authExpired, no counts attempted', () async {
    svc.loggedUser = 'Guest';
    final result = await svc.fetchDigest(kDigestDoctypes);
    expect(result.status, DigestStatus.authExpired);
    expect(svc.countedDoctypes, isEmpty);
  });

  test('probe 401/403 → authExpired', () async {
    svc.probeError = _FakeDigestService.unauthorized();
    expect((await svc.fetchDigest(kDigestDoctypes)).status,
        DigestStatus.authExpired);
    svc.probeError = _FakeDigestService.forbidden();
    expect((await svc.fetchDigest(kDigestDoctypes)).status,
        DigestStatus.authExpired);
  });

  test('probe network error → failed', () async {
    svc.probeError = _FakeDigestService.network();
    expect(
        (await svc.fetchDigest(kDigestDoctypes)).status, DigestStatus.failed);
  });

  test('count network error → failed', () async {
    svc.countResults['Purchase Order'] = _FakeDigestService.network();
    expect((await svc.fetchDigest([kDigestDoctypes.first])).status,
        DigestStatus.failed);
  });

  test('non-int count payload is ignored, others still counted', () async {
    svc.countResults['Purchase Order'] = 'weird'; // malformed server body
    svc.countResults['POS Upload'] = 4;
    final result =
        await svc.fetchDigest([kDigestDoctypes.first, kDigestDoctypes.last]);
    expect(result.status, DigestStatus.ok);
    expect(result.counts, {'pos_upload': 4}); // PO absent, not crashed
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/digest_service_test.dart`
Expected: FAIL — `'DigestService' isn't a class` / no such constructor.

- [ ] **Step 3: Implement DigestService**

Append to `lib/app/data/services/digest_service.dart` (add imports at top of file):

```dart
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
```

and append the class:

```dart
/// Runs the digest count queries against ERPNext using the app's persisted
/// session cookies. Safe to construct in any isolate.
class DigestService {
  final String baseUrl;

  /// Directory of the app's PersistCookieJar — the same
  /// `<appSupportDir>/.cookies/` path ApiProvider uses.
  final String cookieDir;

  Dio? _dio;

  DigestService({required this.baseUrl, required this.cookieDir});

  Dio _client() {
    if (_dio != null) return _dio!;
    final jar =
        PersistCookieJar(ignoreExpires: true, storage: FileStorage(cookieDir));
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

  /// Session probe first (so a narrow-permission role is never misreported
  /// as an expired session), then one get_count per doctype.
  Future<DigestResult> fetchDigest(List<DigestDoctype> doctypes) async {
    try {
      final res =
          await callGet('/api/method/frappe.auth.get_logged_user', const {});
      final who = res.data is Map ? res.data['message'] : null;
      if (who == null || who == 'Guest') return DigestResult.authExpired();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return DigestResult.authExpired();
      return DigestResult.failed();
    }

    final counts = <String, int>{};
    for (final d in doctypes) {
      try {
        final res = await callGet('/api/method/frappe.client.get_count', {
          'doctype': d.doctype,
          'filters': jsonEncode(d.filters),
        });
        final n = res.data is Map ? res.data['message'] : null;
        if (n is int) counts[d.key] = n;
      } on DioException catch (e) {
        if (e.response?.statusCode == 403) continue; // no read permission
        return DigestResult.failed();
      }
    }
    return DigestResult.ok(counts);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/digest_service_test.dart test/unit/digest_message_test.dart`
Expected: all tests PASS (Task 3 tests still green).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/digest_service.dart test/unit/digest_service_test.dart
git commit -m "feat(notifications): DigestService with session probe and permission-safe counts"
```

---

### Task 6: DigestScheduler + WorkScheduler seam

**Files:**
- Modify: `lib/app/data/services/digest_scheduler.dart` (append classes)
- Test: `test/unit/digest_scheduler_test.dart`

**Interfaces:**
- Consumes: `nextDigestOccurrence` (Task 4), `StorageService` digest prefs (Task 2), `kDigestTaskName`/`kDigestUniqueName` constants — **defined here** to avoid a worker↔scheduler import cycle (Task 7's worker imports this file).
- Produces (used by Tasks 7, 8, 9):
  - `const String kDigestTaskName = 'digestTask';`
  - `const String kDigestUniqueName = 'digest-notification';`
  - `abstract class WorkScheduler { Future<void> registerOneOff({required String uniqueName, required String taskName, required Duration initialDelay}); Future<void> cancel(String uniqueName); }`
  - `class WorkmanagerScheduler implements WorkScheduler` (real impl)
  - `class DigestScheduler { DigestScheduler({StorageService? storage, WorkScheduler? work, DateTime Function()? now}); Future<void> rearm(); }` — cancels when logged-out/disabled/never-fires; otherwise registers a replacing one-off task at the next occurrence.

- [ ] **Step 1: Write the failing test**

Create `test/unit/digest_scheduler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class _FakeGetStorage {
  final Map<String, dynamic> _data = {};
  Future<void> write(String key, dynamic value) async {
    _data[key] = value;
  }

  Future<void> remove(String key) async {
    _data.remove(key);
  }

  T? read<T>(String key) => _data[key] as T?;
  bool hasData(String key) => _data.containsKey(key);
}

class _FakeWork implements WorkScheduler {
  final registered = <({String uniqueName, String taskName, Duration delay})>[];
  final cancelled = <String>[];

  @override
  Future<void> registerOneOff(
          {required String uniqueName,
          required String taskName,
          required Duration initialDelay}) async =>
      registered.add(
          (uniqueName: uniqueName, taskName: taskName, delay: initialDelay));

  @override
  Future<void> cancel(String uniqueName) async => cancelled.add(uniqueName);
}

void main() {
  const userJson = {
    'name': 'asif@example.com',
    'full_name': 'Asif',
    'email': 'asif@example.com',
  };
  // Wed 2026-07-15 10:00 local.
  final now = DateTime(2026, 7, 15, 10, 0);

  late _FakeGetStorage box;
  late StorageService storage;
  late _FakeWork work;
  late DigestScheduler scheduler;

  setUp(() {
    box = _FakeGetStorage();
    storage = StorageService.withStorage(box as dynamic);
    work = _FakeWork();
    scheduler = DigestScheduler(storage: storage, work: work, now: () => now);
  });

  test('no logged-in user → cancel', () async {
    await scheduler.rearm();
    expect(work.cancelled, [kDigestUniqueName]);
    expect(work.registered, isEmpty);
  });

  test('logged in but disabled → cancel', () async {
    box._data['currentUser'] = userJson;
    await scheduler.rearm();
    expect(work.cancelled, [kDigestUniqueName]);
    expect(work.registered, isEmpty);
  });

  test('enabled → registers replacing one-off task at next occurrence',
      () async {
    box._data['currentUser'] = userJson;
    await storage.saveDigestEnabled('asif@example.com', true);
    await storage.saveDigestTimes('asif@example.com', ['16:00']);
    await scheduler.rearm();
    expect(work.registered, hasLength(1));
    expect(work.registered.single.uniqueName, kDigestUniqueName);
    expect(work.registered.single.taskName, kDigestTaskName);
    // 10:00 → 16:00 same day = 6h.
    expect(work.registered.single.delay, const Duration(hours: 6));
  });

  test('enabled but empty days → cancel (schedule can never fire)', () async {
    box._data['currentUser'] = userJson;
    await storage.saveDigestEnabled('asif@example.com', true);
    await storage.saveDigestDays('asif@example.com', []);
    await scheduler.rearm();
    expect(work.cancelled, [kDigestUniqueName]);
    expect(work.registered, isEmpty);
  });
}
```

(`_FakeGetStorage._data` is library-private, and Dart privacy is per-library — the test file IS the library, so `box._data[...]` access from tests in the same file is legal.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/digest_scheduler_test.dart`
Expected: FAIL — `WorkScheduler` / `DigestScheduler` / `kDigestUniqueName` undefined.

- [ ] **Step 3: Implement scheduler classes**

Append to `lib/app/data/services/digest_scheduler.dart` (imports go at the top of the file):

```dart
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:workmanager/workmanager.dart';
```

and below `nextDigestOccurrence`:

```dart
/// Task/work identity shared between scheduler, worker, and logout teardown.
const String kDigestTaskName = 'digestTask';
const String kDigestUniqueName = 'digest-notification';

/// Thin seam over Workmanager so DigestScheduler is unit-testable.
abstract class WorkScheduler {
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
  });

  Future<void> cancel(String uniqueName);
}

class WorkmanagerScheduler implements WorkScheduler {
  @override
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
  }) =>
      Workmanager().registerOneOffTask(
        uniqueName,
        taskName,
        initialDelay: initialDelay,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );

  @override
  Future<void> cancel(String uniqueName) =>
      Workmanager().cancelByUniqueName(uniqueName);
}

/// Arms exactly one pending WorkManager task at the next schedule occurrence.
/// Cancel-then-replace semantics come from ExistingWorkPolicy.replace plus
/// the fixed unique name. Reads prefs only — never writes storage, so it is
/// safe to call from the background isolate (see digest_worker.dart).
class DigestScheduler {
  final StorageService _storage;
  final WorkScheduler _work;
  final DateTime Function() _now;

  DigestScheduler({
    StorageService? storage,
    WorkScheduler? work,
    DateTime Function()? now,
  })  : _storage = storage ?? StorageService(),
        _work = work ?? WorkmanagerScheduler(),
        _now = now ?? DateTime.now;

  Future<void> rearm() async {
    final user = _storage.getUser();
    if (user == null || !_storage.getDigestEnabled(user.id)) {
      await _work.cancel(kDigestUniqueName);
      return;
    }
    final next = nextDigestOccurrence(
      after: _now(),
      times: _storage.getDigestTimes(user.id),
      weekdays: _storage.getDigestDays(user.id).toSet(),
    );
    if (next == null) {
      await _work.cancel(kDigestUniqueName);
      return;
    }
    await _work.registerOneOff(
      uniqueName: kDigestUniqueName,
      taskName: kDigestTaskName,
      initialDelay: next.difference(_now()),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/digest_scheduler_test.dart test/unit/digest_next_occurrence_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/data/services/digest_scheduler.dart test/unit/digest_scheduler_test.dart
git commit -m "feat(notifications): DigestScheduler with testable WorkScheduler seam"
```

---

### Task 7: Background worker + notification posting + logout teardown

**Files:**
- Create: `lib/app/data/services/digest_worker.dart`
- Test: none new (the decision logic was TDD'd in Tasks 3–6; this file is thin plugin glue verified by `flutter analyze` and the Task 11 on-device smoke)

**Interfaces:**
- Consumes: `DigestService`, `kDigestDoctypes`, `DigestNotificationPlan` (Tasks 3/5); `DigestScheduler`, `WorkmanagerScheduler`, `kDigestTaskName`, `kDigestUniqueName` (Task 6); `StorageService` digest prefs (Task 2); `ApiProvider.defaultBaseUrl`.
- Produces (used by Task 8):
  - `const int kDigestNotificationId = 1001;`
  - `const String kDigestChannelId = 'pending_documents';`
  - `@pragma('vm:entry-point') void digestCallbackDispatcher()` — passed to `Workmanager().initialize`
  - `Future<void> runDigestTask()` — the tick body
  - `Future<void> cancelDigestOnLogout()` — cancels pending work + clears the notification

- [ ] **Step 1: Create digest_worker.dart**

Create `lib/app/data/services/digest_worker.dart`:

```dart
/// WorkManager background entry point for the scheduled digest.
///
/// Runs in a fresh background isolate with NO GetX bindings — everything here
/// is constructed directly. GetStorage is initialised read-only; this isolate
/// must NEVER write GetStorage (whole-file last-writer-wins across isolates
/// would clobber main-isolate writes).
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

const int kDigestNotificationId = 1001;
const String kDigestChannelId = 'pending_documents';
const String _kChannelName = 'Pending documents';
const String _kChannelDescription =
    'Scheduled digest of documents needing action';

@pragma('vm:entry-point')
void digestCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await runDigestTask();
    } catch (_) {
      // A digest must never nag about its own failures, and returning false
      // would trigger WorkManager backoff retries — the next scheduled tick
      // is the retry.
    }
    return true;
  });
}

/// One digest tick: read prefs, count, notify, chain the next occurrence.
Future<void> runDigestTask() async {
  await GetStorage.init();
  final storage = StorageService();
  final user = storage.getUser();
  if (user == null) return; // logged out since scheduling — do nothing
  if (!storage.getDigestEnabled(user.id)) return;

  final enabledKeys = storage.getDigestDoctypes(user.id).toSet();
  final doctypes =
      kDigestDoctypes.where((d) => enabledKeys.contains(d.key)).toList();

  final supportDir = await getApplicationSupportDirectory();
  final service = DigestService(
    baseUrl: storage.getBaseUrl() ?? ApiProvider.defaultBaseUrl,
    cookieDir: '${supportDir.path}/.cookies/',
  );
  final result = await service.fetchDigest(doctypes);
  final plan = DigestNotificationPlan.forResult(result);

  if (plan.show) {
    final fln = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await fln.initialize(
        settings: const InitializationSettings(android: androidInit));
    final android = fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      kDigestChannelId,
      _kChannelName,
      description: _kChannelDescription,
      importance: Importance.defaultImportance,
    ));
    await fln.show(
      id: kDigestNotificationId, // fixed id: new digest replaces the old one
      title: plan.title,
      body: plan.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kDigestChannelId,
          _kChannelName,
          channelDescription: _kChannelDescription,
          styleInformation: BigTextStyleInformation(plan.body ?? ''),
        ),
      ),
    );
  }

  // Chain the next occurrence. Reads prefs only — no storage writes.
  await DigestScheduler(storage: storage).rearm();
}

/// Called from the main isolate on logout: drop pending work and clear any
/// posted digest so the next user doesn't see the previous user's counts.
Future<void> cancelDigestOnLogout() async {
  try {
    await Workmanager().cancelByUniqueName(kDigestUniqueName);
    final fln = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await fln.initialize(
        settings: const InitializationSettings(android: androidInit));
    await fln.cancel(id: kDigestNotificationId);
  } catch (_) {
    // Best-effort cleanup; never block logout on notification plumbing.
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!` — in particular no errors on the named-parameter fln v22 calls. If `initialize(settings: …)` errors, the resolved fln major is older than 22; re-check `pubspec.lock`.

- [ ] **Step 3: Run the full existing suite (regression gate)**

Run: `flutter test`
Expected: same pass/fail baseline as before this task (no new failures).

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add lib/app/data/services/digest_worker.dart
git commit -m "feat(notifications): background digest worker with notification posting and logout teardown"
```

---

### Task 8: App wiring — main.dart, login re-arm, logout teardown

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app/modules/auth/authentication_controller.dart`

**Interfaces:**
- Consumes: `digestCallbackDispatcher`, `cancelDigestOnLogout` (Task 7); `DigestScheduler` (Task 6).
- Produces: WorkManager initialised at startup; chain self-heals on every launch; digest lifecycle tied to login/logout.

- [ ] **Step 1: Initialize Workmanager and re-arm on launch in main.dart**

In `lib/main.dart` add imports (with the existing imports):

```dart
import 'dart:async' show unawaited;
import 'package:workmanager/workmanager.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_worker.dart';
```

After `await GetStorage.init();` add:

```dart
  // Scheduled digest notifications (Android-only). Registers the background
  // dispatcher; actual work is only ever scheduled by DigestScheduler.
  if (!kIsWeb && Platform.isAndroid) {
    await Workmanager().initialize(digestCallbackDispatcher);
  }
```

After `await authController.checkAuthenticationStatus();` (immediately before `runApp(...)`) add:

```dart
  // Self-heal a broken digest chain (crash/force-stop) on every launch.
  // Fire-and-forget: startup must never block on WorkManager.
  if (!kIsWeb && Platform.isAndroid && authController.isAuthenticated.value) {
    unawaited(DigestScheduler().rearm().catchError((_) {}));
  }
```

- [ ] **Step 2: Re-arm after login in AuthenticationController**

In `lib/app/modules/auth/authentication_controller.dart`, add imports:

```dart
import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_worker.dart';
```

(keep only the ones not already imported — the file already imports GetX etc.)

In `fetchUserDetails`, immediately after the block that persists the user
(`await Get.find<StorageService>().saveUser(user);` inside its
`if (Get.isRegistered<StorageService>())` guard), add:

```dart
          // Arm the scheduled digest for the user who just signed in.
          if (!kIsWeb && Platform.isAndroid) {
            unawaited(DigestScheduler().rearm().catchError((_) {}));
          }
```

- [ ] **Step 3: Teardown on logout**

In the same file, in `_clearSessionAndLocalData()`, add as the FIRST statement of the method (before `await _apiProvider.clearSessionCookies();`):

```dart
    // Cancel pending digest work and clear any posted digest notification
    // before the user identity disappears from storage.
    if (!kIsWeb && Platform.isAndroid) {
      await cancelDigestOnLogout();
    }
```

- [ ] **Step 4: Analyze + full suite**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: baseline unchanged (auth-controller tests, if any touch `_clearSessionAndLocalData`, still pass — `cancelDigestOnLogout` is inert off-Android and swallows plugin errors).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/main.dart lib/app/modules/auth/authentication_controller.dart
git commit -m "feat(notifications): wire digest scheduler into app startup, login and logout"
```

---

### Task 9: NotificationSettingsController (TDD)

**Files:**
- Create: `lib/app/modules/notification_settings/notification_settings_controller.dart`
- Create: `lib/app/modules/notification_settings/notification_settings_binding.dart`
- Test: `test/unit/notification_settings_controller_test.dart`

**Interfaces:**
- Consumes: `StorageService` digest prefs (Task 2), `DigestScheduler` (Task 6), `kDigestDoctypes` (Task 3), `AppNotification`.
- Produces (used by Task 10's screen):
  - `class NotificationSettingsController extends GetxController` with:
    - observables `RxBool enabled`, `RxList<String> times`, `RxSet<int> days`, `RxSet<String> doctypeKeys`
    - `Future<void> setEnabled(bool value)` — on enable, awaits the injected permission request; denial reverts + warns
    - `Future<void> addTime(int hour, int minute)` — formats `HH:mm`, dedupes, caps at 4 (warns), keeps sorted
    - `Future<void> removeTime(String time)`
    - `Future<void> toggleDay(int weekday)`
    - `Future<void> toggleDoctype(String key)`
    - constructor `NotificationSettingsController({StorageService? storage, DigestScheduler? scheduler, Future<bool> Function()? requestPermission})`
  - `class NotificationSettingsBinding extends Bindings` — lazyPuts the controller.

- [ ] **Step 1: Write the failing test**

Create `test/unit/notification_settings_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_controller.dart';

class _FakeGetStorage {
  final Map<String, dynamic> _data = {};
  Future<void> write(String key, dynamic value) async {
    _data[key] = value;
  }

  Future<void> remove(String key) async {
    _data.remove(key);
  }

  T? read<T>(String key) => _data[key] as T?;
  bool hasData(String key) => _data.containsKey(key);
}

class _FakeWork implements WorkScheduler {
  @override
  Future<void> registerOneOff(
      {required String uniqueName,
      required String taskName,
      required Duration initialDelay}) async {}

  @override
  Future<void> cancel(String uniqueName) async {}
}

class _CountingScheduler extends DigestScheduler {
  int rearms = 0;
  _CountingScheduler(StorageService storage)
      : super(storage: storage, work: _FakeWork());

  @override
  Future<void> rearm() async => rearms++;
}

void main() {
  const user = 'asif@example.com';
  late _FakeGetStorage box;
  late StorageService storage;
  late _CountingScheduler scheduler;
  bool permissionAnswer = true;
  int permissionAsks = 0;

  NotificationSettingsController build() => NotificationSettingsController(
        storage: storage,
        scheduler: scheduler,
        requestPermission: () async {
          permissionAsks++;
          return permissionAnswer;
        },
      );

  setUp(() {
    box = _FakeGetStorage();
    box._data['currentUser'] = {
      'name': user,
      'full_name': 'Asif',
      'email': user,
    };
    storage = StorageService.withStorage(box as dynamic);
    scheduler = _CountingScheduler(storage);
    permissionAnswer = true;
    permissionAsks = 0;
  });

  tearDown(() => Get.deleteAll(force: true));

  test('loads defaults on init', () {
    final c = build()..onInit();
    expect(c.enabled.value, isFalse);
    expect(c.times, ['09:00']);
    expect(c.days, {1, 2, 3, 4, 5, 6, 7});
    expect(c.doctypeKeys, {
      'purchase_order',
      'purchase_receipt',
      'delivery_note',
      'stock_entry',
      'pos_upload',
    });
  });

  test('enable asks permission, persists, re-arms', () async {
    final c = build()..onInit();
    await c.setEnabled(true);
    expect(permissionAsks, 1);
    expect(c.enabled.value, isTrue);
    expect(storage.getDigestEnabled(user), isTrue);
    expect(scheduler.rearms, 1);
  });

  test('permission denied → reverts, does not persist', () async {
    permissionAnswer = false;
    final c = build()..onInit();
    await c.setEnabled(true);
    expect(c.enabled.value, isFalse);
    expect(storage.getDigestEnabled(user), isFalse);
    expect(scheduler.rearms, 0);
  });

  test('disable never asks permission, persists, re-arms', () async {
    final c = build()..onInit();
    await c.setEnabled(true);
    await c.setEnabled(false);
    expect(permissionAsks, 1); // only the enable asked
    expect(storage.getDigestEnabled(user), isFalse);
    expect(scheduler.rearms, 2);
  });

  test('addTime formats, sorts, dedupes and caps at 4', () async {
    final c = build()..onInit();
    await c.addTime(16, 0);
    await c.addTime(8, 5);
    expect(c.times, ['08:05', '09:00', '16:00']);
    await c.addTime(8, 5); // duplicate → ignored
    expect(c.times, ['08:05', '09:00', '16:00']);
    await c.addTime(12, 0); // 4th → ok
    await c.addTime(13, 0); // 5th → rejected
    expect(c.times, ['08:05', '09:00', '12:00', '16:00']);
    expect(storage.getDigestTimes(user), ['08:05', '09:00', '12:00', '16:00']);
  });

  test('removeTime persists and re-arms', () async {
    final c = build()..onInit();
    await c.removeTime('09:00');
    expect(c.times, isEmpty);
    expect(storage.getDigestTimes(user), isEmpty);
    expect(scheduler.rearms, 1);
  });

  test('toggleDay flips membership and persists sorted', () async {
    final c = build()..onInit();
    await c.toggleDay(7);
    expect(c.days, {1, 2, 3, 4, 5, 6});
    expect(storage.getDigestDays(user), [1, 2, 3, 4, 5, 6]);
    await c.toggleDay(7);
    expect(storage.getDigestDays(user), [1, 2, 3, 4, 5, 6, 7]);
  });

  test('toggleDoctype flips membership and persists in registry order',
      () async {
    final c = build()..onInit();
    await c.toggleDoctype('purchase_order');
    expect(c.doctypeKeys.contains('purchase_order'), isFalse);
    expect(storage.getDigestDoctypes(user), [
      'purchase_receipt',
      'delivery_note',
      'stock_entry',
      'pos_upload',
    ]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/notification_settings_controller_test.dart`
Expected: FAIL — controller file missing.

- [ ] **Step 3: Implement controller + binding**

Create `lib/app/modules/notification_settings/notification_settings_controller.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';

/// Android 13+ POST_NOTIFICATIONS prompt. Kept as a free function so the
/// controller can take a test seam instead of touching the plugin.
Future<bool> requestNotificationsPermission() async {
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? false;
}

class NotificationSettingsController extends GetxController {
  static const int maxTimes = 4;

  final StorageService _storage;
  final DigestScheduler _scheduler;
  final Future<bool> Function() _requestPermission;

  NotificationSettingsController({
    StorageService? storage,
    DigestScheduler? scheduler,
    Future<bool> Function()? requestPermission,
  })  : _storage = storage ?? Get.find<StorageService>(),
        _scheduler = scheduler ?? DigestScheduler(),
        _requestPermission = requestPermission ?? requestNotificationsPermission;

  final enabled = false.obs;
  final times = <String>[].obs;
  final days = <int>{}.obs;
  final doctypeKeys = <String>{}.obs;

  String get _user => _storage.getUser()?.id ?? '';

  @override
  void onInit() {
    super.onInit();
    enabled.value = _storage.getDigestEnabled(_user);
    times.assignAll(_storage.getDigestTimes(_user));
    days.assignAll(_storage.getDigestDays(_user));
    doctypeKeys.assignAll(_storage.getDigestDoctypes(_user));
  }

  Future<void> setEnabled(bool value) async {
    if (value) {
      final granted = await _requestPermission();
      if (!granted) {
        enabled.value = false;
        AppNotification.warning(
            'Allow notifications for Multimax in system settings');
        return;
      }
    }
    enabled.value = value;
    await _storage.saveDigestEnabled(_user, value);
    await _scheduler.rearm();
  }

  Future<void> addTime(int hour, int minute) async {
    final t = '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
    if (times.contains(t)) return;
    if (times.length >= maxTimes) {
      AppNotification.warning('Up to $maxTimes times per day');
      return;
    }
    times
      ..add(t)
      ..sort();
    await _persistTimes();
  }

  Future<void> removeTime(String time) async {
    times.remove(time);
    await _persistTimes();
  }

  Future<void> toggleDay(int weekday) async {
    days.contains(weekday) ? days.remove(weekday) : days.add(weekday);
    await _storage.saveDigestDays(_user, days.toList()..sort());
    await _scheduler.rearm();
  }

  Future<void> toggleDoctype(String key) async {
    doctypeKeys.contains(key) ? doctypeKeys.remove(key) : doctypeKeys.add(key);
    // Persist in registry order so the digest body order never varies.
    final ordered = kDigestDoctypes
        .map((d) => d.key)
        .where(doctypeKeys.contains)
        .toList();
    await _storage.saveDigestDoctypes(_user, ordered);
    await _scheduler.rearm();
  }

  Future<void> _persistTimes() async {
    await _storage.saveDigestTimes(_user, times.toList());
    await _scheduler.rearm();
  }
}
```

Create `lib/app/modules/notification_settings/notification_settings_binding.dart`:

```dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_controller.dart';

class NotificationSettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<NotificationSettingsController>(
        () => NotificationSettingsController());
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/notification_settings_controller_test.dart`
Expected: all tests PASS. (`AppNotification` no-ops when `Get.context` is null, so warnings are safe in tests.)

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/notification_settings/ test/unit/notification_settings_controller_test.dart
git commit -m "feat(notifications): notification settings controller and binding"
```

---

### Task 10: Settings screen, route, and User Area entry

**Files:**
- Create: `lib/app/modules/notification_settings/notification_settings_screen.dart`
- Modify: `lib/app/data/routes/app_routes.dart` (two constant blocks)
- Modify: `lib/app/data/routes/app_pages.dart` (import + GetPage)
- Modify: `lib/app/modules/user_area/user_area_screen.dart` (Preferences group)
- Test: `test/widget/notification_settings_screen_test.dart`

**Interfaces:**
- Consumes: `NotificationSettingsController` (Task 9), `SettingsGroup`/`SettingsRow`/`SettingsSwitchRow`/`SelectableFilterChip`, `MainAppBar`, `AppSpace`/`AppColors`, `kDigestDoctypes`.
- Produces: route `AppRoutes.NOTIFICATION_SETTINGS = '/notification-settings'`; visible entry point on Android.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/notification_settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_controller.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_screen.dart';

class _FakeGetStorage {
  final Map<String, dynamic> _data = {};
  Future<void> write(String key, dynamic value) async {
    _data[key] = value;
  }

  Future<void> remove(String key) async {
    _data.remove(key);
  }

  T? read<T>(String key) => _data[key] as T?;
  bool hasData(String key) => _data.containsKey(key);
}

class _FakeWork implements WorkScheduler {
  @override
  Future<void> registerOneOff(
      {required String uniqueName,
      required String taskName,
      required Duration initialDelay}) async {}

  @override
  Future<void> cancel(String uniqueName) async {}
}

void main() {
  late StorageService storage;

  setUp(() {
    final box = _FakeGetStorage();
    box._data['currentUser'] = {
      'name': 'a@b.c',
      'full_name': 'A',
      'email': 'a@b.c',
    };
    storage = StorageService.withStorage(box as dynamic);
    Get.put<NotificationSettingsController>(NotificationSettingsController(
      storage: storage,
      scheduler: DigestScheduler(storage: storage, work: _FakeWork()),
      requestPermission: () async => true,
    ));
  });

  tearDown(() => Get.deleteAll(force: true));

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        GetMaterialApp(home: const NotificationSettingsScreen()),
      );

  testWidgets('renders master switch off with sections hidden',
      (tester) async {
    await pump(tester);
    expect(find.text('Scheduled digest'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget); // master only
    expect(find.text('Times'), findsNothing);
  });

  testWidgets('enabling reveals times, days and documents sections',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Times'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Purchase Order'), findsOneWidget);
    expect(find.text('POS Upload'), findsOneWidget);
    // master + five doctype switches
    expect(find.byType(Switch), findsNWidgets(6));
  });

  testWidgets('renders in dark theme without contrast crashes',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.dark(),
      home: const NotificationSettingsScreen(),
    ));
    expect(find.text('Scheduled digest'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/notification_settings_screen_test.dart`
Expected: FAIL — screen file missing.

- [ ] **Step 3: Implement the screen**

Create `lib/app/modules/notification_settings/notification_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/digest_service.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_controller.dart';

class NotificationSettingsScreen
    extends GetView<NotificationSettingsController> {
  const NotificationSettingsScreen({super.key});

  static const _dayLabels = {
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Notifications'),
      body: Obx(
        () => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroup(
                children: [
                  SettingsSwitchRow(
                    title: 'Scheduled digest',
                    subtitle:
                        'Notify me about documents that need action, even '
                        'when the app is closed',
                    value: controller.enabled.value,
                    onChanged: controller.setEnabled,
                  ),
                ],
              ),
              if (controller.enabled.value) ...[
                const SizedBox(height: AppSpace.s4),
                SettingsGroup(
                  label: 'Times',
                  children: [_timesEditor(context)],
                ),
                const SizedBox(height: AppSpace.s4),
                SettingsGroup(
                  label: 'Days',
                  children: [_daysEditor()],
                ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _timesEditor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s3),
      child: Wrap(
        spacing: AppSpace.s2,
        runSpacing: AppSpace.s2,
        children: [
          for (final t in controller.times)
            InputChip(
              label: Text(t),
              onDeleted: () => controller.removeTime(t),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Add time'),
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 9, minute: 0),
              );
              if (picked != null) {
                controller.addTime(picked.hour, picked.minute);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _daysEditor() {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s3),
      child: Wrap(
        spacing: AppSpace.s2,
        runSpacing: AppSpace.s2,
        children: [
          for (final entry in _dayLabels.entries)
            SelectableFilterChip(
              label: entry.value,
              selected: controller.days.contains(entry.key),
              onSelected: (_) => controller.toggleDay(entry.key),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Register the route**

In `lib/app/data/routes/app_routes.dart` add alongside the THEME/SESSION_DEFAULTS pairs:

```dart
  static const NOTIFICATION_SETTINGS = _Paths.NOTIFICATION_SETTINGS;
```

and in the `_Paths` class:

```dart
  static const NOTIFICATION_SETTINGS = '/notification-settings';
```

In `lib/app/data/routes/app_pages.dart` add imports:

```dart
import 'package:multimax/app/modules/notification_settings/notification_settings_screen.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_binding.dart';
```

and after the SESSION_DEFAULTS GetPage:

```dart
    GetPage(
      name: AppRoutes.NOTIFICATION_SETTINGS,
      page: () => const NotificationSettingsScreen(),
      binding: NotificationSettingsBinding(),
      transition: Transition.rightToLeft,
    ),
```

- [ ] **Step 5: Add the User Area row (Android-gated)**

In `lib/app/modules/user_area/user_area_screen.dart` add imports:

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
```

and inside the `Preferences` `SettingsGroup`, after the `Session Defaults` `SettingsRow`, add:

```dart
                if (!kIsWeb && Platform.isAndroid)
                  SettingsRow(
                    icon: Icons.notifications_outlined,
                    iconTint: AppColors.orange500,
                    title: 'Notifications',
                    onTap: () => Get.toNamed(AppRoutes.NOTIFICATION_SETTINGS),
                  ),
```

- [ ] **Step 6: Run the widget test + analyze**

Run: `flutter test test/widget/notification_settings_screen_test.dart`
Expected: all tests PASS.
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git branch --show-current
git add lib/app/modules/notification_settings/ lib/app/data/routes/ lib/app/modules/user_area/user_area_screen.dart test/widget/notification_settings_screen_test.dart
git commit -m "feat(notifications): notification settings screen, route and User Area entry"
```

---

### Task 11: Final verification

**Files:**
- Modify: `CHANGELOG.md` (prepend entry)

**Interfaces:**
- Consumes: everything above.
- Produces: verified feature branch ready for review/merge.

- [ ] **Step 1: Full analyze + test suite**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: no failures beyond the pre-existing baseline (record the numbers; the suite had a known pre-existing-failure baseline — compare against a run from before Task 1, not against zero).

- [ ] **Step 2: Debug build**

Run: `flutter build apk --debug`
Expected: builds clean.

- [ ] **Step 3: CHANGELOG entry**

Prepend to `CHANGELOG.md` under a new heading following the file's existing format:

```markdown
## Scheduled Digest Notifications (Android)

- New User Area → Notifications screen: schedule a recurring digest of
  draft Purchase Orders / Purchase Receipts / Delivery Notes / Stock
  Entries and open POS Uploads (Pending / In Progress).
- OS notification fires at chosen times/days even when the app is closed
  (WorkManager background fetch); silent when nothing is pending.
- Session-expiry and permission edge cases degrade silently — the digest
  never nags about its own failures.
```

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add CHANGELOG.md
git commit -m "docs: changelog entry for scheduled digest notifications"
```

- [ ] **Step 5: On-device manual smoke checklist (user-assisted, Zebra/Android device)**

Report these to the user to run — they are the release gate, not automatable here:

1. Enable digest in User Area → Notifications; accept the permission prompt (Android 13+).
2. Add a time ~3 minutes ahead; confirm with drafts present the notification arrives with correct counts (WorkManager may add a few minutes' latency).
3. Clear/complete all pending docs; next tick → no notification.
4. Log out → pending digest notification disappears; log back in → schedule resumes.
5. Reboot the device → digest still fires at the next scheduled time.
6. Deny the permission → master switch reverts with the warning snackbar.

Version note: this is a `feat:` (new module + screen + flow) → **MINOR** bump at release time per `docs/versioning_conventions.md` (do not bump in this plan; releases are cut separately).
