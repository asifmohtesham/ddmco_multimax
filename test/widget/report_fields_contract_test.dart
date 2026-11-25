import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:dio/dio.dart';
// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_fields.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_screen.dart';

import '../support/report_fields_test_kit.dart';
import '../support/stock_result_fields_tests.dart'
    show registerStockResultFieldsTests;
import 'hr_report_screens_test.dart' show registerHrReportFieldsTests;
import 'item_variant_details_screen_test.dart'
    show registerItemVariantDetailsFieldsContract;
import 'manufacturing_report_fields_contract.dart'
    show registerManufacturingReportFieldsTests;
import 'stock_ageing_screen_test.dart' show registerStockAgeingFieldsContract;
import 'suppliers_by_item_screen_test.dart'
    show registerSuppliersByItemFieldsContract;

const _site = 'https://one.example/Tenant';
const _user = 'Sales@example.com';
const _batchColumns = [
  {'fieldname': 'balance_value', 'label': 'Balance Value'},
  {'fieldname': 'batch', 'label': 'Lot'},
  {'fieldname': 'item', 'label': 'Item'},
  {'fieldname': 'balance_qty', 'label': 'Available Units'},
  {'fieldname': 'warehouse', 'label': 'Location'},
  {'fieldname': 'item_name', 'label': 'Item Name'},
  {'fieldname': 'in_qty', 'label': 'In Qty'},
  {'fieldname': 'out_qty', 'label': 'Out Qty'},
  {'fieldname': 'opening_qty', 'label': 'Opening Qty'},
  {'fieldname': 'uom', 'label': 'UOM'},
  {'fieldname': 'expiry_date', 'label': ''},
];

class _BatchApi extends ApiProvider {
  int requests = 0;
  bool empty = false;
  bool fails = false;
  int length = 3;
  bool duplicate = false;
  bool german = false;

  @override
  Future<BatchWiseBalanceResult> getBatchWiseBalanceReport({
    required String itemCode,
    String? batchNo,
    String? warehouse,
    String? fromDate,
    String? toDate,
  }) async {
    requests++;
    if (fails) throw StateError('Fixture request failed');
    if (german) {
      return ApiProvider.parseBatchWiseBalanceReport({
        'columns': [
          for (final (key, label, type, target) in const [
            ('element', 'Element', 'Link', 'Item'),
            ('artikelname', 'Artikelname', 'Data', ''),
            ('beschreibung', 'Beschreibung', 'Data', ''),
            ('lager', 'Lager', 'Link', 'Warehouse'),
            ('charge', 'Charge', 'Link', 'Batch'),
            ('anfangsmenge', 'Anfangsmenge', 'Float', ''),
            ('in_menge', 'In Menge', 'Float', ''),
            ('ausgabe_menge', 'Ausgabe-Menge', 'Float', ''),
            ('bilanzmenge', 'Bilanzmenge', 'Float', ''),
            ('wertansatz', 'Wertansatz', 'Float', ''),
            ('bilanzwert', 'Bilanzwert', 'Currency', ''),
            ('einheit', 'Einheit', 'Data', ''),
          ])
            {
              'fieldname': key,
              'label': label,
              'fieldtype': type,
              'options': target,
            },
        ],
        'add_total_row': true,
        'result': [
          {
            'element': 'A-25',
            'artikelname': 'Artikel Alpha',
            'lager': 'Lager West',
            'charge': 'Charge-1',
            'anfangsmenge': 2,
            'in_menge': 5,
            'ausgabe_menge': 0,
            'bilanzmenge': 7,
            'einheit': 'Stk',
          },
          ['Gesamt', '', '', '', '', 2, 5, 0, 7, null, null, ''],
        ],
      });
    }
    return ApiProvider.parseBatchWiseBalanceReport({
      'columns': _batchColumns,
      'result': [
        if (!empty) ...[
          {
            'batch': 'Lot-zero',
            'item': 'Total',
            'item_name': 'Movement ended in zero',
            'warehouse': 'Warehouse East',
            'balance_qty': 0,
            'opening_qty': 2,
            'in_qty': 7,
            'out_qty': 9,
            'uom': 'Box',
          },
          [
            987,
            'Lot-open',
            'SKU-2',
            7,
            'Warehouse West',
            'Item Two',
            4,
            -1,
            2,
            'Box',
            '2030-07-01',
          ],
          {'batch': 'Lot-missing', 'item': 'SKU-3', 'in_qty': 3},
          if (duplicate)
            {
              'batch': 'Lot-missing',
              'item': 'SKU-3',
              'item_name': 'Repeated batch',
            },
          for (var index = 3; index < length; index++)
            {
              'batch': 'Lot-$index',
              'item': 'SKU-$index',
              'balance_qty': index,
              'warehouse': 'Warehouse West',
            },
          ['Total', null, null, 700, null, null, 700, null, null, null],
          {'item': 'Total', 'balance_qty': 700},
        ],
      ],
    });
  }
}

class _BatchFixture implements ReportFieldsFixture {
  final owner = ReportFieldsTestOwner();
  final database = ReportFieldsTestConfig();
  final storage = ReportFieldsTestStorage();
  final api = _BatchApi();
  late BatchWiseBalanceController controller;

  @override
  List<ExpectedField> get expectedFields => const [
    (
      key: 'balance_qty',
      section: 'Batch rows',
      column: 'balance_qty',
      label: 'Available Units',
      defaultVisible: true,
      locked: false,
    ),
    (
      key: 'item',
      section: 'Fixed identity',
      column: 'item',
      label: 'Item',
      defaultVisible: true,
      locked: true,
    ),
    (
      key: 'item_name',
      section: 'Fixed identity',
      column: 'item_name',
      label: 'Item Name',
      defaultVisible: true,
      locked: true,
    ),
    (
      key: 'warehouse',
      section: 'Fixed identity',
      column: 'warehouse',
      label: 'Location',
      defaultVisible: true,
      locked: true,
    ),
    (
      key: 'batch',
      section: 'Fixed identity',
      column: 'batch',
      label: 'Lot',
      defaultVisible: true,
      locked: true,
    ),
  ];

  @override
  int get reportRequests => api.requests;

  @override
  Future<void> mount(
    WidgetTester tester, {
    required String site,
    required String user,
    bool settle = true,
  }) async {
    owner.change(site, user);
    Get
      ..put<ApiProvider>(api)
      ..put<ReportOwnerSource>(owner)
      ..put<ReportFieldsStore>(
        ScopedReportFieldsStore(database: database, storage: storage),
      );
    controller = Get.put(BatchWiseBalanceController());
    await tester.pumpWidget(
      const GetMaterialApp(home: BatchWiseBalanceScreen()),
    );
    await _pump(tester, settle);
    await _run(tester, settle: settle);
  }

  Future<void> _pump(WidgetTester tester, bool settle) =>
      settle ? tester.pumpAndSettle() : tester.pump();

  Future<void> _run(WidgetTester tester, {bool settle = true}) async {
    controller.itemCodeController.text = 'Fixture';
    await controller.runReport();
    await _pump(tester, settle);
  }

  @override
  Future<void> reopenWithFreshStore(WidgetTester tester) async {
    final ownerScope = owner.current!.scope;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await Get.delete<BatchWiseBalanceController>();
    await Get.delete<ReportFieldsStore>();
    await mount(tester, site: ownerScope.site, user: ownerScope.user);
  }

  @override
  Future<List<Object>> readAllOccurrenceIdsInOrder(WidgetTester tester) async {
    final rows = find.byWidgetPredicate(
      (widget) => switch (widget.key) {
        ValueKey<Object>(value: BatchOccurrence()) => true,
        _ => false,
      },
    );
    final cards = rows.evaluate().map((element) => element.widget).toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b)).dy),
      );
    void expectDetail(Finder card, String label, Object? value) {
      final caption = find.descendant(of: card, matching: find.text(label));
      final pair = find
          .ancestor(of: caption, matching: find.byType(Column))
          .first;
      expect(
        find.descendant(
          of: pair,
          matching: find.text(value?.toString() ?? '—'),
        ),
        findsOneWidget,
      );
    }

    final rendered = <Object>[];
    for (final widget in cards) {
      final id = (widget.key! as ValueKey<Object>).value as BatchOccurrence;
      final card = find.byWidget(widget);
      expect(
        find.descendant(of: card, matching: find.text(id.item.toString())),
        findsOneWidget,
      );
      expectDetail(card, 'Location', id.warehouse);
      expectDetail(card, 'Lot', id.batch);
      if (id.batch == 'Lot-missing') {
        final quantity = find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Available Units',
          ),
        );
        expect(quantity, findsOneWidget);
        expect(
          find.descendant(of: quantity, matching: find.text('—')),
          findsOneWidget,
        );
        if (id.occurrence == 1) {
          expect(
            find.descendant(of: card, matching: find.text('Repeated batch')),
            findsOneWidget,
          );
        }
      }
      rendered.add(id);
    }
    return rendered;
  }

  @override
  Future<void> expectDefaultCards(WidgetTester tester) async {
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Lot-open'), findsOneWidget);
    expect(find.text('Expiry'), findsOneWidget);
    expect(find.text('2030-07-01'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('987'), findsNothing);
    expect(find.text('700'), findsNothing);
  }

  @override
  Future<void> expectProtectedContentAndTotals(WidgetTester tester) async {
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Movement ended in zero'), findsOneWidget);
    expect(find.text('Warehouse East'), findsOneWidget);
    expect(find.text('Lot-zero'), findsOneWidget);
    expect(find.text('End of list'), findsOneWidget);
    expect(find.text('Totals'), findsOneWidget);
    final footer = find
        .ancestor(of: find.text('End of list'), matching: find.byType(Column))
        .first;
    final expected = {
      'Box': [
        ('Opening Qty', '4'),
        ('In Qty', '11'),
        ('Out Qty', '8'),
        ('Available Units', '7'),
      ],
      'Unknown unit': [('In Qty', '3')],
    };
    expect(
      find.descendant(of: footer, matching: find.byType(Wrap)),
      findsNWidgets(expected.length),
    );
    for (final entry in expected.entries) {
      final title = find.descendant(of: footer, matching: find.text(entry.key));
      final group = find
          .ancestor(of: title, matching: find.byType(Column))
          .first;
      final wrap = find.descendant(of: group, matching: find.byType(Wrap));
      final pairs = tester.widget<Wrap>(wrap).children;
      expect(
        [
          for (final pair in pairs)
            tester
                .widgetList<Text>(
                  find.descendant(
                    of: find.byWidget(pair),
                    matching: find.byType(Text),
                  ),
                )
                .map((text) => text.data)
                .toList(),
        ],
        unorderedEquals([
          for (final (label, value) in entry.value) [label, value],
        ]),
      );
    }
  }

  @override
  Future<void> expectOccurrenceDetail(
    WidgetTester tester,
    String key,
    bool shown,
  ) async {
    expect(key, 'balance_qty');
    expect(find.text('0'), shown ? findsOneWidget : findsNothing);
  }

  @override
  Future<void> showSuccessfulEmpty(WidgetTester tester) async {
    api.empty = true;
    await _run(tester);
  }

  @override
  Future<void> showFailure(WidgetTester tester) async {
    api.fails = true;
    await _run(tester);
  }
}

const _posColumns = {
  'status': 'Status',
  'ref_code': 'Customer Code',
  'item_code': 'Item Code',
  'item_group': 'Product Family',
  'dn_item': 'Delivery Description',
  'upload_item': 'Upload Description',
  'customer': 'Customer',
  'customer_group': 'Customer Group',
  'account_manager': 'Account Manager',
  'upload_qty': 'Uploaded Quantity',
  'upload_rate': 'Uploaded Rate',
  'dn_qty': 'Delivered Quantity',
  'dn_name': 'DN #',
  'pos_upload': 'POS #',
  'idx': 'Invoice Line Serial Number',
};

class _PosApi extends ApiProvider {
  var requests = 0;
  var imageRequests = 0;
  var extraRows = 0;

  @override
  Future<Response> runPosDnItemRateReport({
    List<String> posUploads = const [],
    String? fromDate,
    String? toDate,
    List<String> customers = const [],
    List<String> customerGroups = const [],
    List<String> itemGroups = const [],
    bool showMapped = false,
    bool onlyCoded = false,
  }) async {
    requests++;
    return Response(
      requestOptions: RequestOptions(),
      statusCode: 200,
      data: {
        'message': {
          'columns': [
            for (final entry in _posColumns.entries)
              {'fieldname': entry.key, 'label': entry.value},
          ],
          'result': [
            {
              'status': 'New',
              'ref_code': 'REF-1',
              'item_code': 'ART-1',
              'item_group': 'Travel',
              'dn_item': 'Delivery Brown Tote',
              'upload_item': 'Upload Brown Tote',
              'customer': 'Example Shop',
              'customer_group': 'Retail',
              'account_manager': 'Keep absent',
              'upload_qty': 8,
              'upload_rate': 12,
              'dn_qty': 3,
              'dn_name': 'DL-1',
              'pos_upload': 'UP-1',
              'idx': 14,
            },
            [
              'Already mapped',
              'REF-1',
              'ART-1',
              'Travel',
              'Delivery Blue Tote',
              'Upload Blue Tote',
              'Example Shop',
              'Wholesale',
              null,
              9,
              12,
              5,
              'DL-2',
              'UP-2',
              14,
            ],
            {
              'status': 'No code',
              'upload_item': 'Unmatched Line',
              'upload_qty': 1,
              'pos_upload': 'UP-3',
              'idx': 2,
            },
            for (var index = 0; index < extraRows; index++)
              {
                'status': 'New',
                'item_code': 'ART-Long-$index',
                'item_group': 'Stock group',
                'customer_group': 'Often repeated',
                'upload_item': 'POS name for row $index',
                'upload_qty': index,
                'upload_rate': 12,
                'dn_qty': 1,
                'dn_name': 'DN-Long-$index',
                'pos_upload': 'POS-Long-$index',
                'idx': index,
              },
            ['Total', null, null, null, null, null, null, null, null, 500],
            {'status': 'Total', 'upload_qty': 500},
          ],
        },
      },
    );
  }

  @override
  Future<Map<String, String>> getItemImages(List<String> itemCodes) async {
    imageRequests++;
    return {};
  }
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);
  registerItemVariantDetailsFieldsContract();
  registerStockAgeingFieldsContract();
  registerStockResultFieldsTests();
  registerSuppliersByItemFieldsContract();
  registerHrReportFieldsTests();
  registerManufacturingReportFieldsTests();

  testWidgets('Batch Fields protects rows and persists by site and account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _BatchFixture()..api.duplicate = true;
    final driver = WidgetReportFieldsDriver(tester, fixture.owner);
    final semantics = tester.ensureSemantics();
    await fixture.mount(tester, site: _site, user: _user);
    await fixture.expectDefaultCards(tester);
    await fixture.expectProtectedContentAndTotals(tester);
    final identities = await fixture.readAllOccurrenceIdsInOrder(tester);
    expect(identities, [
      (
        item: 'Total',
        warehouse: 'Warehouse East',
        batch: 'Lot-zero',
        occurrence: 0,
      ),
      (
        item: 'SKU-2',
        warehouse: 'Warehouse West',
        batch: 'Lot-open',
        occurrence: 0,
      ),
      (item: 'SKU-3', warehouse: null, batch: 'Lot-missing', occurrence: 0),
      (item: 'SKU-3', warehouse: null, batch: 'Lot-missing', occurrence: 1),
    ]);
    expect(
      tester.widget<Text>(find.text('Total')).semanticsLabel,
      'Item Total',
    );
    expect(
      tester.widget<Text>(find.text('Movement ended in zero')).semanticsLabel,
      'Item Name Movement ended in zero',
    );
    await driver.openFields();
    for (final expected in fixture.expectedFields) {
      final checkbox = await driver.read(expected.key);
      final tile = find.byWidget(checkbox);
      final label = _batchColumns.singleWhere(
        (column) => column['fieldname'] == expected.column,
      )['label']!;
      expect(label, expected.label);
      expect(checkbox.value, expected.defaultVisible);
      expect(checkbox.onChanged == null, expected.locked);
      expect(
        find.descendant(of: tile, matching: find.text(label)),
        findsOneWidget,
      );
      final headings = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.header == true &&
              widget.child is Text,
        ),
      );
      final preceding = tester
          .widgetList<Semantics>(headings)
          .where(
            (heading) =>
                tester.getTopLeft(find.byWidget(heading)).dy <
                tester.getTopLeft(tile).dy,
          );
      expect((preceding.last.child! as Text).data, expected.section);
      final data = tester.getSemantics(tile).getSemanticsData();
      expect(data.label, contains('${expected.section}, $label'));
      expect(data.flagsCollection.isChecked, CheckedState.isTrue);
      expect(
        data.flagsCollection.isEnabled,
        expected.locked ? Tristate.isFalse : Tristate.isTrue,
      );
    }
    semantics.dispose();
    await driver.setVisible('balance_qty', false);
    await driver.dismiss();
    await fixture.expectOccurrenceDetail(tester, 'balance_qty', false);
    await fixture.expectProtectedContentAndTotals(tester);
    expect(await fixture.readAllOccurrenceIdsInOrder(tester), identities);
    expect(fixture.reportRequests, 1);

    await fixture.reopenWithFreshStore(tester);
    await fixture.expectOccurrenceDetail(tester, 'balance_qty', false);
    await driver.openFields();
    await driver.switchOwner(site: _site, user: 'Other');
    expect((await driver.read('balance_qty')).value, isTrue);
    await driver.switchOwner(site: 'https://other.example/Tenant', user: _user);
    expect((await driver.read('balance_qty')).value, isTrue);
    await driver.switchOwner(site: _site, user: _user);
    expect((await driver.read('balance_qty')).value, isFalse);
    await driver.reset();
    expect((await driver.read('balance_qty')).value, isTrue);
    await driver.dismiss();
    expect(fixture.reportRequests, 2);
    await fixture.reopenWithFreshStore(tester);
    await fixture.expectOccurrenceDetail(tester, 'balance_qty', true);
  });

  testWidgets(
    'German Batch report keeps returned identities, labels and totals',
    (tester) async {
      final fixture = _BatchFixture()..api.german = true;
      final driver = WidgetReportFieldsDriver(tester, fixture.owner);
      await fixture.mount(tester, site: _site, user: _user);
      final card = find
          .ancestor(of: find.text('A-25'), matching: find.byType(Material))
          .first;
      Finder cardText(String text) =>
          find.descendant(of: card, matching: find.text(text));
      final footer = find
          .ancestor(of: find.text('End of list'), matching: find.byType(Column))
          .first;
      void protected() {
        for (final value in [
          'Artikel Alpha',
          'Lager West',
          'Charge-1',
          'Lager',
          'Charge',
        ]) {
          expect(cardText(value), findsOneWidget);
        }
        for (final value in [
          'Stk',
          'Anfangsmenge',
          'In Menge',
          'Ausgabe-Menge',
          'Bilanzmenge',
          '7',
        ]) {
          expect(
            find.descendant(of: footer, matching: find.text(value)),
            findsOneWidget,
          );
        }
        expect(find.text('Gesamt'), findsNothing);
      }

      protected();
      expect(cardText('7'), findsOneWidget);
      expect(
        tester.widget<Text>(cardText('A-25')).semanticsLabel,
        'Element A-25',
      );
      expect(
        tester.widget<Text>(cardText('Artikel Alpha')).semanticsLabel,
        'Artikelname Artikel Alpha',
      );
      await driver.openFields();
      expect((await driver.read('balance_qty')).value, isTrue);
      expect(find.text('Bilanzmenge'), findsWidgets);
      expect(find.text('Artikelname'), findsOneWidget);
      await driver.setVisible('balance_qty', false);
      await driver.dismiss();
      expect(cardText('7'), findsNothing);
      protected();
      await driver.openFields();
      await driver.reset();
      await driver.dismiss();
      expect(cardText('7'), findsOneWidget);
      protected();
      expect(fixture.reportRequests, 1);
    },
  );

  testWidgets('Batch empty keeps its schema and failure shows Retry', (
    tester,
  ) async {
    final fixture = _BatchFixture();
    final driver = WidgetReportFieldsDriver(tester, fixture.owner);
    await fixture.mount(tester, site: _site, user: _user);
    await fixture.showSuccessfulEmpty(tester);
    expect(find.text('No rows for these filters'), findsOneWidget);
    expect(find.text('End of list'), findsOneWidget);
    expect(find.text('Totals'), findsNothing);
    await driver.openFields();
    expect((await driver.read('balance_qty')).value, isTrue);
    expect(find.text('Available Units'), findsOneWidget);
    await driver.dismiss();
    await fixture.showFailure(tester);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No rows for these filters'), findsNothing);
    expect(find.text('End of list'), findsNothing);
  });

  testWidgets('Batch Fields restores the deepest painted row across edits', (
    tester,
  ) async {
    final fixture = _BatchFixture()..api.length = 70;
    final driver = WidgetReportFieldsDriver(tester, fixture.owner);
    await fixture.mount(tester, site: _site, user: _user);
    const id = (
      item: 'SKU-22',
      warehouse: 'Warehouse West',
      batch: 'Lot-22',
      occurrence: 0,
    );
    await driver.scrollToOccurrence(id);
    const desired = -4.0;
    driver.position.jumpTo(
      driver.position.pixels + driver.readPaintedOffset(id) - desired,
    );
    await tester.pumpAndSettle();
    expect(driver.readPaintedOffset(id), closeTo(desired, 1));

    await driver.openFields();
    await driver.setVisible('balance_qty', false);
    await driver.dismiss();
    expect(driver.readPaintedOffset(id), closeTo(desired, 1));
    await driver.openFields();
    await driver.reset();
    await driver.dismiss();
    expect(driver.readPaintedOffset(id), closeTo(desired, 1));
  });

  testWidgets('Fields reports a failed save after dismissal and retries', (
    tester,
  ) async {
    final fixture = _BatchFixture();
    final driver = WidgetReportFieldsDriver(tester, fixture.owner);
    await fixture.mount(tester, site: _site, user: _user);
    fixture.database.beforeWrite = (_, _) async => throw StateError('Disk');
    await driver.openFields();
    await driver.setVisible('balance_qty', false);
    await driver.dismiss();
    expect(find.text('Could not save field settings'), findsOneWidget);
    fixture.database.beforeWrite = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save field settings'), findsNothing);
    await fixture.reopenWithFreshStore(tester);
    await fixture.expectOccurrenceDetail(tester, 'balance_qty', false);
  });

  testWidgets('Fields retries a failed save inside the open sheet', (
    tester,
  ) async {
    final fixture = _BatchFixture();
    final driver = WidgetReportFieldsDriver(tester, fixture.owner);
    await fixture.mount(tester, site: _site, user: _user);
    fixture.database.beforeWrite = (_, _) async => throw StateError('Disk');
    await driver.openFields();
    await driver.setVisible('balance_qty', false);
    final sheet = find.byType(DraggableScrollableSheet);
    final error = find.descendant(
      of: sheet,
      matching: find.text('Could not save field settings'),
    );
    final retry = find
        .descendant(
          of: sheet,
          matching: find.widgetWithText(TextButton, 'Retry'),
        )
        .hitTestable();
    expect(error.hitTestable(), findsOneWidget);
    expect(retry, findsOneWidget);
    fixture.database.beforeWrite = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(error, findsNothing);
    expect(sheet, findsOneWidget);
    expect((await driver.read('balance_qty')).value, isFalse);
    await driver.dismiss();
    await fixture.reopenWithFreshStore(tester);
    await fixture.expectOccurrenceDetail(tester, 'balance_qty', false);
  });

  testWidgets(
    'Visible pending save retains its original owner on account change',
    (tester) async {
      final fixture = _BatchFixture();
      final driver = WidgetReportFieldsDriver(tester, fixture.owner);
      await fixture.mount(tester, site: _site, user: _user);
      final write = Completer<void>();
      final originalKey = ScopedReportFieldsStore.configKey(
        'batch_wise_balance',
        (site: _site, user: _user),
      );
      fixture.database.beforeWrite = (key, _) async {
        if (key == originalKey) await write.future;
      };
      await driver.openFields();
      await driver.read('balance_qty');
      await tester.tap(find.byKey(const ValueKey('balance_qty')));
      await tester.pump();
      expect(find.text('Saving field settings…'), findsOneWidget);

      await driver.switchOwner(site: _site, user: 'Buyer');
      expect((await driver.read('balance_qty')).value, isTrue);
      write.complete();
      await tester.pumpAndSettle();
      expect(fixture.database.values, {originalKey: '{"balance_qty":false}'});

      await driver.switchOwner(site: _site, user: _user);
      expect((await driver.read('balance_qty')).value, isFalse);
      await driver.dismiss();
    },
  );

  testWidgets(
    'Keyboard-opened Fields blocks edits during load and restores focus',
    (tester) async {
      final fixture = _BatchFixture();
      final driver = WidgetReportFieldsDriver(tester, fixture.owner);
      final reading = Completer<void>();
      fixture.database.beforeRead = (_) async {
        await reading.future;
        throw StateError('Preference read failed');
      };
      await fixture.mount(tester, site: _site, user: _user, settle: false);
      final action = tester.widget<IconButton>(
        find
            .widgetWithIcon(IconButton, Icons.view_agenda_outlined)
            .hitTestable()
            .first,
      );
      action.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Loading field settings…'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const ValueKey('balance_qty')))
            .onChanged,
        isNull,
      );

      reading.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not load field settings'), findsWidgets);
      fixture.database.beforeRead = null;
      await tester.tap(find.text('Retry').hitTestable().last);
      await tester.pumpAndSettle();
      expect((await driver.read('balance_qty')).onChanged, isNotNull);
      await driver.dismiss();
      expect(action.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'POS Fields leaves group order, status, links and totals intact',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final owner = ReportFieldsTestOwner()..change(_site, _user);
      final api = _PosApi();
      Get
        ..put<ApiProvider>(api)
        ..put<ReportOwnerSource>(owner)
        ..put<ReportFieldsStore>(
          ScopedReportFieldsStore(
            database: ReportFieldsTestConfig(),
            storage: ReportFieldsTestStorage(),
          ),
        );
      final controller = Get.put(PosDnItemRateController());
      final driver = WidgetReportFieldsDriver(tester, owner);
      await tester.pumpWidget(
        const GetMaterialApp(home: PosDnItemRateScreen()),
      );
      await controller.runReport();
      controller.setPrimaryGroup(PosDnGroupField.itemGroup);
      controller.setSecondaryGroup(PosDnGroupField.rate);
      await tester.pumpAndSettle();

      final tiles = find.byType(PosDnItemRateTile);
      final headers = find.byType(PosDnGroupHeader);
      List<String?> renderedVouchers() => [
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: tiles,
            matching: find.textContaining(
              RegExp(r'^UP-\d+ · Invoice Line Serial Number '),
            ),
          ),
        ))
          text.data,
      ];
      const rows = [
        'UP-1 · Invoice Line Serial Number 14',
        'UP-2 · Invoice Line Serial Number 14',
        'UP-3 · Invoice Line Serial Number 2',
      ];
      expect(renderedVouchers(), rows);
      expect(headers, findsNWidgets(4));
      expect(find.text('Delivery Description'), findsNWidgets(2));
      expect(find.text('Upload Description'), findsNWidgets(3));
      expect(find.text('UP-3 · Invoice Line Serial Number 2'), findsOneWidget);
      expect(find.text('Product Family'), findsOneWidget);
      expect(find.text('Uploaded Rate'), findsNWidgets(4));
      expect(find.text('Keep absent'), findsNothing);

      await driver.openFields();
      expect(find.text('Account Manager'), findsNothing);
      for (final (key, label) in const [
        ('item_group', 'Product Family'),
        ('customer_group', 'Customer Group'),
        ('upload_qty', 'Uploaded Quantity'),
        ('upload_rate', 'Uploaded Rate'),
        ('dn_qty', 'Delivered Quantity'),
      ]) {
        final tile = await driver.read(key);
        expect(tile.value, isTrue);
        expect(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
        await driver.setVisible(key, false);
      }
      await driver.dismiss();
      expect(renderedVouchers(), rows);
      expect(headers, findsNWidgets(4));
      expect(
        find.descendant(of: tiles, matching: find.text('Retail')),
        findsNothing,
      );
      expect(
        find.descendant(of: tiles, matching: find.text('Uploaded Quantity')),
        findsNothing,
      );
      expect(
        find.descendant(of: tiles, matching: find.text('No code')),
        findsOneWidget,
      );
      expect(find.text('UP-2 · Invoice Line Serial Number 14'), findsOneWidget);
      expect(find.text('UP-3 · Invoice Line Serial Number 2'), findsOneWidget);
      expect(find.text('Uploaded Quantity 17'), findsNWidgets(2));
      expect(find.text('Delivered Quantity 8'), findsNWidgets(2));
      final footer = find
          .ancestor(of: find.text('Totals'), matching: find.byType(Column))
          .first;
      for (final text in [
        'Uploaded Quantity',
        'Delivered Quantity',
        '18',
        '8',
      ]) {
        expect(
          find.descendant(of: footer, matching: find.text(text)),
          findsOneWidget,
        );
      }

      controller.setSearchQuery('Wholesale');
      await tester.pumpAndSettle();
      expect(tiles, findsOneWidget);
      expect(find.text('UP-2 · Invoice Line Serial Number 14'), findsOneWidget);
      controller.setSearchQuery('');
      controller.collapseAllGroups();
      await tester.pumpAndSettle();
      expect(tiles, findsNothing);
      expect(find.textContaining('End of list'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      await driver.openFields();
      await driver.reset();
      expect((await driver.read('upload_rate')).value, isTrue);
      await driver.dismiss();
      expect(tiles, findsNothing);
      expect(api.requests, 1);
      expect(api.imageRequests, 1);
    },
  );

  testWidgets(
    'POS grouped Fields keep the same painted leaf on hide and reset',
    (tester) async {
      final owner = ReportFieldsTestOwner()..change(_site, _user);
      final api = _PosApi()..extraRows = 48;
      Get
        ..put<ApiProvider>(api)
        ..put<ReportOwnerSource>(owner)
        ..put<ReportFieldsStore>(
          ScopedReportFieldsStore(
            database: ReportFieldsTestConfig(),
            storage: ReportFieldsTestStorage(),
          ),
        );
      final controller = Get.put(PosDnItemRateController());
      final driver = WidgetReportFieldsDriver(tester, owner);
      await tester.pumpWidget(
        const GetMaterialApp(home: PosDnItemRateScreen()),
      );
      await controller.runReport();
      controller.setPrimaryGroup(PosDnGroupField.itemGroup);
      controller.setSecondaryGroup(PosDnGroupField.rate);
      await tester.pumpAndSettle();
      const id = (('POS-Long-18', 18, 'ART-Long-18', 'DN-Long-18'), 0);
      await driver.scrollToOccurrence(id);
      const offset = -5.0;
      driver.position.jumpTo(
        driver.position.pixels + driver.readPaintedOffset(id) - offset,
      );
      await tester.pumpAndSettle();
      await driver.openFields();
      for (final key in ['upload_qty', 'upload_rate', 'dn_qty']) {
        await driver.setVisible(key, false);
      }
      await driver.dismiss();
      expect(driver.readPaintedOffset(id), closeTo(offset, 1));
      await driver.openFields();
      await driver.reset();
      await driver.dismiss();
      expect(driver.readPaintedOffset(id), closeTo(offset, 1));
      expect(api.requests, 1);
      expect(api.imageRequests, 1);
    },
  );
}
