import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_group_card.dart';

const _rows = [
  {'item_name': 'STRAPS 40mm', 'item_code': '2001272', 'in_stock_qty': 816,
   'running_total': 816, 'required_qty': 36, 'shortage_qty': 0},
  {'item_name': 'STRAPS 35mm', 'item_code': '2001999', 'in_stock_qty': 84,
   'running_total': 84, 'required_qty': 108, 'shortage_qty': 24},
];

Widget _wrap({required bool expanded}) => MaterialApp(
      home: Scaffold(
        body: BomStockGroupCard(
          group: const BomStockGroup('5052483', _rows),
          expanded: expanded,
          onToggle: () {},
        ),
      ),
    );

void main() {
  testWidgets('collapsed: header (code + count + short pill), no line rows',
      (tester) async {
    await tester.pumpWidget(_wrap(expanded: false));
    expect(find.text('Code 5052483'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Short 24'), findsOneWidget); // group totalShortage = 24 → red
    expect(find.text('STRAPS 40mm'), findsNothing); // collapsed: lines hidden
  });

  testWidgets('expanded: line rows visible', (tester) async {
    await tester.pumpWidget(_wrap(expanded: true));
    await tester.pumpAndSettle();
    expect(find.text('STRAPS 40mm'), findsOneWidget);
    expect(find.text('STRAPS 35mm'), findsOneWidget);
  });

  testWidgets('all-covered group shows Covered pill', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BomStockGroupCard(
          group: const BomStockGroup('A', [
            {'item_name': 'Z', 'item_code': 'Z1', 'in_stock_qty': 10,
             'running_total': 10, 'required_qty': 4, 'shortage_qty': 0},
          ]),
          expanded: false,
          onToggle: () {},
        ),
      ),
    ));
    expect(find.text('Covered'), findsOneWidget);
  });
}
