import 'dart:async';

import 'package:dio/dio.dart';
// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_search/bom_search_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_search/bom_search_screen.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';
import 'package:multimax/app/modules/manufacturing/reports/job_card_summary/job_card_summary_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/job_card_summary/job_card_summary_screen.dart';

import '../support/report_fields_test_kit.dart';

Finder _row(Object id) => find.byKey(ValueKey<Object>(id));

Finder _textIn(Finder parent, String text) =>
    find.descendant(of: parent, matching: find.text(text));

Finder _metricIn(Finder parent, String label) =>
    find.descendant(of: parent, matching: find.widgetWithText(StatCell, label));

Future<void> _expectCatalogue(
  WidgetTester tester,
  WidgetReportFieldsDriver driver,
  List<(String key, String section, String caption, bool selected, bool locked)>
  expected,
) async {
  await driver.openFields();
  final scroll = tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        ),
      )
      .position;
  final visits = <String, (String, String, String, bool, bool)>{};
  while (true) {
    for (final tile in tester.widgetList<CheckboxListTile>(
      find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(CheckboxListTile),
      ),
    )) {
      final key = (tile.key as ValueKey<String>).value;
      final title = tile.title as Semantics;
      final caption = (title.child as Text).data!;
      visits[key] = (
        key,
        title.properties.label!,
        caption,
        tile.value!,
        tile.onChanged == null,
      );
    }
    if (scroll.extentAfter < 1) break;
    scroll.jumpTo((scroll.pixels + 120).clamp(0.0, scroll.maxScrollExtent));
    await tester.pumpAndSettle();
  }
  expect(visits.values, [
    for (final (key, section, caption, selected, locked) in expected)
      (key, '$section, $caption', caption, selected, locked),
  ]);
  await driver.dismiss();
}

class _ReportApi extends ApiProvider {
  Map<String, Object?> message = const {};
  int requests = 0;
  int posRequests = 0;
  Object? failure;
  final warehouseReplies = <Future<List<String>>>[];
  int warehouseRequests = 0;

  Future<Response> _reply() async {
    requests++;
    if (failure case final error?) throw error;
    return Response(
      requestOptions: RequestOptions(
        path: '/api/method/frappe.desk.query_report.run',
      ),
      statusCode: 200,
      data: {'message': message},
    );
  }

  @override
  Future<Response> searchBom({
    String? item,
    String? bom,
    String? item1,
    String? item2,
    String? item3,
    String? item4,
    String? item5,
  }) => _reply();

  @override
  Future<Response> runBomStockWithCustomerCode({
    String? customer,
    List<String> customerCodes = const [],
    List<String> warehouses = const [],
    String? posUpload,
    bool showExplodedView = false,
    bool hideOutOfStock = false,
  }) => _reply();

  @override
  Future<List<String>> getPosUploadRefCodes(String posUpload) async {
    posRequests++;
    return ['C-01', 'C-MISSING'];
  }

  @override
  Future<List<String>> getWarehouseNames() {
    warehouseRequests++;
    return warehouseReplies.removeAt(0);
  }

  @override
  Future<Response> getJobCardSummary({
    required String fromDate,
    required String toDate,
    String? workOrder,
    String? productionItem,
    String? workstation,
  }) => _reply();
}

class _WorkOrders extends WorkOrderProvider {
  @override
  Future<List<WorkOrder>> fetchRecent({int limit = 20}) async => const [];
}

List<Map<String, String>> _columns(Map<String, String> labels) => [
  for (final entry in labels.entries)
    {'fieldname': entry.key, 'label': entry.value},
];

void _phone(WidgetTester tester, {double width = 420}) {
  tester.view.physicalSize = Size(width * 3, 2700);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _hide(
  WidgetTester tester,
  WidgetReportFieldsDriver driver,
  Map<String, String> labels,
) async {
  await driver.openFields();
  for (final entry in labels.entries) {
    expect((await driver.read(entry.key)).value, isTrue);
    expect(
      find.descendant(
        of: find.byKey(ValueKey(entry.key)),
        matching: find.text(entry.value),
      ),
      findsOneWidget,
    );
    await driver.setVisible(entry.key, false);
  }
  await driver.dismiss();
}

Future<void> _keepOffset(
  WidgetReportFieldsDriver driver,
  Object id,
  Iterable<String> keys,
) async {
  await driver.positionOccurrenceUnderHeader(id);
  await driver.openFields();
  for (final key in keys) {
    await driver.setVisible(key, false);
  }
  await driver.dismiss();
  expect(driver.readPaintedOffset(id), closeTo(-5, 1));
  await driver.openFields();
  await driver.reset();
  await driver.dismiss();
  expect(driver.readPaintedOffset(id), closeTo(-5, 1));
}

void registerManufacturingReportFieldsTests() {
  group('Manufacturing report Fields', () {
    late _ReportApi api;
    late ReportFieldsTestOwner owner;
    late ReportFieldsTestConfig config;

    setUpAll(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => r'C:\temp\test_cookies',
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.ddmco.multimax/scan'),
        (call) async => null,
      );
    });

    setUp(() {
      Get.testMode = true;
      api = _ReportApi();
      owner = ReportFieldsTestOwner()
        ..change('https://reports.example', 'reader');
      config = ReportFieldsTestConfig();
      final storage = ReportFieldsTestStorage();
      Get.put<StorageService>(storage);
      Get.put<ReportOwnerSource>(owner);
      Get.put<ReportFieldsStore>(
        ScopedReportFieldsStore(database: config, storage: storage),
      );
      Get.put<ApiProvider>(api);
      Get.put(PermissionService());
      Get.put(AuthenticationController());
    });
    tearDown(Get.reset);

    testWidgets('BOM Search protects distinguishing document types', (
      tester,
    ) async {
      _phone(tester);
      Get.put(DataWedgeService());
      Get.put(ScanService());
      final controller = Get.put(BomSearchController());
      await tester.pumpWidget(
        GetMaterialApp(
          home: const BomSearchScreen(),
          getPages: [
            GetPage(
              name: AppRoutes.BOM_FORM,
              page: () => const Scaffold(body: Text('BOM destination')),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final driver = WidgetReportFieldsDriver(tester, owner);
      expect(find.text('Set Item Code 1 and tap Run Report'), findsOneWidget);
      final header = _columns(const {'parent': 'BOM', 'doctype': 'Type'});
      final documents = <(String?, String)>[
        ('BOM-ordinary', 'BOM'),
        ('BOM-shared', 'BOM'),
        ('BOM-shared', 'Product Bundle'),
        ('KIT-01', 'Kit Definition'),
        (null, 'BOM'),
        for (var i = 5; i < 28; i++) ('BOM-$i', 'BOM'),
      ];
      api.message = {
        'columns': header,
        'result': [
          for (final (parent, type) in documents) [parent, type],
        ],
      };
      controller.item1Controller.text = 'ITEM-1';
      await Future.wait([controller.runReport(), controller.runReport()]);
      await tester.pumpAndSettle();
      expect(api.requests, 1);
      for (final (i, (parent, type)) in documents.take(5).indexed) {
        final row = _row((type, parent, i));
        expect(_textIn(row, parent ?? '—'), findsOneWidget);
        expect(_textIn(row, type), findsOneWidget);
      }
      await _keepOffset(driver, ('BOM', 'BOM-8', 8), ['doctype']);
      driver.position.jumpTo(0);
      await tester.pumpAndSettle();
      await _hide(tester, driver, const {'doctype': 'Type'});
      for (final (i, (parent, type)) in documents.take(5).indexed) {
        final row = _row((type, parent, i));
        expect(_textIn(row, parent ?? '—'), findsOneWidget);
        expect(_textIn(row, type), i == 0 ? findsNothing : findsOneWidget);
        if (parent == null) continue;
        final title = _textIn(row, parent);
        await tester.ensureVisible(title);
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(find.text('BOM destination'), findsOneWidget);
        expect(Get.arguments, {'name': parent});
        Get.back<void>();
        await tester.pumpAndSettle();
      }
      expect(api.requests, 1);
      driver.position.jumpTo(0);
      await tester.pumpAndSettle();
      final rendered = <Object>{};
      while (true) {
        final visible =
            [
              for (final (i, (parent, type)) in documents.indexed)
                if (_textIn(
                  _row((type, parent, i)),
                  parent ?? '—',
                ).hitTestable().evaluate().isNotEmpty)
                  (type, parent, i),
            ]..sort(
              (a, b) => tester
                  .getTopLeft(_row(a))
                  .dy
                  .compareTo(tester.getTopLeft(_row(b)).dy),
            );
        rendered.addAll(visible);
        if (driver.position.extentAfter < 1) break;
        final scroll = driver.position;
        scroll.jumpTo((scroll.pixels + 220).clamp(0.0, scroll.maxScrollExtent));
        await tester.pumpAndSettle();
      }
      expect(rendered.toList(), [
        for (final (i, (parent, type)) in documents.indexed) (type, parent, i),
      ]);
      expect(find.text('End of list · 28 results'), findsOneWidget);
      await driver.openFields();
      await driver.reset();
      await driver.dismiss();
      expect(api.requests, 1);
      for (final invalidResult in [
        <String, Object?>{},
        {'result': 'invalid'},
      ]) {
        api.message = {
          'columns': _columns(const {'parent': 'BOM', 'doctype': 'Malformed'}),
          ...invalidResult,
        };
        await controller.runReport();
        await tester.pumpAndSettle();
        expect(
          find.text('Could not run BOM Search. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(controller.hasResult.value, isFalse);
        expect(
          controller.fields.state.value.definition.label('doctype'),
          'Type',
        );
      }
      api.message = {'columns': header, 'result': const []};
      await controller.runReport();
      await tester.pumpAndSettle();
      expect(
        find.text('No BOMs found for the selected items.'),
        findsOneWidget,
      );
      expect(find.textContaining('End of list'), findsNothing);
    });

    testWidgets(
      'BOM Stock protects shortage status, lines and filtered totals',
      (tester) async {
        _phone(tester);
        final driver = WidgetReportFieldsDriver(tester, owner);
        final controller = Get.put(BomStockCustomerCodeController());
        const labels = {
          'sl_no': '#',
          'item_group': 'Item Group',
          'in_stock_qty': 'In Stock Qty',
          'required_qty': 'Required Qty',
          'running_total': 'Running Total',
          'shortage_qty': 'Parts Short',
          'enough_parts_to_build': 'Enough Parts to Build',
        };
        const first = {
          'sl_no': 1,
          'item_code': 'I-1',
          'item_name': 'First item',
          'item_group': 'Hardware',
          'customer_code': 'C-01',
          'bom': 'B-1',
          'in_stock_qty': -2,
          'required_qty': 12,
          'running_total': -5,
          'shortage_qty': 14,
          'enough_parts_to_build': 0,
        };
        const second = {
          'sl_no': 2,
          'item_code': 'I-2',
          'item_name': 'Second item',
          'customer_code': 'C-01',
          'in_stock_qty': 0,
          'required_qty': 0,
          'running_total': 0,
          'shortage_qty': 0,
        };
        api.message = {
          'columns': _columns(const {
            'sl_no': '#',
            'image_tag': 'Image',
            'customer': 'Customer',
            'customer_code': 'Customer Code',
            'item_code': 'Part Code',
            'item_name': 'Part Name',
            'item_group': 'Item Group',
            'parent_item_group': 'Parent Item Group',
            'bom': 'BOM',
            'in_stock_qty': 'In Stock Qty',
            'required_qty': 'Required Qty',
            'running_total': 'Running Total',
            'shortage_qty': 'Parts Short',
            'enough_parts_to_build': 'Enough Parts to Build',
          }),
          'result': const [
            first,
            second,
            ['Total', null, null, null, null, null, 999],
          ],
        };

        await tester.pumpWidget(
          const GetMaterialApp(home: BomStockCustomerCodeScreen()),
        );
        await tester.pumpAndSettle();
        await controller.runReport();
        await tester.pumpAndSettle();
        await _expectCatalogue(tester, driver, const [
          ('item_code', 'Flat cards and POS lines', 'Part Code', true, true),
          ('item_name', 'Flat cards and POS lines', 'Part Name', true, true),
          (
            'customer_code',
            'Flat cards and POS lines',
            'Customer Code',
            true,
            true,
          ),
          ('item_group', 'Flat cards and POS lines', 'Item Group', true, false),
          (
            'in_stock_qty',
            'Flat cards and POS lines',
            'In Stock Qty',
            true,
            false,
          ),
          (
            'required_qty',
            'Flat cards and POS lines',
            'Required Qty',
            true,
            false,
          ),
          ('bom', 'Flat cards', 'BOM', true, true),
          ('sl_no', 'Flat cards', '#', true, false),
          ('shortage_qty', 'Flat cards', 'Parts Short', true, false),
          (
            'enough_parts_to_build',
            'Flat cards',
            'Enough Parts to Build',
            true,
            false,
          ),
          ('running_total', 'Expanded POS lines', 'Running Total', true, false),
        ]);
        final name = find.text('First item');
        final withGroup = find.text('I-1 · Hardware');
        final code = find.text('I-1');
        expect(
          tester.widget<Text>(withGroup).semanticsLabel,
          'Part Code I-1, Item Group Hardware',
        );
        expect(
          tester.widget<Text>(name).semanticsLabel,
          'Part Name First item',
        );
        expect(
          tester.widget<Text>(find.text('I-2')).semanticsLabel,
          'Part Code I-2',
        );
        expect(find.text('Enough Parts to Build'), findsOneWidget);
        await driver.openFields();
        final shortage = await driver.read('shortage_qty');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('shortage_qty')),
            matching: find.text('Parts Short'),
          ),
          findsOneWidget,
        );
        expect(
          (shortage.subtitle as Text).data,
          'POS lines and totals always show this field.',
        );
        await driver.dismiss();
        await _hide(tester, driver, labels);
        final flatFirst = _row(('I-1', 'B-1', 0));
        final flatSecond = _row(('I-2', null, 1));
        expect(find.byType(BomStockTile), findsNWidgets(2));
        for (final (row, texts) in [
          (flatFirst, ['First item', 'I-1', 'C-01', 'B-1', 'Short 14']),
          (flatSecond, ['Second item', 'I-2', 'C-01', 'Covered']),
        ]) {
          for (final text in texts) {
            expect(_textIn(row, text), findsOneWidget);
          }
        }
        expect(
          tester.widget<Text>(name).semanticsLabel,
          'Part Name First item',
        );
        expect(tester.widget<Text>(code).semanticsLabel, 'Part Code I-1');
        expect(withGroup, findsNothing);
        expect(find.text('Short 14'), findsOneWidget);
        final footer = find.byType(BomStockTotalsFooter);
        for (final (key, label, value) in const [
          ('in_stock_qty', 'In Stock Qty', '-2'),
          ('required_qty', 'Required Qty', '12'),
          ('shortage_qty', 'Parts Short', '14'),
          ('enough_parts_to_build', 'Enough Parts to Build', '0'),
        ]) {
          await driver.openFields();
          await driver.setVisible(key, true);
          await driver.dismiss();
          expect(_textIn(_metricIn(flatFirst, label), value), findsOneWidget);
          expect(
            find.descendant(of: flatFirst, matching: find.byType(StatCell)),
            findsOneWidget,
          );
          expect(_textIn(footer, '-2'), findsOneWidget);
          await driver.openFields();
          await driver.setVisible(key, false);
          await driver.dismiss();
          expect(_metricIn(flatFirst, label), findsNothing);
        }

        await controller.onPosUploadSelected('POS-1');
        await tester.pumpAndSettle();
        expect(find.textContaining('C-MISSING'), findsOneWidget);
        expect(find.byType(BomStockLineRow), findsNothing);
        expect(find.text('Short 14'), findsOneWidget);
        void expectPosTotals() {
          for (final (caption, value) in const [
            ('In Stock Qty', '-2'),
            ('Required Qty', '12'),
            ('Parts Short', '14'),
          ]) {
            final cell = find
                .ancestor(
                  of: _textIn(footer, caption),
                  matching: find.byType(Column),
                )
                .first;
            expect(_textIn(cell, value), findsOneWidget);
          }
        }

        expectPosTotals();
        await tester.tap(find.text('C-01'));
        await tester.pumpAndSettle();
        final lines = find.byType(BomStockLineRow);
        expect(lines, findsNWidgets(2));
        expect(
          tester
              .widget<Text>(find.descendant(of: lines, matching: name))
              .semanticsLabel,
          'Part Name First item',
        );
        expect(
          tester
              .widget<Text>(find.descendant(of: lines, matching: code))
              .semanticsLabel,
          'Part Code I-1',
        );
        final lineFirst = _row(('C-01', 'I-1', 'B-1', 0));
        final lineSecond = _row(('C-01', 'I-2', null, 1));
        for (final (line, itemName, itemCode, shortage) in [
          (lineFirst, 'First item', 'I-1', '14'),
          (lineSecond, 'Second item', 'I-2', '0'),
        ]) {
          expect(_textIn(line, itemName), findsOneWidget);
          expect(_textIn(line, itemCode), findsOneWidget);
          expect(
            _textIn(_metricIn(line, 'Parts Short'), shortage),
            findsOneWidget,
          );
        }
        for (final (key, caption, value) in const [
          ('running_total', 'Running Total', '-5'),
          ('in_stock_qty', 'In Stock Qty', '-2'),
          ('required_qty', 'Required Qty', '12'),
        ]) {
          expect(_metricIn(lines, caption), findsNothing);
          await driver.openFields();
          await driver.setVisible(key, true);
          await driver.dismiss();
          expect(_textIn(_metricIn(lineFirst, caption), value), findsOneWidget);
          expect(_textIn(_metricIn(lineSecond, caption), '0'), findsOneWidget);
          expect(
            find.descendant(of: lineFirst, matching: find.byType(StatCell)),
            findsNWidgets(2),
          );
          expectPosTotals();
          await driver.openFields();
          await driver.setVisible(key, false);
          await driver.dismiss();
          expect(_metricIn(lines, caption), findsNothing);
          expect(
            _textIn(_metricIn(lineFirst, 'Parts Short'), '14'),
            findsOneWidget,
          );
          expectPosTotals();
        }
        expect(find.text('End of list'), findsOneWidget);
        await tester.tap(find.text('In Stock'));
        await tester.pumpAndSettle();
        expect(find.text('No items match this filter'), findsOneWidget);
        expect(
          find.descendant(of: footer, matching: find.text('0')),
          findsNWidgets(3),
        );
        expect(api.requests, 2);
        expect(api.posRequests, 1);

        const olderLabels = {
          'item_code': 'Item',
          'item_name': 'Item Name',
          'customer_code': 'Customer Code',
          'required_qty': 'Required Qty',
          'in_stock_qty': 'In Stock Qty',
        };
        const olderRow = {
          'item_code': 'I-3',
          'item_name': 'Older script',
          'customer_code': 'C-01',
          'required_qty': 6,
          'in_stock_qty': 0,
        };
        api.message = {
          'columns': _columns(olderLabels),
          'result': [olderRow],
        };
        controller.setRowFilter('ALL');
        await controller.runReport();
        await tester.pumpAndSettle();
        expect(find.text('Covered'), findsNothing);
        expect(
          find.descendant(of: footer, matching: find.text('—')),
          findsOneWidget,
        );
        await tester.tap(find.text('Shortage').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('No items match this filter'), findsOneWidget);
        expect(
          find.descendant(of: footer, matching: find.text('—')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('0')),
          findsNWidgets(2),
        );
        api.message = {
          'columns': _columns({...olderLabels, 'shortage_qty': 'Parts Short'}),
          'result': [
            {...olderRow, 'shortage_qty': 0},
          ],
        };
        await controller.runReport();
        await tester.pumpAndSettle();
        expect(find.text('No items match this filter'), findsOneWidget);
        await driver.scrollToEnd();
        final end = find.text('End of list');
        expect(end, findsOneWidget);
        expect(
          tester.getBottomLeft(end).dy,
          lessThan(tester.getTopLeft(footer).dy),
        );
        expect(
          find.descendant(of: footer, matching: find.text('—')),
          findsNothing,
        );
        expect(
          find.descendant(of: footer, matching: find.text('0')),
          findsNWidgets(3),
        );
      },
    );

    testWidgets('BOM Stock warehouse picker ignores the previous site lookup', (
      tester,
    ) async {
      _phone(tester);
      final a = Completer<List<String>>();
      final b = Completer<List<String>>();
      api.warehouseReplies.addAll([a.future, b.future]);
      final controller = Get.put(BomStockCustomerCodeController());
      await tester.pumpWidget(
        const GetMaterialApp(home: BomStockCustomerCodeScreen()),
      );
      await tester.pumpAndSettle();
      final filter = find.byTooltip('Filters');
      final add = find.text('Add warehouse');
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(api.warehouseRequests, 1);
      Navigator.of(tester.element(add)).pop();
      await tester.pumpAndSettle();

      owner.change('https://second.example', 'reader');
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(api.warehouseRequests, 2);
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final picker = find.byType(WarehousePickerSheet);
      expect(picker, findsOneWidget);
      a.complete(['Old warehouse']);
      await tester.pump();
      expect(controller.isLoadingWarehouses.value, isTrue);
      expect(controller.warehouseOptions, isEmpty);
      expect(find.text('Old warehouse'), findsNothing);
      b.complete(['Current warehouse']);
      await tester.pumpAndSettle();
      expect(controller.warehouseOptions, ['Current warehouse']);
      expect(controller.isLoadingWarehouses.value, isFalse);
      expect(find.text('Current warehouse'), findsOneWidget);
      expect(find.text('Old warehouse'), findsNothing);
      Navigator.of(tester.element(picker)).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(add)).pop();
      await tester.pumpAndSettle();
    });

    for (final jobCards in [false, true]) {
      testWidgets('${jobCards ? 'Job Card Summary' : 'BOM Stock'} restores the '
          'exact partly covered row and drops results on owner change', (
        tester,
      ) async {
        _phone(tester);
        final driver = WidgetReportFieldsDriver(tester, owner);
        if (jobCards) {
          api.message = {
            'columns': _columns(const {
              'name': 'Id',
              'operation': 'Operation',
              'total_completed_qty': 'Completed Qty',
            }),
            'result': [
              for (var i = 0; i < 22; i++) ['JC-$i', 'Cut', 1],
            ],
          };
          Get.put<WorkOrderProvider>(_WorkOrders());
          Get.put(JobCardSummaryController());
          await tester.pumpWidget(
            const GetMaterialApp(home: JobCardSummaryScreen()),
          );
        } else {
          api.message = {
            'columns': _columns(const {
              'item_code': 'Item',
              'item_name': 'Item Name',
              'item_group': 'Item Group',
              'in_stock_qty': 'In Stock Qty',
              'customer_code': 'Customer Code',
              'running_total': 'Running Total',
            }),
            'result': [
              for (var i = 0; i < 22; i++)
                ['I-$i', 'Item $i', 'Parts', 1, 'C-01', 2],
            ],
          };
          final controller = Get.put(BomStockCustomerCodeController());
          await tester.pumpWidget(
            const GetMaterialApp(home: BomStockCustomerCodeScreen()),
          );
          await tester.pumpAndSettle();
          await controller.runReport();
        }
        await tester.pumpAndSettle();
        final id = jobCards ? ('JC-6', 6) : ('I-6', null, 6);
        final identity = jobCards ? 'JC-6' : 'Item 6';
        await _keepOffset(
          driver,
          id,
          jobCards ? ['operation'] : ['in_stock_qty'],
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey<Object>(id)),
            matching: find.text(identity),
          ),
          findsOneWidget,
        );
        final groupedId = ('C-01', 'I-6', null, 6);
        if (!jobCards) {
          final controller = Get.find<BomStockCustomerCodeController>();
          await controller.onPosUploadSelected('POS-1');
          await tester.pumpAndSettle();
          driver.position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.tap(_textIn(_row(('code', 'C-01')), 'C-01'));
          await tester.pumpAndSettle();
          await _keepOffset(driver, groupedId, ['running_total']);
          expect(_textIn(_row(groupedId), 'Item 6'), findsOneWidget);
        }
        await driver.switchOwner(site: 'https://other.example', user: 'reader');
        expect(_row(jobCards ? id : groupedId), findsNothing);
        expect(find.textContaining('End of list'), findsNothing);
        expect(find.byType(BomStockTotalsFooter), findsNothing);
        expect(api.requests, jobCards ? 1 : 2);
      });
    }

    for (final (report, key, detail, identity) in const [
      ('bom_search', 'doctype', 'BOM', 'BOM-1'),
      ('bom_stock_customer_code', 'item_group', 'I-1 · Hardware', 'Item one'),
      ('job_card_summary', 'operation', 'Seal', 'JC-1'),
    ]) {
      testWidgets('$report cold-restores and resets only its scoped Fields', (
        tester,
      ) async {
        _phone(tester);
        const siteA = 'https://reports.example';
        const siteB = 'https://reports.example/Other';
        const userX = 'reader';
        const userY = 'reader2';
        final driver = WidgetReportFieldsDriver(tester, owner);
        final storage = Get.find<StorageService>();

        String configKey(String reportId, String site, String user) =>
            '${reportId}_fields::${Uri.encodeComponent(site)}::$user';
        final target = configKey(report, siteA, userX);
        final controls = {
          configKey(report, siteA, userY): '{"other_user_field":false}',
          configKey(report, siteB, userX): '{"other_site_field":true}',
          configKey('stock_balance', siteA, userX): '{"in_qty":false}',
        };
        config.values.addAll(controls);

        Future<void> mount(String site, String user) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await Get.delete<BomSearchController>();
          await Get.delete<BomStockCustomerCodeController>();
          await Get.delete<JobCardSummaryController>();
          await Get.delete<ReportFieldsStore>();
          owner.change(site, user);
          Get.put<ReportFieldsStore>(
            ScopedReportFieldsStore(database: config, storage: storage),
          );

          switch (report) {
            case 'bom_search':
              api.message = {
                'columns': _columns(const {'parent': 'BOM', 'doctype': 'Type'}),
                'result': const [
                  ['BOM-1', 'BOM'],
                ],
              };
              Get.put(DataWedgeService());
              Get.put(ScanService());
              final controller = Get.put(BomSearchController());
              await tester.pumpWidget(
                const GetMaterialApp(home: BomSearchScreen()),
              );
              controller.item1Controller.text = 'ITEM-1';
              await controller.runReport();
            case 'bom_stock_customer_code':
              api.message = {
                'columns': _columns(const {
                  'item_code': 'Item',
                  'item_name': 'Item Name',
                  'item_group': 'Item Group',
                }),
                'result': const [
                  ['I-1', 'Item one', 'Hardware'],
                ],
              };
              final controller = Get.put(BomStockCustomerCodeController());
              await tester.pumpWidget(
                const GetMaterialApp(home: BomStockCustomerCodeScreen()),
              );
              await controller.runReport();
            case 'job_card_summary':
              api.message = {
                'columns': _columns(const {
                  'name': 'Id',
                  'operation': 'Operation',
                }),
                'result': const [
                  ['JC-1', 'Seal'],
                ],
              };
              Get.put<WorkOrderProvider>(_WorkOrders());
              Get.put(JobCardSummaryController());
              await tester.pumpWidget(
                const GetMaterialApp(home: JobCardSummaryScreen()),
              );
          }
          await tester.pumpAndSettle();
          expect(find.text(identity).hitTestable(), findsOneWidget);
        }

        void expectDetail(bool visible) {
          expect(
            find.text(detail).hitTestable(),
            visible ? findsOneWidget : findsNothing,
          );
        }

        await mount(siteA, userX);
        expectDetail(true);
        await driver.openFields();
        await driver.setVisible(key, false);
        await driver.dismiss();
        expectDetail(false);
        expect(config.values, {...controls, target: '{"$key":false}'});
        await mount(siteA, userX);
        expectDetail(false);
        await mount(siteA, userY);
        expectDetail(true);
        await mount(siteB, userX);
        expectDetail(true);
        await mount(siteA, userX);
        expectDetail(false);
        await driver.openFields();
        await driver.reset();
        await driver.dismiss();
        expectDetail(true);
        expect(config.values, {...controls, target: '{}'});
        await mount(siteA, userX);
        expectDetail(true);
        expect(config.values, {...controls, target: '{}'});
        expect(api.requests, 6);
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('Job Card Summary paints raw On Hold and unknown status '
          'with readable ink (${brightness.name})', (tester) async {
        _phone(tester);
        Get.put<WorkOrderProvider>(_WorkOrders());
        Get.put(JobCardSummaryController());
        api.message = {
          'columns': _columns(const {'name': 'Id', 'status': 'Status'}),
          'result': const [
            ['JC-1', 'On Hold'],
            ['JC-2', 'Waiting for material'],
          ],
        };
        await tester.pumpWidget(
          GetMaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const JobCardSummaryScreen(),
          ),
        );
        await tester.pumpAndSettle();
        final dark = brightness == Brightness.dark;
        for (final (label, ink, tint) in [
          (
            'On Hold',
            dark ? AppColors.orange300 : AppColors.orange700,
            AppColors.orange500,
          ),
          (
            'Waiting for material',
            dark ? AppColors.gray300 : AppColors.gray700,
            AppColors.gray500,
          ),
        ]) {
          final text = find.text(label);
          expect(tester.widget<Text>(text).style?.color, ink);
          expect(
            find.ancestor(
              of: text,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration as BoxDecoration).color ==
                        tint.withValues(alpha: 0.13),
              ),
            ),
            findsOneWidget,
          );
        }
      });
    }

    testWidgets('Job Card Fields keep the chart, dates and undated quantity', (
      tester,
    ) async {
      _phone(tester, width: 360);
      Get.put<WorkOrderProvider>(_WorkOrders());
      const labels = {
        'work_order': 'Work Order',
        'operation': 'Operation',
        'workstation': 'Workstation',
        'total_completed_qty': 'Finished Units',
        'total_time_in_mins': 'Time Required (In Mins)',
      };
      api.message = {
        'columns': _columns(const {
          'name': 'Id',
          'posting_date': 'Posting Date',
          'status': 'Auftragsstatus',
          'production_item': 'Produktions-Artikel',
          'item_name': 'Artikelname',
          ...labels,
          'from_time': 'From Time',
          'to_time': 'To Time',
        }),
        'add_total_row': true,
        'result': const [
          [
            'JC-1',
            '2026-11-24',
            'Completed',
            'I-1',
            'First item',
            'WO-1234-12345',
            'Cut',
            'Station 1',
            5,
            14.25,
            '08:00',
            '08:15',
          ],
          [
            'JC-2',
            '2026-11-25',
            'Open',
            'I-2',
            'Second item',
            'WO-2',
            'Seal',
            'Station 2',
            7,
            null,
          ],
          [
            'JC-3',
            null,
            'Open',
            'I-3',
            'Undated item',
            null,
            null,
            null,
            11,
            null,
          ],
          [
            'Summe',
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            23,
            14.25,
            null,
            null,
          ],
        ],
      };
      final controller = Get.put(JobCardSummaryController());
      await tester.pumpWidget(
        GetMaterialApp(
          home: const JobCardSummaryScreen(),
          getPages: [
            GetPage(
              name: AppRoutes.JOB_CARD_FORM,
              page: () => const Scaffold(body: Text('Job Card destination')),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final driver = WidgetReportFieldsDriver(tester, owner);
      expect(controller.dailyProductionData.map((day) => day.completed), [
        5,
        7,
      ]);
      expect(controller.totalCompletedQty, 23);
      final item = find.text('I-1 · First item');
      final status = find.text('Completed');
      final workOrder = find.text('WO-1234-12345');
      final date = find.text('2026-11-24');
      expect(
        tester.widget<Text>(item).semanticsLabel,
        'Produktions-Artikel I-1, Artikelname First item',
      );
      expect(
        tester.widget<Text>(status).semanticsLabel,
        'Auftragsstatus Completed',
      );
      expect(tester.getTopRight(date).dx, tester.getTopRight(item).dx);
      expect(
        tester.getSize(workOrder).height,
        tester.getSize(find.text('WO-2')).height,
      );
      expect(find.text('Cut · Station 1'), findsOneWidget);
      expect(find.text('14.25 min'), findsOneWidget);
      expect(find.text('Finished Units'), findsWidgets);
      await _expectCatalogue(tester, driver, const [
        ('name', 'Job card', 'Id', true, true),
        ('posting_date', 'Job card', 'Posting Date', true, true),
        ('status', 'Job card', 'Auftragsstatus', true, true),
        ('production_item', 'Job card', 'Produktions-Artikel', true, true),
        ('item_name', 'Job card', 'Artikelname', true, true),
        ('work_order', 'Job card', 'Work Order', true, false),
        ('operation', 'Job card', 'Operation', true, false),
        ('workstation', 'Job card', 'Workstation', true, false),
        ('total_completed_qty', 'Job card', 'Finished Units', true, false),
        (
          'total_time_in_mins',
          'Job card',
          'Time Required (In Mins)',
          true,
          false,
        ),
      ]);

      await _hide(tester, driver, labels);
      expect(workOrder, findsNothing);
      expect(find.text('Cut · Station 1'), findsNothing);
      expect(find.text('JC-1'), findsOneWidget);
      expect(find.text('2026-11-24'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Completed Qty by Day'), findsOneWidget);
      expect(find.text('Finished Units'), findsOneWidget);
      expect(find.text('Time Required (In Mins)'), findsNothing);
      final chart = find.descendant(
        of: find.byType(AnimatedCrossFade),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
      );
      expect(chart, findsOneWidget);
      expect(chart, paintsExactlyCountTimes(#drawRRect, 2));
      final bounds = tester.getRect(chart);
      final messenger = ScaffoldMessenger.of(
        tester.element(find.byType(JobCardSummaryScreen)),
      );
      for (final (x, date, completed) in const [
        (0.12, '2026-11-24', 5),
        (0.62, '2026-11-25', 7),
      ]) {
        await tester.tapAt(bounds.topLeft + Offset(bounds.width * x, 90));
        await tester.pumpAndSettle();
        expect(
          find.text('$date  •  Finished Units: $completed'),
          findsOneWidget,
        );
        messenger.hideCurrentSnackBar();
        await tester.pumpAndSettle();
      }
      for (final (id, identity) in const [
        (('JC-1', 0), 'I-1 · First item'),
        (('JC-2', 1), 'I-2 · Second item'),
        (('JC-3', 2), 'I-3 · Undated item'),
      ]) {
        await driver.scrollToOccurrence(id);
        expect(_textIn(_row(id), identity), findsOneWidget);
      }
      await driver.scrollToEnd();
      final undated = _textIn(_row(('JC-3', 2)), 'JC-3');
      expect(undated, findsOneWidget);
      expect(find.text('Summe'), findsNothing);
      expect(find.text('End of list · Finished Units 23'), findsOneWidget);
      expect(api.requests, 1);
      await tester.tap(undated.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Job Card destination'), findsOneWidget);
      expect(Get.arguments, {'name': 'JC-3'});
    });

    testWidgets(
      'Job Card totals exclude the translated summary and keep small quantities',
      (tester) async {
        _phone(tester);
        Get.put<WorkOrderProvider>(_WorkOrders());
        final labels = const {
          'work_order': 'Work Order',
          'operation': 'Operation',
          'workstation': 'Workstation',
          'total_completed_qty': 'Fertiggestellte Menge',
          'total_time_in_mins': 'Time Required (In Mins)',
        };
        final columns = _columns({
          'name': 'Id',
          'posting_date': 'Posting Date',
          ...labels,
        });
        api.message = {
          'columns': columns,
          'add_total_row': 1,
          'result': const [
            {
              'name': 'JC-1',
              'posting_date': '2026-11-24',
              'total_completed_qty': 5,
            },
            {'name': 'Summe', 'total_completed_qty': 7},
            ['Summe', '', '', '', '', 12, ''],
          ],
        };
        final controller = Get.put(JobCardSummaryController());
        await tester.pumpWidget(
          const GetMaterialApp(home: JobCardSummaryScreen()),
        );
        await tester.pumpAndSettle();
        final driver = WidgetReportFieldsDriver(tester, owner);
        Future<void> expectRetainedCards() async {
          expect(_textIn(_row(('JC-1', 0)), 'JC-1'), findsOneWidget);
          expect(_textIn(_row(('Summe', 1)), 'Summe'), findsOneWidget);
          expect(find.text('Summe'), findsOneWidget);
          await driver.scrollToEnd();
          expect(
            find.text('End of list · Fertiggestellte Menge 12'),
            findsOneWidget,
          );
        }

        await expectRetainedCards();
        await _hide(tester, driver, labels);
        await expectRetainedCards();

        api.message = {
          'columns': columns,
          'add_total_row': false,
          'result': const [
            ['Total', null, null, null, null, 0.004, null],
          ],
        };
        await controller.runReport();
        await tester.pumpAndSettle();
        expect(find.text('Total'), findsOneWidget);
        await driver.scrollToEnd();
        expect(
          find.text('End of list · Fertiggestellte Menge 0.004'),
          findsOneWidget,
        );
        expect(
          find.text('End of list · Fertiggestellte Menge 0.00'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Job Card prepared failures, unrun and empty responses stay distinct',
      (tester) async {
        _phone(tester);
        Get.put<WorkOrderProvider>(_WorkOrders());
        api.message = const {
          'prepared_report': true,
          'doc': {'status': 'Error'},
          'error': 'Job card calculation failed.',
        };
        final controller = Get.put(JobCardSummaryController());
        await tester.pumpWidget(
          const GetMaterialApp(home: JobCardSummaryScreen()),
        );
        await tester.pumpAndSettle();
        final retry = find.text('Retry');
        final empty = find.textContaining('No Job Cards found');
        expect(find.text('Job card calculation failed.'), findsOneWidget);
        expect(retry, findsOneWidget);
        expect(empty, findsNothing);
        expect(controller.hasResult.value, isFalse);

        api.message = const {'prepared_report': true, 'doc': null};
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'The prepared Job Card Summary is not available yet. Try again.',
          ),
          findsOneWidget,
        );
        expect(retry, findsOneWidget);
        expect(empty, findsNothing);

        api.message = const {
          'result': {'invalid': true},
        };
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(
          find.text('Could not run Job Card Summary. Try again.'),
          findsOneWidget,
        );
        expect(retry, findsOneWidget);
        expect(empty, findsNothing);

        api.message = const {
          'result': [
            {'name': 'JC-1', 'total_completed_qty': 3},
          ],
        };
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(find.text('JC-1'), findsOneWidget);
        expect(retry, findsNothing);
        final loadedRequests = api.requests;

        final clear = find.text('Reset filters');
        await tester.ensureVisible(clear);
        await tester.pumpAndSettle();
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(find.text('JC-1'), findsNothing);
        expect(
          find.text('Set a date range and tap Run Report.'),
          findsOneWidget,
        );
        expect(find.text('Set Filters'), findsOneWidget);
        expect(empty, findsNothing);
        expect(api.requests, loadedRequests);

        api.message = const {'result': []};
        await controller.runReport();
        await tester.pumpAndSettle();
        expect(empty, findsOneWidget);
        expect(find.text('Set Filters'), findsOneWidget);
        expect(retry, findsNothing);
      },
    );
  });
}
