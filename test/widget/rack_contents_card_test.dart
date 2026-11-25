import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/home/rack_contents_fields.dart';
import 'package:multimax/app/modules/home/rack_contents_logic.dart';
import 'package:multimax/app/modules/home/widgets/rack_contents_sheet.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../support/report_fields_test_kit.dart';

/// The Dashboard rack-contents card and sheet at phone width (360 px), in
/// light and dark: Item fields under their Item DocType labels, Balance Qty
/// as the largest figure, a neutral image placeholder, the quiet note when
/// Item details failed, and the list conventions (scrollbar, end-of-list
/// total).
void main() {
  registerRackContentsFieldsTests();
  const full = RackContentsEntry(
    itemCode: '3000247',
    itemName: 'BELTS LADIES PU',
    balanceQty: 36,
    stockUom: 'Nos',
    itemGroup: 'Belts',
    image: '/files/3000247-SGPU-14.jpg',
    variantOf: 'SGPU-14',
    countryOfOrigin: 'China',
    brand: 'FOCUS',
    description:
        'BELTS LADIES PU-FOCUS-PU-Pin-Womens-MIX-4MM-110-115CM-PU-25mm-PIN',
  );

  const bare = RackContentsEntry(
    itemCode: '2002654',
    itemName: '2002654',
    balanceQty: 0,
    stockUom: 'Nos',
    itemGroup: 'Belts',
    disabled: true,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Brightness brightness,
    double height = 1200,
  }) async {
    await tester.binding.setSurfaceSize(Size(360, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scheme = brightness == Brightness.dark
        ? AppScheme.dark
        : AppScheme.light;
    final theme = buildAppTheme(scheme, brightness);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        darkTheme: theme,
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: Scaffold(body: child),
      ),
    );
    // Let the test HTTP client fail the image load so errorBuilder runs.
    await tester.pump();
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    group('RackContentsCard ($mode)', () {
      testWidgets('shows the Item fields under their DocType labels', (
        tester,
      ) async {
        await pump(
          tester,
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: RackContentsCard(
              entry: full,
              imageUrl: 'https://erp.domain.com/files/3000247-SGPU-14.jpg',
            ),
          ),
          brightness: brightness,
        );

        expect(tester.takeException(), isNull);
        for (final label in [
          'Variant Of',
          'Country of Origin',
          'Item Group',
          'Brand',
          'Description',
          'Balance Qty',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('SGPU-14'), findsOneWidget);
        expect(find.text('China'), findsOneWidget);
        expect(find.text('FOCUS'), findsOneWidget);
        expect(find.text('3000247'), findsOneWidget);
        expect(find.text('36'), findsOneWidget);
        expect(find.text('Nos'), findsOneWidget);
      });

      testWidgets('Balance Qty is the largest figure on the card', (
        tester,
      ) async {
        await pump(
          tester,
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: RackContentsCard(entry: full, imageUrl: null),
          ),
          brightness: brightness,
        );

        final qty = tester.widget<Text>(
          find.byKey(const ValueKey('rack-card-qty')),
        );
        final qtySize = qty.style!.fontSize!;
        final others = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(RackContentsCard),
                matching: find.byType(Text),
              ),
            )
            .where((t) => t.key != const ValueKey('rack-card-qty'));
        for (final t in others) {
          expect(
            t.style?.fontSize ?? 14,
            lessThan(qtySize),
            reason: '"${t.data}" must be smaller than the quantity',
          );
        }
        // Ink comes from the scheme, never a hardcoded colour.
        final element = tester.element(find.byType(RackContentsCard));
        expect(qty.style!.color, element.scheme.text);
      });

      testWidgets('no image and a failed image both show the placeholder', (
        tester,
      ) async {
        await pump(
          tester,
          const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                RackContentsCard(entry: bare, imageUrl: null),
                SizedBox(height: 12),
                RackContentsCard(
                  entry: full,
                  imageUrl: 'https://erp.domain.com/files/missing.jpg',
                ),
              ],
            ),
          ),
          brightness: brightness,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('rack-card-image-placeholder')),
          findsNWidgets(2),
        );
      });

      testWidgets(
        'a bare row shows Disabled and a muted zero, no empty labels',
        (tester) async {
          await pump(
            tester,
            const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: RackContentsCard(entry: bare, imageUrl: null),
            ),
            brightness: brightness,
          );

          expect(find.text('Disabled'), findsOneWidget);
          expect(find.text('Variant Of'), findsNothing);
          expect(find.text('Country of Origin'), findsNothing);
          expect(find.text('Description'), findsNothing);
          final qty = tester.widget<Text>(
            find.byKey(const ValueKey('rack-card-qty')),
          );
          expect(qty.data, '0');
          final element = tester.element(find.byType(RackContentsCard));
          expect(qty.style!.color, element.scheme.textMuted);
        },
      );
    });

    group('RackContentsSheet ($mode)', () {
      Widget sheet({bool failed = false, ValueChanged<String>? onTap}) => Align(
        alignment: Alignment.bottomCenter,
        child: RackContentsSheet(
          rackId: 'KA-WH-DXB1-121D',
          entries: const [full, bare],
          baseUrl: 'https://erp.domain.com',
          itemDetailsFailed: failed,
          onItemTap: onTap,
        ),
      );

      testWidgets('ends with the list marker and the Balance Qty total', (
        tester,
      ) async {
        await pump(tester, sheet(), brightness: brightness, height: 2000);

        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollbar), findsOneWidget);
        expect(
          find.text('End of list · 2 items · Balance Qty 36 Nos'),
          findsOneWidget,
        );
        expect(find.text('Item details could not be loaded.'), findsNothing);
      });

      testWidgets('says quietly when Item details could not be loaded', (
        tester,
      ) async {
        await pump(tester, sheet(failed: true), brightness: brightness);

        expect(find.text('Item details could not be loaded.'), findsOneWidget);
        expect(find.byType(RackContentsCard), findsWidgets);
      });

      testWidgets('tapping a card opens that item', (tester) async {
        final tapped = <String>[];
        await pump(
          tester,
          sheet(onTap: tapped.add),
          brightness: brightness,
          height: 2000,
        );

        await tester.tap(find.text('BELTS LADIES PU'));
        await tester.pump();
        expect(tapped, ['3000247']);
      });
    });
  }

  group('RackContentsSheet search and as-on date', () {
    Widget sheet({
      List<RackContentsEntry> entries = const [full, bare],
      List<DeskColumn>? columns,
      DateTime? asOf,
      RackContentsLoader? load,
    }) => Align(
      alignment: Alignment.bottomCenter,
      child: RackContentsSheet(
        rackId: 'KA-WH-DXB1-121D',
        warehouse: 'WH-DXB1 - KA',
        entries: entries,
        columns: columns,
        baseUrl: 'https://erp.domain.com',
        asOf: asOf,
        loadAsOf: load,
      ),
    );

    /// Types the date into the picker rather than tapping a calendar day, so
    /// the test does not depend on today's date. Leaves the picker closed
    /// but the load un-settled when [settle] is false.
    Future<void> pickDate(
      WidgetTester tester,
      String typed, {
      bool settle = true,
    }) async {
      await tester.tap(find.byKey(const ValueKey('rack-as-of')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, typed);
      await tester.tap(find.text('OK'));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    testWidgets('search narrows the cards and the footer counts them', (
      tester,
    ) async {
      await pump(tester, sheet(), brightness: Brightness.light, height: 2000);

      await tester.enterText(
        find.byKey(const ValueKey('rack-search')),
        'focus',
      );
      await tester.pump();

      expect(find.byType(RackContentsCard), findsOneWidget);
      expect(find.text('BELTS LADIES PU'), findsOneWidget);
      expect(
        find.text('End of list · 1 of 2 items · Balance Qty 36 Nos'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.byType(RackContentsCard), findsNWidgets(2));
      expect(
        find.text('End of list · 2 items · Balance Qty 36 Nos'),
        findsOneWidget,
      );
    });

    testWidgets('a search with no match says so and can be cleared', (
      tester,
    ) async {
      await pump(tester, sheet(), brightness: Brightness.dark, height: 2000);

      await tester.enterText(find.byKey(const ValueKey('rack-search')), 'zzz');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(RackContentsCard), findsNothing);
      expect(find.text('No matching items'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await tester.pump();
      expect(find.byType(RackContentsCard), findsNWidgets(2));
    });

    testWidgets('opens on today and reloads the rack for a picked date', (
      tester,
    ) async {
      final asked = <DateTime>[];
      await pump(
        tester,
        sheet(
          asOf: DateTime.now(),
          load: (date) async {
            asked.add(date);
            return RackContentsSnapshot(
              entries: const [full],
              columns: isSameDay(date, DateTime.now())
                  ? null
                  : const [
                      (fieldname: 'bal_qty', label: 'Saldo'),
                      (fieldname: 'item_code', label: 'Element'),
                      (fieldname: 'item_name', label: 'Artikelname'),
                      (fieldname: 'warehouse', label: 'Lager'),
                    ],
            );
          },
        ),
        brightness: Brightness.light,
        height: 2000,
      );
      expect(find.textContaining('· Today'), findsOneWidget);
      expect(find.bySemanticsLabel('Warehouse WH-DXB1 - KA'), findsOneWidget);

      await pickDate(tester, '01/15/2025');

      expect(asked, [DateTime(2025, 1, 15)]);
      expect(find.text('As on 15 Jan 2025'), findsOneWidget);
      expect(find.byType(RackContentsCard), findsOneWidget);
      expect(find.text('Saldo'), findsOneWidget);
      expect(find.text('End of list · 1 item · Saldo 36 Nos'), findsOneWidget);
      expect(find.bySemanticsLabel('Lager WH-DXB1 - KA'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Artikelname BELTS LADIES PU')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Element 3000247')), findsOneWidget);
      expect(find.text('WH-DXB1 - KA'), findsOneWidget);

      // "Today" goes back to the current stock.
      await tester.tap(find.widgetWithText(TextButton, 'Today'));
      await tester.pumpAndSettle();
      expect(asked, hasLength(2));
      expect(isSameDay(asked.last, DateTime.now()), isTrue);
      expect(find.textContaining('· Today'), findsOneWidget);
      expect(find.bySemanticsLabel('Warehouse WH-DXB1 - KA'), findsOneWidget);
    });

    testWidgets('the date button is disabled with a spinner while loading', (
      tester,
    ) async {
      final pending = Completer<RackContentsSnapshot>();
      await pump(
        tester,
        sheet(asOf: DateTime.now(), load: (_) => pending.future),
        brightness: Brightness.dark,
        height: 2000,
      );

      await pickDate(tester, '01/15/2025', settle: false);

      final button = find.byKey(const ValueKey('rack-as-of'));
      expect(tester.widget<ButtonStyleButton>(button).enabled, isFalse);
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // The old list stays until the new one arrives.
      expect(find.byType(RackContentsCard), findsNWidgets(2));

      pending.complete(const RackContentsSnapshot(entries: [bare]));
      await tester.pumpAndSettle();
      expect(tester.widget<ButtonStyleButton>(button).enabled, isTrue);
      expect(find.byType(RackContentsCard), findsOneWidget);
    });

    testWidgets('a failed load keeps the previous date and list', (
      tester,
    ) async {
      await pump(
        tester,
        sheet(
          asOf: DateTime.now(),
          columns: const [(fieldname: 'bal_qty', label: 'Saldo anterior')],
          load: (_) async => throw const FormatException('bad'),
        ),
        brightness: Brightness.light,
        height: 2000,
      );

      await pickDate(tester, '01/15/2025');

      expect(find.byKey(const ValueKey('rack-load-error')), findsOneWidget);
      expect(
        find.textContaining('Could not load stock as on 15 Jan 2025'),
        findsOneWidget,
      );
      expect(find.textContaining('· Today'), findsOneWidget);
      expect(find.byType(RackContentsCard), findsNWidgets(2));
      expect(
        find.text('End of list · 2 items · Saldo anterior 36 Nos'),
        findsOneWidget,
      );
    });

    testWidgets('a date the rack was empty shows the empty state', (
      tester,
    ) async {
      await pump(
        tester,
        sheet(
          asOf: DateTime.now(),
          load: (_) async => const RackContentsSnapshot(entries: []),
        ),
        brightness: Brightness.dark,
        height: 2000,
      );

      await pickDate(tester, '01/15/2025');

      expect(tester.takeException(), isNull);
      expect(find.text('Rack was empty'), findsOneWidget);
      expect(
        find.text('Nothing was on KA-WH-DXB1-121D on 15 Jan 2025.'),
        findsOneWidget,
      );
      expect(find.text('Back to Today'), findsOneWidget);
    });
  });

  test('footer names the full count while a search narrows the list', () {
    expect(
      rackContentsFooterLabel(const [full], outOf: 5),
      'End of list · 1 of 5 items · Balance Qty 36 Nos',
    );
    expect(
      rackContentsFooterLabel(const [full], outOf: 1),
      'End of list · 1 item · Balance Qty 36 Nos',
    );
  });

  test('footer omits the unit when rows mix UOMs', () {
    const pair = RackContentsEntry(
      itemCode: 'x',
      itemName: 'x',
      balanceQty: 1500,
      stockUom: 'Pair',
    );
    expect(
      rackContentsFooterLabel(const [full, pair]),
      'End of list · 2 items · Balance Qty 1,536',
    );
    expect(
      rackContentsFooterLabel(const [full]),
      'End of list · 1 item · Balance Qty 36 Nos',
    );
  });
}

void registerRackContentsFieldsTests() {
  testWidgets(
    'Rack search preserves unknown balances when quantity is hidden',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await tester.binding.setSurfaceSize(const Size(470, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final owner = ReportFieldsTestOwner()
        ..change('https://a.example', 'reader');
      Get.put<ReportOwnerSource>(owner);
      Get.put<ReportFieldsStore>(
        ScopedReportFieldsStore(
          database: ReportFieldsTestConfig(),
          storage: ReportFieldsTestStorage(),
        ),
      );
      final driver = WidgetReportFieldsDriver(tester, owner);
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: RackContentsSheet(
              rackId: 'R-1',
              baseUrl: 'https://a.example',
              entries: mergeRackContents([
                {'item_code': 'STOCK', 'bal_qty': 8, 'stock_uom': 'Nos'},
                {'item_code': 'MISSING', 'bal_qty': '', 'stock_uom': 'Nos'},
                {'item_code': 'ZERO', 'bal_qty': 0, 'stock_uom': 'Nos'},
              ], null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await driver.openFields();
      await driver.setVisible('bal_qty', false);
      await driver.dismiss();

      expect(find.byType(RackContentsCard), findsNWidgets(3));
      expect(find.byKey(const ValueKey('rack-card-qty')), findsNothing);
      expect(find.text('Balance Qty unavailable'), findsOneWidget);
      expect(
        find.text('End of list · 3 items · Balance Qty 8 Nos (incomplete)'),
        findsOneWidget,
      );
      final search = find.byKey(const ValueKey('rack-search'));
      await tester.enterText(search, 'MISSING');
      await tester.pumpAndSettle();
      expect(find.text('Balance Qty unavailable'), findsOneWidget);
      expect(
        find.text('End of list · 1 of 3 items · Balance Qty unavailable'),
        findsOneWidget,
      );
      await tester.enterText(search, 'ZERO');
      await tester.pumpAndSettle();
      expect(find.text('Balance Qty unavailable'), findsNothing);
      expect(
        find.text('End of list · 1 of 3 items · Balance Qty 0 Nos'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Rack Contents Fields keep batches, item search and rack totals',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await tester.binding.setSurfaceSize(const Size(470, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final owner = ReportFieldsTestOwner()
        ..change('https://a.example', 'reader');
      final database = ReportFieldsTestConfig();
      final storage = ReportFieldsTestStorage();
      Get.put<ReportOwnerSource>(owner);
      final driver = WidgetReportFieldsDriver(tester, owner);
      final tapped = <String>[];
      const balanceKey =
          'stock_balance_fields::https%3A%2F%2Fa.example::reader';
      const rackKey = 'rack_contents_fields::https%3A%2F%2Fa.example::reader';
      database.values[balanceKey] = '{"bal_qty":false}';
      const columns = <DeskColumn>[
        (fieldname: 'bal_qty', label: 'Saldo'),
        (fieldname: 'stock_uom', label: 'Unidad de existencias'),
        (fieldname: 'item_group', label: 'Grupo'),
        (fieldname: 'batch_no', label: 'Lote'),
      ];
      const entries = [
        RackContentsEntry(
          itemCode: 'I-01',
          itemName: 'Item one',
          stockUom: 'Each',
          itemGroup: 'Supplies',
          batchNo: 'B1',
          balanceQty: 2,
        ),
        RackContentsEntry(
          itemCode: 'I-01',
          itemName: 'Item one',
          stockUom: 'Pair',
          itemGroup: 'Tools',
          batchNo: 'B2',
          balanceQty: 0,
          disabled: true,
        ),
      ];
      const rack = 'KA-WH-DXB1-121D';

      Future<void> mount() async {
        Get.put<ReportFieldsStore>(
          ScopedReportFieldsStore(database: database, storage: storage),
        );
        await tester.pumpWidget(
          GetMaterialApp(
            home: Scaffold(
              body: TextButton(
                onPressed: () => Get.bottomSheet(
                  RackContentsSheet(
                    rackId: rack,
                    warehouse: 'WH-DXB1 - KA',
                    entries: entries,
                    columns: columns,
                    baseUrl: 'https://a.example',
                    itemDetailsFailed: true,
                    onItemTap: tapped.add,
                  ),
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                ),
                child: const Text('Open rack'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open rack'));
        await tester.pumpAndSettle();
      }

      await mount();
      expect(find.text('Rack Contents'), findsOneWidget);
      expect(find.text('Saldo'), findsNWidgets(2));
      expect(find.text('Grupo'), findsNWidgets(2));
      expect(find.text('Lote'), findsNWidgets(2));
      expect(rackContentsOccurrenceIds(rack, entries).toSet(), hasLength(2));
      final search = find.byKey(const ValueKey('rack-search'));
      final quantity = find.byKey(const ValueKey('rack-card-qty'));
      Future<void> expectSupplies({required bool showUnit}) async {
        await tester.enterText(search, 'Supplies');
        await tester.pumpAndSettle();
        expect(find.text('B1'), findsOneWidget);
        expect(find.text('B2'), findsNothing);
        expect(tester.widget<Text>(quantity).data, '2');
        expect(find.text('Each'), showUnit ? findsOneWidget : findsNothing);
        expect(
          find.text('End of list · 1 of 2 items · Saldo 2 Each'),
          findsOneWidget,
        );
      }

      await driver.openFields();
      await driver.setVisible('stock_uom', false);
      await driver.dismiss();
      await expectSupplies(showUnit: false);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      await driver.openFields();
      for (final key in ['item_group', 'bal_qty']) {
        expect((await driver.read(key)).value, isTrue);
        await driver.setVisible(key, false);
      }
      await driver.dismiss();
      expect(find.text('Grupo'), findsNothing);
      expect(find.byKey(const ValueKey('rack-card-qty')), findsNothing);
      expect(find.text('Lote'), findsNWidgets(2));
      expect(find.text('B1'), findsOneWidget);
      expect(find.text('B2'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Item details could not be loaded.'), findsOneWidget);
      expect(find.text('End of list · 2 items · Saldo 2'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('rack-search')),
        'Supplies',
      );
      await tester.pumpAndSettle();
      expect(find.text('B1'), findsOneWidget);
      expect(find.text('B2'), findsNothing);
      expect(
        find.text('End of list · 1 of 2 items · Saldo 2 Each'),
        findsOneWidget,
      );
      await tester.tap(find.text('Item one'));
      expect(tapped, ['I-01']);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await Get.delete<ReportFieldsStore>(force: true);
      await mount();
      await driver.openFields();
      expect((await driver.read('bal_qty')).value, isFalse);
      expect((await driver.read('stock_uom')).value, isFalse);
      await driver.switchOwner(site: 'https://a.example', user: 'other');
      expect((await driver.read('bal_qty')).value, isTrue);
      await driver.switchOwner(site: 'https://b.example', user: 'reader');
      expect((await driver.read('bal_qty')).value, isTrue);
      await driver.switchOwner(site: 'https://a.example', user: 'reader');
      expect((await driver.read('bal_qty')).value, isFalse);
      await driver.dismiss();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await Get.delete<ReportFieldsStore>(force: true);
      await mount();
      await driver.openFields();
      expect((await driver.read('bal_qty')).value, isFalse);
      await driver.reset();
      expect((await driver.read('bal_qty')).value, isTrue);
      expect((await driver.read('stock_uom')).value, isTrue);
      expect(database.values[rackKey], '{}');
      expect(database.values[balanceKey], '{"bal_qty":false}');
      await driver.dismiss();
      await expectSupplies(showUnit: true);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await Get.delete<ReportFieldsStore>(force: true);
      await mount();
      await expectSupplies(showUnit: true);
    },
  );

  testWidgets(
    'Rack Contents Fields restores the painted batch across layout edits',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(385, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const rack = 'KA-WH-DXB1-121D';
      final entries = [
        for (var index = 0; index < 48; index++)
          RackContentsEntry(
            itemCode: 'I-$index',
            itemName: 'Item $index',
            batchNo: 'Stock batch identifier $index',
            itemGroup: 'Maintenance and equipment supplies for production',
            balanceQty: index.toDouble(),
            stockUom: 'Each',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RackContentsSheet(
              rackId: rack,
              entries: entries,
              baseUrl: 'https://a.example',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final driver = WidgetReportFieldsDriver(tester, ReportFieldsTestOwner());
      final id = rackContentsOccurrenceIds(rack, entries)[20];
      await driver.scrollToOccurrence(id);
      const offset = -4.0;
      driver.position.jumpTo(
        driver.position.pixels + driver.readPaintedOffset(id) - offset,
      );
      await tester.pumpAndSettle();
      expect(driver.readPaintedOffset(id), closeTo(offset, 1));
      await driver.openFields();
      await driver.setVisible('item_group', false);
      await driver.setVisible('bal_qty', false);
      await driver.dismiss();
      expect(driver.readPaintedOffset(id), closeTo(offset, 1));
      await driver.openFields();
      await driver.reset();
      await driver.dismiss();
      expect(driver.readPaintedOffset(id), closeTo(offset, 1));
    },
  );
}
