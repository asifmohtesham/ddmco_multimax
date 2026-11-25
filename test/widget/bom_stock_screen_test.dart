import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/main.dart' show buildAppTheme;

void main() {
  const fontFamily = 'BomStockTestInter';
  setUpAll(() async {
    final loader = FontLoader(fontFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('lib/assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
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

  testWidgets('POS active: renders grouped customer-code cards (not flat tiles)',
      (tester) async {
    final c = Get.find<BomStockCustomerCodeController>();
    c.posUpload.value = 'ML-2026-02011';
    c.reportRows.assignAll([
      {'sl_no': '1', 'item_name': 'STRAPS 40mm', 'item_code': '2001272',
       'customer_code': '5052483', 'in_stock_qty': 816, 'running_total': 816,
       'required_qty': 36, 'shortage_qty': 0},
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('5052483'), findsOneWidget);          // group header value (no 'Code ' prefix)
    expect(find.text('STRAPS 40mm'), findsNothing);       // collapsed by default
  });

  testWidgets('totals footer is hidden until rows exist', (tester) async {
    // Empty state (no run yet) — no footer.
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('Total'), findsNothing);

    // With rows — footer appears.
    final c = Get.find<BomStockCustomerCodeController>();
    c.reportRows.assignAll([
      {'sl_no': '1', 'item_name': 'BELTS PU HQ', 'item_code': '2002843', 'in_stock_qty': 396},
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('Total'), findsOneWidget);
  });

  testWidgets('loaded totals leave a hittable result below the scaled header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 380));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Get.put(
      ThemeController(persist: (_, _) async {}, restore: (_) async => null),
    );
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: fontFamily),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        home: const BomStockCustomerCodeScreen(),
      ),
    );
    final footer = find.byType(BomStockTotalsFooter);
    expect(footer, findsNothing);
    Get.find<BomStockCustomerCodeController>().reportRows.assignAll([
      for (var i = 0; i < 30; i++)
        {'item_name': 'Result $i', 'item_code': 'Item $i', 'in_stock_qty': 12},
    ]);
    await tester.pumpAndSettle();
    expect(footer, findsOneWidget);
    expect(tester.getSize(footer).height, greaterThan(0));
    final list = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ).first,
    );
    list.position.jumpTo(600);
    await tester.pumpAndSettle();

    final result = find.descendant(
      of: find.byType(BomStockTile),
      matching: find.textContaining('Result '),
    ).hitTestable();
    expect(result, findsWidgets);
    expect(
      tester.getCenter(result.first).dy,
      lessThan(tester.getTopLeft(footer).dy),
    );
  });
}
