import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
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
  });

  tearDown(() => Get.deleteAll(force: true));
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        GetMaterialApp(home: const NotificationSettingsScreen()),
      );

  testWidgets('renders master switch off with sections hidden',
      (tester) async {
    await pump(tester);
    expect(find.text('Scheduled digest'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget); // master only
    // SectionLabel (settings_group.dart) uppercases group labels — the
    // rendered text is "TIMES", not "Times". See task-10-report.md.
    expect(find.text('TIMES'), findsNothing);
  });

  testWidgets('enabling reveals times, days and documents sections',
      (tester) async {
    // debugDefaultTargetPlatformOverride must be reset *inside* the test body
    // (not just via the outer tearDown) — flutter_test's end-of-test
    // invariant check (debugAssertAllFoundationVarsUnset) runs before the
    // package:test tearDown queue, so a leaked override fails the test even
    // when every expectation passed. See form_test.dart in the Flutter SDK
    // for the same try/finally idiom.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pump(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('TIMES'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('DAYS'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('DOCUMENTS'), findsOneWidget);
      expect(find.text('Purchase Order'), findsOneWidget);
      expect(find.text('POS Upload'), findsOneWidget);
      // master + five doctype switches
      expect(find.byType(Switch), findsNWidgets(6));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('renders in dark theme without contrast crashes',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData.dark(),
      home: const NotificationSettingsScreen(),
    ));
    expect(find.text('Scheduled digest'), findsOneWidget);
  });

  testWidgets('Android: shows Documents + alert-style segments',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pump(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
          find.text('DOCUMENTS'), findsOneWidget); // SectionLabel uppercases
      expect(find.text('ALERT STYLE'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Alarm'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS: hides Documents, keeps alert-style', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('DOCUMENTS'), findsNothing);
      expect(find.text('ALERT STYLE'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a linked employee sees Attendance reminders and no digest', (tester) async {
    Get.deleteAll(force: true);
    final box = _FakeGetStorage();
    box._data['currentUser'] = {
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
    box._data['currentUser'] = {
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
}
