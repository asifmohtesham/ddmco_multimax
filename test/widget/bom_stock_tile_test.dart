import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';

Widget _wrap(Map<String, dynamic> row) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 380, child: BomStockTile(row: row))),
      ),
    );

void main() {
  testWidgets('renders item name, code/group subline, customer-code chip, In Stock',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '1',
      'item_name': 'STRAPS T/X PRINT 40mm',
      'item_code': '2001272',
      'item_group': 'Straps',
      'customer_code': '5052483',
      'in_stock_qty': 816,
    }));
    expect(find.text('STRAPS T/X PRINT 40mm'), findsOneWidget);
    expect(find.textContaining('2001272'), findsWidgets);
    expect(find.text('5052483'), findsOneWidget);
    expect(find.text('In Stock'), findsOneWidget);
    expect(find.text('816'), findsOneWidget);
  });

  testWidgets('no POS: hides Need/Short and the status pill', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '1', 'item_name': 'X', 'item_code': 'X1', 'in_stock_qty': 10,
    }));
    expect(find.text('Need'), findsNothing);
    expect(find.text('Short'), findsNothing);
    expect(find.text('Covered'), findsNothing);
  });

  testWidgets('POS covered row: shows Need/Short stats + green Covered pill',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '2', 'item_name': 'STRAPS', 'item_code': '2001272',
      'in_stock_qty': 816, 'required_qty': 36, 'shortage_qty': 0,
    }));
    expect(find.text('Need'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('Covered'), findsOneWidget);
  });

  testWidgets('POS shortfall row: shows red Short pill with the deficit',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '3', 'item_name': 'BELTS PU HQ', 'item_code': '2002843',
      'in_stock_qty': 396, 'required_qty': 2400, 'shortage_qty': 2004,
    }));
    expect(find.text('Short 2004'), findsOneWidget);
    expect(find.text('Covered'), findsNothing);
  });

  testWidgets('shows Build only when enough_parts_to_build present', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '4', 'item_name': 'SUB', 'item_code': 'S1',
      'in_stock_qty': 5, 'enough_parts_to_build': 12, 'bom': 'BOM-S1-001',
    }));
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('long BOM name does not overflow', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '5', 'item_name': 'SUB ASSEMBLY ITEM', 'item_code': 'S2',
      'in_stock_qty': 1, 'bom': 'BOM-VERY-LONG-NAME-2001272-REV-003-EXTENDED',
    }));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
