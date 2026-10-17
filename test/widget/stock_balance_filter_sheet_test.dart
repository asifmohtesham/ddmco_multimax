import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

// The Stock Balance filter sheet must expose every filter the v15 desk report
// does. Descriptors are static on the controller so they render here without
// GetX; the controllers map is hand-built the same way onInit builds it.
void main() {
  late Map<String, TextEditingController> ctrls;

  setUp(() {
    ctrls = {
      for (final f in StockBalanceController.filterFields)
        f.key: TextEditingController(),
      for (final t in StockBalanceController.toggles)
        t.key: TextEditingController(),
    };
  });
  tearDown(() {
    for (final c in ctrls.values) {
      c.dispose();
    }
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showReportFilterSheet(
              context: ctx,
              title: 'Stock Balance Filters',
              fields: StockBalanceController.filterFields,
              controllers: ctrls,
              toggles: StockBalanceController.toggles,
              togglesLabel: 'Display Options',
              onRun: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  /// Builds the lazy row (scrollUntilVisible) and then actually brings it
  /// into the ListView viewport — otherwise it sits under the Run button.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  testWidgets('sheet shows every desk filter and toggle', (tester) async {
    await open(tester);
    for (final label in [
      'From Date', 'To Date', 'Item Group', 'Items', 'Warehouses',
      'Warehouse Type', 'Rack', 'Include UOM', 'Customer Code',
    ]) {
      await reveal(tester, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final label in [
      'Dimension-wise', 'Variant Attributes', 'Stock Ageing',
      'Ignore Closing Balance', 'Include Zero Stock',
    ]) {
      await reveal(tester, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Run Report'), findsOneWidget);
  });

  testWidgets('multi-link values render as removable chips', (tester) async {
    ctrls['warehouse']!.text = joinMultiValue(['WH-A', 'WH-B']);
    await open(tester);
    await reveal(tester, find.text('WH-A'));
    expect(find.text('WH-A'), findsOneWidget);
    expect(find.text('WH-B'), findsOneWidget);

    // Delete the first chip → the controller keeps only the second value.
    final chipA = find.ancestor(of: find.text('WH-A'), matching: find.byType(InputChip));
    expect(chipA, findsOneWidget);
    // Fire the chip's delete action directly: the delete glyph differs across
    // Material versions, the contract under test is the controller write-back.
    tester.widget<InputChip>(chipA).onDeleted!();
    await tester.pumpAndSettle();
    expect(ctrls['warehouse']!.text, 'WH-B');
    expect(find.text('WH-A'), findsNothing);
    expect(splitMultiValue(ctrls['warehouse']!.text), ['WH-B']);
  });

  testWidgets('toggles write 1/empty into their controllers', (tester) async {
    ctrls['include_zero_stock']!.text = '1';
    await open(tester);
    await reveal(tester, find.text('Stock Ageing'));

    FilterChip chip(String label) => tester.widget<FilterChip>(
        find.ancestor(of: find.text(label), matching: find.byType(FilterChip)));
    expect(chip('Include Zero Stock').selected, isTrue);
    expect(chip('Stock Ageing').selected, isFalse);

    await tester.tap(find.text('Stock Ageing'));
    await tester.pumpAndSettle();
    expect(ctrls['show_stock_ageing']!.text, '1');
    expect(chip('Stock Ageing').selected, isTrue);

    await reveal(tester, find.text('Include Zero Stock'));
    await tester.tap(find.text('Include Zero Stock'));
    await tester.pumpAndSettle();
    expect(ctrls['include_zero_stock']!.text, '');
    expect(chip('Include Zero Stock').selected, isFalse);
  });
}
