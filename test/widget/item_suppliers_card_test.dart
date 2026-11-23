// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
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
  bool isTemplate = false,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: ItemSuppliersCard(
          isTemplate: isTemplate,
          loadReport: () async => SuppliersByItemNode.parseRows(rows),
          onViewReport: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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
  });

  testWidgets('Template combines quantities by UOM and weights lead times', (
    tester,
  ) async {
    const template = 'TEMPLATE';
    await _showCard(tester, [
      {'node_id': 'template:$template'},
      _item('A', template: template, uom: 'Nos', projected: 1),
      _supplier('A', 'Supplier', uom: 'Nos', open: 3, days: 2, receipts: 1),
      _item('B', template: template, uom: 'Nos', projected: 2),
      _supplier('B', 'Supplier', uom: 'Nos', open: 4, days: 6, receipts: 3),
      _item('C', template: template, uom: 'Kg', projected: 3),
      _supplier('C', 'Supplier', uom: 'Kg', open: 8),
    ], isTemplate: true);

    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('Open: 7 Nos'), findsOneWidget);
    expect(find.text('Open: 8 Kg'), findsOneWidget);
    expect(find.text('Lead time: 5.0 days (4 receipts)'), findsOneWidget);
    expect(find.textContaining('Projected:'), findsNothing);
  });

  testWidgets('Template keeps variant lead times when a count is missing', (
    tester,
  ) async {
    const template = 'TEMPLATE';
    await _showCard(tester, [
      {'node_id': 'template:$template', 'projected_qty': 9, 'stock_uom': 'Nos'},
      _item('A', template: template, uom: 'Nos'),
      _supplier('A', 'Supplier', uom: 'Nos', days: 2, receipts: 1),
      _item('B', template: template, uom: 'Nos'),
      _supplier('B', 'Supplier', uom: 'Nos', days: 6),
    ], isTemplate: true);

    expect(find.text('Projected: 9 Nos'), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('A · Lead time: 2.0 days (1 receipts)'), findsOneWidget);
    expect(find.text('B · Lead time: 6.0 days'), findsOneWidget);
  });
}
