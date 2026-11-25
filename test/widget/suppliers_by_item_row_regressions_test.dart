import 'dart:ui' show Tristate;

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_layout.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_rows.dart';

typedef _Field = SuppliersByItemField;

Finder _row(String id) => find.byKey(ValueKey((nodeId: id)));

Finder _within(Finder row, String text) =>
    find.descendant(of: row, matching: find.text(text));

Finder _badge(Finder row, String label) =>
    find.descendant(of: row, matching: find.widgetWithText(StatusPill, label));

Finder _tile(bool Function(SuppliersByItemLayoutRow) matches) =>
    find.byWidgetPredicate(
      (widget) => widget is SuppliersByItemDisplayTile && matches(widget.entry),
    );

Future<void> _pumpRows(
  WidgetTester tester,
  List<Map<String, Object?>> fixture, {
  Size size = const Size(600, 900),
  double textScale = 1,
  List<_Field> showFields = const [],
  List<_Field> hideFields = const [],
  bool showFooter = false,
  bool showPlaceholders = true,
  bool groupBySupplier = false,
  bool expandAll = true,
  bool evidenceExpanded = true,
  bool collapseGroups = false,
  String query = '',
  bool supplierFilterActive = false,
  Brightness brightness = Brightness.light,
  ValueChanged<SuppliersByItemLayoutRow>? onBranch,
  ValueChanged<SuppliersByItemLayoutRow>? onEvidence,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final source = SuppliersByItemNode.parseRows(fixture);
  final index = indexReport(source);
  final projection = groupBySupplier
      ? buildSupplierView(index, showPlaceholders: showPlaceholders)
      : buildTemplateView(index, showPlaceholders: showPlaceholders);
  final expandable = structuralKeys(projection);
  final expanded = collapseGroups
      ? <SuppliersByItemRowKey>{}
      : expandAll
      ? expandable
      : {for (final entry in projection) entry.key};
  final visible = flattenTemplateView(
    projection,
    expanded,
    search: searchIndex(
      index,
      query,
      showPlaceholders: showPlaceholders,
      group: groupBySupplier
          ? SuppliersByItemGroup.supplier
          : SuppliersByItemGroup.template,
    ),
  );
  final fields = SuppliersByItemFieldVisibility({
    for (final field in hideFields) field.name: false,
    for (final field in showFields) field.name: true,
  });
  final columnRuns = suppliersByItemColumnRuns(visible.rows, fields.shows);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: ListView(
            children: [
              for (final entry in visible.rows)
                SuppliersByItemDisplayTile(
                  key: switch (entry.key) {
                    final SuppliersByItemSourceKey source => ValueKey(source),
                    final occurrence => ValueKey(occurrence),
                  },
                  entry: entry,
                  shows: fields.shows,
                  includeDrafts: true,
                  supplierFilterActive: supplierFilterActive,
                  expanded: expanded.contains(entry.key),
                  evidenceExpanded: evidenceExpanded,
                  onToggleBranch: expandable.contains(entry.key)
                      ? () => onBranch?.call(entry)
                      : null,
                  onToggleEvidence: () => onEvidence?.call(entry),
                  columnRun: columnRuns[entry.key],
                ),
              if (showFooter)
                SuppliersByItemFooter(
                  totals: SuppliersByItemNode.quantityTotalsByUom(source),
                  hasResults: true,
                  excludesUnknownUom: false,
                  bottomPadding: 0,
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _glyph(RenderParagraph paragraph, int offset) => paragraph
    .getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    )
    .single
    .toRect();

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'supplier grouping wraps pair identity, path, and separate controls in ${brightness.name}',
      (tester) async {
        const supplier = 'Supplier with a long returns and logistics name';
        const status = 'On Hold (Payments) until 2027-01-01';
        const item = 'ASSEMBLY-3000338';
        const component = 'COMPONENT-1004879';
        const bom = 'BOM-ASSEMBLY-3000338-001';
        const path = '$item › $bom › $component';
        final branchTaps = <SuppliersByItemLayoutRow>[];
        final evidenceTaps = <SuppliersByItemLayoutRow>[];
        await _pumpRows(
          tester,
          [
            {
              'node_id': 'item:KIT',
              'item_code': item,
              'open_order_qty': 1200,
              'draft_order_qty': 24,
              'stock_uom': 'Nos',
            },
            {
              'node_id': 'supplier:KIT:EDGE',
              'parent_id': 'item:KIT',
              'supplier': 'EDGE',
              'supplier_name': supplier,
              'last_purchase_date': '2025-10-01',
              'open_order_qty': 6,
              'stock_uom': 'Nos',
              'supplier_status': status,
            },
            {'node_id': 'bom:KIT', 'parent_id': 'item:KIT', 'bom_no': bom},
            {
              'node_id': 'component:PART',
              'parent_id': 'bom:KIT',
              'item_code': component,
              'bom_qty_per_unit': 0.004,
              'stock_uom': 'Kg',
            },
            {
              'node_id': 'supplier:PART:EDGE',
              'parent_id': 'component:PART',
              'supplier': 'EDGE',
              'supplier_name': supplier,
              'matched_supplier': 1,
              'last_purchase_date': '2026-11-10',
              'supplier_status': status,
              'stock_uom': 'Kg',
            },
          ],
          size: const Size(320, 2400),
          textScale: 2,
          groupBySupplier: true,
          expandAll: false,
          supplierFilterActive: true,
          brightness: brightness,
          onBranch: branchTaps.add,
          onEvidence: evidenceTaps.add,
          showFields: [_Field.itemOpenOrders, _Field.itemDraftOrders],
        );

        final direct = _tile(
          (row) => row.isPairOccurrence && !row.isComponentMatch,
        );
        final match = _tile((row) => row.isComponentMatch);
        expect(_within(direct, 'Last Purchase Date 1 Oct 25'), findsOneWidget);
        expect(_within(match, 'Last Purchase Date 10 Nov 26'), findsOneWidget);
        expect(_within(direct, 'Open Order Qty 1,200 Nos'), findsOneWidget);
        expect(_within(direct, 'Draft Order Qty 24 Nos'), findsOneWidget);
        expect(_within(direct, 'Open Order Qty'), findsOneWidget);
        expect(_within(direct, '6\u00a0Nos'), findsOneWidget);
        expect(_within(direct, 'Draft Order Qty'), findsNothing);
        expect(
          _within(match, 'BOM Qty per Unit 0.004 Kg per Nos'),
          findsOneWidget,
        );
        final breadcrumb = tester.renderObject<RenderParagraph>(
          _within(match, path),
        );
        expect(breadcrumb.didExceedMaxLines, isFalse);
        expect(
          _glyph(breadcrumb, path.length - 1).top,
          greaterThan(_glyph(breadcrumb, 0).top),
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              '^Component $component for item $item, $path, Supplier Name $supplier',
            ),
          ),
          findsOneWidget,
        );
        final group = find.bySemanticsLabel(
          'Supplier Name $supplier, Items 1, BOM components 1, Matches Suppliers filter, Supplier Status $status',
        );
        expect(group, findsOneWidget);
        final groupSemantics = tester.getSemantics(group).getSemanticsData();
        expect(groupSemantics.flagsCollection.isHeader, isTrue);
        expect(groupSemantics.flagsCollection.isExpanded, Tristate.isTrue);

        final (background, ink) = StatusPill.colourForStatus(
          'On Hold',
          brightness: brightness,
        );
        expect(_within(direct, status), findsNothing);
        expect(_within(match, status), findsNothing);
        expect(find.text(status), findsOneWidget);
        expect(tester.widget<Text>(find.text(status)).style!.color, ink);
        expect(
          ink,
          brightness == Brightness.light
              ? AppColors.orange700
              : AppColors.orange300,
        );
        final luminances = [
          background.computeLuminance(),
          ink.computeLuminance(),
        ]..sort();
        expect(
          (luminances.last + 0.05) / (luminances.first + 0.05),
          greaterThanOrEqualTo(4.5),
        );

        for (final label in ['Show BOM components', 'Hide supplier details']) {
          final button = find.descendant(
            of: direct,
            matching: find.widgetWithText(TextButton, label),
          );
          expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          final action = find.bySemanticsLabel(label);
          expect(action, findsOneWidget);
          expect(
            tester
                .getSemantics(action)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        expect(branchTaps.single.key, evidenceTaps.single.key);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'supplier grouping with all fields off keeps BOM navigation and signed totals',
    (tester) async {
      await _pumpRows(
        tester,
        [
          {'node_id': 'item:KIT', 'balance_qty': -2, 'stock_uom': 'Nos'},
          {
            'node_id': 'supplier:KIT:EDGE',
            'parent_id': 'item:KIT',
            'supplier': 'EDGE',
            'last_purchase_date': '2026-11-10',
            'open_order_qty': 1,
          },
          {'node_id': 'bom:KIT', 'parent_id': 'item:KIT', 'bom_no': 'BOM-KIT'},
          {
            'node_id': 'component:PART',
            'parent_id': 'bom:KIT',
            'item_code': 'PART',
            'balance_qty': 100,
            'stock_uom': 'Nos',
          },
          {
            'node_id': 'supplier:PART:EDGE',
            'parent_id': 'component:PART',
            'supplier': 'EDGE',
          },
          {'node_id': 'item:OTHER', 'balance_qty': 5, 'stock_uom': 'Nos'},
          {
            'node_id': 'none:OTHER',
            'parent_id': 'item:OTHER',
            'tree_label': 'Legacy placeholder for OTHER',
          },
        ],
        size: const Size(600, 900),
        groupBySupplier: true,
        hideFields: _Field.values,
        showFooter: true,
      );

      expect(
        _within(
          _tile((row) => row.group?.label == 'No supplier recorded'),
          'No supplier recorded',
        ),
        findsOneWidget,
      );
      expect(
        _within(
          _tile(
            (row) => row.node.row.kind == SuppliersByItemRowKind.placeholder,
          ),
          'No supplier recorded',
        ),
        findsOneWidget,
      );
      expect(find.text('Legacy placeholder for OTHER'), findsNothing);
      expect(find.text('Hide BOM components'), findsOneWidget);
      expect(find.text('Component PART for KIT'), findsOneWidget);
      expect(find.text('KIT › BOM-KIT › PART'), findsOneWidget);
      expect(find.text('Items 1'), findsNothing);
      expect(find.text('BOM components 1'), findsNothing);
      expect(
        find.textContaining(RegExp(r'^Last Purchase Date \d+ \w+ \d+$')),
        findsNothing,
      );
      expect(find.text('Last Purchase Date -'), findsNWidgets(2));
      expect(find.textContaining('supplier details'), findsNothing);
      expect(find.text('Open Order Qty'), findsNothing);
      expect(
        find.text('End of list · Totals for all loaded items'),
        findsOneWidget,
      );
      expect(
        _within(find.byType(SuppliersByItemFooter), '3 Nos'),
        findsOneWidget,
      );
    },
  );

  testWidgets('footer aligns totals, mutes zeros and wraps UOM pairs at 2x', (
    tester,
  ) async {
    const fixture = [
      {'node_id': 'item:K', 'balance_qty': 1234.5, 'stock_uom': 'Kg'},
      {'node_id': 'item:M', 'balance_qty': 123, 'stock_uom': 'M'},
      {
        'node_id': 'item:N',
        'balance_qty': 5678.5,
        'projected_qty': 0,
        'stock_uom': 'Nos',
      },
    ];
    final footer = find.byType(SuppliersByItemFooter);
    final heading = _within(
      footer,
      'End of list · Totals for all loaded items',
    );
    final label = _within(footer, 'Balance Qty');
    final kg = _within(footer, '1,234.5 Kg');
    final nos = _within(footer, '5,678.5 Nos');
    final zero = _within(footer, '0 Nos');
    await _pumpRows(tester, fixture, showFooter: true);
    expect(heading, findsOneWidget);
    expect(tester.getTopLeft(label).dy, tester.getTopLeft(kg).dy);
    expect(tester.getTopRight(nos).dx, tester.getTopRight(zero).dx);
    final colors = tester.element(zero).scheme;
    expect(tester.widget<Text>(kg).style!.color, colors.text);
    expect(tester.widget<Text>(zero).style!.color, colors.textMuted);
    expect(
      tester.widget<Text>(zero).style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    await _pumpRows(
      tester,
      fixture,
      showFooter: true,
      textScale: 2,
      size: const Size(320, 900),
    );
    expect(tester.getTopLeft(kg).dy, greaterThan(tester.getTopLeft(label).dy));
    expect(tester.getTopLeft(nos).dy, greaterThan(tester.getTopLeft(kg).dy));
    for (final amount in [kg, nos]) {
      final paragraph = tester.renderObject<RenderParagraph>(amount);
      final lastGlyph = tester.widget<Text>(amount).data!.length - 1;
      expect(_glyph(paragraph, 0).top, _glyph(paragraph, lastGlyph).top);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained supplier group counts distinguish direct and component rows',
    (tester) async {
      await _pumpRows(
        tester,
        [
          for (final code in ['OWNER-AX', 'OWNER-BY']) ...[
            {'node_id': 'item:$code', 'item_code': code},
            {
              'node_id': 'supplier:$code:S',
              'parent_id': 'item:$code',
              'supplier': 'S',
            },
          ],
          {'node_id': 'item:OWNER-CZ', 'item_code': 'OWNER-CZ'},
          {'node_id': 'bom:CZ', 'parent_id': 'item:OWNER-CZ'},
          {'node_id': 'component:CZ', 'parent_id': 'bom:CZ'},
          {
            'node_id': 'supplier:CZ:S',
            'parent_id': 'component:CZ',
            'supplier': 'S',
          },
        ],
        groupBySupplier: true,
        query: 'OWNER-AX',
      );
      final group = _tile((row) => row.group?.label == 'S');
      expect(_within(group, 'Items 1 of 2'), findsOneWidget);
      expect(_within(group, 'BOM components 0 of 1'), findsOneWidget);
      expect(find.text('OWNER-AX'), findsOneWidget);
      expect(find.text('OWNER-BY'), findsNothing);
      expect(_tile((row) => row.isComponentMatch), findsNothing);
    },
  );

  testWidgets(
    'collapsed groups show shared status and mixed status stays on pairs',
    (tester) async {
      final fixture = [
        for (final code in ['A', 'B']) ...[
          {'node_id': 'item:$code', 'item_code': code},
          {
            'node_id': 'supplier:$code:SHARED',
            'parent_id': 'item:$code',
            'supplier': 'SHARED',
            'supplier_status': 'Disabled',
            if (code == 'A') 'open_order_qty': 1,
            if (code == 'B') 'draft_order_qty': 2,
          },
          {
            'node_id': 'supplier:$code:MIXED',
            'parent_id': 'item:$code',
            'supplier': 'MIXED',
            'supplier_status': code == 'A' ? 'On Hold' : 'Disabled',
          },
        ],
      ];
      final shared = _tile((row) => row.group?.label == 'SHARED');
      final mixed = _tile((row) => row.group?.label == 'MIXED');
      final sharedPairs = _tile(
        (row) => row.isPairOccurrence && row.supplierLabel == 'SHARED',
      );
      final mixedPairs = _tile(
        (row) => row.isPairOccurrence && row.supplierLabel == 'MIXED',
      );
      await _pumpRows(
        tester,
        fixture,
        groupBySupplier: true,
        collapseGroups: true,
      );
      expect(_within(shared, 'Disabled'), findsOneWidget);
      expect(_within(mixed, 'Disabled'), findsNothing);
      expect(sharedPairs, findsNothing);

      await _pumpRows(tester, fixture, groupBySupplier: true);
      expect(_within(sharedPairs, 'Disabled'), findsNothing);
      expect(
        _badge(sharedPairs, 'Open Order Qty 1 (Stock UOM unavailable)'),
        findsNothing,
      );
      expect(
        _badge(sharedPairs, 'Draft Order Qty 2 (Stock UOM unavailable)'),
        findsOneWidget,
      );
      expect(_within(mixedPairs, 'Disabled'), findsOneWidget);
      expect(_within(mixedPairs, 'On Hold'), findsOneWidget);

      await _pumpRows(
        tester,
        fixture,
        groupBySupplier: true,
        hideFields: [_Field.supplierStatus],
      );
      expect(_within(shared, 'Disabled'), findsOneWidget);
      expect(_within(mixedPairs, 'Disabled'), findsOneWidget);
      expect(_within(mixedPairs, 'On Hold'), findsOneWidget);
      expect(sharedPairs, findsNWidgets(2));
      expect(mixedPairs, findsNWidgets(2));
      expect(
        _badge(sharedPairs, 'Open Order Qty 1 (Stock UOM unavailable)'),
        findsNothing,
      );
      expect(
        _badge(sharedPairs, 'Draft Order Qty 2 (Stock UOM unavailable)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'grouped pair semantics identify the supplier and disambiguating code',
    (tester) async {
      await _pumpRows(
        tester,
        [
          {'node_id': 'item:KIT', 'item_code': 'KIT'},
          for (final supplier in ['A', 'B'])
            {
              'node_id': 'supplier:KIT:$supplier',
              'parent_id': 'item:KIT',
              'supplier': supplier,
              'supplier_name': 'Same name',
            },
        ],
        groupBySupplier: true,
        hideFields: _Field.values,
      );
      for (final supplier in ['A', 'B']) {
        expect(find.text('Same name ($supplier)'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Item KIT, Supplier Name Same name ($supplier), '
            'Last Purchase Date unavailable',
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'supplier semantics distinguish names from IDs and fallback labels',
    (tester) async {
      final fixture = [
        {'node_id': 'item:A'},
        {
          'node_id': 'supplier:A:SHARED',
          'parent_id': 'item:A',
          'supplier': 'SHARED',
        },
        {
          'node_id': 'supplier:A:ID-ONLY',
          'parent_id': 'item:A',
          'supplier': 'ID-ONLY',
        },
        {
          'node_id': 'unresolved-A',
          'row_type': 'supplier',
          'parent_id': 'item:A',
          'tree_label': 'Imported vendor',
        },
        {'node_id': 'item:B'},
        {
          'node_id': 'supplier:B:SHARED',
          'parent_id': 'item:B',
          'supplier': 'SHARED',
          'supplier_name': 'Vendor Name',
        },
      ];
      await _pumpRows(tester, fixture, hideFields: _Field.values);
      for (final label in [
        'Item / Supplier SHARED',
        'Item / Supplier ID-ONLY',
        'Item / Supplier Imported vendor',
        'Supplier Name Vendor Name',
      ]) {
        expect(
          find.bySemanticsLabel('$label, Last Purchase Date unavailable'),
          findsOneWidget,
        );
      }
      await _pumpRows(
        tester,
        fixture,
        groupBySupplier: true,
        hideFields: _Field.values,
      );
      for (final label in [
        'Supplier Name Vendor Name',
        'Item A, Supplier Name Vendor Name, Last Purchase Date unavailable',
        'Item B, Supplier Name Vendor Name, Last Purchase Date unavailable',
        'Item / Supplier ID-ONLY',
        'Item A, Item / Supplier ID-ONLY, Last Purchase Date unavailable',
        'Item / Supplier Imported vendor',
        'Item A, Item / Supplier Imported vendor, Last Purchase Date unavailable',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
    },
  );

  testWidgets(
    'shows the no-supplier message once whether the placeholder is kept or omitted',
    (tester) async {
      final fixture = [
        {'node_id': 'template:STYLE'},
        {'node_id': 'item:A', 'parent_id': 'template:STYLE'},
        {
          'node_id': 'item:B',
          'parent_id': 'template:STYLE',
          'supplier_count': 2,
        },
        {'node_id': 'none:A', 'parent_id': 'item:A'},
      ];
      const message = 'No supplier recorded';
      for (final (open, showPlaceholders) in [
        (true, true),
        (false, true),
        (true, false),
      ]) {
        await _pumpRows(
          tester,
          fixture,
          expandAll: open,
          showPlaceholders: showPlaceholders,
        );
        final usesChild = open && showPlaceholders;
        expect(find.text(message), findsOneWidget);
        expect(
          _within(_row(usesChild ? 'none:A' : 'item:A'), message),
          findsOneWidget,
        );
        expect(_within(_row('item:B'), message), findsNothing);
      }
    },
  );

  testWidgets('component match details use the exact supplier purchase date', (
    tester,
  ) async {
    final fixture = [
      {'node_id': 'item:KIT', 'item_code': 'KIT'},
      {'node_id': 'bom:KIT', 'parent_id': 'item:KIT'},
      {
        'node_id': 'component:PART',
        'parent_id': 'bom:KIT',
        'item_code': 'PART',
        'last_purchase_date': '2026-03-01',
      },
      for (final (supplier, date) in [
        ('A', '2026-03-01'),
        ('B', '2026-01-01'),
        ('C', null),
      ])
        {
          'node_id': 'supplier:PART:$supplier',
          'parent_id': 'component:PART',
          'supplier': supplier,
          'last_purchase_date': date,
        },
    ];
    await _pumpRows(
      tester,
      fixture,
      groupBySupplier: true,
      showFields: [_Field.componentLastPurchase],
      hideFields: [_Field.supplierLastBuyColumn],
    );
    Finder pair(String supplier) =>
        _tile((row) => row.isComponentMatch && row.supplierLabel == supplier);
    expect(_within(pair('A'), 'Last Purchase Date 2026-03-01'), findsOneWidget);
    expect(_within(pair('B'), 'Last Purchase Date 2026-01-01'), findsOneWidget);
    expect(_within(pair('B'), 'Last Purchase Date 2026-03-01'), findsNothing);
    expect(_within(pair('C'), 'Last Purchase Date 2026-03-01'), findsNothing);
    expect(
      find.textContaining(RegExp(r'^Last Purchase Date \d+ \w+ \d+$')),
      findsNothing,
    );
    expect(_within(pair('C'), 'Last Purchase Date -'), findsOneWidget);

    await _pumpRows(
      tester,
      fixture,
      showFields: [_Field.componentLastPurchase],
    );
    expect(
      _within(_row('component:PART'), 'Last Purchase Date 2026-03-01'),
      findsOneWidget,
    );
  });

  testWidgets(
    'grouped quantities have visible and spoken item and supplier sections',
    (tester) async {
      await _pumpRows(
        tester,
        [
          {
            'node_id': 'item:KIT',
            'item_code': 'KIT',
            'stock_uom': 'Nos',
            'total_qty_received': 10,
            'open_order_qty': 12,
            'draft_order_qty': 8,
          },
          for (final (supplier, quantity) in [('A', 3), ('B', 7)])
            {
              'node_id': 'supplier:KIT:$supplier',
              'parent_id': 'item:KIT',
              'supplier': supplier,
              'supplier_name': 'Supplier $supplier',
              'stock_uom': 'Nos',
              'total_qty_received': quantity,
              'open_order_qty': quantity,
              'draft_order_qty': quantity,
            },
        ],
        groupBySupplier: true,
        showFields: [
          _Field.itemQtyReceived,
          _Field.supplierQtyReceived,
          _Field.itemOpenOrders,
          _Field.itemDraftOrders,
          _Field.supplierDraftOrders,
        ],
      );
      for (final (supplier, quantity) in [('A', 3), ('B', 7)]) {
        final pair = _tile(
          (row) =>
              row.isPairOccurrence && row.supplierLabel == 'Supplier $supplier',
        );
        final itemTitle = _within(pair, 'Item');
        final supplierTitle = _within(pair, 'Supplier $supplier');
        expect(itemTitle, findsOneWidget);
        expect(supplierTitle, findsOneWidget);
        for (final (header, itemQuantity) in [
          ('Total Qty Received', 10),
          ('Open Order Qty', 12),
          ('Draft Order Qty', 8),
        ]) {
          final itemValue = _within(pair, '$header $itemQuantity Nos');
          final supplierHeader = _within(pair, header);
          expect(itemValue, findsOneWidget);
          expect(supplierHeader, findsOneWidget);
          expect(
            tester.getTopLeft(itemValue).dy,
            greaterThan(tester.getTopLeft(itemTitle).dy),
          );
          expect(
            tester.getTopLeft(itemValue).dy,
            lessThan(tester.getTopLeft(supplierTitle).dy),
          );
          expect(
            tester.getTopLeft(supplierHeader).dy,
            greaterThan(tester.getTopLeft(supplierTitle).dy),
          );
        }
        expect(_within(pair, '$quantity\u00a0Nos'), findsNWidgets(3));
        expect(
          find.bySemanticsLabel(
            RegExp(
              'Supplier Name Supplier $supplier.*Item,.*Total Qty Received 10 Nos',
            ),
          ),
          findsOneWidget,
        );
        final spokenTitle = tester
            .getSemantics(supplierTitle)
            .getSemanticsData();
        expect(spokenTitle.label, 'Supplier $supplier');
        expect(spokenTitle.flagsCollection.isHeader, isTrue);
      }
    },
  );

  testWidgets(
    'dated and undated sibling suppliers reflow to the same Last Purchase Date edge',
    (tester) async {
      await _pumpRows(tester, [
        {'node_id': 'item:ITEM'},
        {
          'node_id': 'supplier:ITEM:NONE',
          'parent_id': 'item:ITEM',
          'supplier': 'Date unavailable',
        },
        {
          'node_id': 'supplier:ITEM:DATE',
          'parent_id': 'item:ITEM',
          'supplier': 'Date available',
          'last_purchase_date': '2025-11-10',
          'open_order_qty': 1,
          'stock_uom': 'Kg',
        },
      ], textScale: 2);

      final rightEdges = <double>[];
      for (final (identity, label) in [
        ('Date unavailable', 'Last Purchase Date -'),
        ('Date available', 'Last Purchase Date 10 Nov 25'),
      ]) {
        final date = find.text(label);
        expect(
          tester.getTopLeft(date).dy,
          closeTo(tester.getBottomLeft(find.text(identity)).dy, 0.5),
        );
        final paragraph = tester.renderObject<RenderParagraph>(date);
        rightEdges.add(
          paragraph
              .localToGlobal(_glyph(paragraph, label.length - 1).topRight)
              .dx,
        );
      }
      expect(rightEdges.first, closeTo(rightEdges.last, 0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tiny signed row quantities stay nonzero and footer totals sum raw values',
    (tester) async {
      await _pumpRows(
        tester,
        [
          for (final item in ['A', 'B']) ...[
            {
              'node_id': 'item:$item',
              'open_order_qty': 0.004,
              'draft_order_qty': 0.004,
              'projected_qty': item == 'A' ? -0.004 : null,
              'stock_uom': 'Kg',
            },
            {
              'node_id': 'supplier:$item:SUPPLIER',
              'parent_id': 'item:$item',
              'supplier': 'Supplier $item',
              'open_order_qty': 0.004,
              'draft_order_qty': item == 'A' ? 0.004 : -0.004,
              'stock_uom': 'Kg',
            },
          ],
        ],
        showFields: [
          _Field.itemOpenOrders,
          _Field.itemDraftOrders,
          _Field.itemProjected,
          _Field.supplierDraftOrders,
        ],
        showFooter: true,
      );

      for (final item in ['A', 'B']) {
        final top = _row('item:$item');
        final supplier = _row('supplier:$item:SUPPLIER');
        expect(_badge(top, 'Open Order Qty 0.004 Kg'), findsNothing);
        expect(_badge(top, 'Draft Order Qty 0.004 Kg'), findsNothing);
        expect(_within(top, 'Open Order Qty 0.004 Kg'), findsOneWidget);
        expect(_within(top, 'Draft Order Qty 0.004 Kg'), findsOneWidget);
        expect(_badge(supplier, 'Open Order Qty 0.004 Kg'), findsNothing);
        expect(_within(supplier, '0.004\u00a0Kg'), findsWidgets);
      }
      final positive = _row('supplier:A:SUPPLIER');
      expect(_badge(positive, 'Draft Order Qty 0.004 Kg'), findsNothing);
      expect(_within(positive, '0.004\u00a0Kg'), findsNWidgets(2));
      final negative = _row('supplier:B:SUPPLIER');
      expect(_badge(negative, 'Draft Order Qty -0.004 Kg'), findsNothing);
      expect(_within(negative, '-0.004\u00a0Kg'), findsOneWidget);

      final footer = find.byType(SuppliersByItemFooter);
      expect(_within(footer, '0.01 Kg'), findsNWidgets(2));
      expect(_within(footer, '-0.004 Kg'), findsOneWidget);
      expect(_within(footer, '0 Kg'), findsNothing);
    },
  );

  testWidgets(
    'order badges show and announce values and yield to visible details',
    (tester) async {
      final fixture = [
        {
          'node_id': 'item:KIT',
          'open_order_qty': 12,
          'draft_order_qty': 8,
          'stock_uom': 'Nos',
        },
        {
          'node_id': 'supplier:KIT:VENDOR',
          'parent_id': 'item:KIT',
          'supplier': 'VENDOR',
          'open_order_qty': 4,
          'draft_order_qty': 2,
          'stock_uom': 'Nos',
        },
      ];
      final item = _row('item:KIT');
      final supplier = _row('supplier:KIT:VENDOR');
      await _pumpRows(tester, fixture, evidenceExpanded: false);
      for (final (row, open, draft) in [(item, 12, 8), (supplier, 4, 2)]) {
        expect(_badge(row, 'Open Order Qty $open Nos'), findsOneWidget);
        expect(_badge(row, 'Draft Order Qty $draft Nos'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            RegExp('Open Order Qty $open Nos, Draft Order Qty $draft Nos'),
          ),
          findsOneWidget,
        );
      }
      await _pumpRows(
        tester,
        fixture,
        showFields: [_Field.itemOpenOrders, _Field.supplierDraftOrders],
        hideFields: [_Field.itemStockUom, _Field.supplierStockUom],
      );
      expect(_within(item, 'Open Order Qty 12'), findsOneWidget);
      expect(_badge(item, 'Open Order Qty 12'), findsNothing);
      expect(_badge(item, 'Draft Order Qty 8'), findsOneWidget);
      expect(_badge(supplier, 'Open Order Qty 4'), findsNothing);
      expect(_badge(supplier, 'Draft Order Qty 2'), findsNothing);
      expect(_within(supplier, 'Open Order Qty'), findsOneWidget);
      expect(_within(supplier, 'Draft Order Qty'), findsOneWidget);
      expect(_within(supplier, '4'), findsOneWidget);
      expect(_within(supplier, '2'), findsOneWidget);
    },
  );

  testWidgets(
    'supplier quantity and unit move together below the label at 412dp and 2x',
    (tester) async {
      await _pumpRows(
        tester,
        [
          {'node_id': 'item:ITEM'},
          {
            'node_id': 'supplier:ITEM:SUPPLIER',
            'parent_id': 'item:ITEM',
            'supplier': 'Supplier',
            'open_order_qty': 999999.25,
            'stock_uom': 'Kg',
          },
        ],
        size: const Size(412, 900),
        textScale: 2,
        hideFields: [_Field.supplierOpenPoBadge],
      );

      const text = '999,999.25\u00a0Kg';
      final amount = find.text(text);
      final caption = find.text('Open Order Qty');
      expect(
        tester.getTopLeft(amount).dy,
        closeTo(tester.getBottomLeft(caption).dy, 0.5),
      );
      final paragraph = tester.renderObject<RenderParagraph>(amount);
      expect(_glyph(paragraph, 0).top, _glyph(paragraph, text.length - 1).top);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('qualified supplier hold status wraps at depth three and 2x', (
    tester,
  ) async {
    const status = 'On Hold (Payments) until 2027-01-01';
    await _pumpRows(
      tester,
      [
        {'node_id': 'item:KIT'},
        {'node_id': 'bom:KIT', 'parent_id': 'item:KIT'},
        {'node_id': 'component:PART', 'parent_id': 'bom:KIT'},
        {
          'node_id': 'supplier:PART:SUPPLIER',
          'parent_id': 'component:PART',
          'supplier': 'Supplier',
          'supplier_status': status,
        },
      ],
      size: const Size(412, 900),
      textScale: 2,
    );

    final row = _row('supplier:PART:SUPPLIER');
    expect(tester.widget<SuppliersByItemDisplayTile>(row).entry.depth, 3);
    final text = _within(row, status);
    expect(tester.widget<Text>(text).style!.fontSize, greaterThanOrEqualTo(11));
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      _glyph(paragraph, status.length - 1).top,
      greaterThan(_glyph(paragraph, 0).top),
    );
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(status))),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('receipt lines without lead-time days keep their own label', (
    tester,
  ) async {
    await _pumpRows(
      tester,
      [
        {'node_id': 'item:KIT'},
        {
          'node_id': 'supplier:KIT:VENDOR',
          'parent_id': 'item:KIT',
          'supplier': 'Vendor',
          'lead_time_receipts': 9,
          'receipt_count': 3,
        },
      ],
      showFields: [
        _Field.supplierLeadTime,
        _Field.supplierLeadTimeReceipts,
        _Field.supplierReceiptCount,
      ],
    );

    final supplier = _row('supplier:KIT:VENDOR');
    expect(_within(supplier, 'Lead Time (Days)'), findsNothing);
    final lines = _within(supplier, 'Lead Time Receipts');
    final receipts = _within(supplier, 'Receipt Count');
    expect(
      tester.getTopLeft(_within(supplier, '9')).dy,
      tester.getTopLeft(lines).dy,
    );
    expect(
      tester.getTopLeft(_within(supplier, '3')).dy,
      tester.getTopLeft(receipts).dy,
    );
  });
}
