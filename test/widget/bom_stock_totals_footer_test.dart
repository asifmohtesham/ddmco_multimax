import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';

void main() {
  testWidgets('renders nothing when total is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BomStockTotalsFooter(total: null)),
    ));
    expect(find.text('Total'), findsNothing);
  });

  testWidgets('renders the total figures when present', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BomStockTotalsFooter(total: {
          'in_stock_qty': 16239,
          'required_qty': 7644,
          'running_total': 16239,
        }),
      ),
    ));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('16239'), findsWidgets);
    expect(find.text('7644'), findsOneWidget);
  });
}
