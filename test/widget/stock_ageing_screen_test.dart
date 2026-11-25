import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_fields.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_screen.dart';

import '../support/report_fields_test_kit.dart';

class _MemoryCache extends StockAgeingCache {
  final snapshots = <FieldsScope, StockAgeingSnapshot>{};

  @override
  Future<StockAgeingSnapshot?> read(FieldsScope scope) async =>
      snapshots[scope];

  @override
  Future<void> write(FieldsScope scope, StockAgeingSnapshot snapshot) async {
    snapshots[scope] = snapshot;
  }
}

class _PendingImageApi extends ApiProvider {
  final pending = Completer<Uint8List>();
  int requests = 0;

  @override
  Future<Uint8List> getFileBytes(String url) {
    requests++;
    return pending.future;
  }
}

const _identityColumns = [
  {'fieldname': 'item_code', 'label': 'Item Code'},
  {'fieldname': 'item_name', 'label': 'Item Name'},
  {'fieldname': 'qty', 'label': 'Available Qty', 'fieldtype': 'Float'},
  {'fieldname': 'uom', 'label': 'UOM'},
];

const _savedIntervals = ['0 - 90', '91 - 180', '181 - Above'];

Future<({StockAgeingController report, WidgetReportFieldsDriver driver})>
_mountAgeing(
  WidgetTester tester, {
  required List<Map<String, Object?>> rows,
  required String range,
  ThemeData? theme,
  ApiProvider? api,
  List<Map<String, Object?>> extraColumns = const [],
}) async {
  Get.testMode = true;
  addTearDown(Get.reset);
  Get.put<ApiProvider>(api ?? ApiProvider(), permanent: true);
  Get.put(AuthenticationController(), permanent: true);
  final owner = ReportFieldsTestOwner()..change('https://one.example', 'Buyer');
  final store = ScopedReportFieldsStore(
    database: ReportFieldsTestConfig(),
    storage: ReportFieldsTestStorage(),
  );
  ScopedReportFieldsController fields(ReportFieldsDefinition definition) =>
      ScopedReportFieldsController(
        definition: definition,
        owner: owner,
        store: store,
      );
  final report = Get.put(
    StockAgeingController(
      cache: _MemoryCache(),
      fields: fields(stockAgeingFields()),
      view: fields(stockAgeingView),
      company: () => 'Company',
      baseUrl: () => 'https://one.example',
      run: ({Map<String, dynamic>? filters}) async => Response(
        requestOptions: RequestOptions(path: '/'),
        data: {
          'message': {
            'columns': [
              ..._identityColumns,
              ...extraColumns,
              for (final (index, interval) in _savedIntervals.indexed) ...[
                {
                  'fieldname': 'range${index + 1}',
                  'label': 'Age ($interval)',
                  'fieldtype': 'Float',
                },
                {
                  'fieldname': 'range${index + 1}value',
                  'label': 'Value ($interval)',
                  'fieldtype': 'Float',
                },
              ],
            ],
            'result': rows,
            'custom_filters': {'range': range},
          },
        },
      ),
    ),
  );
  await tester.pumpWidget(
    GetMaterialApp(theme: theme, home: const StockAgeingScreen()),
  );
  await tester.pumpAndSettle();
  return (report: report, driver: WidgetReportFieldsDriver(tester, owner));
}

void registerStockAgeingFieldsContract() {
  testWidgets('Stock Ageing closes the details and a pending image on switch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(470, 940));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _PendingImageApi();
    final rows = <Map<String, Object?>>[
      {
        'item_code': 'A-17',
        'item_name': 'First owner item',
        'qty': 5,
        'uom': 'Nos',
        'image': '/private/files/site-a-preview.png',
      },
    ];
    final (:driver, report: _) = await _mountAgeing(
      tester,
      api: api,
      range: '360,720',
      rows: rows,
    );
    await tester.tap(find.text('A-17'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final detailsPhoto = find.byType(CachedNetworkImage);
    expect(detailsPhoto, findsOneWidget);
    await tester.tapAt(tester.getTopLeft(detailsPhoto) + const Offset(24, 64));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ItemImagePreview), findsOneWidget);
    expect(api.requests, 1);

    rows.clear();
    driver.owner.change('https://two.example', 'Buyer');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ItemImagePreview), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('First owner item'), findsNothing);
    expect(find.byType(StockAgeingScreen), findsOneWidget);
    api.pending.complete(Uint8List(0));
    await tester.pump();
    expect(find.byType(ItemImagePreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stock Ageing keeps a named offset through Fields and reset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(470, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:driver, report: _) = await _mountAgeing(
      tester,
      range: '360,720',
      extraColumns: const [
        {'fieldname': 'variant_of', 'label': 'Variant Of'},
        {'fieldname': 'warehouse', 'label': 'Warehouse'},
      ],
      rows: [
        for (var index = 0; index < 42; index++)
          {
            'item_code': 'SA-$index',
            'warehouse': 'MAIN',
            'variant_of': 'Template-$index',
            'qty': 5,
            'uom': 'Nos',
            'range1': 5,
          },
      ],
    );
    const occurrence = ('SA-14', 'MAIN', 0);
    await driver.scrollToOccurrence(occurrence);
    const offset = -5.0;
    driver.position.jumpTo(
      driver.position.pixels + driver.readPaintedOffset(occurrence) - offset,
    );
    await tester.pumpAndSettle();
    expect(driver.readPaintedOffset(occurrence), closeTo(offset, 1));
    await driver.openFields();
    await driver.setVisible('variant_of', false);
    await driver.dismiss();
    expect(driver.readPaintedOffset(occurrence), closeTo(offset, 1));
    await driver.openFields();
    await driver.reset();
    await driver.dismiss();
    expect(driver.readPaintedOffset(occurrence), closeTo(offset, 1));
  });

  for (final range in ['-1,360,720', '360,foo,720']) {
    testWidgets('Stock Ageing reports three actual intervals for $range', (
      tester,
    ) async {
      final (:driver, :report) = await _mountAgeing(
        tester,
        range: range,
        rows: const [
          {
            'item_code': 'A-17',
            'qty': 5,
            'uom': 'Nos',
            'range1': 1,
            'range1value': 10,
            'range2': 2,
            'range2value': 20,
            'range3': 2,
            'range3value': 20,
          },
        ],
      );
      const actualIntervals = ['0–360', '361–720', '721–Above'];
      const quantities = [1, 2, 2];
      expect(report.buckets, hasLength(3));
      for (final (i, interval) in actualIntervals.indexed) {
        expect(
          find.text(
            'Age (${_savedIntervals[i]}) · Range for this run: '
            '$interval: ${quantities[i]}',
          ),
          findsOneWidget,
        );
      }
      await driver.openFields();
      for (final (i, interval) in actualIntervals.indexed) {
        for (final suffix in ['', 'value']) {
          final field = await driver.read('range${i + 1}$suffix');
          final title = (field.title! as Semantics).child! as Text;
          final caption = suffix.isEmpty ? 'Age' : 'Value';
          expect(title.data, '$caption (${_savedIntervals[i]})');
          expect(
            (field.subtitle! as Text).data,
            'Range for this run: $interval',
          );
        }
      }
      await driver.dismiss();
      await driver.scrollToEnd();
      expect(find.text('End of list'), findsOneWidget);
      for (final (i, interval) in actualIntervals.indexed) {
        expect(
          find.textContaining('$interval · ${quantities[i]} Nos'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('Stock Ageing distinguishes partial, missing and measured zero', (
    tester,
  ) async {
    final (:driver, :report) = await _mountAgeing(
      tester,
      range: '+30,60',
      rows: const [
        {
          'item_code': 'Measured',
          'qty': 8,
          'uom': 'Nos',
          'range1': 8,
          'range2': 0,
        },
        {
          'item_code': 'Sparse',
          'uom': 'Nos',
          'qty': null,
          'range1': '—',
          'range2': 0,
        },
      ],
    );
    await driver.scrollToEnd();
    expect(find.text('— Nos'), findsOneWidget);
    expect(
      find.textContaining('Available Qty 8 Nos (partial)'),
      findsOneWidget,
    );
    expect(find.textContaining('0–60 · 8 Nos (partial)'), findsOneWidget);
    expect(find.textContaining('61–Above · 0 Nos'), findsOneWidget);
    expect(report.buckets, hasLength(2));

    report.onSearchChanged('Sparse');
    await tester.pumpAndSettle();
    await driver.scrollToEnd();
    expect(find.text('Sparse'), findsOneWidget);
    expect(find.text('— Nos'), findsOneWidget);
    expect(find.textContaining('Available Qty — Nos'), findsOneWidget);
    expect(find.textContaining('0–60 · — Nos'), findsOneWidget);
    expect(find.textContaining('61–Above · 0 Nos'), findsOneWidget);
    expect(find.text('End of list'), findsOneWidget);
  });

  testWidgets('Stock Ageing keeps the item name beside the spoken UOM', (
    tester,
  ) async {
    const fontFamily = 'StockAgeingTest';
    final loader = FontLoader(fontFamily)
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
    await tester.runAsync(loader.load);
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const name = 'Stainless Steel Mounting Bracket';
    await _mountAgeing(
      tester,
      range: '360,720',
      theme: ThemeData(fontFamily: fontFamily),
      rows: const [
        {'item_code': 'A-17', 'item_name': name, 'qty': 5, 'uom': 'Nos'},
      ],
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(name), matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.width, greaterThan(148));
    expect(find.text('5 Nos'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('5 UOM Nos')), findsOneWidget);
  });

  testWidgets(
    'Stock Ageing keeps raw labels, identities and independent View',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      await tester.binding.setSurfaceSize(const Size(470, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Get.put(ApiProvider(), permanent: true);
      Get.put(AuthenticationController(), permanent: true);
      final config = ReportFieldsTestConfig();
      const fieldsKey = 'stock_ageing_fields::https%3A%2F%2Fone.example::Buyer';
      const viewKey = 'stock_ageing_view::https%3A%2F%2Fone.example::Buyer';
      final storage = ReportFieldsTestStorage();
      final owner = ReportFieldsTestOwner()
        ..change('https://one.example', 'Buyer');
      final cache = _MemoryCache();
      var calls = 0;
      var includeAverageAge = true;
      final driver = WidgetReportFieldsDriver(tester, owner);
      const columns = [
        {'fieldname': 'item_code', 'label': 'Product'},
        {'fieldname': 'item_name', 'label': 'Product Name'},
        {'fieldname': 'warehouse', 'label': 'Warehouse'},
        {'fieldname': 'variant_of', 'label': 'Variante De'},
        {'fieldname': 'qty', 'label': 'Available Qty', 'fieldtype': 'Float'},
        {'fieldname': 'uom', 'label': 'UOM'},
        {
          'fieldname': 'average_age',
          'label': 'Average Age',
          'fieldtype': 'Float',
        },
        {'fieldname': 'range1', 'label': 'Age (0 - 90)', 'fieldtype': 'Float'},
        {
          'fieldname': 'range2',
          'label': 'Age (91 - 180)',
          'fieldtype': 'Float',
        },
        {
          'fieldname': 'range3',
          'label': 'Age (181 - 360)',
          'fieldtype': 'Float',
        },
      ];
      const rows = [
        {
          'item_code': 'Product A',
          'item_name': 'Description A',
          'warehouse': 'Warehouse A',
          'variant_of': 'Template A',
          'qty': 5,
          'uom': 'Nos',
          'average_age': 34,
          'range1': 3,
          'range2': 2,
          'range3': 0,
        },
        {
          'item_code': 'Product Box',
          'qty': 13,
          'uom': 'Box',
          'range1': 4,
          'range2': 8,
          'range3': 1,
        },
        {
          'item_code': 'Product Unknown',
          'qty': 19,
          'uom': ' ',
          'range1': 7,
          'range2': 3,
          'range3': 9,
        },
      ];

      const nosTotal =
          'Available Qty 5 Nos\n'
          'Age (0 - 90) · Range for this run: 0–360 · 3 Nos\n'
          'Age (91 - 180) · Range for this run: 361–720 · 2 Nos\n'
          'Age (181 - 360) · Range for this run: 721–Above · 0 Nos';
      const boxTotal =
          'Available Qty 13 Box\n'
          'Age (0 - 90) · Range for this run: 0–360 · 4 Box\n'
          'Age (91 - 180) · Range for this run: 361–720 · 8 Box\n'
          'Age (181 - 360) · Range for this run: 721–Above · 1 Box';
      const unknownTotal =
          'Available Qty 19 Unknown UOM\n'
          'Age (0 - 90) · Range for this run: 0–360 · 7 Unknown UOM\n'
          'Age (91 - 180) · Range for this run: 361–720 · 3 Unknown UOM\n'
          'Age (181 - 360) · Range for this run: 721–Above · 9 Unknown UOM';

      late StockAgeingController report;
      Future<void> mount() async {
        final store = ScopedReportFieldsStore(
          database: config,
          storage: storage,
        );
        ReportFieldsController fields(ReportFieldsDefinition definition) =>
            ScopedReportFieldsController(
              definition: definition,
              owner: owner,
              store: store,
            );
        report = Get.put(
          StockAgeingController(
            cache: cache,
            fields: fields(stockAgeingFields()),
            view: fields(stockAgeingView),
            company: () => 'Company',
            baseUrl: () => 'https://one.example',
            run: ({Map<String, dynamic>? filters}) async {
              calls++;
              return Response(
                requestOptions: RequestOptions(path: '/'),
                data: {
                  'message': {
                    'columns': [
                      for (final column in columns)
                        if (includeAverageAge ||
                            column['fieldname'] != 'average_age')
                          column,
                    ],
                    'result': rows,
                    'custom_filters': {'range': '360, 720'},
                  },
                },
              );
            },
          ),
        );
        await tester.pumpWidget(
          const GetMaterialApp(home: StockAgeingScreen()),
        );
        await tester.pumpAndSettle();
      }

      final card = find
          .ancestor(of: find.text('Product A'), matching: find.byType(InkWell))
          .first;
      Finder cardText(String text) => find.descendant(
        of: card,
        matching: find.text(text, findRichText: true),
      );
      Finder bar(double height) => find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox &&
            widget.height == height &&
            widget.child is Row,
      );
      final cardAgeBar = find.descendant(of: card, matching: bar(6));
      final summary = find
          .ancestor(
            of: find.text('Age (0 - 90) · Range for this run: 0–360: 14'),
            matching: find.byType(Material),
          )
          .first;
      final summaryAgeBar = find.descendant(of: summary, matching: bar(10));
      final variantBadge = cardText('Variante De  Template A');
      final averageAge = cardText('Average Age  34');
      final bucket = cardText('Age (0 - 90)  3\nRange for this run: 0–360');
      final search = find.byType(TextField);

      Future<void> expectFullFooter() async {
        await driver.scrollToEnd();
        expect(find.text('End of list'), findsOneWidget);
        for (final total in [nosTotal, boxTotal, unknownTotal]) {
          expect(find.text(total), findsOneWidget);
        }
        driver.position.jumpTo(driver.position.minScrollExtent);
        await tester.pumpAndSettle();
      }

      await mount();
      await expectFullFooter();
      expect(variantBadge, findsOneWidget);
      expect(averageAge, findsOneWidget);
      expect(cardAgeBar, findsOneWidget);
      expect(summaryAgeBar, findsOneWidget);
      expect(bucket, findsNothing);
      await driver.openFields();
      expect((await driver.read('warehouse')).onChanged, isNull);
      final age = await driver.read('range1');
      expect((age.title as Semantics).child, isA<Text>());
      expect(((age.title as Semantics).child as Text).data, 'Age (0 - 90)');
      expect((age.subtitle as Text).data, 'Range for this run: 0–360');
      expect(age.value, isFalse);
      await driver.setVisible('range1', true);
      await driver.dismiss();
      expect(bucket, findsOneWidget);
      expect(averageAge, findsOneWidget);
      await driver.openFields();
      await driver.setVisible('range1', false);
      await driver.setVisible('variant_of', false);
      await driver.setVisible('average_age', false);
      await driver.dismiss();
      expect(bucket, findsNothing);
      expect(variantBadge, findsNothing);
      expect(averageAge, findsNothing);
      expect(cardAgeBar, findsOneWidget);
      expect(find.text('Product A'), findsOneWidget);
      expect(find.text('Description A'), findsOneWidget);
      expect(
        find.textContaining('Warehouse A', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Product A'));
      await tester.pumpAndSettle();
      expect(find.text('Template A'), findsOneWidget);
      void expectDetail(String label, String value) {
        final line = find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first;
        expect(
          find.descendant(of: line, matching: find.text(value)),
          findsOneWidget,
        );
      }

      expectDetail('Average Age', '34 days');
      expectDetail('Age (0 - 90)\nRange for this run: 0–360', '3');
      Get.back<void>();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('View').hitTestable().first);
      await tester.pumpAndSettle();
      final viewWrite = Completer<void>();
      config.beforeWrite = (_, _) => viewWrite.future;
      final viewProgress = find.descendant(
        of: find.byType(CheckboxMenuButton),
        matching: find.byType(CircularProgressIndicator),
      );
      expect(report.view.canEdit('ageBar'), isTrue);
      await tester.tap(find.byType(CheckboxMenuButton).hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(report.view.state.value.pendingKeys, contains('ageBar'));
      expect(find.text('Age bar').hitTestable(), findsOneWidget);
      expect(viewProgress, findsOneWidget);
      viewWrite.complete();
      await tester.pumpAndSettle();
      expect(viewProgress, findsNothing);
      await tester.tap(find.byTooltip('View').hitTestable().first);
      await tester.pumpAndSettle();
      expect(cardAgeBar, findsNothing);
      expect(summaryAgeBar, findsOneWidget);
      expect(calls, 1);
      await expectFullFooter();
      await tester.enterText(search, 'Product Box');
      await tester.pumpAndSettle();
      await driver.scrollToEnd();
      expect(find.text('End of list'), findsOneWidget);
      expect(find.text(boxTotal), findsOneWidget);
      expect(find.text(nosTotal), findsNothing);
      expect(find.text(unknownTotal), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await Get.delete<StockAgeingController>(force: true);
      await mount();
      expect(variantBadge, findsNothing);
      await driver.openFields();
      await driver.switchOwner(site: 'https://two.example', user: 'Buyer');
      expect((await driver.read('variant_of')).value, isTrue);
      await driver.switchOwner(site: 'https://one.example', user: 'Seller');
      expect((await driver.read('variant_of')).value, isTrue);
      await driver.switchOwner(site: 'https://one.example', user: 'Buyer');
      expect((await driver.read('variant_of')).value, isFalse);
      expect((await driver.read('average_age')).value, isFalse);
      includeAverageAge = false;
      await report.runReport();
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(CheckboxListTile, 'Average Age'),
        findsNothing,
      );
      await driver.reset();
      expect((await driver.read('variant_of')).value, isTrue);
      expect(config.values[fieldsKey], '{}');
      expect(config.values[viewKey], '{"ageBar":false}');
      await driver.dismiss();
      expect(variantBadge, findsOneWidget);
      expect(cardAgeBar, findsNothing);
      expect(summaryAgeBar, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await Get.delete<StockAgeingController>(force: true);
      includeAverageAge = true;
      cache.snapshots.clear();
      await mount();
      expect(variantBadge, findsOneWidget);
      expect(averageAge, findsOneWidget);
      expect(cardAgeBar, findsNothing);
      expect(summaryAgeBar, findsOneWidget);
    },
  );
}

void main() => registerStockAgeingFieldsContract();
