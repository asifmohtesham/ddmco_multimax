import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';

Widget _wrap(Map<String, dynamic> row) =>
    MaterialApp(home: Scaffold(body: BomStockTile(row: row)));

void main() {
  testWidgets('renders item name, code, and customer code', (tester) async {
    await tester.pumpWidget(_wrap({
      'item_name': 'BELTS PU HQ',
      'item_code': '2002843',
      'customer_code': '5067101',
      'in_stock_qty': 396,
      'running_total': 396,
    }));

    expect(find.text('BELTS PU HQ'), findsOneWidget);
    expect(find.text('2002843'), findsOneWidget);
    expect(find.text('5067101'), findsOneWidget);
  });

  testWidgets('shows the Required metric only when required_qty is present',
      (tester) async {
    await tester.pumpWidget(_wrap({
      'item_name': 'X',
      'item_code': 'X1',
      'in_stock_qty': 10,
      'running_total': 10,
    }));
    expect(find.text('Required'), findsNothing);

    await tester.pumpWidget(_wrap({
      'item_name': 'X',
      'item_code': 'X1',
      'in_stock_qty': 10,
      'required_qty': 5,
      'running_total': 10,
    }));
    expect(find.text('Required'), findsOneWidget);
  });
}
