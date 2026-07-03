import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
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
}
