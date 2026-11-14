import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';

// The sticky total bar and the segmented state filter render aggregates / view
// state. These render them across light/dark on a narrow viewport — guarding the
// dense layouts against overflow and confirming segment wiring.
void main() {
  const totals = StockBalanceTotals(
    itemCount: 24,
    warehouseCount: 1,
    negativeCount: 1,
    opening: 1208,
    inQty: 642,
    outQty: 418,
    balance: 1432,
    value: 64180,
  );

  Future<void> pump(WidgetTester tester, Widget child, Brightness b) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF870E18),
            brightness: b,
          ),
        ),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final b in Brightness.values) {
    final mode = b.name;

    testWidgets('total bar shows value + ledger totals without overflow ($mode)',
        (tester) async {
      await pump(tester, buildStockBalanceTotalBarForTest(totals), b);
      expect(find.textContaining('TOTAL'), findsWidgets);
      expect(find.text('64,180.00'), findsOneWidget);
      expect(find.text('+642'), findsOneWidget);
      expect(find.text('−418'), findsOneWidget); // U+2212
      expect(find.text('1,432'), findsOneWidget);
    });

    testWidgets('state filter renders the four segments + wires onState ($mode)',
        (tester) async {
      var picked = '';
      await pump(
        tester,
        buildStockBalanceStateFilterForTest(onState: (v) => picked = v),
        b,
      );
      // The four state segments.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('In stock'), findsOneWidget);
      expect(find.text('Negative'), findsOneWidget);
      expect(find.text('Empty'), findsOneWidget);

      await tester.tap(find.text('Negative'));
      expect(picked, 'neg');
    });

    testWidgets('warehouse pills render All + each warehouse, single-tap ($mode)',
        (tester) async {
      var picked = '';
      await pump(
        tester,
        buildStockBalanceWarehouseChipsForTest(
          warehouses: const ['WH-DXB1 - KA', 'WH-DXB3 - KA'],
          onSelected: (v) => picked = v,
        ),
        b,
      );
      expect(find.text('All'), findsOneWidget);
      expect(find.text('WH-DXB1 - KA'), findsOneWidget);
      expect(find.text('WH-DXB3 - KA'), findsOneWidget);

      // First warehouse chip is on-screen; later chips scroll horizontally.
      await tester.tap(find.text('WH-DXB1 - KA'));
      expect(picked, 'WH-DXB1 - KA');
    });
  }
}
