import 'dart:async';

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/item/form/widgets/item_suppliers_card.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_screen.dart';

import 'package:multimax/main.dart' show buildAppTheme;

import '../helpers/auth_fakes.dart';

class _FakeApi extends FakeApiProvider {
  final requests = <SuppliersByItemFilters>[];
  Future<List<SuppliersByItemNode>> Function() load = () async => [];

  @override
  Future<List<SuppliersByItemNode>> runSuppliersByItem(
    SuppliersByItemFilters filters,
  ) {
    requests.add(filters);
    return load();
  }

  @override
  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    expect(doctype, 'Item');
    expect(filters, {'has_variants': 1});
    return ['SHIRT', 'JACKET'];
  }
}

const _acp25Rows = [
  {
    'node_id': 'template:ACP-25',
    'row_type': 'template',
    'template': 'ACP-25',
    'tree_label': 'ACP-25',
    'indent': 0,
    'supplier_count': 1,
    'total_qty_received': 0,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'item:2002492',
    'parent_id': 'template:ACP-25',
    'row_type': 'item',
    'item_code': '2002492',
    'tree_label': '2002492',
    'indent': 1,
    'supplier_count': 0,
    'total_qty_received': 0,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'none:7:2002492',
    'parent_id': 'item:2002492',
    'row_type': 'placeholder',
    'item_code': '2002492',
    'tree_label': 'No supplier recorded',
    'indent': 2,
    'is_placeholder': 1,
    'supplier': null,
    'last_rate': null,
    'total_qty_received': null,
  },
  {
    'node_id': 'item:2002506',
    'parent_id': 'template:ACP-25',
    'row_type': 'item',
    'item_code': '2002506',
    'tree_label': '2002506',
    'indent': 1,
    'supplier_count': 1,
    'total_qty_received': 0,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'supplier:7:2002506:KANG KAI',
    'parent_id': 'item:2002506',
    'row_type': 'supplier',
    'item_code': '2002506',
    'tree_label': 'KANG KAI',
    'indent': 2,
    'is_placeholder': 0,
    'supplier': 'KANG KAI',
    'supplier_name': 'KANG KAI',
    'supplier_part_number': '1234-B',
    'total_qty_received': 0,
    'stock_uom': 'Nos',
    'last_po_date': '2026-11-05',
    'last_rate': 0,
    'currency': 'AED',
    'rate_source': 'Purchase Order',
    'rate_date': '2026-11-05',
    'rate_document': 'PO-123',
  },
];

void main() {
  late _FakeApi api;

  setUp(() {
    Get.testMode = true;
    api = _FakeApi();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put(AuthenticationController(), permanent: true);
  });
  tearDown(Get.reset);

  Future<void> openReport(
    WidgetTester tester, {
    SuppliersByItemFilters? filters,
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(390, 780),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GetMaterialApp(
        theme: buildAppTheme(AppScheme.light, Brightness.light),
        darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
        themeMode: themeMode,
        home: const Scaffold(),
        getPages: [
          GetPage(
            name: AppRoutes.SUPPLIERS_BY_ITEM,
            page: () => const SuppliersByItemScreen(),
            binding: SuppliersByItemBinding(),
            transition: Transition.noTransition,
          ),
        ],
      ),
    );
    Get.toNamed(AppRoutes.SUPPLIERS_BY_ITEM, arguments: filters);
    await tester.pump();
  }

  testWidgets('ACP-25 tree omits supplier placeholders in dark mode', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      ..._acp25Rows,
      {'node_id': 'item:GLOVES', 'item_name': 'Gloves', 'supplier_count': 1},
      {
        'node_id': 'supplier:GLOVES:LEATHER',
        'parent_id': 'item:GLOVES',
        'is_placeholder': 0,
        'supplier_name': 'Leather Shop',
        'last_rate': '',
        'currency': 'USD',
        'rate_source': 'Purchase Order',
        'rate_date': '2026-11-01',
      },
    ]);
    await openReport(
      tester,
      size: const Size(360, 800),
      themeMode: ThemeMode.dark,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 supplier'), findsNWidgets(2));
    expect(find.text('2002492'), findsNothing);
    expect(find.text('2002506'), findsNothing);
    expect(find.text('KANG KAI'), findsNothing);

    await tester.tap(find.text('ACP-25'));
    await tester.pumpAndSettle();

    final itemWithoutSupplier = find.widgetWithText(ListTile, '2002492');
    final noSupplier = find.descendant(
      of: itemWithoutSupplier,
      matching: find.text('No supplier recorded'),
    );
    expect(noSupplier, findsOneWidget);
    expect(tester.widget<ListTile>(itemWithoutSupplier).onTap, isNull);
    expect(find.byKey(const ValueKey('none:7:2002492')), findsNothing);
    expect(find.text('1 supplier'), findsNWidgets(3));
    expect(find.text('KANG KAI'), findsNothing);

    final context = tester.element(noSupplier);
    final scheme = Theme.of(context).colorScheme;
    final card = tester.widget<Card>(
      find.ancestor(of: noSupplier, matching: find.byType(Card)),
    );
    final background = card.color!;
    final ink =
        tester.widget<Text>(noSupplier).style?.color ??
        DefaultTextStyle.of(context).style.color!;
    final foreground = Color.alphaBlend(ink, background);
    final lighter = foreground.computeLuminance();
    final darker = background.computeLuminance();
    expect(scheme.brightness, Brightness.dark);
    expect(background, scheme.surface);
    expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));

    await tester.tap(find.text('2002506'));
    await tester.pumpAndSettle();
    final supplier = find.widgetWithText(Card, 'KANG KAI');
    expect(supplier, findsOneWidget);
    for (final detail in [
      '1234-B',
      '0 Nos',
      '2026-11-05',
      'AED 0.00 from Purchase Order 2026-11-05',
    ]) {
      expect(
        find.descendant(of: supplier, matching: find.text(detail)),
        findsOneWidget,
      );
    }

    await tester.tap(find.text('ACP-25'));
    await tester.pumpAndSettle();
    expect(find.text('KANG KAI'), findsNothing);
    expect(find.text('2002506'), findsNothing);

    await tester.tap(find.text('Gloves'));
    await tester.pumpAndSettle();
    expect(find.text('Leather Shop'), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
    expect(find.textContaining('Purchase Order'), findsNothing);
    expect(find.textContaining('USD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a placeholder-only report keeps the item visible', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      {..._acp25Rows[1], 'parent_id': null, 'indent': 0},
      {..._acp25Rows[2], 'indent': 1},
    ]);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(items: ['2002492']),
    );
    await tester.pumpAndSettle();

    final item = find.widgetWithText(ListTile, '2002492');
    expect(
      find.descendant(of: item, matching: find.text('No supplier recorded')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('none:7:2002492')), findsNothing);
  });

  testWidgets('Item Overview lists only real suppliers from the report', (
    tester,
  ) async {
    Future<void> showCard(
      List<Map<String, Object?>> rows, {
      required bool isTemplate,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ItemSuppliersCard(
              key: ValueKey(isTemplate),
              isTemplate: isTemplate,
              loadReport: () async => SuppliersByItemNode.parseRows(rows),
              onViewReport: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await showCard(_acp25Rows, isTemplate: true);
    expect(find.text('KANG KAI'), findsOneWidget);
    expect(find.text('No supplier recorded'), findsNothing);
    expect(find.text('No suppliers recorded'), findsNothing);

    await showCard(_acp25Rows.sublist(1, 3), isTemplate: false);
    expect(find.text('No suppliers recorded'), findsOneWidget);
    expect(find.text('KANG KAI'), findsNothing);
  });

  testWidgets('refresh shows busy feedback and guards against re-entry', (
    tester,
  ) async {
    await openReport(tester);
    await tester.pumpAndSettle();

    final button = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Refresh report',
    );
    expect(find.text('No suppliers recorded'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);

    final result = Completer<List<SuppliersByItemNode>>();
    api.load = () => result.future;
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(
      find.descendant(
        of: button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('No suppliers recorded'), findsNothing);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    expect(api.requests, hasLength(2));

    result.complete([]);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No suppliers recorded'), findsOneWidget);
  });

  testWidgets('footer sums received quantities per stock UOM', (tester) async {
    const systemBottomPadding = 48.0;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: systemBottomPadding);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    api.load = () async => SuppliersByItemNode.parseRows([
      {..._acp25Rows[0], 'total_qty_received': 26.5},
      _acp25Rows[1],
      _acp25Rows[2],
      {..._acp25Rows[3], 'supplier_count': 2, 'total_qty_received': 26.5},
      {
        ..._acp25Rows[4],
        'last_rate': 110,
        'rate_source': 'Purchase Receipt',
        'total_qty_received': 20,
      },
      {
        'node_id': 'supplier:7:2002506:OTHER',
        'parent_id': 'item:2002506',
        'supplier': 'OTHER',
        'last_rate': 250,
        'currency': 'AED',
        'total_qty_received': 6.5,
        'stock_uom': 'Nos',
      },
      {
        'node_id': 'item:BULK',
        'supplier_count': 1,
        'total_qty_received': 4,
        'stock_uom': 'Kg',
      },
      {
        'node_id': 'supplier:4:BULK:WHOLESALE',
        'parent_id': 'item:BULK',
        'total_qty_received': 4,
        'stock_uom': 'Kg',
        'last_rate': 510,
        'currency': 'AED',
      },
    ]);
    await openReport(tester, size: const Size(390, 240));
    await tester.pumpAndSettle();

    final scrollView = find.byType(CustomScrollView);
    final controller = tester.widget<CustomScrollView>(scrollView).controller!;
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.controller, same(controller));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.text('End of list'), findsOneWidget);
    expect(find.text('Total qty received'), findsOneWidget);
    expect(find.text('26.5 Nos'), findsOneWidget);
    final lastTotal = find.text('4 Kg');
    expect(lastTotal, findsOneWidget);
    expect(find.textContaining('AED'), findsNothing);
    expect(find.textContaining('870'), findsNothing);
    expect(
      tester.getBottomLeft(scrollView).dy - tester.getBottomLeft(lastTotal).dy,
      greaterThanOrEqualTo(systemBottomPadding),
    );
  });

  testWidgets('shows a permission error and retries with the same filter', (
    tester,
  ) async {
    api.load = () async => throw const SuppliersByItemReportException(
      SuppliersByItemReportException.denied,
      permissionDenied: true,
    );
    const filters = SuppliersByItemFilters(items: ['BLUE']);
    await openReport(tester, filters: filters);
    await tester.pumpAndSettle();

    expect(find.text(SuppliersByItemReportException.denied), findsOneWidget);
    expect(find.text('No suppliers recorded'), findsNothing);
    expect(api.requests.single.toJson(), {
      'items': ['BLUE'],
    });

    api.load = () async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No suppliers recorded'), findsOneWidget);
    expect(api.requests, [filters, filters]);
  });

  testWidgets('opens a template-only multi-select filter', (tester) async {
    await openReport(tester, size: const Size(1024, 768));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final variant = find.text('Variant Of');
    expect(variant, findsOneWidget);
    final add = find.descendant(
      of: find.ancestor(of: variant, matching: find.byType(InputDecorator)),
      matching: find.text('Tap to select'),
    );
    await tester.tap(add);
    await tester.pumpAndSettle();

    await tester.tap(find.text('SHIRT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JACKET'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();

    expect(api.requests.last.toJson(), {
      'variant_of': ['SHIRT', 'JACKET'],
    });
    expect(find.text('Variant Of · 2 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
