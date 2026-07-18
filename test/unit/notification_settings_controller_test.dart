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
    // 3 persisting adds (16:00, 08:05, 12:00); the duplicate and the
    // over-cap add both return before persisting/re-arming.
    expect(scheduler.rearms, 3);
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
    expect(scheduler.rearms, 2);
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
    expect(scheduler.rearms, 1);
  });

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
}
