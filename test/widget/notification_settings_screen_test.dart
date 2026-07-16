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
    // SectionLabel (settings_group.dart) uppercases group labels — the
    // rendered text is "TIMES", not "Times". See task-10-report.md.
    expect(find.text('TIMES'), findsNothing);
  });

  testWidgets('enabling reveals times, days and documents sections',
      (tester) async {
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
