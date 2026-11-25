import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_ledger_fields.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart';

import '../support/report_fields_test_kit.dart';

// The three drill-down sheet bodies (Phase 2, feature 4) take already-resolved
// data, so they render directly here — covering both populated and empty states
// and the customer "Filter to this customer" action.
void main() {
  registerStockLedgerFieldsTests();
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

  testWidgets('ledger sheet lists entries with running balance', (
    tester,
  ) async {
    await pump(
      tester,
      const StockLedgerSheetBody(
        itemCode: '2003120',
        itemName: 'WALLET BIFOLD',
        warehouse: 'WH-DXB3 - KA',
        entries: [
          {
            'date': '2026-06-21',
            'voucher_type': 'Purchase Receipt',
            'voucher_no': 'MAT-PRE-0142',
            'qty': 64.0,
            'balance': 244.0,
          },
          {
            'date': '2026-06-21',
            'voucher_type': 'Delivery Note',
            'voucher_no': 'MAT-DN-0391',
            'qty': -24.0,
            'balance': 220.0,
          },
        ],
      ),
    );
    expect(find.text('Stock Ledger'), findsOneWidget);
    expect(find.text('Voucher #'), findsOneWidget);
    expect(find.text('Balance Qty'), findsOneWidget);
    expect(find.text('MAT-PRE-0142'), findsOneWidget);
    expect(find.text('+64'), findsOneWidget);
    expect(find.text('−24'), findsOneWidget); // U+2212
    expect(find.text('220'), findsOneWidget); // running balance reconciles
  });

  testWidgets('ledger sheet shows an empty state with no movements', (
    tester,
  ) async {
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
          {
            'voucher_no': 'SO-2026-1187',
            'reserved': 110.0,
            'status': 'Partially Reserved',
          },
          {
            'voucher_no': 'SO-2026-1190',
            'reserved': 90.0,
            'status': 'Reserved',
          },
        ],
      ),
    );
    expect(find.text('Reserved Stock 200'), findsOneWidget);
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

  testWidgets('customer sheet lists items and the filter CTA fires', (
    tester,
  ) async {
    var filtered = false;
    await pump(
      tester,
      CustomerItemsSheetBody(
        customerCode: '5067049',
        items: const [
          {
            'item_code': '2002855',
            'item_name': 'BELTS FORMAL AUTO CP',
            'bal_qty': 12,
          },
          {
            'item_code': '2003120',
            'item_name': 'WALLET BIFOLD',
            'bal_qty': 220,
          },
        ],
        onFilter: () => filtered = true,
      ),
    );
    expect(find.text('5067049'), findsOneWidget);
    expect(find.textContaining('2 linked items'), findsOneWidget);
    expect(find.text('2002855'), findsOneWidget);
    expect(find.text('Balance Qty'), findsOneWidget);

    await tester.tap(find.text('Filter report to this customer'));
    await tester.pumpAndSettle();
    expect(filtered, isTrue);
  });
}

void registerStockLedgerFieldsTests() {
  testWidgets(
    'Stock Ledger Fields persist independently and preserve movements',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await tester.binding.setSurfaceSize(const Size(470, 1250));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final owner = ReportFieldsTestOwner()
        ..change('https://a.example', 'reader');
      final database = ReportFieldsTestConfig();
      final storage = ReportFieldsTestStorage();
      Get.put<ReportOwnerSource>(owner);
      final driver = WidgetReportFieldsDriver(tester, owner);
      final pending = Completer<StockLedgerReportResult>();
      var requests = 0;
      var itemName = 'Stock item';
      final report = ApiProvider.parseStockLedgerReport({
        'columns': [
          for (final (key, label) in [
            ('voucher_no', 'Voucher #'),
            ('date', 'Date'),
            ('voucher_type', 'Voucher Type'),
            ('item_code', 'Artikel'),
            ('item_name', 'Artikelname'),
            ('warehouse', 'Lager'),
            ('stock_uom', 'Stock UOM'),
            ('in_qty', 'In Qty'),
            ('out_qty', 'Out Qty'),
            ('qty_after_transaction', 'Saldo'),
          ])
            {'fieldname': key, 'label': label},
        ],
        'result': [
          [
            'Total',
            '2026-06-21',
            'Stock Entry',
            'C001',
            'Stock item',
            'W-ONE',
            'Each',
            64,
            0,
            244,
          ],
          [
            'TX-001',
            '2026-06-22',
            'Delivery Note',
            'C001',
            'Stock item',
            'W-ONE',
            'Each',
            0,
            -24,
            220,
          ],
          ['Gesamt', '', '', '', '', '', '', 64, -24, 464],
        ],
        'add_total_row': '1',
        'skip_total_row': 0,
      });
      const balanceKey =
          'stock_balance_fields::https%3A%2F%2Fa.example::reader';
      const ledgerKey = 'stock_ledger_fields::https%3A%2F%2Fa.example::reader';
      database.values[balanceKey] = '{"bal_qty":false}';

      Future<void> mount() async {
        Get.put<ReportFieldsStore>(
          ScopedReportFieldsStore(database: database, storage: storage),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showStockLedgerSheet(
                    context,
                    itemCode: 'C001',
                    itemName: itemName,
                    warehouse: 'W-ONE',
                    load: () async {
                      requests++;
                      if (requests == 1) return pending.future;
                      if (requests == 4) {
                        return (
                          columns: report.columns,
                          rows: const <Map<String, dynamic>>[],
                        );
                      }
                      return report;
                    },
                  ),
                  child: const Text('Open ledger'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open ledger'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      void expectMovements() {
        final first = find.byKey(
          const ValueKey<Object>((('Total', 'Stock Entry', '2026-06-21'), 0)),
        );
        final second = find.byKey(
          const ValueKey<Object>((
            ('TX-001', 'Delivery Note', '2026-06-22'),
            0,
          )),
        );
        expect(
          tester.getTopLeft(first).dy,
          lessThan(tester.getTopLeft(second).dy),
        );
        for (final (row, voucher, context, qty) in [
          (first, 'Total', 'Stock Entry · 2026-06-21', '+64'),
          (second, 'TX-001', 'Delivery Note · 2026-06-22', '−24'),
        ]) {
          for (final text in [voucher, context, qty]) {
            expect(
              find.descendant(of: row, matching: find.text(text)),
              findsOneWidget,
            );
          }
        }
        expect(find.text('Gesamt'), findsNothing);
        expect(find.text('W-ONE'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('C001')).semanticsLabel,
          'Artikel C001',
        );
        expect(
          tester.widget<Text>(find.text('Stock item')).semanticsLabel,
          'Artikelname Stock item',
        );
        expect(
          tester.widget<Text>(find.text('W-ONE')).semanticsLabel,
          'Lager W-ONE',
        );
        expect(
          find.text(
            'End of list · 2 movements\nIn Qty 64 · Out Qty −24 · Each',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('464'), findsNothing);
      }

      await mount();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(const FormatException('server reply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No ledger movements'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expectMovements();
      expect(find.text('Saldo'), findsOneWidget);
      expect(find.text('244'), findsOneWidget);
      expect(find.text('220'), findsOneWidget);

      await driver.openFields();
      expect((await driver.read('voucher_no')).onChanged, isNull);
      expect((await driver.read('qty_after_transaction')).value, isTrue);
      await driver.setVisible('qty_after_transaction', false);
      await driver.dismiss();
      expect(find.text('Saldo'), findsNothing);
      expect(find.text('244'), findsNothing);
      expect(find.text('220'), findsNothing);
      expectMovements();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await Get.delete<ReportFieldsStore>(force: true);

      await mount();
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(find.text('220'), findsNothing);
      await driver.openFields();
      await driver.switchOwner(site: 'https://b.example', user: 'reader');
      expect((await driver.read('qty_after_transaction')).value, isTrue);
      expect(database.values[balanceKey], '{"bal_qty":false}');
      await driver.dismiss();
      expect(find.text('Stock item'), findsNothing);
      expect(find.text('C001'), findsNothing);
      expect(find.text('W-ONE'), findsNothing);
      expect(find.text('TX-001'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(
        find.text('Open the ledger from a new Stock Balance result.'),
        findsOneWidget,
      );
      expect(requests, 3);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      itemName = 'Other owner stock item';
      await mount();
      await tester.pumpAndSettle();
      expect(requests, 4);
      expect(find.text('Other owner stock item'), findsOneWidget);
      expect(find.text('Stock item'), findsNothing);
      expect(find.textContaining('No ledger movements'), findsOneWidget);
      expect(find.textContaining('End of list'), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await Get.delete<ReportFieldsStore>(force: true);
      owner.change('https://a.example', 'reader');
      itemName = 'Stock item';
      await mount();
      await tester.pumpAndSettle();
      expectMovements();
      expect(find.text('220'), findsNothing);
      await driver.openFields();
      await driver.reset();
      expect(database.values[ledgerKey], '{}');
      expect(database.values[balanceKey], '{"bal_qty":false}');
      await driver.dismiss();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await Get.delete<ReportFieldsStore>(force: true);
      await mount();
      await tester.pumpAndSettle();
      expect(requests, 6);
      expectMovements();
      expect(find.text('220'), findsOneWidget);
    },
  );

  testWidgets('Stock Ledger Fields restores the same painted movement row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(355, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = [
      for (var i = 0; i < 60; i++)
        <String, dynamic>{
          'name': 'SLE-$i',
          'date': '2026-06-21',
          'voucher_type': 'Purchase Receipt',
          'voucher_no': 'Stock ledger purchase receipt voucher number $i',
          'qty': 64.0,
          'balance': 244.0,
        },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockLedgerSheetBody(
            itemCode: 'I-01',
            itemName: 'Item one',
            warehouse: 'WH',
            entries: entries,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final driver = WidgetReportFieldsDriver(tester, ReportFieldsTestOwner());
    final id = stockLedgerOccurrenceIds(entries)[20];
    await driver.scrollToOccurrence(id);
    const offset = -4.0;
    driver.position.jumpTo(
      driver.position.pixels + driver.readPaintedOffset(id) - offset,
    );
    await tester.pumpAndSettle();
    expect(driver.readPaintedOffset(id), closeTo(offset, 1));
    await driver.openFields();
    await driver.setVisible('qty_after_transaction', false);
    await driver.dismiss();
    expect(driver.readPaintedOffset(id), closeTo(offset, 1));
    await driver.openFields();
    await driver.reset();
    await driver.dismiss();
    expect(driver.readPaintedOffset(id), closeTo(offset, 1));
  });
}
