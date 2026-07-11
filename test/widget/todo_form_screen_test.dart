import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
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

/// Grants every permission immediately, so DocTypeGuard-wrapped header
/// actions render without a network round-trip.
///
/// Reads a dummy `.obs` so DocTypeGuard's `Obx` still has a reactive
/// dependency to track — an override that returns a bare `true` with no
/// Rx read at all trips GetX's "improper use of Obx" assertion (Obx throws
/// when its builder registers zero subscriptions).
class _FakePermissionService extends PermissionService {
  final _granted = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) =>
      _granted.value;
}

Map<String, dynamic> _todoJson() => {
      'name': 'TD-0001',
      'status': 'Open',
      'description':
          '<div class="ql-editor read-mode"><p>Inventory: Price List</p></div>',
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
    Get.put<PermissionService>(_FakePermissionService());
    // Bare construction reads Get.arguments (null) → mode 'view', name '';
    // the cascade sets the name so Edit/Delete gating sees a saved doc.
    Get.put(ToDoFormController()..name = 'TD-0001');
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
    // Two pumps: mount + flush the zero-delay fake fetch.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('titles the form with the description text, not the hash',
      (tester) async {
    await pump(tester);
    // flutter_html renders its content as a plain Text (not RichText), so
    // this appears twice: once as the header title, once as the rendered
    // body. findsWidgets pins the actual regression under test — that the
    // hash no longer appears — without over-asserting on flutter_html's
    // internal rendering choice.
    expect(find.text('Inventory: Price List'), findsWidgets);
    expect(find.text('TD-0001'), findsNothing);
  });

  testWidgets('renders the description as rich text, not raw HTML',
      (tester) async {
    await pump(tester);
    expect(find.byType(Html), findsOneWidget);
    expect(find.textContaining('<div', findRichText: true), findsNothing);
  });

  testWidgets('labels the date field Due Date (v15 label)', (tester) async {
    await pump(tester);
    expect(find.text('Due Date'), findsOneWidget);
    expect(find.text('2026-07-15'), findsOneWidget);
  });

  testWidgets('view mode offers Edit; tapping flips to edit in place',
      (tester) async {
    await pump(tester);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pump();

    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.byType(Html), findsNothing,
        reason: 'edit mode swaps the rendered view for the text editor');
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
    // See the fallback note above: flutter_html's plain-Text rendering
    // means this text appears twice (title + body).
    expect(find.text('Inventory: Price List'), findsWidgets);
  });
}
