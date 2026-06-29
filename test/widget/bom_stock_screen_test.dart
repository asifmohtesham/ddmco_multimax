import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart';

void main() {
  setUpAll(() {
    // ApiProvider() fires _initDio() asynchronously which calls path_provider.
    // Stub the MethodChannel so the background async doesn't leak into tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    // AppShellScaffold → AppNavDrawer requires AuthenticationController and
    // PermissionService (via DocTypeGuard). Register them before the screen is
    // pumped so Get.find() inside their build() methods succeeds.
    Get.put(ApiProvider());
    Get.put(PermissionService());
    Get.put(AuthenticationController());
    Get.put(BomStockCustomerCodeController());
  });
  tearDown(Get.reset);

  testWidgets('shows the empty-state prompt before any run', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.textContaining('Run Report'), findsWidgets);
  });

  testWidgets('renders a tile for each result row', (tester) async {
    final c = Get.find<BomStockCustomerCodeController>();
    c.reportRows.assignAll([
      {'item_name': 'BELTS PU HQ', 'item_code': '2002843', 'in_stock_qty': 396, 'running_total': 396},
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('BELTS PU HQ'), findsOneWidget);
  });

  testWidgets('shows the All | In Stock | Shortage segmented filter when rows exist',
      (tester) async {
    final c = Get.find<BomStockCustomerCodeController>();
    c.reportRows.assignAll([
      {'sl_no': '1', 'item_name': 'BELTS PU HQ', 'item_code': '2002843', 'in_stock_qty': 396},
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('All'), findsOneWidget);
    expect(find.text('In Stock'), findsWidgets);
    expect(find.text('Shortage'), findsOneWidget);
  });
}
