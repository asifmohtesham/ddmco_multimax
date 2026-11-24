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
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
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
    'balance_qty': 12.5,
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
    'balance_qty': 0,
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
    'balance_qty': 12.5,
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
    'sources': 'Purchase Order, Batch',
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
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'ACP-25'),
        matching: find.text('Balance: 12.5 Nos'),
      ),
      findsOneWidget,
    );
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
    expect(
      find.descendant(
        of: itemWithoutSupplier,
        matching: find.text('Balance: 0 Nos'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<ListTile>(itemWithoutSupplier).onTap, isNull);
    expect(find.byKey(const ValueKey('none:7:2002492')), findsNothing);
    expect(find.text('1 supplier'), findsNWidgets(3));
    expect(find.text('KANG KAI'), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '2002506'),
        matching: find.text('Balance: 12.5 Nos'),
      ),
      findsOneWidget,
    );

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
      'Purchase Order, Batch',
      '0 Nos',
      '2026-11-05',
      'AED 0.00 from Purchase Order 2026-11-05',
    ]) {
      expect(
        find.descendant(of: supplier, matching: find.text(detail)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: supplier, matching: find.textContaining('Balance:')),
      findsNothing,
    );

    await tester.tap(find.text('ACP-25'));
    await tester.pumpAndSettle();
    expect(find.text('KANG KAI'), findsNothing);
    expect(find.text('2002506'), findsNothing);

    await tester.tap(find.text('GLOVES'));
    await tester.pumpAndSettle();
    expect(find.text('Leather Shop'), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
    expect(find.textContaining('Purchase Order'), findsNothing);
    expect(find.textContaining('USD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows variant codes above shared names under the template', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      {
        'node_id': 'template:ALS',
        'item_name': 'Automatic watches',
        'tree_label': 'Automatic watches',
      },
      for (final (code, name) in [
        ('2002906', 'AUTO'),
        ('2002907', 'AUTO'),
        ('SAME', 'SAME'),
        ('BLANK', '  '),
        ('DASH', '-'),
      ])
        {
          'node_id': 'item:$code',
          'parent_id': 'template:ALS',
          'item_name': name,
          'tree_label': name,
        },
    ]);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(variantOf: ['ALS']),
    );
    await tester.pumpAndSettle();

    final template = find.widgetWithText(ListTile, 'ALS');
    final templateName = find.descendant(
      of: template,
      matching: find.text('Automatic watches'),
    );
    expect(templateName, findsOneWidget);
    expect(
      tester.getTopLeft(templateName).dy,
      greaterThan(tester.getTopLeft(find.text('ALS')).dy),
    );
    await tester.tap(template);
    await tester.pumpAndSettle();

    for (final code in ['2002906', '2002907']) {
      final tile = find.widgetWithText(ListTile, code);
      final name = find.descendant(of: tile, matching: find.text('AUTO'));
      expect(name, findsOneWidget);
      expect(
        tester.getTopLeft(name).dy,
        greaterThan(tester.getTopLeft(find.text(code)).dy),
      );
    }
    for (final code in ['SAME', 'BLANK', 'DASH']) {
      final tile = find.widgetWithText(ListTile, code);
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: tile, matching: find.byType(Text)),
            )
            .map((text) => text.data),
        [code, 'No supplier recorded'],
      );
    }
  });

  for (final textScale in [0.85, 1.3]) {
    testWidgets('fits long item labels on a Pixel 7 at scale $textScale', (
      tester,
    ) async {
      const viewport = Size(1080 / 2.625, 2400 / 2.625);
      const code =
          'UNBROKENITEMCODE0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      const name =
          'Long descriptive item name with enough words to wrap to several '
          'lines on the report screen when the phone text scale is increased';
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      api.load = () async => SuppliersByItemNode.parseRows([
        {'node_id': 'item:$code', 'item_name': name},
      ]);
      await openReport(
        tester,
        size: viewport,
        filters: const SuppliersByItemFilters(items: [code]),
      );
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(ListTile, code);
      final title = find.descendant(of: tile, matching: find.text(code));
      final description = find.descendant(of: tile, matching: find.text(name));
      for (final text in [title, description]) {
        final bounds = tester.getRect(text);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(viewport.width));
      }
      expect(
        tester.getTopLeft(description).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
      );

      final chip = find.widgetWithText(FilterChipWidget, 'Items · $code');
      expect(tester.getSize(chip).width, lessThanOrEqualTo(viewport.width));
      final delete = find.descendant(
        of: chip,
        matching: find.byIcon(Icons.close),
      );
      expect(delete.hitTestable(), findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final selected = find.widgetWithText(InputChip, code);
      expect(selected, findsOneWidget);
      expect(tester.getSize(selected).width, lessThan(viewport.width));
      final selectedLabel = tester.widget<InputChip>(selected).label as Text;
      expect(selectedLabel.maxLines, 1);
      expect(selectedLabel.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('emphasizes the matched supplier and shows the other supplier', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      {
        ..._acp25Rows[3],
        'parent_id': null,
        'supplier_count': 2,
        'balance_qty': 4,
      },
      {..._acp25Rows[4], 'matched_supplier': 1},
      {
        'node_id': 'supplier:2002506:OTHER',
        'parent_id': 'item:2002506',
        'supplier_name': 'Other Supplier',
        'matched_supplier': 0,
      },
    ]);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(
        suppliers: ['KANG KAI'],
        warehouses: ['Stores - MM'],
      ),
      themeMode: ThemeMode.dark,
    );
    await tester.pumpAndSettle();
    expect(find.text('2 suppliers'), findsOneWidget);
    expect(find.text('Balance: 4 Nos'), findsOneWidget);

    await tester.tap(find.text('2002506'));
    await tester.pumpAndSettle();

    final matched = tester.widget<Text>(find.text('KANG KAI'));
    final other = tester.widget<Text>(find.text('Other Supplier'));
    expect(matched.style?.fontWeight, FontWeight.bold);
    expect(other.style?.fontWeight, isNot(FontWeight.bold));
    expect(matched.style?.color, other.style?.color);
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

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('shows below reorder level in ${mode.name} mode', (
      tester,
    ) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {..._acp25Rows[0], 'projected_qty': 7, 'reorder_level': 9},
        {..._acp25Rows[1], 'projected_qty': 4, 'reorder_level': 4},
        _acp25Rows[2],
        {..._acp25Rows[3], 'projected_qty': 3, 'reorder_level': 5},
        _acp25Rows[4],
        {'node_id': 'item:LEGACY', 'reorder_level': 2},
        {'node_id': 'item:ZERO', 'projected_qty': -1, 'reorder_level': 0},
      ]);
      await openReport(tester, themeMode: mode);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ACP-25'));
      await tester.pumpAndSettle();

      expect(find.text('Balance: 12.5 Nos'), findsNWidgets(2));
      expect(find.text('Projected: 7 Nos'), findsOneWidget);
      expect(find.text('Projected: 3 Nos'), findsOneWidget);
      expect(find.text('Reorder level: 9 Nos'), findsOneWidget);
      expect(find.text('Reorder level: 5 Nos'), findsOneWidget);
      expect(find.text('Reorder level: 0'), findsNothing);
      final warnings = tester.widgetList<Text>(
        find.text('Below reorder level'),
      );
      expect(warnings, hasLength(2));
      final ink = mode == ThemeMode.dark
          ? AppColors.orange300
          : AppColors.orange700;
      expect(warnings.map((text) => text.style!.color), everyElement(ink));
    });
  }

  testWidgets('supplier rows show procurement details and sources', (
    tester,
  ) async {
    const sources =
        'Purchase Order (Draft), Batch (draft PO), '
        'Batch (cancelled PO), Batch (no PO)';
    api.load = () async => SuppliersByItemNode.parseRows([
      {..._acp25Rows[3], 'parent_id': null},
      {
        ..._acp25Rows[4],
        'supplier_status': 'On Hold (Orders) until 2027-01-01',
        'open_order_qty': 1234.5,
        'draft_order_qty': 2.5,
        'lead_time_days': 4,
        'lead_time_receipts': 3,
        'po_count': 5,
        'receipt_count': 2,
        'sources': sources,
      },
      {
        'node_id': 'supplier:2002506:ACTIVE',
        'parent_id': 'item:2002506',
        'supplier_name': 'Second Supplier',
        'supplier_status': 'Active',
        'open_order_qty': 0,
        'draft_order_qty': 0,
        'lead_time_days': null,
      },
    ]);
    await openReport(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2002506'));
    await tester.pumpAndSettle();

    final supplier = find.widgetWithText(Card, 'KANG KAI');
    for (final detail in [
      'On Hold (Orders) until 2027-01-01',
      'Open: 1,234.5 Nos',
      'Draft: 2.5',
      'Lead time: 4.0 days (3 receipts)',
      '5 POs · 2 receipts',
      sources,
    ]) {
      expect(
        find.descendant(of: supplier, matching: find.text(detail)),
        findsOneWidget,
      );
    }
    final activeSupplier = find.widgetWithText(Card, 'Second Supplier');
    expect(activeSupplier, findsOneWidget);
    for (final detail in ['Active', 'Open:', 'Draft:', 'Lead time:']) {
      expect(
        find.descendant(
          of: activeSupplier,
          matching: find.textContaining(detail),
        ),
        findsNothing,
      );
    }
  });

  for (final (count, suppliers, components, boms, procurement, leadTime) in [
    (
      0,
      '0 suppliers',
      '0 components',
      '0 BOMs',
      '0 POs · 0 receipts',
      'Lead time: 0.0 days (0 receipts)',
    ),
    (
      1,
      '1 supplier',
      '1 component',
      '1 BOM',
      '1 PO · 1 receipt',
      'Lead time: 1.0 day (1 receipt)',
    ),
    (
      2,
      '2 suppliers',
      '2 components',
      '2 BOMs',
      '2 POs · 2 receipts',
      'Lead time: 2.0 days (2 receipts)',
    ),
  ]) {
    testWidgets('uses the correct count labels for $count', (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {'node_id': 'template:STYLE', 'supplier_count': count},
        {'node_id': 'item:KIT'},
        {
          'node_id': 'supplier:KIT:VENDOR',
          'parent_id': 'item:KIT',
          'po_count': count,
          'receipt_count': count,
          'lead_time_days': count,
          'lead_time_receipts': count,
        },
        {
          'node_id': 'bom:kit',
          'parent_id': 'item:KIT',
          'bom_no': 'BOM-KIT',
          'component_count': count,
        },
        {
          'node_id': 'bom:usage',
          'parent_id': 'item:KIT',
          'bom_no': 'BOM-USAGE',
          'component_count': 1,
        },
        {
          'node_id': 'component:usage:PART',
          'parent_id': 'bom:usage',
          'item_code': 'PART',
          'used_in_bom_count': count,
        },
      ]);
      await openReport(
        tester,
        filters: const SuppliersByItemFilters(expandBom: true),
      );
      await tester.pumpAndSettle();

      expect(find.text(suppliers), findsOneWidget);
      await tester.tap(find.text('KIT'));
      await tester.pumpAndSettle();
      expect(find.text(procurement), findsOneWidget);
      expect(find.text(leadTime), findsOneWidget);
      expect(find.text('BOM-KIT · $components'), findsOneWidget);

      await tester.tap(find.text('BOM-USAGE · 1 component'));
      await tester.pumpAndSettle();
      expect(find.text('Used in $boms'), findsOneWidget);
    });
  }

  testWidgets('expands BOMs and keeps the direct supplier rows first', (
    tester,
  ) async {
    const item = 'item:3000339';
    const bom = 'bom:12:item:3000339|BOM-3000339-001';
    const component = 'component:$bom|1|2002400';
    const missing = 'none:$component';
    const draft = 'bom:12:item:3000339|BOM-3000339-002';
    api.load = () async => SuppliersByItemNode.parseRows([
      {
        'row_type': 'item',
        'node_id': item,
        'item_code': '3000339',
        'supplier_count': 1,
      },
      {
        'row_type': 'supplier',
        'node_id': 'supplier:3000339:DIRECT',
        'parent_id': item,
        'item_code': '3000339',
        'supplier': 'DIRECT',
        'supplier_name': 'Direct Supplier',
      },
      {
        'row_type': 'bom',
        'node_id': bom,
        'parent_id': item,
        'is_component': 1,
        'bom_no': 'BOM-3000339-001',
        'bom_status': 'Submitted',
        'bom_is_default': 1,
        'component_count': 1,
      },
      {
        'row_type': 'component',
        'node_id': component,
        'parent_id': bom,
        'is_component': 1,
        'item_code': '2002400',
        'item_name': 'Component with a descriptive name',
        'bom_qty_per_unit': 2.5,
        'stock_uom': 'Nos',
        'balance_qty': 4,
        'used_in_bom_count': 3,
        'include_in_manufacturing': 0,
        'supplier_count': 0,
        'bom_cycle': 1,
      },
      {
        'row_type': 'placeholder',
        'node_id': missing,
        'parent_id': component,
        'is_component': 1,
      },
      {
        'row_type': 'bom',
        'node_id': draft,
        'parent_id': item,
        'is_component': 1,
        'bom_no': 'BOM-3000339-002',
        'bom_status': 'Draft',
        'component_count': 0,
      },
    ]);
    await openReport(
      tester,
      themeMode: ThemeMode.dark,
      filters: const SuppliersByItemFilters(expandBom: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 supplier'), findsOneWidget);
    await tester.tap(find.text('3000339'));
    await tester.pumpAndSettle();

    final title = find.text('BOM-3000339-001 · default · 1 component');
    expect(
      tester.getTopLeft(find.text('Direct Supplier')).dy,
      lessThan(tester.getTopLeft(title).dy),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey(draft)),
        matching: find.text('Draft'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey(component)), findsNothing);

    await tester.tap(title);
    await tester.pumpAndSettle();
    final componentTile = find.widgetWithText(ListTile, '2002400');
    for (final detail in [
      'Component with a descriptive name',
      '2.5 Nos per unit',
      'Balance: 4 Nos',
      'Used in 3 BOMs',
      'Not used in manufacturing',
      'BOM cycle detected',
    ]) {
      expect(
        find.descendant(of: componentTile, matching: find.text(detail)),
        findsOneWidget,
      );
    }
    final manufacturingNote = tester.widget<Text>(
      find.text('Not used in manufacturing'),
    );
    expect(manufacturingNote.style?.color, AppScheme.dark.textMuted);
    await tester.tap(componentTile);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey(missing)),
        matching: find.text('No supplier recorded'),
      ),
      findsOneWidget,
    );

    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(component)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caps the visual indent across ten BOM levels on a phone', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var parentId = 'item:3000338';
    final rows = <Map<String, Object?>>[
      {'row_type': 'item', 'node_id': parentId, 'item_code': '3000338'},
    ];
    for (var level = 1; level <= 10; level++) {
      final bomId = 'bom:$parentId|$level';
      final componentId = 'component:$bomId|1|COMPONENT-$level';
      rows.addAll([
        {
          'row_type': 'bom',
          'node_id': bomId,
          'parent_id': parentId,
          'is_component': 1,
          'bom_no': 'BOM-LONG-COMPONENT-$level',
          'bom_status': 'Draft',
          'component_count': 1,
        },
        {
          'row_type': 'component',
          'node_id': componentId,
          'parent_id': bomId,
          'is_component': 1,
          'item_code': 'COMPONENT-$level',
          'item_name': 'A component description that wraps on a narrow phone',
          'bom_qty_per_unit': 1250.5,
          'stock_uom': 'Nos',
          'balance_qty': 25000,
          'used_in_bom_count': 11,
          'include_in_manufacturing': 0,
          'bom_depth_limit': level == 10 ? 1 : 0,
        },
      ]);
      parentId = componentId;
    }
    const supplierName = 'Long supplier name that needs to wrap';
    rows.add({
      'row_type': 'supplier',
      'node_id': 'supplier:$parentId|EDGE',
      'parent_id': parentId,
      'is_component': 1,
      'supplier': 'EDGE',
      'supplier_name': supplierName,
      'supplier_status': 'On Hold (Orders) until 2027-01-01',
      'matched_supplier': 1,
      'sources': 'Purchase Order (Draft), Batch (draft PO)',
    });
    api.load = () async => SuppliersByItemNode.parseRows(rows);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(expandBom: true),
      size: const Size(300, 620),
    );
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> reveal(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
      }
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(finder.hitTestable(), findsOneWidget);
    }

    Future<void> expand(Finder finder) async {
      await reveal(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await expand(find.text('3000338'));
    double? cappedIndent;
    for (var level = 1; level <= 10; level++) {
      await expand(find.text('BOM-LONG-COMPONENT-$level · 1 component'));
      final component = find.widgetWithText(ListTile, 'COMPONENT-$level');
      await expand(find.text('COMPONENT-$level'));
      if (level == 2) cappedIndent = tester.getTopLeft(component).dx;
      if (level == 10) {
        expect(tester.getTopLeft(component).dx, cappedIndent);
        expect(find.text('Depth 20'), findsOneWidget);
        expect(find.text('BOM depth limit reached'), findsOneWidget);
      }
    }
    final supplier = find.widgetWithText(Card, supplierName);
    await reveal(find.text(supplierName));
    expect(
      find.descendant(of: supplier, matching: find.text('Depth 21')),
      findsOneWidget,
    );
    expect(find.text('On Hold (Orders) until 2027-01-01'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(supplierName)).style?.fontWeight,
      FontWeight.bold,
    );
    expect(tester.takeException(), isNull);
  });

  Future<void> showItemCard(
    WidgetTester tester,
    List<Map<String, Object?>> rows, {
    required bool isTemplate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemSuppliersCard(
            key: ValueKey(rows),
            itemCode: isTemplate ? 'ACP-25' : '2002492',
            isTemplate: isTemplate,
            loadReport: () async => SuppliersByItemNode.parseRows(rows),
            onViewReport: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Item Overview shows the item or template balance and suppliers',
    (tester) async {
      final rows = [
        {..._acp25Rows[0], 'balance_qty': 1234.5},
        {..._acp25Rows[1], 'balance_qty': 0},
        ..._acp25Rows.skip(2),
      ];

      await showItemCard(tester, rows, isTemplate: true);
      expect(find.text('Balance: 1,234.5 Nos'), findsOneWidget);
      expect(find.text('KANG KAI'), findsOneWidget);
      expect(find.text('No supplier recorded'), findsNothing);
      expect(find.text('No suppliers recorded'), findsNothing);

      await showItemCard(tester, rows.take(3).toList(), isTemplate: false);
      expect(find.text('Balance: 0 Nos'), findsOneWidget);
      expect(find.text('Balance: 1,234.5 Nos'), findsNothing);
      expect(find.text('No suppliers recorded'), findsOneWidget);
      expect(find.text('KANG KAI'), findsNothing);
    },
  );

  testWidgets('Item Overview leaves mixed-UOM template balance blank', (
    tester,
  ) async {
    await showItemCard(tester, [
      {..._acp25Rows[0], 'stock_uom': null, 'balance_qty': null},
      {..._acp25Rows[1], 'balance_qty': 4},
      _acp25Rows[2],
      {..._acp25Rows[3], 'stock_uom': 'Kg', 'balance_qty': 6.5},
      _acp25Rows[4],
    ], isTemplate: true);

    expect(find.textContaining('Balance:'), findsNothing);
    expect(find.text('KANG KAI'), findsOneWidget);
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

  testWidgets(
    'footer totals only item balance, projected, and open quantities by UOM',
    (tester) async {
      const systemBottomPadding = 48.0;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: systemBottomPadding);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      api.load = () async => SuppliersByItemNode.parseRows([
        {
          ..._acp25Rows[0],
          'total_qty_received': 26.5,
          'projected_qty': 15,
          'open_order_qty': 3,
        },
        {..._acp25Rows[1], 'projected_qty': 5, 'open_order_qty': 1},
        _acp25Rows[2],
        {
          ..._acp25Rows[3],
          'supplier_count': 2,
          'total_qty_received': 26.5,
          'projected_qty': 10,
          'open_order_qty': 2,
        },
        {
          ..._acp25Rows[4],
          'last_rate': 110,
          'rate_source': 'Purchase Receipt',
          'total_qty_received': 20,
          'open_order_qty': 2,
          'draft_order_qty': 11,
          'po_count': 3,
          'receipt_count': 4,
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
          'balance_qty': 7.25,
          'projected_qty': -1.5,
          'open_order_qty': 8,
          'stock_uom': 'Kg',
        },
        {
          'node_id': 'supplier:4:BULK:WHOLESALE',
          'parent_id': 'item:BULK',
          'total_qty_received': 4,
          'open_order_qty': 8,
          'stock_uom': 'Kg',
          'last_rate': 510,
          'currency': 'AED',
        },
      ]);
      await openReport(tester, size: const Size(390, 240));
      await tester.pumpAndSettle();

      final scrollView = find.byType(CustomScrollView);
      final controller = tester
          .widget<CustomScrollView>(scrollView)
          .controller!;
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.controller, same(controller));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.text('End of list'), findsOneWidget);
      expect(find.text('Total qty received'), findsNothing);
      expect(find.text('26.5 Nos'), findsNothing);
      expect(find.text('Total balance qty'), findsOneWidget);
      expect(find.text('12.5 Nos'), findsOneWidget);
      expect(find.text('7.25 Kg'), findsOneWidget);
      expect(find.text('25 Nos'), findsNothing);
      expect(find.text('Total projected qty'), findsOneWidget);
      expect(find.text('15 Nos'), findsOneWidget);
      expect(find.text('-1.5 Kg'), findsOneWidget);
      expect(find.text('30 Nos'), findsNothing);
      expect(find.text('Total open order qty'), findsOneWidget);
      expect(find.text('3 Nos'), findsOneWidget);
      expect(find.text('6 Nos'), findsNothing);
      expect(find.text('16 Kg'), findsNothing);
      expect(find.text('11 Nos'), findsNothing);
      final lastTotal = find.text('8 Kg');
      expect(lastTotal, findsOneWidget);
      expect(find.textContaining('AED'), findsNothing);
      expect(find.textContaining('870'), findsNothing);
      expect(
        tester.getBottomLeft(scrollView).dy -
            tester.getBottomLeft(lastTotal).dy,
        greaterThanOrEqualTo(systemBottomPadding),
      );
    },
  );

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
      'include_drafts': 1,
      'expand_bom': 0,
    });

    api.load = () async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No suppliers recorded'), findsOneWidget);
    expect(api.requests, [filters, filters]);
  });

  testWidgets('opens a template-only multi-select filter', (tester) async {
    await openReport(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('From Date'), findsNothing);
    expect(find.text('To Date'), findsNothing);
    expect(
      find.text(
        "Shows items bought from these suppliers, with all of each item's suppliers.",
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Filters balance, projected stock, and reorder quantities.',
      ),
      findsOneWidget,
    );

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
      'include_drafts': 1,
      'expand_bom': 0,
    });
    expect(find.text('Variant Of · 2 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft switch defaults on and remembers the applied choice', (
    tester,
  ) async {
    await openReport(tester);
    await tester.pumpAndSettle();
    expect(api.requests.single.includeDrafts, isTrue);
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final draftSwitch = find.widgetWithText(
      SwitchListTile,
      'Include draft purchase orders',
    );
    await tester.ensureVisible(draftSwitch);
    expect(tester.widget<SwitchListTile>(draftSwitch).value, isTrue);
    expect(
      find.text(
        'Suppliers that appear only on draft purchase orders are hidden when off.',
      ),
      findsOneWidget,
    );
    await tester.tap(draftSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(draftSwitch).value, isFalse);
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(api.requests.last.includeDrafts, isFalse);

    final chip = find.widgetWithText(FilterChipWidget, 'Draft POs · Off');
    await tester.tap(find.text('Draft POs · Off'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(draftSwitch).value, isFalse);
    Navigator.of(tester.element(draftSwitch)).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();
    expect(api.requests.last.includeDrafts, isTrue);
    expect(chip, findsNothing);
  });

  testWidgets('BOM switch starts off, applies, and clears', (tester) async {
    await openReport(tester);
    await tester.pumpAndSettle();
    expect(api.requests.single.toJson()['expand_bom'], 0);
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final bomSwitch = find.widgetWithText(
      SwitchListTile,
      'Expand BOM components',
    );
    await tester.ensureVisible(bomSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(bomSwitch).value, isFalse);
    expect(
      find.text(
        'Shows what each item is made from and who supplies those components.',
      ),
      findsOneWidget,
    );
    await tester.tap(bomSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(api.requests.last.toJson()['expand_bom'], 1);

    final chip = find.widgetWithText(FilterChipWidget, 'BOM components · On');
    await tester.tap(find.text('BOM components · On'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(bomSwitch).value, isTrue);
    Navigator.of(tester.element(bomSwitch)).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();
    expect(api.requests.last.toJson()['expand_bom'], 0);
    expect(chip, findsNothing);
  });
}
