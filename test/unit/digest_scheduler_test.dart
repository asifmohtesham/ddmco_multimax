import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/reminder_scheduler.dart';
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

void main() {
  const userJson = {
    'name': 'asif@example.com',
    'full_name': 'Asif',
    'email': 'asif@example.com',
    'roles': [
      {'role': 'Stock Manager'}
    ],
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
    scheduler = DigestScheduler(
        storage: storage, work: work, now: () => now, isIos: false);
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

  test('enabled but no doctypes selected → cancel (no-op wake avoided)',
      () async {
    box._data['currentUser'] = userJson;
    await storage.saveDigestEnabled('asif@example.com', true);
    await storage.saveDigestDoctypes('asif@example.com', []);
    await scheduler.rearm();
    expect(work.cancelled, [kDigestUniqueName]);
    expect(work.registered, isEmpty);
  });

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

  test('iOS manager, standard style -> reschedules with timeSensitive:false',
      () async {
    box._data['currentUser'] = userJson; // manager
    await storage.saveDigestEnabled('asif@example.com', true);
    await storage.saveDigestTimes('asif@example.com', ['09:00']);
    await storage.saveDigestAlarmStyle('asif@example.com', 'standard');
    final reminders = _FakeReminders();
    final scheduler = DigestScheduler(
        storage: storage, reminders: reminders, now: () => now, isIos: true);
    await scheduler.rearm();
    expect(reminders.lastTimeSensitive, isFalse);
  });

  test('iOS manager, empty times -> cancelAll, no reschedule', () async {
    box._data['currentUser'] = userJson; // manager
    await storage.saveDigestEnabled('asif@example.com', true);
    await storage.saveDigestTimes('asif@example.com', <String>[]);
    final reminders = _FakeReminders();
    final scheduler = DigestScheduler(
        storage: storage, reminders: reminders, now: () => now, isIos: true);
    await scheduler.rearm();
    expect(reminders.rescheduled, isEmpty);
    expect(reminders.cancelAllCount, greaterThan(0));
  });
}
