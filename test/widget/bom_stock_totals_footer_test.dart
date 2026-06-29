import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';

void main() {
  testWidgets('renders nothing when totals is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BomStockTotalsFooter(totals: null, hasDemand: true)),
    ));
    expect(find.text('Total'), findsNothing);
  });

  testWidgets('no demand: shows Stock only (no Need/Short)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BomStockTotalsFooter(
          totals: {'in_stock': 16239, 'required': 0, 'shortage': 0},
          hasDemand: false,
        ),
      ),
    ));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('16239'), findsOneWidget);
    expect(find.text('Need'), findsNothing);
    expect(find.text('Short'), findsNothing);
  });

  testWidgets('with demand: shows Stock + Need + Short', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BomStockTotalsFooter(
          totals: {'in_stock': 16239, 'required': 7644, 'shortage': 2004},
          hasDemand: true,
        ),
      ),
    ));
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Need'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('7644'), findsOneWidget);
    expect(find.text('2004'), findsOneWidget);
  });
}
