import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';

// The summary strip (counts + view toggles + negative chip), the sticky total
// bar, and the quick-filter control bar all render aggregates / view state.
// These render them across light/dark on a narrow viewport — guarding the dense
// layouts against overflow and confirming toggle/chip wiring.
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

    testWidgets('summary strip shows counts, toggles + negative chip ($mode)',
        (tester) async {
      var hideToggled = false, imgToggled = false, negToggled = false;
      await pump(
        tester,
        buildStockBalanceSummaryForTest(
          shownCount: 9,
          warehouseCount: 2,
          negativeCount: 2,
          onToggleHideEmpty: () => hideToggled = true,
          onToggleImages: () => imgToggled = true,
          onToggleNegative: () => negToggled = true,
        ),
        b,
      );
      expect(find.textContaining('shown'), findsOneWidget);
      expect(find.textContaining('warehouses'), findsOneWidget);
      expect(find.text('Images'), findsOneWidget);
      expect(find.text('Hide empty'), findsOneWidget);
      expect(find.text('2 negative'), findsOneWidget);

      await tester.tap(find.text('Hide empty'));
      await tester.tap(find.text('Images'));
      await tester.tap(find.text('2 negative'));
      expect(hideToggled, isTrue);
      expect(imgToggled, isTrue);
      expect(negToggled, isTrue);
    });

    testWidgets('summary strip hides the negative chip when zero ($mode)',
        (tester) async {
      await pump(
        tester,
        buildStockBalanceSummaryForTest(
          shownCount: 3,
          warehouseCount: 1,
          negativeCount: 0,
        ),
        b,
      );
      expect(find.textContaining('negative'), findsNothing);
      expect(find.textContaining('warehouse'), findsOneWidget); // singular
    });

    testWidgets('total bar shows value + ledger totals without overflow ($mode)',
        (tester) async {
      await pump(tester, buildStockBalanceTotalBarForTest(totals), b);
      expect(find.textContaining('TOTAL'), findsWidgets);
      expect(find.text('64,180.00'), findsOneWidget);
      expect(find.text('+642'), findsOneWidget);
      expect(find.text('−418'), findsOneWidget); // U+2212
      expect(find.text('1,432'), findsOneWidget);
    });

    testWidgets('quick-filter bar renders search, dropdowns + segments ($mode)',
        (tester) async {
      var picked = '';
      await pump(
        tester,
        buildStockBalanceQuickFilterBarForTest(
          warehouses: const ['WH-DXB1 - MAIN', 'WH-DXB3 - KA'],
          onState: (v) => picked = v,
        ),
        b,
      );
      expect(find.byType(TextField), findsOneWidget);
      // The four state segments.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('In stock'), findsOneWidget);
      expect(find.text('Negative'), findsOneWidget);
      expect(find.text('Empty'), findsOneWidget);

      await tester.tap(find.text('Negative'));
      expect(picked, 'neg');
    });
  }
}
