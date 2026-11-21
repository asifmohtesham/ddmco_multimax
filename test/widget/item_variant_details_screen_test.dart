import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_binding.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart';
import 'package:multimax/main.dart' show buildAppTheme;

class _FakeApi extends ApiProvider {
  late final report = Completer<ItemVariantDetailsResult>();
  final requests = <Map<String, dynamic>>[];
  final detailRequests = <List<String>>[];
  final stockRequests = <String>[];
  final stockRows = <Map<String, dynamic>>[];
  final details = <String, Map<String, dynamic>>{};

  @override
  Future<List<Map<String, dynamic>>> getStockBalanceWithDimension({
    required String itemCode,
    String? warehouse,
    String? batchNo,
  }) async {
    stockRequests.add(itemCode);
    return stockRows;
  }

  @override
  Future<ItemVariantDetailsResult> getItemVariantDetails({
    List<String> items = const [],
    List<String> itemGroups = const [],
    List<String> warehouses = const [],
  }) {
    requests.add(
      ApiProvider.itemVariantDetailsFilters(
        items: items,
        itemGroups: itemGroups,
        warehouses: warehouses,
      ),
    );
    return report.future;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getItemDetails(
    List<String> itemCodes,
  ) async {
    detailRequests.add(itemCodes);
    return details;
  }

  @override
  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    switch (doctype) {
      case 'Item':
        expect(filters, {'has_variants': 1});
        return ['ACP-25', 'ACP-MIX'];
      case 'Item Group':
        return ['Belts', 'Wallets'];
      case 'Warehouse':
        return ['POS-DXB2 - KA', 'WH-DXB1 - KA'];
      default:
        throw StateError('Unexpected picker for $doctype');
    }
  }
}

void main() {
  late _FakeApi api;

  setUpAll(() {
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
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GetMaterialApp(
        theme: buildAppTheme(AppScheme.light, Brightness.light),
        darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
        themeMode: mode,
        home: const Scaffold(),
        getPages: [
          GetPage(
            name: AppRoutes.ITEM_FORM,
            page: () => const Scaffold(body: Text('Item form')),
          ),
          GetPage(
            name: '/variants',
            page: () => const ItemVariantDetailsScreen(),
            binding: ItemVariantDetailsBinding(),
          ),
        ],
      ),
    );
    Get.toNamed('/variants', arguments: preset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Filters'));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String field, String value) async {
    final row = find.ancestor(
      of: find.text(field),
      matching: find.byType(InputDecorator),
    );
    final action = find.descendant(of: row, matching: find.byType(ActionChip));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, value));
    await tester.pumpAndSettle();
  }

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

  testWidgets(
    'large reports show a passive scrollbar and allow body scrolling',
    (tester) async {
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

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(controller.scrollController.offset, greaterThan(0));
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('card layout and stock in ${mode.name} mode', (tester) async {
      await open(tester, preset: 'ACP-25', mode: mode);
      if (mode == ThemeMode.dark) {
        await pick(tester, 'Warehouses', 'POS-DXB2 - KA');
      }
      api.stockRows.add({'rack': 'Rack A', 'qty': 1.5});
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
      expect(find.text('Total  1.5 Nos'), findsOneWidget);
      expect(find.text('1.5 Nos'), findsOneWidget);
      expect(find.textContaining('pcs'), findsNothing);
    });
  }

  testWidgets('the card gallery banner uses the full card width', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
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
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    final banner = tester.getRect(find.byType(Image));
    expect(banner.left, card.left);
    expect(banner.right, card.right);
    expect(tester.getTopLeft(find.text('ACP-25')).dx, banner.left);
    expect(banner.height, 84);
    await tester.tap(find.byType(Image));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ItemImagePreview), findsOneWidget);
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
    expect(api.stockRequests, ['Variant-0']);

    await tester.tapAt(
      tester.getRect(cardHeader).centerRight - const Offset(2, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item form'), findsOneWidget);
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
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.filter_alt_outlined).first,
          )
          .onPressed,
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
    await tester.tap(find.text('In stock in 2 warehouses'));
    await tester.pumpAndSettle();
    expect(find.text('ACP-25'), findsOneWidget);
    expect(find.text('ACP-MIX'), findsNothing);
    expect(find.text('2 templates · 1 of 2 variants'), findsOneWidget);
    expect(api.requests, hasLength(1));
  });

  for (final size in [2, 205]) {
    testWidgets('sticky heading switches in a $size-group report', (
      tester,
    ) async {
      await open(tester, preset: 'ACP-25');
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
      }
      final scroll = Get.find<ItemVariantDetailsController>().scrollController;
      final toolbar = tester
          .getBottomLeft(find.text('Item Variant Details'))
          .dy;
      scroll.jumpTo(460);
      await tester.pumpAndSettle();
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
