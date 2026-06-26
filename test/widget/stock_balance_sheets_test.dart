import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart';

// The three drill-down sheet bodies (Phase 2, feature 4) take already-resolved
// data, so they render directly here — covering both populated and empty states
// and the customer "Filter to this customer" action.
void main() {
  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF870E18)),
        ),
        home: Scaffold(body: body),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('ledger sheet lists entries with running balance', (tester) async {
    await pump(
      tester,
      const StockLedgerSheetBody(
        itemCode: '2003120',
        itemName: 'WALLET BIFOLD',
        warehouse: 'WH-DXB3 - KA',
        entries: [
          {'date': '2026-06-21', 'voucher_type': 'Purchase Receipt', 'voucher_no': 'MAT-PRE-0142', 'qty': 64.0, 'balance': 244.0},
          {'date': '2026-06-21', 'voucher_type': 'Delivery Note', 'voucher_no': 'MAT-DN-0391', 'qty': -24.0, 'balance': 220.0},
        ],
      ),
    );
    expect(find.text('STOCK LEDGER'), findsOneWidget); // uppercased eyebrow
    expect(find.text('MAT-PRE-0142'), findsOneWidget);
    expect(find.text('+64'), findsOneWidget);
    expect(find.text('−24'), findsOneWidget); // U+2212
    expect(find.text('220'), findsOneWidget); // running balance reconciles
  });

  testWidgets('ledger sheet shows an empty state with no movements',
      (tester) async {
    await pump(
      tester,
      const StockLedgerSheetBody(
        itemCode: 'X',
        itemName: 'Item X',
        warehouse: 'WH',
        entries: [],
      ),
    );
    expect(find.textContaining('No ledger movements'), findsOneWidget);
  });

  testWidgets('reservations sheet lists Sales Orders', (tester) async {
    await pump(
      tester,
      const ReservationsSheetBody(
        itemCode: '2003120',
        itemName: 'WALLET BIFOLD',
        reserved: 200,
        reservations: [
          {'voucher_no': 'SO-2026-1187', 'reserved': 110.0, 'status': 'Partially Reserved'},
          {'voucher_no': 'SO-2026-1190', 'reserved': 90.0, 'status': 'Reserved'},
        ],
      ),
    );
    expect(find.textContaining('committed'), findsOneWidget);
    expect(find.text('SO-2026-1187'), findsOneWidget);
    expect(find.text('110'), findsOneWidget);
  });

  testWidgets('reservations sheet empty state', (tester) async {
    await pump(
      tester,
      const ReservationsSheetBody(
        itemCode: 'X',
        itemName: 'Item X',
        reserved: 0,
        reservations: [],
      ),
    );
    expect(find.textContaining('No reservation details'), findsOneWidget);
  });

  testWidgets('customer sheet lists items and the filter CTA fires',
      (tester) async {
    var filtered = false;
    await pump(
      tester,
      CustomerItemsSheetBody(
        customerCode: '5067049',
        items: const [
          {'item_code': '2002855', 'item_name': 'BELTS FORMAL AUTO CP', 'bal_qty': 12},
          {'item_code': '2003120', 'item_name': 'WALLET BIFOLD', 'bal_qty': 220},
        ],
        onFilter: () => filtered = true,
      ),
    );
    expect(find.text('5067049'), findsOneWidget);
    expect(find.textContaining('2 linked items'), findsOneWidget);
    expect(find.text('2002855'), findsOneWidget);

    await tester.tap(find.text('Filter report to this customer'));
    await tester.pumpAndSettle();
    expect(filtered, isTrue);
  });
}
