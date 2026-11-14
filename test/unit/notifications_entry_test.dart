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
