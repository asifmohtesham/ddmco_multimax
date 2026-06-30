import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart';

Widget _wrap(Map<String, dynamic> row) =>
    MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 380, child: BomStockLineRow(row: row)))));

void main() {
  testWidgets('shows item name + In Stock/Avail/Need/Short figures', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'item_name': 'STRAPS IT 35mm', 'item_code': '2001999', 'item_group': 'Straps',
      'in_stock_qty': 84, 'running_total': 84, 'required_qty': 108, 'shortage_qty': 24,
    }));
    expect(find.text('STRAPS IT 35mm'), findsOneWidget);
    expect(find.text('In Stock'), findsOneWidget);
    expect(find.text('Avail'), findsOneWidget);
    expect(find.text('Need'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('108'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('covered row shows Short 0', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'item_name': 'X', 'item_code': 'X1', 'in_stock_qty': 816,
      'running_total': 816, 'required_qty': 36, 'shortage_qty': 0,
    }));
    expect(find.text('0'), findsOneWidget); // Short 0
  });
}
