import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart';

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
    Get.put(PermissionService());
    Get.put(AuthenticationController());
    Get.put(PosDnItemRateController());
  });
  tearDown(Get.reset);

  List<Map<String, dynamic>> fourRows() => [
        {'status': 'New', 'ref_code': '5067101', 'item_code': '2001272',
         'upload_item': 'STRAP TX', 'pos_upload': 'KA-1', 'idx': 1},
        {'status': 'Already mapped', 'ref_code': '5067102',
         'item_code': '2001273', 'upload_item': 'BELT PU',
         'pos_upload': 'KA-1', 'idx': 2},
        {'status': 'No delivery line', 'ref_code': '5067103',
         'upload_item': 'WALLETS COW', 'pos_upload': 'KA-1', 'idx': 3},
        {'status': 'No code', 'upload_item': 'CARD CASE',
         'pos_upload': 'KA-1', 'idx': 4},
      ];

  testWidgets('shows the run prompt before any run', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.textContaining('Run Report'), findsWidgets);
  });

  testWidgets('renders summary counts and one tile per row', (tester) async {
    // The default 800x600 test surface only leaves room for ~1 of the 4
    // tiles below the DocTypeListHeader + summary strip + chip row (lazy
    // slivers only build on-screen children) — enlarge so all 4 render.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(fourRows());
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();

    expect(find.text('1 new'), findsOneWidget);
    expect(find.text('1 no delivery'), findsOneWidget);
    expect(find.text('1 no code'), findsOneWidget);
    expect(find.text('STRAP TX'), findsOneWidget);
    expect(find.text('CARD CASE'), findsOneWidget);
  });

  testWidgets('status chip filters the list', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(fourRows());
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();

    // The chip label is 'No delivery line (1)' — textContaining hits the chip
    // (chips row precedes the tile list in the tree, so .first is the chip).
    await tester.tap(find.textContaining('No delivery line').first);
    await tester.pump();
    expect(find.text('WALLETS COW'), findsOneWidget);
    expect(find.text('STRAP TX'), findsNothing);
  });

  testWidgets('Already mapped chip appears only when such rows exist',
      (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(
        fourRows().where((r) => r['status'] != 'Already mapped').toList());
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.text('Already mapped'), findsNothing);
  });

  testWidgets('error state renders when a run failed with no rows',
      (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.errorMessage.value = 'Report not deployed on this instance.';
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.text('Report not deployed on this instance.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
