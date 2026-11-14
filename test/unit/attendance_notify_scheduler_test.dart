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
