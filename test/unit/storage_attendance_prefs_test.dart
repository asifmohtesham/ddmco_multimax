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
