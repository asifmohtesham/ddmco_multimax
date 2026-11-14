import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart';

Widget _wrap(Map<String, dynamic> row, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Center(
            child: SizedBox(width: 380, child: PosDnItemRateTile(row: row))),
      ),
    );

const _newRow = {
  'status': 'New',
  'ref_code': '5067101',
  'item_code': '2001272',
  'item_group': 'Straps',
  'dn_item': 'STRAPS T/X PRINT 40mm',
  'upload_item': 'STRAP TX 40',
  'customer': 'MULTI BRAND TRADING',
  'customer_group': 'Commercial',
  'upload_qty': 108,
  'upload_rate': 120.0,
  'dn_qty': 108,
  'dn_name': 'MAT-DN-2025-01234',
  'pos_upload': 'KA-2025-61960',
  'idx': 7,
};

void main() {
  // GetMaterialApp keeps its navigator/route state in a global singleton;
  // without a reset, route assertions in one test can leak into the next.
  tearDown(Get.reset);

  testWidgets('New row: shows pill, hero code+item, both item names, numbers',
      (tester) async {
    await tester.pumpWidget(_wrap(_newRow));
    expect(find.text('New'), findsOneWidget);
    expect(find.text('5067101'), findsOneWidget);
    expect(find.text('2001272'), findsOneWidget);
    expect(find.text('STRAPS T/X PRINT 40mm'), findsOneWidget);
    expect(find.text('STRAP TX 40'), findsOneWidget);
    expect(find.text('MULTI BRAND TRADING'), findsOneWidget);
    expect(find.text('MAT-DN-2025-01234'), findsOneWidget);
    expect(find.textContaining('KA-2025-61960'), findsOneWidget);
  });

  testWidgets('No delivery line row: renders without item_code or DN link',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'status': 'No delivery line',
      'ref_code': '5067103',
      'upload_item': 'WALLETS COW',
      'upload_qty': 72,
      'pos_upload': 'KA-2025-61961',
      'idx': 3,
    }));
    expect(find.text('No delivery line'), findsOneWidget);
    expect(find.text('WALLETS COW'), findsOneWidget);
  });

  testWidgets('No code row: renders em-dash for the missing ref_code',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'status': 'No code',
      'upload_item': 'CARD CASE FANCY',
      'upload_qty': 108,
      'pos_upload': 'KA-2025-61960',
      'idx': 1,
    }));
    expect(find.text('No code'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('Already mapped row renders its pill', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'status': 'Already mapped',
      'ref_code': '5067102',
      'item_code': '2001273',
      'upload_item': 'BELT PU',
      'pos_upload': 'KA-2025-61960',
      'idx': 2,
    }));
    expect(find.text('Already mapped'), findsOneWidget);
  });

  group('posDnStatusAccent uses the theme-aware ramp', () {
    testWidgets('light: New=green700, No delivery line=orange700',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      expect(posDnStatusAccent(ctx, 'New'), AppColors.green700);
      expect(posDnStatusAccent(ctx, 'No delivery line'), AppColors.orange700);
    });

    testWidgets('dark: New=green300, No delivery line=orange300',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      expect(posDnStatusAccent(ctx, 'New'), AppColors.green300);
      expect(posDnStatusAccent(ctx, 'No delivery line'), AppColors.orange300);
    });
  });

  testWidgets('renders a thumbnail (initials) for a New row', (tester) async {
    await tester.pumpWidget(_wrap(_newRow));
    // ItemThumbnail present; initials from 'STRAPS T/X PRINT 40mm' -> 'ST'
    expect(find.byType(ItemThumbnail), findsOneWidget);
  });

  testWidgets('tapping the card navigates to ITEM_FORM when item_code present',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/home',
      getPages: [
        GetPage(name: '/home', page: () => Scaffold(
          body: Center(child: SizedBox(width: 380,
              child: PosDnItemRateTile(row: _newRow))))),
        GetPage(name: AppRoutes.ITEM_FORM,
            page: () => const Scaffold(body: Text('ITEM FORM STUB'))),
      ],
    ));
    // Tap the card body (avoid the thumbnail and voucher chips).
    await tester.tapAt(tester.getCenter(find.text('DN')));
    await tester.pumpAndSettle();
    expect(find.text('ITEM FORM STUB'), findsOneWidget);
    expect(Get.arguments, {'itemCode': '2001272'});
  });

  testWidgets('card is NOT tappable for a No code row (no item_code)',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/home',
      getPages: [
        GetPage(name: '/home', page: () => Scaffold(
          body: Center(child: SizedBox(width: 380, child: PosDnItemRateTile(row: const {
            'status': 'No code', 'upload_item': 'CARD CASE',
            'pos_upload': 'KA-1', 'idx': 1,
          }))))),
        GetPage(name: AppRoutes.ITEM_FORM,
            page: () => const Scaffold(body: Text('ITEM FORM STUB'))),
      ],
    ));
    await tester.tapAt(tester.getCenter(find.text('CARD CASE')));
    await tester.pumpAndSettle();
    expect(find.text('ITEM FORM STUB'), findsNothing);
  });

  testWidgets('long-pressing the customer code copies it to the clipboard',
      (tester) async {
    final copied = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add(call);
      return null;
    });
    await tester.pumpWidget(_wrap(_newRow));
    await tester.longPress(find.text('5067101'));
    await tester.pump();
    expect(copied, isNotEmpty);
    expect(copied.first.arguments['text'], '5067101');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
