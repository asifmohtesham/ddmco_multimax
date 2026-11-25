import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_fields.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart';

import '../support/report_fields_test_kit.dart';

// The sticky total bar and the segmented state filter render aggregates / view
// state. These render them across light/dark on a narrow viewport — guarding the
// dense layouts against overflow and confirming segment wiring.
void registerStockBalanceFieldsTests() {
  testWidgets('Stock Balance drops delayed enrichments after owner changes', (
    tester,
  ) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    final owner = ReportFieldsTestOwner()
      ..change('https://a.example', 'reader');
    final customer = Completer<Map<String, String>>();
    final image = Completer<Map<String, String>>();
    final api = _StockFieldsApi()..customerGate = customer;
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(_StockTestStorage());
    Get.put<ReportOwnerSource>(owner);
    final controller = Get.put(StockBalanceController());

    final first = controller.runReport();
    await tester.pump();
    expect(api.customerRequests, 1);
    expect(controller.reportData, isEmpty);
    owner.change('https://a.example', 'other');
    customer.complete({'T-1': 'Stale code'});
    await first;
    expect(controller.reportColumns, isEmpty);
    expect(controller.reportData, isEmpty);
    expect(api.imageRequests, 0);

    api.customerGate = null;
    api.imageGate = image;
    final second = controller.runReport();
    await tester.pump();
    expect(api.imageRequests, 1);
    owner.change('https://b.example', 'other');
    image.complete({'T-1': '/files/stale.png'});
    await second;
    expect(controller.reportColumns, isEmpty);
    expect(controller.reportData, isEmpty);
    expect(controller.isLoading.value, isFalse);

    api.imageGate = null;
    await controller.runReport();
    expect(controller.reportData.single['item_code'], 'T-1');
    expect(controller.reportData.single['customer_code'], isNull);
    expect(controller.reportData.single['item_image'], isNull);
  });

  testWidgets('Stock Balance Fields keep rows, drill-downs and sticky totals', (
    tester,
  ) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    await tester.binding.setSurfaceSize(const Size(470, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = ReportFieldsTestConfig();
    const fieldsKey = 'stock_balance_fields::https%3A%2F%2Fa.example::reader';
    const controlKey = 'stock_balance_fields::https%3A%2F%2Fa.example::other';
    database.values[controlKey] = '{"brand":true}';
    final owner = ReportFieldsTestOwner()
      ..change('https://a.example', 'reader');
    final api = _StockFieldsApi()
      ..includeSecondRow = true
      ..includeColour = true;
    Get.put<ApiProvider>(api);
    final storage = Get.put<StorageService>(_StockTestStorage());
    Get.put(AuthenticationController());
    Get.put(PermissionService());
    Get.put<ReportOwnerSource>(owner);
    final driver = WidgetReportFieldsDriver(tester, owner);

    Future<void> mount() async {
      Get.put<ReportFieldsStore>(
        ScopedReportFieldsStore(database: database, storage: storage),
      );
      final controller = Get.put(StockBalanceController());
      await controller.runReport();
      await tester.pumpWidget(const GetMaterialApp(home: StockBalanceScreen()));
      await tester.pumpAndSettle();
    }

    Finder cardText(String item, String text) => find.descendant(
      of: find
          .ancestor(of: find.text(item), matching: find.byType(InkWell))
          .first,
      matching: find.text(text, findRichText: true),
    );

    void expectSticky({
      required String count,
      required String opening,
      required String incoming,
      required String outgoing,
      required String balance,
      required String value,
    }) {
      final nav = tester
          .widget<Scaffold>(find.byType(Scaffold))
          .bottomNavigationBar!;
      final sticky = find.byWidget(nav);
      expect(
        find.descendant(
          of: sticky,
          matching: find.text(count, findRichText: true),
        ),
        findsOneWidget,
      );
      for (final (label, amount) in [
        ('Opening Qty', opening),
        ('In Qty', incoming),
        ('Out Qty', outgoing),
        ('Saldo', balance),
        ('Balance Value', value),
      ]) {
        final caption = find.descendant(of: sticky, matching: find.text(label));
        final cell = find
            .ancestor(of: caption, matching: find.byType(Column))
            .first;
        expect(
          find.descendant(of: cell, matching: find.text(amount)),
          findsOneWidget,
        );
      }
    }

    void expectAllTotals() => expectSticky(
      count: 'TOTAL  2 items  ·  2 warehouses',
      opening: '12',
      incoming: '+13',
      outgoing: '−13',
      balance: '12',
      value: '190.00',
    );

    void protected() {
      expect(find.text('Total Tools'), findsOneWidget);
      expect(find.textContaining('A-01'), findsOneWidget);
      expect(find.textContaining('Negative stock'), findsOneWidget);
      expect(find.text('End of list'), findsOneWidget);
    }

    await mount();
    expectAllTotals();
    final firstBalance = find.byWidgetPredicate(
      (widget) => widget is Text && widget.semanticsLabel == 'Saldo -1',
    );
    final secondBalance = find.byWidgetPredicate(
      (widget) => widget is Text && widget.semanticsLabel == 'Saldo 13',
    );
    expect(firstBalance, findsOneWidget);
    expect(secondBalance, findsOneWidget);
    final details = [
      ('stock_uom', 'EACH', 'BOX'),
      ('opening_qty', '2', '10'),
      ('in_qty', '+8', '+5'),
      ('out_qty', '−11', '−2'),
      ('val_rate', 'Valuation Rate 92.00', 'Valuation Rate 21.00'),
      ('bal_val', 'Balance Value 80.00', 'Balance Value 110.00'),
      ('colour', 'Colour Cerulean', 'Colour Saffron'),
      ('bal_qty', 'Saldo', 'Saldo'),
    ];
    for (final (_, first, second) in details) {
      expect(cardText('T-1', first), findsWidgets);
      expect(cardText('T-2', second), findsWidgets);
    }
    await driver.openFields();
    final item = await driver.read('item_code');
    expect(item.value, isTrue);
    expect(item.onChanged, isNull);
    await driver.dismiss();
    for (final (index, (key, first, second)) in details.indexed) {
      await driver.openFields();
      expect((await driver.read(key)).value, isTrue);
      await driver.setVisible(key, false);
      if (key == 'stock_uom') {
        await driver.dismiss();
        expect(cardText('T-1', first), findsNothing);
        expect(cardText('T-2', second), findsNothing);
        expect(firstBalance, findsOneWidget);
        expect(secondBalance, findsOneWidget);
        await driver.openFields();
        await driver.setVisible(key, true);
      }
      if (key == 'bal_qty') {
        final semantics = tester.ensureSemantics();
        try {
          final unit = await driver.read('stock_uom');
          expect(unit.value, isTrue);
          expect(unit.onChanged, isNull);
          final unitData = tester
              .getSemantics(find.byWidget(unit))
              .getSemanticsData();
          expect(unitData.flagsCollection.isChecked, CheckedState.isTrue);
          expect(unitData.flagsCollection.isEnabled, Tristate.isFalse);
        } finally {
          semantics.dispose();
        }
      }
      await driver.dismiss();
      if (key != 'stock_uom') {
        expect(cardText('T-1', first), findsNothing);
        expect(cardText('T-2', second), findsNothing);
      }
      for (final (_, remaining, _) in details.skip(index + 1)) {
        expect(cardText('T-1', remaining), findsWidgets);
      }
      expectAllTotals();
    }
    protected();
    expect(cardText('T-1', 'EACH'), findsNothing);
    expect(cardText('T-2', 'BOX'), findsNothing);
    expect(firstBalance, findsNothing);
    expect(secondBalance, findsNothing);
    await tester.tap(find.text('Negative'));
    await tester.pumpAndSettle();
    expect(find.text('T-2'), findsNothing);
    expectSticky(
      count: 'TOTAL  1 item  ·  1 warehouse',
      opening: '2',
      incoming: '+8',
      outgoing: '−11',
      balance: '-1',
      value: '80.00',
    );
    protected();
    expect(api.queries, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await Get.delete<StockBalanceController>(force: true);
    await Get.delete<ReportFieldsStore>(force: true);
    await mount();
    await driver.openFields();
    expect((await driver.read('bal_qty')).value, isFalse);
    expect((await driver.read('colour')).value, isFalse);
    await driver.switchOwner(site: 'https://a.example', user: 'other');
    expect((await driver.read('bal_qty')).value, isTrue);
    await driver.switchOwner(site: 'https://b.example', user: 'reader');
    expect((await driver.read('bal_qty')).value, isTrue);
    await driver.switchOwner(site: 'https://a.example', user: 'reader');
    expect((await driver.read('bal_qty')).value, isFalse);
    expect(api.queries, 2);
    api.includeColour = false;
    await Get.find<StockBalanceController>().runReport();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Colour'), findsNothing);
    await driver.reset();
    expect((await driver.read('bal_qty')).value, isTrue);
    expect(database.values[fieldsKey], '{}');
    expect(database.values[controlKey], '{"brand":true}');
    await driver.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await Get.delete<StockBalanceController>(force: true);
    await Get.delete<ReportFieldsStore>(force: true);
    api.includeColour = true;
    await mount();
    expect(cardText('T-1', 'EACH'), findsOneWidget);
    expect(cardText('T-1', 'Colour Cerulean'), findsOneWidget);
    expect(cardText('T-1', 'Valuation Rate 92.00'), findsOneWidget);
    expectAllTotals();
  });

  testWidgets(
    'Stock Balance selects warehouse measures and exact-case attributes',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await tester.binding.setSurfaceSize(const Size(470, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _StockFieldsApi()
        ..payload = {
          'columns': [
            for (final (key, label) in [
              ('item_code', 'Item'),
              ('warehouse', 'Warehouse'),
              ('stock_uom', 'Stock UOM'),
              ('bal_qty', 'Balance Qty'),
              ('reserved_stock', 'Reserved Stock'),
              ('average_age', 'Durchschnittsalter'),
              ('earliest_age', 'Ältestes Alter'),
              ('latest_age', 'Jüngstes Alter'),
              ('bal_qty_alt', 'Balance Qty (Box)'),
              ('Model', 'Upper Model'),
              ('model', 'Lower Model'),
            ])
              {'fieldname': key, 'label': label},
          ],
          'result': [
            [
              'ATTR-1',
              'W-ATTR',
              'Each',
              10,
              15,
              41,
              62,
              17,
              2,
              'Modern',
              'Classic',
            ],
          ],
        };
      Get.put<ApiProvider>(api);
      Get.put<StorageService>(_StockTestStorage());
      Get.put(AuthenticationController());
      Get.put(PermissionService());
      final controller = Get.put(StockBalanceController());
      await controller.runReport();
      await tester.pumpWidget(const GetMaterialApp(home: StockBalanceScreen()));
      await tester.pumpAndSettle();
      final driver = WidgetReportFieldsDriver(tester, ReportFieldsTestOwner());
      final card = find
          .ancestor(of: find.text('ATTR-1'), matching: find.byType(InkWell))
          .first;
      Finder cardText(String text) => find.descendant(
        of: card,
        matching: find.text(text, findRichText: true),
      );
      final reserved = cardText('Reserved 10');
      final rawReservation = cardText('Reserved Stock 15');
      expect(reserved.hitTestable(), findsOneWidget);
      expect(rawReservation, findsNothing);
      await driver.openFields();
      final reservation = await driver.read('reserved_stock');
      expect(
        ((reservation.title as Semantics).child as Text).data,
        'Reserved Stock',
      );
      expect(reservation.value, isFalse);
      await driver.setVisible('reserved_stock', true);
      await driver.dismiss();
      expect(rawReservation, findsOneWidget);
      expect(reserved.hitTestable(), findsOneWidget);
      await tester.tap(reserved);
      await tester.pumpAndSettle();
      expect(api.reservationQueries, [('ATTR-1', 'W-ATTR')]);
      expect(find.text('SO-FIXTURE'), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();

      final details = [
        ('average_age', 'Durchschnittsalter', '41'),
        ('earliest_age', 'Ältestes Alter', '62'),
        ('latest_age', 'Jüngstes Alter', '17'),
        ('bal_qty_alt', 'Balance Qty (Box)', '2'),
        ('Model', 'Upper Model', 'Modern'),
        ('model', 'Lower Model', 'Classic'),
      ];
      for (final (key, label, value) in details) {
        expect(cardText('$label $value'), findsOneWidget);
        await driver.openFields();
        final tile = await driver.read(key);
        expect(((tile.title as Semantics).child as Text).data, label);
        expect(tile.value, isTrue);
        await driver.setVisible(key, false);
        await driver.dismiss();
        expect(cardText('$label $value'), findsNothing);
        for (final (sibling, siblingLabel, siblingValue) in details) {
          if (sibling == key) continue;
          expect(cardText('$siblingLabel $siblingValue'), findsOneWidget);
        }
        await driver.openFields();
        await driver.setVisible(key, true);
        await driver.dismiss();
        expect(cardText('$label $value'), findsOneWidget);
      }
      await driver.openFields();
      await driver.setVisible('reserved_stock', false);
      await driver.dismiss();
      expect(rawReservation, findsNothing);
      expect(reserved.hitTestable(), findsOneWidget);
      await tester.tap(reserved);
      await tester.pumpAndSettle();
      expect(api.reservationQueries, [
        ('ATTR-1', 'W-ATTR'),
        ('ATTR-1', 'W-ATTR'),
      ]);
      expect(find.text('SO-FIXTURE'), findsOneWidget);
      expect(api.queries, 1);
    },
  );

  testWidgets(
    'Stock Balance keeps rack and reservation identities and preserves attribute defaults',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await tester.binding.setSurfaceSize(const Size(470, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final owner = ReportFieldsTestOwner()
        ..change('https://a.example', 'reader');
      final storage = Get.put<StorageService>(_StockTestStorage());
      Get.put<ReportOwnerSource>(owner);
      Get.put<ReportFieldsStore>(
        ScopedReportFieldsStore(
          database: ReportFieldsTestConfig(),
          storage: storage,
        ),
      );
      final api = _StockFieldsApi()
        ..payload = {
          'columns': [
            {'fieldname': 'warehouse', 'label': 'Warehouse'},
            {'fieldname': 'item_code', 'label': 'Item'},
            {'fieldname': 'bal_qty', 'label': 'Balance Qty'},
            {'fieldname': 'stock_uom', 'label': 'Stock UOM'},
            {'fieldname': 'reserved_stock', 'label': 'Reserved Stock'},
            {
              'fieldname': 'warehouse_rack',
              'label': 'Warehouse Rack',
              'fieldtype': 'Link',
              'options': 'Warehouse Rack',
            },
            {'fieldname': 'Model', 'label': 'Model'},
          ],
          'result': [
            {
              'warehouse': 'Total',
              'item_code': 'I-1',
              'bal_qty': 7,
              'stock_uom': 'Each',
              'warehouse_rack': 'R-7',
              'model': 'Classic',
            },
            {
              'warehouse': 'Warehouse A',
              'item_code': 'I-2',
              'bal_qty': 0,
              'stock_uom': 'Each',
              'warehouse_rack': 'R-8',
              'Model': 'Deluxe',
              'reserved_stock': 3,
            },
            ['Gesamt', '', 7, '', 3, '', ''],
          ],
          'add_total_row': true,
        };
      Get.put<ApiProvider>(api);
      Get.put(AuthenticationController());
      Get.put(PermissionService());
      final controller = Get.put(StockBalanceController());
      await controller.runReport();
      await tester.pumpWidget(const GetMaterialApp(home: StockBalanceScreen()));
      await tester.pumpAndSettle();
      final driver = WidgetReportFieldsDriver(tester, owner);
      final classic = find.textContaining('Classic', findRichText: true);
      final deluxe = find.textContaining('Deluxe', findRichText: true);

      expect(classic, findsOneWidget);
      expect(deluxe, findsNothing);
      await driver.openFields();
      for (final key in ['stock_uom', 'bal_qty', 'Model']) {
        await driver.setVisible(key, false);
      }
      await driver.dismiss();
      expect(find.textContaining('R-7', findRichText: true), findsOneWidget);
      expect(find.textContaining('R-8', findRichText: true), findsOneWidget);
      expect(find.textContaining('No rack assigned'), findsNothing);
      expect(find.textContaining('Total'), findsWidgets);
      expect(find.textContaining('Gesamt'), findsNothing);
      expect(find.text('I-1'), findsOneWidget);
      expect(find.text('I-2'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('14'), findsNothing);
      expect(find.textContaining('Out of stock'), findsOneWidget);
      expect(find.textContaining('Reserved Stock'), findsNothing);
      await tester.tap(find.text('View warehouse reservations'));
      await tester.pumpAndSettle();
      expect(api.reservationQueries, [('I-2', 'Warehouse A')]);
      expect(find.text('SO-FIXTURE'), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();

      await driver.openFields();
      await driver.setVisible('Model', true);
      await driver.dismiss();
      expect(classic, findsOneWidget);
      expect(deluxe, findsOneWidget);
      await driver.openFields();
      await driver.reset();
      await driver.dismiss();
      expect(classic, findsOneWidget);
      expect(deluxe, findsNothing);
      expect(api.queries, 1);
    },
  );

  testWidgets(
    'Stock Balance Fields restore the painted row through hide and reset',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await tester.binding.setSurfaceSize(const Size(470, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _StockFieldsApi()..anchorRows = 48;
      Get.put<ApiProvider>(api);
      Get.put<StorageService>(_StockTestStorage());
      Get.put(AuthenticationController());
      Get.put(PermissionService());
      final controller = Get.put(StockBalanceController());
      await controller.runReport();
      await tester.pumpWidget(const GetMaterialApp(home: StockBalanceScreen()));
      await tester.pumpAndSettle();

      final occurrences = stockBalanceOccurrenceIds(
        controller.visibleRows,
        controller.reportColumns,
      );
      final driver = WidgetReportFieldsDriver(tester, ReportFieldsTestOwner());
      final id = occurrences[20];
      await driver.scrollToOccurrence(id);
      const paintedOffset = -4.0;
      driver.position.jumpTo(
        driver.position.pixels + driver.readPaintedOffset(id) - paintedOffset,
      );
      await tester.pumpAndSettle();
      expect(driver.readPaintedOffset(id), closeTo(paintedOffset, 1));

      await driver.openFields();
      await driver.setVisible('colour', false);
      await driver.dismiss();
      expect(driver.readPaintedOffset(id), closeTo(paintedOffset, 1));
      await driver.openFields();
      await driver.reset();
      await driver.dismiss();
      expect(driver.readPaintedOffset(id), closeTo(paintedOffset, 1));
      expect(api.queries, 1);
    },
  );

  testWidgets('Stock Balance opens and retries the selected warehouse Ledger', (
    tester,
  ) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    await tester.binding.setSurfaceSize(const Size(470, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _StockFieldsApi()
      ..ledgerResult = ApiProvider.parseStockLedgerReport({
        'columns': [
          {'fieldname': 'voucher_no', 'label': 'Voucher #'},
          {'fieldname': 'voucher_type', 'label': 'Voucher Type'},
          {'fieldname': 'date', 'label': 'Date'},
          {'fieldname': 'qty_after_transaction', 'label': 'Balance Qty'},
        ],
        'result': [
          {
            'name': 'SLE-0001',
            'date': '2026-06-21',
            'voucher_no': 'SR-1',
            'voucher_type': 'Stock Reconciliation',
            'actual_qty': 0,
            'in_qty': 4,
            'out_qty': 0,
            'qty_after_transaction': 10,
            'stock_uom': 'Each',
          },
        ],
      });
    api.payload = {
      'columns': [
        for (final (key, label) in [
          ('item_code', 'Item'),
          ('item_name', 'Item Name'),
          ('warehouse', 'Warehouse'),
          ('stock_uom', 'Stock UOM'),
          ('bal_qty', 'Balance Qty'),
        ])
          {'fieldname': key, 'label': label},
      ],
      'result': [
        for (var i = 0; i < 42; i++)
          {
            'item_code': i == 0 || i == 22 ? 'SHARED' : 'I-$i',
            'item_name': i == 0 || i == 22 ? 'Same item' : 'Item $i',
            'warehouse': i == 22 ? 'SECOND' : 'FIRST',
            'stock_uom': 'Each',
            'bal_qty': 10,
          },
      ],
    };
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(_StockTestStorage());
    Get.put(AuthenticationController());
    Get.put(PermissionService());
    final controller = Get.put(StockBalanceController());
    controller.fromDateController.text = '2026-06-01';
    controller.toDateController.text = '2026-06-30';
    await controller.runReport();
    await tester.pumpWidget(const GetMaterialApp(home: StockBalanceScreen()));
    await tester.pumpAndSettle();
    // The displayed period stays June while the draft is edited.
    controller.fromDateController.text = '2026-07-01';
    controller.toDateController.text = '2026-07-31';

    const occurrence = (identity: '["SHARED",null,"SECOND"]', occurrence: 0);
    final driver = WidgetReportFieldsDriver(tester, ReportFieldsTestOwner());
    await driver.positionOccurrenceUnderHeader(occurrence, offset: -4);
    final secondWarehouseRow = find.byKey(const ValueKey<Object>(occurrence));
    final secondWarehouse = find.descendant(
      of: secondWarehouseRow,
      matching: find.text('SECOND'),
    );
    expect(secondWarehouse, findsOneWidget);
    final tappedItem = find.descendant(
      of: secondWarehouseRow,
      matching: find.text('Same item'),
    );
    expect(tappedItem.hitTestable(), findsOneWidget);
    await tester.tap(tappedItem);
    await tester.pumpAndSettle();

    const expectedQuery = ('SHARED', 'SECOND', '2026-06-01', '2026-06-30');
    expect(api.ledgerQueries, [expectedQuery]);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.ledgerQueries, [expectedQuery, expectedQuery]);
    final ledger = find.byType(StockLedgerSheetBody);
    expect(
      find.descendant(of: ledger, matching: find.text('SECOND')),
      findsOneWidget,
    );
    final balance = find.descendant(
      of: ledger,
      matching: find.text('Balance Qty'),
    );
    expect(balance, findsOneWidget);
    await driver.openFields();
    await driver.setVisible('qty_after_transaction', false);
    await driver.dismiss();
    expect(balance, findsNothing);
    final row = find.byKey(const ValueKey<Object>(('SLE-0001', 0)));
    for (final text in ['SR-1', 'Stock Reconciliation · 2026-06-21', '—']) {
      expect(
        find.descendant(of: row, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(
      find.text('End of list · 1 movement\nIn Qty 4 · Out Qty 0 · Each'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Back').hitTestable());
    await tester.pumpAndSettle();
    expect(ledger, findsNothing);
    expect(driver.readPaintedOffset(occurrence), closeTo(-4, 1));
    expect(secondWarehouse, findsOneWidget);
  });
}

void main() {
  registerStockBalanceFieldsTests();
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

    testWidgets(
      'total bar shows value + ledger totals without overflow ($mode)',
      (tester) async {
        await pump(tester, buildStockBalanceTotalBarForTest(totals), b);
        expect(find.textContaining('TOTAL'), findsWidgets);
        expect(find.text('64,180.00'), findsOneWidget);
        expect(find.text('+642'), findsOneWidget);
        expect(find.text('−418'), findsOneWidget); // U+2212
        expect(find.text('1,432'), findsOneWidget);
      },
    );

    testWidgets(
      'state filter renders the four segments + wires onState ($mode)',
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
      },
    );

    testWidgets(
      'warehouse pills render All + each warehouse, single-tap ($mode)',
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
      },
    );
  }
}

class _StockTestStorage extends StorageService {
  _StockTestStorage() : super.withStorage(null);

  @override
  bool getSbHideEmpty() => false;

  @override
  bool getSbShowImages() => false;
}

class _StockFieldsApi extends ApiProvider {
  int queries = 0;
  bool includeSecondRow = false;
  bool includeColour = false;
  int anchorRows = 0;
  int customerRequests = 0;
  int imageRequests = 0;
  Completer<Map<String, String>>? customerGate;
  Completer<Map<String, String>>? imageGate;
  Map<String, dynamic>? payload;
  StockLedgerReportResult? ledgerResult;
  final reservationQueries = <(String, String)>[];
  final ledgerQueries = <(String, String, String, String)>[];

  @override
  Future<
    ({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})
  >
  getStockBalanceReport({
    required String fromDate,
    required String toDate,
    List<String>? itemCodes,
    List<String>? warehouses,
    String? itemGroup,
    String? warehouseType,
    String? rack,
    String? includeUom,
    bool showDimensionWise = false,
    bool showVariantAttributes = false,
    bool showStockAgeing = false,
    bool ignoreClosingBalance = false,
    bool includeZeroStockItems = false,
  }) async {
    queries++;
    return ApiProvider.parseStockBalanceResponse(
      payload ??
          {
            'columns': [
              for (final (key, label) in [
                ('item_code', 'Item'),
                ('item_name', 'Item Name'),
                ('warehouse', 'Warehouse'),
                ('rack', 'Rack'),
                ('stock_uom', 'Stock UOM'),
                ('bal_qty', 'Saldo'),
                ('opening_qty', 'Opening Qty'),
                ('in_qty', 'In Qty'),
                ('out_qty', 'Out Qty'),
                ('val_rate', 'Valuation Rate'),
                ('bal_val', 'Balance Value'),
                if (includeColour || anchorRows > 0) ('colour', 'Colour'),
              ])
                {'fieldname': key, 'label': label},
            ],
            'result': [
              if (anchorRows == 0)
                {
                  'item_code': 'T-1',
                  'item_name': 'Total Tools',
                  'warehouse': 'W-1',
                  'rack': 'A-01',
                  'stock_uom': 'Each',
                  'bal_qty': -1,
                  'opening_qty': 2,
                  'in_qty': 8,
                  'out_qty': 11,
                  'val_rate': 92,
                  'bal_val': 80,
                  if (includeColour) 'colour': 'Cerulean',
                },
              if (includeSecondRow)
                {
                  'item_code': 'T-2',
                  'item_name': 'Second Tools',
                  'warehouse': 'W-2',
                  'rack': 'A-02',
                  'stock_uom': 'Box',
                  'bal_qty': 13,
                  'opening_qty': 10,
                  'in_qty': 5,
                  'out_qty': 2,
                  'val_rate': 21,
                  'bal_val': 110,
                  if (includeColour) 'colour': 'Saffron',
                },
              for (var index = 0; index < anchorRows; index++)
                {
                  'item_code': 'I-$index',
                  'item_name': 'Stock item $index',
                  'warehouse': 'W-1',
                  'rack': 'A-01',
                  'stock_uom': 'Each',
                  'bal_qty': -1,
                  'opening_qty': 2,
                  'in_qty': 8,
                  'out_qty': 11,
                  'val_rate': 92,
                  'bal_val': 80,
                  'colour': 'Mixed',
                },
            ],
          },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getStockReservations({
    required String itemCode,
    required String warehouse,
  }) async {
    reservationQueries.add((itemCode, warehouse));
    return const [
      {
        'voucher_type': 'Sales Order',
        'voucher_no': 'SO-FIXTURE',
        'reserved': 3,
      },
    ];
  }

  @override
  Future<StockLedgerReportResult> getStockLedgerReport({
    required String itemCode,
    required String warehouse,
    required String fromDate,
    required String toDate,
  }) async {
    ledgerQueries.add((itemCode, warehouse, fromDate, toDate));
    if (ledgerQueries.length == 1) {
      throw const FormatException('Ledger unavailable');
    }
    return ledgerResult!;
  }

  @override
  Future<Map<String, String>> getItemCustomerCodes(
    List<String> itemCodes,
  ) async {
    customerRequests++;
    return await customerGate?.future ?? {};
  }

  @override
  Future<Map<String, String>> getItemImages(List<String> itemCodes) async {
    imageRequests++;
    return await imageGate?.future ?? {};
  }
}
