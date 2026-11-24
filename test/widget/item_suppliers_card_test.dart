// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/widgets/item_suppliers_card.dart';

Map<String, Object?> _item(
  String code, {
  String? template,
  String? uom,
  num? balance,
  num? projected,
}) => {
  'node_id': 'item:$code',
  if (template != null) 'parent_id': 'template:$template',
  'stock_uom': uom,
  'balance_qty': balance,
  'projected_qty': projected,
};

Map<String, Object?> _supplier(
  String item,
  String name, {
  String? status,
  String? uom,
  num? open,
  num? days,
  int? receipts,
}) => {
  'node_id': 'supplier:$item:$name',
  'parent_id': 'item:$item',
  'supplier_status': status,
  'stock_uom': uom,
  'open_order_qty': open,
  'lead_time_days': days,
  'lead_time_receipts': receipts,
};

Future<void> _showCard(
  WidgetTester tester,
  List<Map<String, Object?>> rows, {
  String itemCode = 'ITEM',
  bool isTemplate = false,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: ItemSuppliersCard(
            itemCode: itemCode,
            isTemplate: isTemplate,
            loadReport: () async => SuppliersByItemNode.parseRows(rows),
            onViewReport: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _component(String bomId, String code, {String? name}) => {
  'node_id': 'component:$bomId|$code',
  'parent_id': bomId,
  'row_type': 'component',
  'item_code': code,
  'item_name': name,
  'is_component': 1,
};

void _expectPill(
  WidgetTester tester,
  String label, {
  required Brightness brightness,
  required Color ink,
  required Color base,
}) {
  final text = find.text(label);
  expect(tester.widget<Text>(text).style?.color, ink);
  final pill = find.ancestor(of: text, matching: find.byType(StatusPill));
  expect(pill, findsOneWidget);
  final containers = find.descendant(
    of: pill,
    matching: find.byType(Container),
  );
  final fills = tester
      .widgetList<Container>(containers)
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.color);
  expect(
    fills,
    containsAll([
      Color.alphaBlend(
        base.withValues(alpha: 0.13),
        AppScheme.of(brightness).fg,
      ),
      base,
    ]),
  );
}

class _ReportApi extends Fake implements ApiProvider {
  _ReportApi(this.rows);

  final List<Map<String, Object?>> rows;
  SuppliersByItemFilters? requestedFilters;

  @override
  Future<List<SuppliersByItemNode>> runSuppliersByItem(
    SuppliersByItemFilters filters,
  ) async {
    requestedFilters = filters;
    return SuppliersByItemNode.parseRows(rows);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Supplier status colours in ${brightness.name} mode', (
      tester,
    ) async {
      const hold = 'On Hold (All) until 2026-12-01';
      await _showCard(tester, [
        _item('ITEM'),
        _supplier('ITEM', 'Supplier A', status: 'Disabled'),
        _supplier('ITEM', 'Supplier B', status: hold),
        _supplier('ITEM', 'Supplier C', status: 'Active'),
        _supplier('ITEM', 'Supplier D'),
      ], brightness: brightness);

      final dark = brightness == Brightness.dark;
      _expectPill(
        tester,
        'Disabled',
        brightness: brightness,
        ink: dark ? AppColors.red300 : AppColors.red700,
        base: AppColors.red500,
      );
      _expectPill(
        tester,
        hold,
        brightness: brightness,
        ink: dark ? AppColors.orange300 : AppColors.orange700,
        base: AppColors.orange500,
      );
      expect(find.byType(StatusPill), findsNWidgets(2));
      expect(find.text('Active'), findsNothing);
    });
  }

  testWidgets('Item card shows stock and supplier procurement details', (
    tester,
  ) async {
    await _showCard(tester, [
      _item('ITEM', uom: 'Nos', balance: 1234.5, projected: -5.25),
      {
        ..._supplier(
          'ITEM',
          'Supplier A',
          uom: 'Nos',
          open: 12.5,
          days: 6.25,
          receipts: 4,
        ),
        'supplier_part_number': 'P-123',
      },
      _supplier('ITEM', 'Supplier B', uom: 'Nos', open: 0, days: 0),
    ]);

    expect(find.text('Balance: 1,234.5 Nos'), findsOneWidget);
    expect(find.text('Projected: -5.25 Nos'), findsOneWidget);
    expect(find.text('Part no. P-123'), findsOneWidget);
    expect(find.text('Open: 12.5 Nos'), findsOneWidget);
    expect(find.text('Open: 0 Nos'), findsNothing);
    expect(find.text('Lead time: 6.3 days (4 receipts)'), findsOneWidget);
    expect(find.text('Lead time: 0.0 days'), findsOneWidget);
    expect(find.text('Made from (BOM)'), findsNothing);
  });

  testWidgets('Item card uses singular and plural lead time labels', (
    tester,
  ) async {
    await _showCard(tester, [
      _item('ITEM'),
      _supplier('ITEM', 'Supplier A', days: 0, receipts: 0),
      _supplier('ITEM', 'Supplier B', days: 1, receipts: 1),
      _supplier('ITEM', 'Supplier C', days: 2, receipts: 2),
    ]);

    expect(find.text('Lead time: 0.0 days (0 receipts)'), findsOneWidget);
    expect(find.text('Lead time: 1.0 day (1 receipt)'), findsOneWidget);
    expect(find.text('Lead time: 2.0 days (2 receipts)'), findsOneWidget);
  });

  testWidgets('Item card previews direct BOMs and opens the expanded report', (
    tester,
  ) async {
    final api = _ReportApi([
      _item('ITEM', template: 'TEMPLATE'),
      {'node_id': 'template:TEMPLATE', 'row_type': 'template'},
      _supplier('ITEM', 'Finished Supplier'),
      {
        'node_id': 'bom:item:ITEM|first',
        'parent_id': 'item:ITEM',
        'row_type': 'bom',
        'bom_no': 'BOM-ITEM-001',
        'bom_is_default': 1,
        'is_component': 1,
      },
      {
        'node_id': 'component:first|1|subassembly',
        'parent_id': 'bom:item:ITEM|first',
        'row_type': 'component',
        'item_code': 'ASSEMBLY',
        'item_name': 'Subassembly',
        'is_component': 1,
      },
      {
        'node_id': 'supplier:component:first|1|subassembly|vendor',
        'parent_id': 'component:first|1|subassembly',
        'row_type': 'supplier',
        'supplier': 'VENDOR',
        'supplier_name': 'Component Supplier',
        'supplier_part_number': 'COMP-PART',
        'is_component': 1,
      },
      {
        'node_id': 'bom:component:first|1|subassembly|nested',
        'parent_id': 'component:first|1|subassembly',
        'row_type': 'bom',
        'bom_no': 'BOM-ASSEMBLY-001',
        'is_component': 1,
      },
      {
        'node_id': 'component:nested|1|raw',
        'parent_id': 'bom:component:first|1|subassembly|nested',
        'row_type': 'component',
        'item_code': 'RAW',
        'is_component': 1,
      },
      {
        'node_id': 'supplier:component:nested|1|raw|nested-vendor',
        'parent_id': 'component:nested|1|raw',
        'row_type': 'supplier',
        'supplier_name': 'Nested Supplier',
        'is_component': 1,
      },
      {
        'node_id': 'bom:item:ITEM|alternate',
        'parent_id': 'item:ITEM',
        'row_type': 'bom',
        'bom_no': 'BOM-ITEM-002',
        'bom_is_default': 1,
        'bom_status': 'Draft',
        'is_component': 1,
      },
      {
        'node_id': 'component:alternate|1|part',
        'parent_id': 'bom:item:ITEM|alternate',
        'row_type': 'component',
        'item_code': 'ALTERNATE',
        'is_component': 1,
      },
    ]);
    Get.put<ApiProvider>(api);
    Get.put(ItemProvider());
    addTearDown(Get.reset);
    final controller = ItemFormController();
    final item = Item.fromJson({'name': 'ITEM', 'item_code': 'ITEM'});
    SuppliersByItemFilters? openedFilters;
    await tester.pumpWidget(
      GetMaterialApp(
        getPages: [
          GetPage(
            name: '/',
            page: () => Scaffold(
              body: ItemSuppliersCard(
                itemCode: item.itemCode,
                isTemplate: item.hasVariants,
                loadReport: () => controller.loadSuppliers(item),
                onViewReport: (expandBom) =>
                    controller.openSuppliersReport(item, expandBom: expandBom),
              ),
            ),
          ),
          GetPage(
            name: AppRoutes.SUPPLIERS_BY_ITEM,
            page: () {
              openedFilters = Get.arguments as SuppliersByItemFilters;
              return const Scaffold(body: Text('Full report'));
            },
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    const expectedFilters = {
      'items': ['ITEM'],
      'include_drafts': 1,
      'expand_bom': 1,
    };
    expect(api.requestedFilters?.toJson(), expectedFilters);
    expect(find.text('Finished Supplier'), findsOneWidget);
    expect(find.text('Made from (BOM)'), findsOneWidget);
    expect(find.text('BOM-ITEM-001 · default'), findsOneWidget);
    expect(find.text('BOM-ITEM-002 · Draft'), findsOneWidget);
    final code = find.text('ASSEMBLY');
    final name = find.text('Subassembly');
    expect(code, findsOneWidget);
    expect(name, findsOneWidget);
    expect(tester.getTopLeft(code).dy, lessThan(tester.getTopLeft(name).dy));
    expect(find.text('ALTERNATE'), findsOneWidget);
    expect(find.text('Component Supplier'), findsOneWidget);
    expect(find.text('No supplier recorded'), findsOneWidget);
    expect(find.textContaining('COMP-PART'), findsNothing);
    expect(find.textContaining('BOM-ASSEMBLY-001'), findsNothing);
    expect(find.text('RAW'), findsNothing);
    expect(find.text('Nested Supplier'), findsNothing);

    await tester.tap(find.text('View full report'));
    await tester.pumpAndSettle();
    expect(find.text('Full report'), findsOneWidget);
    expect(openedFilters?.toJson(), expectedFilters);
  });

  for (final scale in [0.85, 1.3]) {
    testWidgets('Item card fits component labels at phone text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      const bomId = 'bom:item:ITEM|1';
      final longCode = 'LONG-COMPONENT-CODE-' * 5;
      final longName = 'Long component name with multiple words ' * 4 + 'end';
      await _showCard(tester, [
        _item('ITEM'),
        {
          'node_id': bomId,
          'parent_id': 'item:ITEM',
          'row_type': 'bom',
          'bom_no': 'BOM-ITEM-001',
          'is_component': 1,
        },
        _component(bomId, longCode, name: longName),
        _component(bomId, 'SAME', name: 'SAME'),
        _component(bomId, 'DASH', name: '-'),
        _component(bomId, 'BLANK', name: ' '),
      ]);

      for (final label in [longCode, longName, 'SAME', 'DASH', 'BLANK']) {
        final text = find.text(label);
        expect(text, findsOneWidget);
        expect(tester.getRect(text).right, lessThanOrEqualTo(1080 / 2.625));
      }
      expect(find.text('-'), findsNothing);
      expect(find.text(' '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Template combines quantities by UOM and weights lead times', (
    tester,
  ) async {
    const template = 'TEMPLATE';
    await _showCard(
      tester,
      [
        {'node_id': 'template:$template'},
        _item(template, uom: 'Nos', projected: 30),
        _supplier(template, 'Template supplier', uom: 'Nos', open: 100),
        {
          'node_id': 'bom:item:$template|1',
          'parent_id': 'item:$template',
          'row_type': 'bom',
          'bom_no': 'BOM-TEMPLATE-001',
          'is_component': 1,
        },
        _item('A', template: template, uom: 'Nos', projected: 1),
        _supplier('A', 'Supplier', uom: 'Nos', open: 3, days: 2, receipts: 1),
        {
          'node_id': 'bom:item:A|1',
          'parent_id': 'item:A',
          'row_type': 'bom',
          'bom_no': 'BOM-A-001',
          'is_component': 1,
        },
        _item('B', template: template, uom: 'Nos', projected: 2),
        _supplier('B', 'Supplier', uom: 'Nos', open: 4, days: 6, receipts: 3),
        _item('C', template: template, uom: 'Kg', projected: 3),
        _supplier('C', 'Supplier', uom: 'Kg', open: 8),
      ],
      itemCode: template,
      isTemplate: true,
    );

    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('Template supplier'), findsNothing);
    expect(find.text('Open: 7 Nos'), findsOneWidget);
    expect(find.text('Open: 8 Kg'), findsOneWidget);
    expect(find.text('Lead time: 5.0 days (4 receipts)'), findsOneWidget);
    expect(find.textContaining('Projected:'), findsNothing);
    expect(find.text('BOM-TEMPLATE-001'), findsOneWidget);
    expect(find.text('BOM-A-001'), findsNothing);
  });

  testWidgets('Template keeps variant lead times when a count is missing', (
    tester,
  ) async {
    const template = 'TEMPLATE';
    await _showCard(
      tester,
      [
        {
          'node_id': 'template:$template',
          'projected_qty': 9,
          'stock_uom': 'Nos',
        },
        _item('A', template: template, uom: 'Nos'),
        _supplier('A', 'Supplier', uom: 'Nos', days: 2, receipts: 1),
        _item('B', template: template, uom: 'Nos'),
        _supplier('B', 'Supplier', uom: 'Nos', days: 6),
      ],
      itemCode: template,
      isTemplate: true,
    );

    expect(find.text('Projected: 9 Nos'), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('A · Lead time: 2.0 days (1 receipt)'), findsOneWidget);
    expect(find.text('B · Lead time: 6.0 days'), findsOneWidget);
  });
}
