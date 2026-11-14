import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart';

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
    Get.put(PosDnItemRateController());
  });
  tearDown(Get.reset);

  testWidgets('sheet shows all filter sections, defaults, and Run button',
      (tester) async {
    final c = Get.find<PosDnItemRateController>();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showPosDnItemRateFilterSheet(ctx, c),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('POS Uploads'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Customer Groups'), findsOneWidget);
    expect(find.text('Item Groups'), findsOneWidget);
    expect(find.text('From Date'), findsOneWidget);
    expect(find.text('To Date'), findsOneWidget);
    expect(find.text('Show already-mapped'), findsOneWidget);
    expect(find.text('Only lines with a customer code'), findsOneWidget);
    expect(find.text('Run Report'), findsOneWidget);
    // From Date is pre-filled with the 30-day default from onInit.
    expect(c.fromDate.value, isNotNull);
    expect(find.text(c.fromDate.value!), findsOneWidget);
  });

  testWidgets('selected values render as removable chips', (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.posUploads.add('KA-2025-61960');
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showPosDnItemRateFilterSheet(ctx, c),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('KA-2025-61960'), findsOneWidget);
    // Material 3's InputChip defaults its delete icon to Icons.clear (see
    // flutter/material/input_chip.dart), not the pre-M3 Icons.cancel
    // fallback in chip.dart — this app runs Material 3.
    await tester.tap(find.descendant(
        of: find.widgetWithText(InputChip, 'KA-2025-61960'),
        matching: find.byIcon(Icons.clear)));
    await tester.pumpAndSettle();
    expect(c.posUploads, isEmpty);
  });
}
