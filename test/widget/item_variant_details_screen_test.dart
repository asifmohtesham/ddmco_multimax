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
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_binding.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart';
import 'package:multimax/main.dart' show buildAppTheme;

class _FakeApi extends ApiProvider {
  late final report = Completer<ItemVariantDetailsResult>();
  final requests = <Map<String, dynamic>>[];
  final detailRequests = <List<String>>[];
  final stockRequests = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getStockBalanceWithDimension({
    required String itemCode,
    String? warehouse,
    String? batchNo,
  }) async {
    stockRequests.add(itemCode);
    return [];
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
    return {};
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

  Future<void> open(WidgetTester tester, {Object? preset}) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GetMaterialApp(
        darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
        themeMode: ThemeMode.dark,
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
    expect(api.detailRequests, [
      ['2002506', '2002499'],
    ]);

    controller.scrollController.jumpTo(
      controller.scrollController.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    expect(find.text('End of list\nCurrent Stock 936 Nos'), findsOneWidget);
  });

  testWidgets('touch can drag the thumb and tap the right edge of cards', (
    tester,
  ) async {
    await open(tester, preset: 'ACP-25');
    await tester.tap(find.text('Run Report'));
    final ItemVariantDetailsResult result = (
      columns: [],
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
          .widget<DocTypeListHeader>(find.byType(DocTypeListHeader))
          .onFilterTap,
      isNull,
    );

    const ItemVariantDetailsResult empty = (columns: [], rows: []);
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
}
