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
