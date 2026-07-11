import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/modules/todo/form/todo_form_controller.dart';
import 'package:multimax/app/modules/todo/form/todo_form_screen.dart';

class _FakeToDoProvider extends ToDoProvider {
  final Map<String, dynamic> data;
  _FakeToDoProvider(this.data);

  @override
  Future<Response> getTodo(String name) async => Response(
        requestOptions: RequestOptions(path: '/api/resource/ToDo/$name'),
        statusCode: 200,
        data: {'data': data},
      );
}

class _FakeUserProvider extends UserProvider {
  @override
  Future<Response> getUsers() async => Response(
        requestOptions: RequestOptions(path: '/api/resource/User'),
        statusCode: 200,
        data: {'data': const <Map<String, dynamic>>[]},
      );
}

Map<String, dynamic> _todoJson() => {
      'name': 'TD-0001',
      'status': 'Open',
      'description': 'Pack DN-101',
      'modified': '2026-07-11 09:00:00',
      'priority': 'High',
      'date': '2026-07-15',
      'reference_type': 'Delivery Note',
      'reference_name': 'DN-00042',
      'allocated_to': 'ops@x.com',
      'owner': 'ops@x.com',
      'assigned_by': '',
    };

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<ToDoProvider>(_FakeToDoProvider(_todoJson()));
    Get.put<UserProvider>(_FakeUserProvider());
    Get.put(ToDoFormController());
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester,
      {Brightness brightness = Brightness.light}) async {
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const ToDoFormScreen(),
    ));
    // Two pumps: the first lets the widget tree mount and onInit's
    // fire-and-forget fetchDocument() start; the second flushes the
    // now-resolved Future (the fake providers respond with zero delay).
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders the fetched ToDo in view mode', (tester) async {
    await pump(tester);
    expect(find.text('TD-0001'), findsOneWidget);
    expect(find.text('Pack DN-101'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('2026-07-15'), findsOneWidget);
  });

  testWidgets('shows the reference document as an open-in-new chip in view mode',
      (tester) async {
    await pump(tester);
    expect(find.text('DN-00042'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('hides the Save action in view mode', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Save'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    expect(find.text('TD-0001'), findsOneWidget);
  });
}
