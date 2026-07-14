import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/customer_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_screen.dart';

Response _ok(List<Map<String, dynamic>> rows) => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'data': rows},
    );

class _FakePosUploadProvider extends PosUploadProvider {
  static const _rows = [
    {
      'name': 'PU-0001',
      'customer': 'CUST-A',
      'date': '2026-07-01',
      'modified': '2026-07-01 10:00:00',
      'status': 'Pending',
    },
    {
      'name': 'PU-0002',
      'customer': 'CUST-B',
      'date': '2026-07-02',
      'modified': '2026-07-02 10:00:00',
      'status': 'Completed',
    },
  ];

  @override
  Future<Response> getPosUploads({
    int limit = 50,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    final status = filters?['status'];
    final rows = status == null
        ? _rows
        : _rows.where((r) => r['status'] == status).toList();
    return _ok(rows);
  }
}

class _FakeCustomerProvider extends CustomerProvider {
  @override
  Future<Response> getCustomers({int limit = 0, String? searchTerm}) async =>
      _ok(const []);
}

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
    Get.put(ApiProvider());
    Get.put<PosUploadProvider>(_FakePosUploadProvider());
    Get.put<CustomerProvider>(_FakeCustomerProvider());
    Get.put(PosUploadController());
  });
  tearDown(Get.reset);

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GetMaterialApp(home: PosUploadScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a status pill filters the list by that status',
      (tester) async {
    await pumpList(tester);
    expect(find.text('PU-0001'), findsOneWidget);
    expect(find.text('PU-0002'), findsOneWidget);

    await tester.tap(find.widgetWithText(StatusPill, 'Pending'));
    await tester.pumpAndSettle();

    final controller = Get.find<PosUploadController>();
    expect(controller.activeFilters['status'], 'Pending');
    expect(find.text('PU-0001'), findsOneWidget);
    expect(find.text('PU-0002'), findsNothing);
    // Active-filter chip appears in the header and the tap did NOT
    // trigger the card's onTap navigation to the form.
    expect(find.text('Status: Pending'), findsOneWidget);
    expect(find.byType(PosUploadScreen), findsOneWidget);
  });

  testWidgets('tapping the active status again clears the filter',
      (tester) async {
    await pumpList(tester);

    await tester.tap(find.widgetWithText(StatusPill, 'Pending'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(StatusPill, 'Pending'));
    await tester.pumpAndSettle();

    final controller = Get.find<PosUploadController>();
    expect(controller.activeFilters.containsKey('status'), isFalse);
    expect(find.text('PU-0001'), findsOneWidget);
    expect(find.text('PU-0002'), findsOneWidget);
    expect(find.text('Status: Pending'), findsNothing);
  });

  testWidgets('status filter from a pill tap preserves other active filters',
      (tester) async {
    await pumpList(tester);
    final controller = Get.find<PosUploadController>();
    controller.applyFilters({'customer': 'CUST-A'});
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(StatusPill, 'Pending'));
    await tester.pumpAndSettle();

    expect(controller.activeFilters['status'], 'Pending');
    expect(controller.activeFilters['customer'], 'CUST-A');
  });
}
