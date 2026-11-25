import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_fields.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../support/report_fields_test_kit.dart';

void registerItemVariantDetailsFieldsContract() {
  testWidgets('Item Variant Details leaf switches preserve v16 subtotals', (
    tester,
  ) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    await tester.binding.setSurfaceSize(const Size(520, 1450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = Get.put<ApiProvider>(_FakeApi()) as _FakeApi;
    Get.put(AuthenticationController());
    final report = Get.put(ItemVariantDetailsController());
    api.report.complete((
      columns: [
        {'fieldname': 'variant_name', 'label': 'Item'},
        {'fieldname': 'current_stock', 'label': 'Current Stock'},
        {'fieldname': 'stock_uom', 'label': 'Stock UOM'},
        {'fieldname': 'in_production', 'label': 'In Production'},
        {'fieldname': 'open_orders', 'label': 'Open Sales Orders'},
      ],
      rows: [
        {
          'variant_name': 'Template A',
          'indent': 0,
          'stock_uom': 'Nos',
          'current_stock': 6,
          'in_production': 0,
          'open_orders': 3,
        },
        {
          'variant_name': 'Variant A',
          'indent': 1,
          'stock_uom': 'Nos',
          'current_stock': 6,
          'in_production': 0,
          'open_orders': 3,
        },
        {'variant_name': 'Mixed Template', 'indent': 0, 'current_stock': null},
        {
          'variant_name': 'Variant B',
          'indent': 1,
          'stock_uom': 'Nos',
          'current_stock': 0,
          'in_production': 0,
          'open_orders': 0,
        },
        {
          'variant_name': 'Variant C',
          'indent': 1,
          'stock_uom': 'Box',
          'current_stock': 5,
          'in_production': 2,
          'open_orders': 1,
        },
      ],
    ));
    report.filterControllers['item']!.text = 'Template A';
    await tester.pumpWidget(
      const GetMaterialApp(home: ItemVariantDetailsScreen()),
    );
    await report.runReport();
    await tester.pumpAndSettle();
    final driver = WidgetReportFieldsDriver(tester, ReportFieldsTestOwner());
    final leaf = find.ancestor(
      of: find.text('Variant A'),
      matching: find.byType(Card),
    );
    Finder inLeaf(String text) => find.descendant(
      of: leaf,
      matching: find.text(text, findRichText: true),
    );

    expect(inLeaf('Current Stock 6 Nos'), findsOneWidget);
    await driver.openFields();
    await driver.setVisible('in_production', true);
    await driver.setVisible('open_orders', true);
    await driver.setVisible('current_stock', false);
    await driver.dismiss();
    expect(inLeaf('Current Stock 6 Nos'), findsNothing);
    expect(inLeaf('Stock UOM: Nos'), findsOneWidget);
    expect(inLeaf('In Production: 0'), findsOneWidget);
    expect(inLeaf('Open Sales Orders: 3'), findsOneWidget);

    await driver.openFields();
    await driver.setVisible('stock_uom', false);
    await driver.setVisible('in_production', false);
    await driver.setVisible('open_orders', false);
    await driver.dismiss();
    expect(inLeaf('Stock UOM: Nos'), findsNothing);
    expect(inLeaf('In Production: 0'), findsNothing);
    expect(inLeaf('Open Sales Orders: 3'), findsNothing);
    for (final subtotal in [
      'Current Stock  6 Nos',
      'In Production  0 Nos',
      'Open Sales Orders  3',
    ]) {
      expect(find.text(subtotal, findRichText: true), findsOneWidget);
    }
    await tester.tap(find.text('Collapse All'));
    await tester.pumpAndSettle();
    expect(find.text('1 variant · Current Stock 6 Nos'), findsOneWidget);
    expect(find.text('2 variants'), findsOneWidget);
    await driver.scrollToEnd();
    expect(
      find.text(
        'End of list\nQuantity totals for shown results\n'
        'Current Stock 6 Nos\nIn Production 0 Nos\n'
        'Current Stock 5 Box\nIn Production 2 Box',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Item Variant Details settings persist and protect identity', (
    tester,
  ) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    final config = ReportFieldsTestConfig();
    const fieldsKey =
        'item_variant_details_fields::https%3A%2F%2Fone.example::Buyer';
    const controlKey =
        'item_variant_details_fields::https%3A%2F%2Fone.example::Seller';
    config.values[controlKey] = '{"older_attribute":false}';
    final storage = ReportFieldsTestStorage();
    final owner = ReportFieldsTestOwner()
      ..change('https://one.example', 'Buyer');
    final api = Get.put<ApiProvider>(_FakeApi(), permanent: true) as _FakeApi;
    Get.put(AuthenticationController(), permanent: true);
    final products = (
      columns: [
        {'fieldname': 'item_code', 'label': 'Product Code'},
        {'fieldname': 'material', 'label': 'Composition'},
        {'fieldname': 'current_stock', 'label': 'In Inventory'},
        {'fieldname': 'stock_uom', 'label': 'Stock UOM'},
      ],
      rows: [
        {
          'item_code': 'Variant A',
          'item_name': 'Belt A',
          'material': 'Cotton',
          'current_stock': 0,
          'stock_uom': 'Nos',
        },
      ],
    );
    api.report.complete(products);

    late ItemVariantDetailsController report;
    Future<void> mount() async {
      report = Get.put(
        ItemVariantDetailsController(
          fields: ScopedReportFieldsController(
            definition: itemVariantFields(),
            owner: owner,
            store: ScopedReportFieldsStore(database: config, storage: storage),
          ),
        ),
      );
      report.filterControllers['item']!.text = 'Template A';
      await tester.pumpWidget(
        const GetMaterialApp(home: ItemVariantDetailsScreen()),
      );
      await report.runReport();
      await tester.pumpAndSettle();
    }

    final driver = WidgetReportFieldsDriver(tester, owner);
    await mount();
    expect(find.text('Composition: Cotton'), findsOneWidget);
    expect(find.text('In Inventory 0 Nos'), findsOneWidget);
    await driver.openFields();
    expect((await driver.read('item_code')).onChanged, isNull);
    await driver.setVisible('material', false);
    await driver.setVisible('stock_uom', false);
    await driver.setVisible('current_stock', false);
    await driver.dismiss();
    expect(find.text('Composition: Cotton'), findsNothing);
    expect(find.text('Variant A'), findsOneWidget);
    expect(find.text('Belt A'), findsOneWidget);
    expect(find.textContaining('End of list'), findsOneWidget);
    expect(find.textContaining('In Inventory 0 Nos'), findsOneWidget);
    expect(api.requests, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<ItemVariantDetailsController>(force: true);
    await mount();
    expect(find.text('Composition: Cotton'), findsNothing);
    await driver.openFields();
    await driver.switchOwner(site: 'https://other.example', user: 'Buyer');
    await report.runReport();
    await tester.pumpAndSettle();
    expect((await driver.read('material')).value, isTrue);
    await driver.switchOwner(site: 'https://one.example', user: 'Seller');
    await report.runReport();
    await tester.pumpAndSettle();
    expect((await driver.read('material')).value, isTrue);
    await driver.switchOwner(site: 'https://one.example', user: 'Buyer');
    await report.runReport();
    await tester.pumpAndSettle();
    expect((await driver.read('material')).value, isFalse);
    api.reportOverride = (
      columns: products.columns
          .where((column) => column['fieldname'] != 'material')
          .toList(),
      rows: products.rows,
    );
    await report.runReport();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Composition'), findsNothing);
    await driver.reset();
    expect(config.values[fieldsKey], '{}');
    expect(config.values[controlKey], '{"older_attribute":false}');
    await driver.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<ItemVariantDetailsController>(force: true);
    api.reportOverride = null;
    await mount();
    expect(find.text('Composition: Cotton'), findsOneWidget);
  });
}

Rect groupRect(WidgetTester tester, Finder finder) {
  final sliver = tester.renderObject<RenderSliver>(finder);
  final origin = MatrixUtils.transformPoint(
    sliver.getTransformTo(null),
    Offset.zero,
  );
  return origin &
      Size(sliver.constraints.crossAxisExtent, sliver.geometry!.scrollExtent);
}

double listHeaderBottom(WidgetTester tester) {
  final sliver = tester.renderObject<RenderSliverPersistentHeader>(
    find.descendant(
      of: find.byType(DocTypeListHeader),
      matching: find.byType(SliverPersistentHeader),
    ),
  );
  final box = sliver.child!;
  return box.localToGlobal(Offset(0, box.size.height)).dy;
}

class _FakeApi extends ApiProvider {
  late final report = Completer<ItemVariantDetailsResult>();
  ItemVariantDetailsResult? reportOverride;
  final requests = <Map<String, dynamic>>[];
  final detailRequests = <List<String>>[];
  final stockRequests = <({String itemCode, List<String> warehouses})>[];
  final stockRows = <Map<String, dynamic>>[];
  Map<String, dynamic>? stockResponse;
  bool stockFails = false;
  final details = <String, Map<String, dynamic>>{};

  Completer<void>? detailGate;
  Completer<Map<String, String>>? names;
  final nameRequests = <List<String>>[];

  @override
  Future<Map<String, String>> getItemNames(
    List<String> itemCodes, {
    CancelToken? cancelToken,
  }) async {
    nameRequests.add(itemCodes);
    return names == null ? {} : await names!.future;
  }

  @override
  Future<RackStockBalanceResult> getStockBalanceDimensionResult({
    required String itemCode,
    List<String> warehouses = const [],
  }) async {
    stockRequests.add((itemCode: itemCode, warehouses: warehouses));
    if (stockFails) throw StateError('stock check failed');
    if (stockResponse case final response?) {
      return ApiProvider.parseRackStockBalanceResult(response);
    }
    return (
      columns: const <DeskColumn>[],
      rows: stockRows
          .where(
            (row) =>
                warehouses.isEmpty || warehouses.contains(row['warehouse']),
          )
          .toList(),
    );
  }

  @override
  Future<ItemVariantDetailsResult> getItemVariantDetails({
    List<String> items = const [],
    List<String> itemGroups = const [],
    List<String> warehouses = const [],
  }) async {
    requests.add(
      ApiProvider.itemVariantDetailsFilters(
        items: items,
        itemGroups: itemGroups,
        warehouses: warehouses,
      ),
    );
    return reportOverride ?? await report.future;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getItemDetails(
    List<String> itemCodes,
  ) async {
    detailRequests.add(itemCodes);
    await detailGate?.future;
    return {
      for (final code in itemCodes)
        if (details.containsKey(code)) code: details[code]!,
    };
  }

  @override
  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    if (doctype == 'Item') expect(filters, {'has_variants': 1});
    final options = switch (doctype) {
      'Item' => ['ACP-25', 'ACP-MIX'],
      'Item Group' => ['Belts', 'Wallets'],
      'Warehouse' => ['POS-DXB2 - KA', 'WH-DXB1 - KA'],
      _ => throw StateError('Unexpected picker for $doctype'),
    };
    return options
        .where((option) => option.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}

void main() {
  late _FakeApi api;

  const reportFont = 'ItemVariantTestInter';
  setUpAll(() async {
    final loader = FontLoader(reportFont)
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
    await loader.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => r'C:\temp\item_variant_details_test',
        );
  });

  setUp(() {
    Get.testMode = true;
    api = _FakeApi();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put(AuthenticationController(), permanent: true);
  });
  tearDown(Get.reset);

  Future<void> open(
    WidgetTester tester, {
    Object? preset,
    ThemeMode mode = ThemeMode.dark,
    double width = 390,
    double height = 850,
    String? fontFamily,
    double? headerScale,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (headerScale != null) {
      tester.platformDispatcher.textScaleFactorTestValue = headerScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Get.put(
        ThemeController(persist: (_, _) async {}, restore: (_) async => null),
      );
    }
    ThemeData theme(Brightness brightness) {
      final theme = buildAppTheme(AppScheme.of(brightness), brightness);
      if (fontFamily == null) return theme;
      return theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: fontFamily),
      );
    }

    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: mode,
        builder: headerScale == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.noScaling,
                ),
                child: child!,
              ),
        home: const Scaffold(),
        getPages: [
          GetPage(
            name: AppRoutes.ITEM_FORM,
            page: () => const Scaffold(body: Text('Item form')),
          ),
          GetPage(
            name: '/variants',
            page: () => const ItemVariantDetailsScreen(),
            binding: BindingsBuilder(
              () => Get.lazyPut(ItemVariantDetailsController.new),
            ),
          ),
        ],
      ),
    );
    Get.toNamed('/variants', arguments: preset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Filters'));
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester, String field) async {
    final row = find.ancestor(
      of: find.text(field),
      matching: find.byType(InputDecorator),
    );
    final action = find.descendant(of: row, matching: find.byType(ActionChip));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  Finder option(String value) => find.widgetWithText(CheckboxListTile, value);

  Future<void> pick(WidgetTester tester, String field, String value) async {
    await openPicker(tester, field);
    await tester.tap(option(value));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  test(
    'field overrides persist across reports with different columns',
    () async {
      final storage = ReportFieldsTestStorage()
        ..legacyValues['item_variant_details'] = {'material': false};
      final config = ReportFieldsTestConfig();
      final owner = ReportFieldsTestOwner()..change('https://one.example', 'X');
      ItemVariantDetailsController mount(List<DeskColumn> columns) {
        final fields = ScopedReportFieldsController(
          definition: itemVariantFields(columns),
          owner: owner,
          store: ScopedReportFieldsStore(database: config, storage: storage),
        );
        return ItemVariantDetailsController(fields: fields)..onInit();
      }

      final first = mount(const [
        (fieldname: 'material', label: 'Material'),
        (fieldname: 'avg_buying_price_list_rate', label: 'Buying Rate'),
      ]);
      await first.fields.bind();
      expect(first.fields.shows('material'), isFalse);
      expect(first.fields.shows('avg_buying_price_list_rate'), isFalse);
      await first.fields.setVisible('avg_buying_price_list_rate', true);

      final reopened = mount(const [(fieldname: 'colour', label: 'Colour')]);
      await reopened.fields.bind();
      expect(reopened.fields.shows('colour'), isTrue);
      await reopened.fields.setVisible('colour', false);
      final key = ScopedReportFieldsStore.configKey(
        'item_variant_details',
        owner.current!.scope,
      );
      expect(
        config.values[key],
        '{"material":false,"avg_buying_price_list_rate":true,"colour":false}',
      );
      expect(reopened.fields.shows('material'), isFalse);
      await reopened.fields.resetToDefaults();
      expect(config.values[key], '{}');
      expect(storage.legacyValues['item_variant_details'], {'material': false});
      first.onClose();
      reopened.onClose();
    },
  );

  Future<void> cacheImage(double width) async {
    final key = await ResizeImage(
      const NetworkImage('https://example.invalid/belt.png'),
      width: width.ceil(),
    ).obtainKey(ImageConfiguration.empty);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFFFFFFFF), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final bitmap = picture.toImageSync(1, 1);
    picture.dispose();
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () =>
          OneFrameImageStreamCompleter(Future.value(ImageInfo(image: bitmap))),
    );
    addTearDown(() => PaintingBinding.instance.imageCache.evict(key));
  }

  testWidgets('shared header opens server-labelled fields for a flat report', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
    api.report.complete((
      columns: [
        {'fieldname': 'variant_name', 'label': 'Variant'},
        {'fieldname': 'item_name', 'label': 'Description'},
        {'fieldname': 'material', 'label': 'Leather Material'},
        {'fieldname': 'current_stock', 'label': 'Current Stock'},
        {'fieldname': 'stock_uom', 'label': 'Stock UOM'},
        {'fieldname': 'avg_buying_price_list_rate', 'label': 'Buying Rate'},
      ],
      rows: [
        {
          'variant_name': 'Belt-1',
          'item_name': 'Demo Belt',
          'material': 'Leather',
          'current_stock': 3,
          'stock_uom': 'Nos',
          'avg_buying_price_list_rate': 12.5,
          'currency': 'AED',
        },
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(find.byType(DocTypeListHeader), findsOneWidget);
    expect(find.text('Item Variant Details'), findsOneWidget);
    expect(find.text('Items: 1 selected'), findsOneWidget);
    expect(find.byTooltip(RegExp('Image size')), findsNothing);
    expect(find.textContaining('Leather', findRichText: true), findsOneWidget);
    expect(find.text('Current Stock 3 Nos'), findsOneWidget);
    expect(find.textContaining('AED 12.50', findRichText: true), findsNothing);
    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.widgetWithText(CheckboxListTile, label);
    expect(tester.widget<CheckboxListTile>(field('Variant')).onChanged, isNull);
    expect(
      tester.widget<CheckboxListTile>(field('Description')).onChanged,
      isNull,
    );
    expect(
      tester.widget<CheckboxListTile>(field('Leather Material')).value,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(field('Buying Rate')).value,
      isFalse,
    );
    await tester.tap(field('Leather Material'));
    await tester.pumpAndSettle();
    await tester.tap(field('Buying Rate'));
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.textContaining('Leather', findRichText: true), findsNothing);
    expect(
      find.textContaining('AED 12.50', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Quantity totals for shown results\nCurrent Stock 3 Nos',
      ),
      findsOneWidget,
    );
    expect(api.requests, hasLength(1));
  });

  for (final groups in [1, 26]) {
    testWidgets('Fields anchors an exposed variant with $groups templates', (
      tester,
    ) async {
      await open(tester, preset: 'ACP-25');
      api.report.complete((
        columns: [
          {'fieldname': 'variant_name', 'label': 'Variant'},
          {'fieldname': 'current_stock', 'label': 'Current Stock'},
        ],
        rows: [
          for (var group = 0; group < groups; group++) ...[
            {'variant_name': 'Template-$group', 'indent': 0},
            for (var index = 0; index < (group == 0 ? 40 : 1); index++)
              {
                'variant_name': 'Variant-$group-$index',
                'current_stock': 3,
                'indent': 1,
              },
          ],
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();

      final controller = Get.find<ItemVariantDetailsController>();
      final group = controller.results.value!.groups.first;
      final driver = WidgetReportFieldsDriver(tester, ReportFieldsTestOwner());
      final position = controller.scrollController.position;
      expect(
        find.byType(PinnedHeaderSliver),
        groups == 1 ? findsOneWidget : findsNothing,
      );
      position.jumpTo(1250);
      await tester.pumpAndSettle();

      const headingHeight = 52.0;
      double offset(Object id) => driver.readPaintedOffset(id) - headingHeight;
      final id = List.generate(40, (index) => (group, 'variant', index))
          .firstWhere((id) {
            return find.byKey(ValueKey<Object>(id)).evaluate().isNotEmpty &&
                offset(id) > 20 &&
                offset(id) < 300;
          });
      position.jumpTo(position.pixels + offset(id) + 14);
      await tester.pumpAndSettle();
      final before = offset(id);
      expect(before, closeTo(-14, 1));
      final variant = find.byKey(ValueKey<Object>(id));
      final stockLine = find.descendant(
        of: variant,
        matching: find.text('Current Stock 3'),
      );
      expect(stockLine, findsOneWidget);

      await driver.openFields();
      await driver.setVisible('current_stock', false);
      await driver.dismiss();
      expect(variant, findsOneWidget);
      expect(stockLine, findsNothing);
      expect(offset(id), closeTo(before, 1));

      await driver.openFields();
      await driver.reset();
      await driver.dismiss();
      expect(variant, findsOneWidget);
      expect(stockLine, findsOneWidget);
      expect(offset(id), closeTo(before, 1));
    });

    testWidgets('group headings wrap at 2x text with $groups templates', (
      tester,
    ) async {
      const caption = 'Stock disponible à la date du rapport';
      await open(tester, preset: 'ACP-25');
      api.report.complete((
        columns: [
          {'fieldname': 'variant_name', 'label': 'Product'},
          {'fieldname': 'current_stock', 'label': caption},
        ],
        rows: [
          for (var index = 0; index < groups; index++) ...[
            {
              'variant_name': 'Template-$index',
              'current_stock': 3,
              'indent': 0,
            },
            {'variant_name': 'Product-$index', 'current_stock': 3, 'indent': 1},
          ],
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(find.text('Template-0'), findsWidgets);
      expect(tester.takeException(), isNull);

      Get.find<ItemVariantDetailsController>().setAllExpanded(false);
      await tester.pumpAndSettle();
      final summary = find.text('1 variant · $caption 3');
      expect(summary, findsWidgets);
      expect(
        tester.renderObject<RenderParagraph>(summary.first).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'collapsed template shows the full German stock caption at 240dp',
    (tester) async {
      const caption = 'Aktueller Lagerbestand';
      await open(tester, preset: 'ACP-25', width: 240);
      api.report.complete((
        columns: [
          {'fieldname': 'current_stock', 'label': caption},
        ],
        rows: [
          {'variant_name': 'ACP-25', 'current_stock': 936, 'indent': 0},
          {'variant_name': 'Product-1', 'current_stock': 600, 'indent': 1},
          {'variant_name': 'Product-2', 'current_stock': 336, 'indent': 1},
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      Get.find<ItemVariantDetailsController>().setAllExpanded(false);
      await tester.pumpAndSettle();

      final summary = find.text('2 variants · $caption 936');
      final paragraph = tester.renderObject<RenderParagraph>(summary);
      final heading = find
          .ancestor(of: summary, matching: find.byType(InkWell))
          .first;
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        tester.getRect(heading).contains(tester.getRect(summary).center),
        isTrue,
      );
      expect(
        tester.getBottomLeft(summary).dy,
        lessThanOrEqualTo(tester.getBottomLeft(heading).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'template speech preserves punctuation inside the stock caption',
    (tester) async {
      const caption = 'Current Stock · Main Warehouse';
      await open(tester, preset: 'ACP-25');
      api.report.complete((
        columns: [
          {'fieldname': 'current_stock', 'label': caption},
        ],
        rows: [
          {'variant_name': 'ACP-25', 'current_stock': 3, 'indent': 0},
          {'variant_name': 'Product-1', 'current_stock': 3, 'indent': 1},
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      Get.find<ItemVariantDetailsController>().setAllExpanded(false);
      await tester.pumpAndSettle();

      expect(find.text('1 variant · $caption 3'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Template ACP-25, 1 variant, $caption 3'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Check Stock retries unreadable rack balances and speaks quantities',
    (tester) async {
      await open(tester, preset: 'ACP-25');
      api.report.complete((
        columns: [
          {'fieldname': 'current_stock', 'label': 'Aktueller Lagerbestand'},
        ],
        rows: [
          {'variant_name': 'Variant A', 'stock_uom': 'Nos'},
        ],
      ));
      const columns = [
        {'fieldname': 'rack', 'label': 'Regal'},
        {'fieldname': 'bal_qty', 'label': 'Bilanzmenge'},
      ];
      api.stockResponse = {
        'columns': columns,
        'result': [
          ['Rack A', null],
          ['Rack B', 5],
        ],
      };
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check Stock'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No stock in any rack.'), findsNothing);
      expect(find.textContaining('Total · Bilanzmenge'), findsNothing);

      api.stockResponse = {
        'columns': columns,
        'result': [
          ['Rack A', 0],
          ['Rack B', 5],
        ],
      };
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Rack A'), findsOneWidget);
      expect(find.text('Rack B'), findsOneWidget);
      expect(find.text('Total · Bilanzmenge 5 Nos'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Rack A\s+Bilanzmenge 0 Nos')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Rack B\s+Bilanzmenge 5 Nos')),
        findsOneWidget,
      );
      expect(api.stockRequests, hasLength(2));

      await tester.tap(find.text('Hide Stock'));
      await tester.pumpAndSettle();
      expect(find.text('Total · Bilanzmenge 5 Nos'), findsNothing);
      api.stockResponse = {
        'columns': [
          {'fieldname': 'rack', 'label': 'Regal'},
          {'fieldname': 'bal_qty'},
        ],
        'result': [
          ['Rack C', 7],
        ],
      };
      await tester.tap(find.text('Check Stock'));
      await tester.pumpAndSettle();
      expect(find.text('Total · Balance Qty 7 Nos'), findsOneWidget);
      expect(find.textContaining('Total · Bilanzmenge'), findsNothing);
      expect(api.stockRequests.map((request) => request.itemCode), [
        'Variant A',
        'Variant A',
        'Variant A',
      ]);
    },
  );

  testWidgets(
    'rack check failure offers Retry and successful empty is distinct',
    (tester) async {
      await open(tester, preset: 'ACP-25');
      api.stockFails = true;
      api.report.complete((
        columns: <Map<String, dynamic>>[],
        rows: [
          {'variant_name': 'Variant A'},
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check Stock'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not run Stock Balance. Try again.'),
        findsOneWidget,
      );
      expect(find.text('No stock in any rack.'), findsNothing);
      api.stockFails = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No stock in any rack.'), findsOneWidget);
      expect(api.stockRequests, hasLength(2));
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Images use compact placeholders in ${mode.name}', (
      tester,
    ) async {
      await open(tester, preset: 'ACP-25', mode: mode);
      api.detailGate = Completer<void>();
      api.details['Broken'] = {'image': 'https://example.invalid/missing.png'};
      api.report.complete((
        columns: <Map<String, dynamic>>[],
        rows: [
          {'variant_name': 'Missing'},
          {'variant_name': 'Broken'},
        ],
      ));

      Finder card(String code) =>
          find.ancestor(of: find.text(code), matching: find.byType(Card));

      void expectCompact(String code, IconData icon) {
        final placeholder = find.descendant(
          of: card(code),
          matching: find.byIcon(icon),
        );
        final box = find
            .ancestor(of: placeholder, matching: find.byType(Container))
            .first;
        expect(tester.getSize(box), const Size(54, 54));
        expect(
          tester.getTopLeft(box).dx,
          lessThan(tester.getTopLeft(find.text(code)).dx),
        );
        expect(tester.getSize(card(code)).height, lessThan(200));
        expect(
          find.descendant(of: card(code), matching: find.byType(Image)),
          findsNothing,
        );
      }

      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.detailRequests, isNotEmpty);
      expectCompact('Missing', Icons.image_outlined);
      expectCompact('Broken', Icons.image_outlined);

      api.detailGate!.complete();
      await tester.pumpAndSettle();
      expectCompact('Missing', Icons.image_outlined);
      expectCompact('Broken', Icons.broken_image_outlined);
    });
  }

  testWidgets('a newly known image preserves the visible variant', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
    api.detailGate = Completer<void>();
    api.details['Row 0'] = {'image': 'https://example.invalid/belt.png'};
    api.report.complete((
      columns: <Map<String, dynamic>>[],
      rows: [
        for (var i = 0; i < 30; i++) {'variant_name': 'Row $i'},
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    final card = find.byType(Card).first;
    final ratio = tester.view.devicePixelRatio;
    await cacheImage((tester.getSize(card).width - 8) * ratio);
    final scroll = Get.find<ItemVariantDetailsController>().scrollController;
    scroll.jumpTo(tester.getSize(card).height * 3 + 42);
    await tester.pumpAndSettle();

    final toolbarBottom = listHeaderBottom(tester);
    final anchor = find.byType(Card).evaluate().firstWhere((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero).dy + box.size.height >
          toolbarBottom;
    });
    final anchorFinder = find.byElementPredicate(
      (element) => element == anchor,
    );
    final before = tester.getTopLeft(anchorFinder).dy;
    final pixels = scroll.offset;

    api.detailGate!.complete();
    await tester.pumpAndSettle();

    expect(scroll.offset, greaterThan(pixels));
    expect(tester.getTopLeft(anchorFinder).dy, closeTo(before, 0.01));
  });

  testWidgets('image expansion anchors below the scaled pinned header', (
    tester,
  ) async {
    await open(
      tester,
      preset: 'ACP-25',
      width: 320,
      fontFamily: reportFont,
      headerScale: 2,
    );
    api.detailGate = Completer<void>();
    api.details['Row 0'] = {'image': 'https://example.invalid/belt.png'};
    api.report.complete((
      columns: <Map<String, dynamic>>[],
      rows: [
        for (var i = 0; i < 30; i++) {'variant_name': 'Row $i'},
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    Finder card(String code) => find.ancestor(
      of: find.text(code),
      matching: find.byType(Card),
    );
    final first = card('Row 0');
    final next = card('Row 1');
    await cacheImage(
      (tester.getSize(first).width - 8) * tester.view.devicePixelRatio,
    );
    final scroll = Get.find<ItemVariantDetailsController>().scrollController;
    scroll.jumpTo(400);
    await tester.pumpAndSettle();
    final header = listHeaderBottom(tester);
    expect(header, greaterThan(104));
    final hiddenBottom = (header + 104) / 2;
    scroll.jumpTo(scroll.offset + tester.getRect(first).bottom - hiddenBottom);
    await tester.pumpAndSettle();
    expect(tester.getRect(first).bottom, closeTo(hiddenBottom, 0.01));
    final before = tester.getTopLeft(next).dy;
    expect(tester.getRect(next).bottom, greaterThan(header));
    final pixels = scroll.offset;

    api.detailGate!.complete();
    await tester.pumpAndSettle();

    expect(scroll.offset, greaterThan(pixels));
    expect(tester.getTopLeft(next).dy, closeTo(before, 0.01));
  });

  testWidgets('dark report keeps preset and shows loading in the body', (
    tester,
  ) async {
    await open(tester, preset: {'item_code': 'ACP-25'});
    final sheetTitle = find.text('Item Variant Details Filters');
    final scheme = Theme.of(tester.element(sheetTitle)).colorScheme;
    expect(scheme.brightness, Brightness.dark);
    final surfaces = find.ancestor(
      of: sheetTitle,
      matching: find.byType(Container),
    );
    final surface = tester
        .widgetList<Container>(surfaces)
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.color != null);
    expect(surface.color, scheme.surface);

    expect(find.widgetWithText(InputChip, 'ACP-25'), findsOneWidget);
    await pick(tester, 'Items', 'ACP-MIX');
    await pick(tester, 'Warehouses', 'POS-DXB2 - KA');
    await pick(tester, 'Warehouses', 'WH-DXB1 - KA');
    await tester.tap(find.text('Run Report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Item Variant Details Filters'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final controller = Get.find<ItemVariantDetailsController>();
    await controller.runReport(); // Same entry point used by pull to refresh.
    expect(api.requests, [
      {
        'item': ['ACP-25', 'ACP-MIX'],
        'warehouse': ['POS-DXB2 - KA', 'WH-DXB1 - KA'],
      },
    ]);

    // Trimmed from production items.json.
    api.report.complete((
      columns: [
        {'fieldname': 'current_stock', 'label': 'Current Stock'},
      ],
      rows: [
        {'variant_name': 'ACP-25', 'indent': 0, 'current_stock': 936},
        {
          'variant_name': '2002506',
          'indent': 1,
          'current_stock': 936,
          'stock_uom': 'Nos',
        },
        {'variant_name': 'ACP-MIX', 'indent': 0, 'current_stock': 0},
        {
          'variant_name': '2002499',
          'indent': 1,
          'current_stock': 0,
          'stock_uom': 'Nos',
        },
      ],
    ));
    await tester.pumpAndSettle();
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final scrollbar = tester
        .widgetList<Scrollbar>(find.byType(Scrollbar))
        .singleWhere((bar) => bar.controller == controller.scrollController);
    expect(scrollbar.controller, same(scrollView.controller));
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.thumbVisibility, isTrue);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(api.detailRequests.expand((batch) => batch), contains('2002506'));

    controller.scrollController.jumpTo(
      controller.scrollController.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'End of list\nQuantity totals for shown results\nCurrent Stock 936 Nos',
      ),
      findsOneWidget,
    );
  });

  testWidgets('large reports scroll under the pinned filter toolbar', (
    tester,
  ) async {
    await open(tester, preset: {'item_code': 'ACP-25'});
    await tester.tap(find.text('Run Report'));
    await tester.pump();
    api.report.complete((
      columns: <Map<String, dynamic>>[],
      rows: <Map<String, dynamic>>[
        for (var index = 0; index < 501; index++)
          {'variant_name': 'Variant $index'},
      ],
    ));
    await tester.pumpAndSettle();

    final controller = Get.find<ItemVariantDetailsController>();
    final scrollbar = tester
        .widgetList<Scrollbar>(find.byType(Scrollbar))
        .singleWhere((bar) => bar.controller == controller.scrollController);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isFalse);
    expect(find.text('Swipe the list to scroll long results'), findsOneWidget);

    final filter = find.byTooltip('Filters, 1 active');
    final results = find.byType(CustomScrollView);
    await tester.drag(results, const Offset(0, -300));
    await tester.pumpAndSettle();
    final scrolledOffset = controller.scrollController.offset;
    expect(scrolledOffset, greaterThan(0));
    final filterTop = tester.getTopLeft(filter).dy;
    final toolbar = tester.getRect(find.byType(NavigationToolbar));
    expect(filterTop, inInclusiveRange(toolbar.top, toolbar.bottom));

    await tester.drag(results, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(controller.scrollController.offset, greaterThan(scrolledOffset));
    expect(tester.getTopLeft(filter).dy, filterTop);
    await tester.tap(filter.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Item Variant Details Filters'), findsOneWidget);
  });

  testWidgets(
    'collapsed headings keep their extent and stock context in dark mode',
    (tester) async {
      await open(tester, preset: 'ACP-25', width: 520);
      api.report.complete((
        columns: <Map<String, dynamic>>[],
        rows: [
          {
            'variant_name': 'ACP-25',
            'indent': 0,
            'item_name': 'Classic Belt',
            'current_stock': 3,
            'stock_uom': 'Nos',
          },
          {'variant_name': 'A', 'indent': 1, 'current_stock': 3},
          {'variant_name': 'B', 'indent': 1, 'current_stock': 0},
          {'variant_name': 'Mixed', 'indent': 0},
          {'variant_name': 'C', 'indent': 1},
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collapse All'));
      await tester.pumpAndSettle();
      final title = find.text('ACP-25 · Classic Belt');
      final heading = find
          .ancestor(of: title, matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(heading).height, 52);
      final summary = find.text('2 variants · Current Stock 3 Nos');
      final scheme = Theme.of(tester.element(summary)).colorScheme;
      expect(scheme.brightness, Brightness.dark);
      expect(
        tester.widget<Text>(summary).style!.color,
        scheme.onSurfaceVariant,
      );
      expect(find.text('1 variant'), findsOneWidget);
      final stock = find.widgetWithText(FilterChip, 'In stock');
      await tester.ensureVisible(stock);
      await tester.pumpAndSettle();
      final stockBounds = tester.getRect(stock);
      final stockSemantics = tester.getSemantics(stock).rect;
      for (final size in [stockBounds.size, stockSemantics.size]) {
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await tester.tapAt(Offset(stockBounds.center.dx, stockBounds.top + 1));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(stock).selected, isTrue);
      expect(find.text('1 of 2 · Current Stock 3 Nos'), findsOneWidget);
      expect(tester.getSize(heading).height, 52);
      await tester.tapAt(Offset(stockBounds.center.dx, stockBounds.bottom - 1));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(stock).selected, isFalse);
    },
  );

  testWidgets(
    'name-only search shows progress and finds an offscreen variant',
    (tester) async {
      await open(tester, preset: 'ACP-25');
      api.names = Completer<Map<String, String>>();
      api.report.complete((
        columns: <Map<String, dynamic>>[],
        rows: [
          {'variant_name': 'ACP-25', 'indent': 0},
          for (var index = 0; index < 201; index++)
            {'variant_name': 'Code-$index', 'indent': 1},
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      expect(api.detailRequests, isEmpty);
      await tester.enterText(find.byType(TextField), 'Unseen Name');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Searching names… 0 / 201'), findsOneWidget);
      expect(find.text('No variants match.'), findsNothing);
      expect(api.nameRequests.single.last, 'Code-200');
      api.names!.complete({'Code-200': 'Unseen Name'});
      await tester.pumpAndSettle();
      expect(find.text('Code-200'), findsOneWidget);
      expect(find.textContaining('Searching names'), findsNothing);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('card layout and stock in ${mode.name} mode', (tester) async {
      await open(tester, preset: 'ACP-25', mode: mode);
      final warehouses = mode == ThemeMode.dark
          ? ['POS-DXB2 - KA', 'WH-DXB1 - KA']
          : <String>[];
      if (warehouses.isNotEmpty) {
        await openPicker(tester, 'Warehouses');
        for (final warehouse in warehouses) {
          await tester.tap(option(warehouse));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
      api.stockRows.addAll([
        {'rack': 'Rack A', 'qty': 1.5, 'warehouse': 'POS-DXB2 - KA'},
        if (warehouses.isNotEmpty) ...[
          {'rack': 'Rack B', 'qty': 2.5, 'warehouse': 'WH-DXB1 - KA'},
          {'rack': 'Excluded rack', 'qty': 10, 'warehouse': 'Other warehouse'},
        ],
      ]);
      api.report.complete((
        columns: [
          {'fieldname': 'current_stock', 'label': 'Current Stock'},
          {'fieldname': 'item_group', 'label': 'Item Group'},
          {'fieldname': 'stock_uom', 'label': 'Stock UOM'},
          {'fieldname': 'material', 'label': 'Material'},
          {'fieldname': 'brand', 'label': 'Brand'},
          {'fieldname': 'length', 'label': 'Length'},
        ],
        rows: [
          {
            'variant_name': 'ACP-25',
            'item_group': 'Belts',
            'indent': 0,
            'current_stock': 936,
            'stock_uom': 'Nos',
          },
          {
            'variant_name': '2002492',
            'item_group': 'Belts',
            'indent': 1,
            'current_stock': 936,
            'stock_uom': 'Nos',
            'material': 'Cotton',
            'brand': '-',
            'length': ' ',
          },
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();

      final card = find.byType(Card);
      final bounds = tester.getRect(
        find.descendant(of: card, matching: find.byType(Material)).first,
      );
      expect(bounds.left, 390 - bounds.right);
      final group = find.byType(DecoratedSliver);
      final groupBounds = groupRect(tester, group);
      expect(bounds.left, groupBounds.left + 8);
      expect(bounds.right, groupBounds.right - 8);
      expect(tester.getTopLeft(find.text('ACP-25')).dx, bounds.left);
      expect(
        find.text('Current Stock  936 Nos', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Belts'), findsNWidgets(2));
      expect(find.text('Item Group: Belts'), findsNothing);
      expect(find.text('Stock UOM: Nos'), findsNothing);
      expect(find.text('Material: Cotton'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^(Brand|Length):')), findsNothing);
      expect(find.text('20'), findsNothing);
      final placeholder = find.byIcon(Icons.image_outlined);
      final theme = Theme.of(tester.element(card));
      final scheme = theme.colorScheme;
      expect(
        theme.brightness,
        mode == ThemeMode.light ? Brightness.light : Brightness.dark,
      );
      final shape = tester.widget<Card>(card).shape! as RoundedRectangleBorder;
      final decoration =
          tester.widget<DecoratedSliver>(group).decoration as BoxDecoration;
      final groupBorder = decoration.border! as Border;
      final outline = Color.lerp(
        scheme.outlineVariant,
        scheme.onSurface,
        0.60,
      )!;
      expect(shape.side.color, outline);
      expect(shape.side.width, greaterThan(0));
      expect(groupBorder.top.color, outline);
      for (final surface in [
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surface,
      ]) {
        final a = outline.computeLuminance() + 0.05;
        final b = surface.computeLuminance() + 0.05;
        expect(a > b ? a / b : b / a, greaterThanOrEqualTo(3));
      }
      expect(tester.widget<Icon>(placeholder).color, scheme.onPrimaryContainer);
      final stock = tester.widget<Text>(find.text('Current Stock 936 Nos'));
      expect(stock.style?.color, scheme.onSurface);
      final foreground = scheme.onSurface.computeLuminance();
      final background =
          theme.cardTheme.color?.computeLuminance() ??
          scheme.surfaceContainerLow.computeLuminance();
      final ratio = foreground > background
          ? (foreground + 0.05) / (background + 0.05)
          : (background + 0.05) / (foreground + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));

      await tester.tap(
        find.text(
          mode == ThemeMode.dark
              ? 'Check Stock Across Warehouses'
              : 'Check Stock',
        ),
      );
      await tester.pumpAndSettle();
      expect(api.stockRequests.single.itemCode, '2002492');
      expect(api.stockRequests.single.warehouses, warehouses);
      expect(find.text('Rack A'), findsOneWidget);
      expect(find.text('Excluded rack'), findsNothing);
      expect(find.text('1.5 Nos'), findsOneWidget);
      if (warehouses.isNotEmpty) {
        expect(find.text('Rack B'), findsOneWidget);
        expect(find.text('2.5 Nos'), findsOneWidget);
        expect(find.text('Total · Balance Qty 4 Nos'), findsOneWidget);
      } else {
        expect(find.text('Total · Balance Qty 1.5 Nos'), findsOneWidget);
      }
      expect(find.textContaining('pcs'), findsNothing);
    });
  }

  testWidgets('the card gallery fits the outline and closes on owner change', (
    tester,
  ) async {
    final owner = ReportFieldsTestOwner()..change('https://a.example', 'Buyer');
    Get.put<ReportOwnerSource>(owner);
    await open(tester, preset: 'ACP-25');
    api.detailGate = Completer<void>();
    api.details['2002506'] = {'image': 'https://example.invalid/belt.png'};
    api.report.complete((
      columns: <Map<String, dynamic>>[],
      rows: [
        {'variant_name': 'ACP-25', 'indent': 0},
        {'variant_name': '2002506', 'indent': 1},
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    final card = tester.getRect(
      find
          .descendant(of: find.byType(Card), matching: find.byType(Material))
          .first,
    );
    await cacheImage((card.width - 8) * tester.view.devicePixelRatio);
    await tester.pump(const Duration(milliseconds: 50));
    api.detailGate!.complete();
    await tester.pumpAndSettle();
    final bannerFinder = find.byType(RawImage);
    final banner = tester.getRect(bannerFinder);
    expect(banner.left, card.left + 4);
    expect(banner.right, card.right - 4);
    expect(banner.height, 84);
    await tester.tap(bannerFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ItemImagePreview), findsOneWidget);

    owner.change('https://b.example', 'Buyer');
    await tester.pumpAndSettle();
    expect(find.byType(ItemImagePreview), findsNothing);
    expect(find.text('2002506'), findsNothing);
    expect(find.byType(ItemVariantDetailsScreen), findsOneWidget);
  });

  testWidgets('each template enclosure owns only its heading and variants', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25', height: 1100);
    api.report.complete((
      columns: <Map<String, dynamic>>[],
      rows: [
        {
          'variant_name': 'ACP-25',
          'indent': 0,
          'current_stock': 936,
          'stock_uom': 'Nos',
        },
        {'variant_name': 'A', 'indent': 1},
        {'variant_name': 'B', 'indent': 1},
        {'variant_name': 'ACP-MIX', 'indent': 0},
        {'variant_name': 'C', 'indent': 1},
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();

    final semantics = tester.ensureSemantics();
    await tester.pump();
    final groups = find.byType(DecoratedSliver);
    expect(groups, findsNWidgets(2));
    final first = groups.first;
    final second = groups.last;
    Finder inside(Finder group, String code) =>
        find.descendant(of: group, matching: find.text(code));
    for (final code in ['ACP-25', 'A', 'B']) {
      expect(inside(first, code), findsOneWidget);
      expect(inside(second, code), findsNothing);
    }
    for (final code in ['ACP-MIX', 'C']) {
      expect(inside(second, code), findsOneWidget);
      expect(inside(first, code), findsNothing);
    }
    expect(
      find.bySemanticsLabel(
        'Template ACP-25, 2 variants, Current Stock 936 Nos',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Open variant A of ACP-25')),
      findsOneWidget,
    );
    final bounds = groupRect(tester, first);
    expect(bounds.contains(tester.getCenter(inside(first, 'B'))), isTrue);
    expect(groupRect(tester, second).top - bounds.bottom, 8);
    semantics.dispose();
  });

  testWidgets('legacy flat results keep the outlined cards and omit groups', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
    api.report.complete((
      columns: <Map<String, dynamic>>[],
      rows: [
        {'variant_name': 'Legacy'},
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    final card = tester.widget<Card>(find.byType(Card));
    expect((card.shape! as RoundedRectangleBorder).side.width, 1);
    expect(find.byType(DecoratedSliver), findsNothing);
    expect(find.text('Legacy'), findsOneWidget);
  });

  testWidgets('touch can drag the thumb and tap the right edge of cards', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
    await tester.tap(find.text('Run Report'));
    final ItemVariantDetailsResult result = (
      columns: <Map<String, dynamic>>[],
      rows: [
        for (var index = 0; index < 100; index++)
          {'variant_name': 'Variant-$index', 'indent': 1},
      ],
    );
    api.report.complete(result);
    await tester.pumpAndSettle();

    final scrollController =
        Get.find<ItemVariantDetailsController>().scrollController;
    final scrollbar = find.byWidgetPredicate(
      (widget) => widget is Scrollbar && widget.controller == scrollController,
    );
    final bounds = tester.getRect(scrollbar);
    final scrollbarPaint = find.descendant(
      of: scrollbar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ScrollbarPainter,
      ),
    );
    final painter =
        tester.widget<CustomPaint>(scrollbarPaint).foregroundPainter!
            as ScrollbarPainter;
    final paintOrigin = tester.getTopLeft(scrollbarPaint);
    final thumbY = bounds.top + 12 - paintOrigin.dy;
    final touchLeft =
        List.generate(bounds.width.toInt(), (x) => x).firstWhere(
          (x) => painter.hitTestOnlyThumbInteractive(
            Offset(x.toDouble(), thumbY),
            PointerDeviceKind.touch,
          ),
        ) +
        paintOrigin.dx;
    final drag = await tester.startGesture(
      Offset(bounds.right - 2, bounds.top + 12),
    );
    await tester.pump(kLongPressTimeout);
    await drag.moveBy(const Offset(0, 180));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(scrollController.offset, greaterThan(850));

    scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    final cardHeader = find
        .ancestor(of: find.text('Variant-0'), matching: find.byType(InkWell))
        .first;
    final stockButton = find
        .widgetWithText(OutlinedButton, 'Check Stock')
        .first;
    expect(
      touchLeft - tester.getRect(stockButton).right,
      greaterThanOrEqualTo(3),
    );
    expect(
      touchLeft - tester.getRect(cardHeader).right,
      greaterThanOrEqualTo(3),
    );
    expect(
      touchLeft - tester.getRect(find.byIcon(Icons.chevron_right).first).right,
      greaterThanOrEqualTo(3),
    );
    await tester.tapAt(
      tester.getRect(stockButton).centerRight - const Offset(2, 0),
    );
    await tester.pumpAndSettle();
    expect(api.stockRequests.single.itemCode, 'Variant-0');

    await tester.tapAt(
      tester.getRect(cardHeader).centerRight - const Offset(2, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item form'), findsOneWidget);
  });

  testWidgets('items can be searched and selected before one report run', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(
      find.text('Select at least one Item or Item Group.'),
      findsOneWidget,
    );

    await pick(tester, 'Warehouses', 'WH-DXB1 - KA');
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(
      find.text('Select at least one Item or Item Group.'),
      findsOneWidget,
    );
    expect(api.requests, isEmpty);

    await openPicker(tester, 'Items');
    await tester.tap(option('ACP-25'));
    await tester.pumpAndSettle();
    expect(find.text('Select Items'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(option('ACP-25')).value, isTrue);

    await tester.enterText(find.byType(TextField), 'MIX');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(option('ACP-25'), findsNothing);
    await tester.tap(option('ACP-MIX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await openPicker(tester, 'Items');
    expect(tester.widget<CheckboxListTile>(option('ACP-25')).value, isTrue);
    expect(tester.widget<CheckboxListTile>(option('ACP-MIX')).value, isTrue);
    await tester.tap(option('ACP-25'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    for (final code in ['ACP-25', 'ACP-MIX']) {
      expect(find.widgetWithText(InputChip, code), findsOneWidget);
    }

    api.report.complete((
      columns: <Map<String, dynamic>>[],
      rows: [
        {'variant_name': 'Belt-1', 'item_name': 'Demo Belt'},
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(api.requests.single, {
      'item': ['ACP-25', 'ACP-MIX'],
      'warehouse': ['WH-DXB1 - KA'],
    });
    expect(find.text('Belt-1'), findsOneWidget);
    expect(find.text('Items: 2 selected'), findsOneWidget);
    expect(find.text('Warehouses: 1 selected'), findsOneWidget);

    await tester.tap(find.text('Items: 2 selected'));
    await tester.pumpAndSettle();
    expect(find.text('Select Items'), findsOneWidget);
    await tester.tap(option('ACP-25'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'ACP-25'), findsNothing);
    expect(find.widgetWithText(InputChip, 'ACP-MIX'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Belt-1'), findsNothing);
    expect(find.text('Items: 1 selected'), findsNothing);
    expect(find.text('Warehouses: 1 selected'), findsNothing);
    expect(api.requests, hasLength(1));
  });

  testWidgets('group selection validates conflict and supports clearing', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
    await pick(tester, 'Item Groups', 'Belts');
    await pick(tester, 'Item Groups', 'Wallets');
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(find.text('Select either Items or Item Groups.'), findsOneWidget);
    expect(find.text('Item Variant Details Filters'), findsOneWidget);
    expect(find.text('Run Report'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(api.requests, isEmpty);

    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'ACP-25'))
        .onDeleted!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.requests, [
      {
        'item_group': ['Belts', 'Wallets'],
      },
    ]);
    expect(
      tester
          .widget<DocTypeListHeader>(find.byType(DocTypeListHeader))
          .onFilterTap,
      isNull,
    );

    const ItemVariantDetailsResult empty = (
      columns: <Map<String, dynamic>>[],
      rows: [],
    );
    api.report.complete(empty);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(Get.find<ItemVariantDetailsController>().activeFilters, isEmpty);
    expect(
      find.text('Select Items or Item Groups, then run the report.'),
      findsOneWidget,
    );
  });

  testWidgets('debounced search, collapse, and warehouse stock counts', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
    await pick(tester, 'Warehouses', 'POS-DXB2 - KA');
    await pick(tester, 'Warehouses', 'WH-DXB1 - KA');
    api.report.complete((
      columns: [
        {'fieldname': 'material'},
      ],
      rows: [
        {'variant_name': 'ACP-25', 'indent': 0},
        {'variant_name': '2002492', 'indent': 1, 'current_stock': 4},
        {'variant_name': 'ACP-MIX', 'indent': 0},
        {'variant_name': '2002499', 'indent': 1, 'material': 'Microfibre'},
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(find.text('Item Variant Details'), findsOneWidget);
    expect(find.text('2 templates · 2 variants'), findsOneWidget);
    await tester.tap(find.text('Collapse All'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    await tester.tap(find.text('Expand All'));
    await tester.pumpAndSettle();
    expect(find.text('2002492'), findsOneWidget);
    await tester.tap(find.text('Collapse All'));
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Search loaded results');
    await tester.enterText(search, 'Microfibre');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('2 templates · 2 variants'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('2 templates · 1 of 2 variants'), findsOneWidget);
    expect(find.text('2002499'), findsOneWidget);
    expect(find.text('ACP-25'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    await tester.ensureVisible(find.text('In stock in 2 warehouses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In stock in 2 warehouses'));
    await tester.pumpAndSettle();
    expect(find.text('ACP-25'), findsOneWidget);
    expect(find.text('ACP-MIX'), findsNothing);
    expect(find.text('2 templates · 1 of 2 variants'), findsOneWidget);
    expect(api.requests, hasLength(1));
  });

  testWidgets('a sticky group leaves Fields tappable at 200% system text', (
    tester,
  ) async {
    await open(
      tester,
      preset: 'ACP-25',
      width: 320,
      fontFamily: reportFont,
      headerScale: 2,
    );
    api.report.complete((
      columns: [
        {'fieldname': 'variant_name', 'label': 'Variant'},
      ],
      rows: [
        for (var g = 0; g < 25; g++) ...[
          {'variant_name': 'Template $g', 'indent': 0},
          for (var v = 0; v < 8; v++)
            {'variant_name': 'Variant $g/$v', 'indent': 1},
        ],
      ],
    ));
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    final controller = Get.find<ItemVariantDetailsController>();
    controller.setAllExpanded(true);
    controller.scrollController.jumpTo(460);
    await tester.pumpAndSettle();
    final sticky = controller.stickyHeading.value;
    expect(sticky?.group.code, 'Template 0');
    final group = find.text('Template 0').hitTestable();
    expect(group, findsOneWidget);
    final groupTop = tester.getTopLeft(group).dy;
    final headerBottom = listHeaderBottom(tester);

    await tester.tap(find.byTooltip('Fields'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Reset to defaults'), findsOneWidget);
    expect(controller.results.value!.isExpanded(sticky!.group), isTrue);
    expect(groupTop, greaterThanOrEqualTo(headerBottom));
  });

  for (final size in [2, 205]) {
    testWidgets('sticky heading switches in a $size-group report', (
      tester,
    ) async {
      await open(tester, preset: 'ACP-25', fontFamily: reportFont);
      api.report.complete((
        columns: <Map<String, dynamic>>[],
        rows: [
          for (var g = 0; g < size; g++) ...[
            {'variant_name': 'Template $g', 'indent': 0},
            for (var v = 0; v < 8; v++)
              {'variant_name': 'Variant $g/$v', 'indent': 1},
          ],
        ],
      ));
      await tester.tap(find.text('Run Report'));
      await tester.pumpAndSettle();
      if (size > 2) {
        expect(api.detailRequests, isEmpty);
        final search = find.widgetWithText(TextField, 'Search loaded results');
        await tester.enterText(search, 'Template 0');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await tester.enterText(search, 'Template');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Expand All'));
        await tester.pumpAndSettle();
        expect(
          find.text('Collapse groups to drag the scrollbar'),
          findsOneWidget,
        );
      }
      final scroll = Get.find<ItemVariantDetailsController>().scrollController;
      scroll.jumpTo(460);
      await tester.pumpAndSettle();
      final toolbar = listHeaderBottom(tester);
      final first = tester.getCenter(find.text('Template 0').hitTestable());
      expect(first.dy, inInclusiveRange(toolbar, toolbar + 75));
      for (var n = 0; n < 8; n++) {
        scroll.jumpTo(scroll.offset + 240);
        await tester.pumpAndSettle();
        final next = find.text('Template 1').hitTestable();
        if (next.evaluate().length != 1) continue;
        final y = tester.getCenter(next).dy;
        if (y >= toolbar && y < toolbar + 75) break;
      }
      final second = tester.getCenter(find.text('Template 1').hitTestable());
      expect(second.dy, inInclusiveRange(toolbar, toolbar + 75));
      expect(find.text('Template 0').hitTestable(), findsNothing);
      expect(
        api.detailRequests.expand((batch) => batch),
        isNot(contains('Variant 204/0')),
      );
    });
  }
}
