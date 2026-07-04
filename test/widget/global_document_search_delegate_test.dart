import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';
import 'package:multimax/main.dart' show buildAppTheme;

GlobalSearchTarget _target(String d) => GlobalSearchTarget(
      doctype: d,
      label: '$d s',
      icon: Icons.circle,
      color: Colors.blue,
      route: '/x',
      argsFor: (id) => {'name': id},
    );

void main() {
  testWidgets('renders group headers, rows, and fires onTap', (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-1', title: 'Blue Strap', rawData: const {}),
      ]),
      GlobalSearchGroup(target: _target('Delivery Note'), items: [
        GlobalSearchItem(id: 'KA-DN-1', title: 'Acme', rawData: const {}),
      ]),
    ];

    GlobalSearchTarget? tappedTarget;
    GlobalSearchItem? tappedItem;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {
              tappedTarget = t;
              tappedItem = i;
            },
          ),
        ),
      ),
    ));

    // Section headers
    expect(find.text('ITEM S'), findsOneWidget);
    expect(find.text('DELIVERY NOTE S'), findsOneWidget);
    // Rows
    expect(find.text('Blue Strap'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);

    await tester.tap(find.text('Blue Strap'));
    expect(tappedTarget?.doctype, 'Item');
    expect(tappedItem?.id, 'FG-1');
  });

  testWidgets(
      'stays service-free (no ApiProvider) even when an item has an imageUrl',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(
          id: 'FG-1',
          title: 'Blue Strap',
          imageUrl: '/files/x.png',
          rawData: const {},
        ),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
          ),
        ),
      ),
    ));

    // No Get.find<ApiProvider>() call should have been triggered synchronously
    // during build, so nothing should have thrown.
    expect(tester.takeException(), isNull);
    // Falls back to the icon avatar tile; the title still renders.
    expect(find.text('Blue Strap'), findsOneWidget);
  });

  testWidgets('scope chips render All + a chip per target and report taps',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final targets = [_target('Item'), _target('Delivery Note')];

    GlobalSearchTarget? selected; // starts null (All)
    var selectCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildScopeChips(
            context,
            targets,
            selected,
            (t) {
              selected = t;
              selectCalls++;
            },
          ),
        ),
      ),
    ));

    // "All" plus one chip per target.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Item s'), findsOneWidget);
    expect(find.text('Delivery Note s'), findsOneWidget);

    // Tapping a doctype chip reports that target.
    await tester.tap(find.text('Item s'));
    expect(selectCalls, 1);
    expect(selected?.doctype, 'Item');

    // Tapping "All" reports null (clears the scope).
    await tester.tap(find.text('All'));
    expect(selectCalls, 2);
    expect(selected, isNull);
  });

  testWidgets('Item row shows the inline warehouse balance and no chevron',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-1', title: 'Blue Strap', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            balances: const {
              'FG-1': WarehouseStockLine(
                  itemCode: 'FG-1',
                  itemName: 'Blue Strap',
                  balanceQty: 12,
                  uom: 'Nos'),
            },
          ),
        ),
      ),
    ));

    expect(find.text('12 Nos'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('Item row shows a loader while balances are loading',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-1', title: 'Blue Strap', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            balancesLoading: true,
          ),
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('Item with no stock row shows 0 once balances are loaded',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-9', title: 'Ghost Item', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            balances: const <String, WarehouseStockLine>{}, // loaded, empty
          ),
        ),
      ),
    ));

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('non-Item row keeps the chevron even when balances are present',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Delivery Note'), items: [
        GlobalSearchItem(id: 'KA-DN-1', title: 'Acme', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            balances: const {
              'KA-DN-1': WarehouseStockLine(
                  itemCode: 'KA-DN-1', itemName: '', balanceQty: 5, uom: 'Nos'),
            },
          ),
        ),
      ),
    ));

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.text('5 Nos'), findsNothing);
  });

  testWidgets('scope chip reflects the selected target', (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final targets = [_target('Item'), _target('Delivery Note')];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildScopeChips(
            context,
            targets,
            targets.first, // 'Item' selected
            (_) {},
          ),
        ),
      ),
    ));

    // The selected chip is the 'Item' one, and 'All' is not selected.
    final itemChip = tester.widget<ChoiceChip>(
      find.ancestor(
          of: find.text('Item s'), matching: find.byType(ChoiceChip)),
    );
    final allChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('All'), matching: find.byType(ChoiceChip)),
    );
    expect(itemChip.selected, isTrue);
    expect(allChip.selected, isFalse);
  });

  // ── _ScopedResults pagination ──────────────────────────────────────────────
  // Uses the public test entrypoint the delegate exposes for the scoped list.
  testWidgets('scoped results load page 1, then load more on scroll to the end',
      (tester) async {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    final calls = <List<int>>[];
    Future<List<GlobalSearchItem>> fetchPage(int start, int size) async {
      calls.add([start, size]);
      final n = start == 0 ? 20 : 5; // page 2 is short → end of list
      final tag = start == 0 ? 'A' : 'B';
      return List.generate(
        n,
        (i) => GlobalSearchItem(id: '$tag$i', title: 'Item $tag$i', rawData: const {}),
      );
    }

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: scopedResultsForTest(
          target: _target('Item'),
          query: 'belts reversible',
          fetchPage: fetchPage,
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(calls, [
      [0, 20]
    ]);
    expect(find.text('Item A0'), findsOneWidget);

    // Scroll to the bottom → triggers load-more.
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(calls.any((c) => c[0] == 20), isTrue); // page 2 requested at offset 20

    // Page 2 landed, so the list is now longer and the drag above only
    // reached the *old* bottom — the footer is further down and not yet
    // built. Drag again to reach the new (grown) bottom so it's visible.
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(find.text('End of results'), findsOneWidget);
  });

  testWidgets('scoped results: a short first page shows End of results',
      (tester) async {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    Future<List<GlobalSearchItem>> fetchPage(int start, int size) async =>
        List.generate(
            3, (i) => GlobalSearchItem(id: 'X$i', title: 'X$i', rawData: const {}));

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: scopedResultsForTest(
          target: _target('Item'),
          query: 'belts',
          fetchPage: fetchPage,
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('X0'), findsOneWidget);
    expect(find.text('End of results'), findsOneWidget);
  });

  testWidgets('scoped results: empty first page shows the no-documents message',
      (tester) async {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    Future<List<GlobalSearchItem>> fetchPage(int start, int size) async => [];

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: scopedResultsForTest(
          target: _target('Item'),
          query: 'zzz',
          fetchPage: fetchPage,
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No documents found'), findsOneWidget);
  });

  testWidgets('scoped results: a balance-fetch failure still shows the items',
      (tester) async {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    Future<List<GlobalSearchItem>> fetchPage(int start, int size) async =>
        List.generate(3,
            (i) => GlobalSearchItem(id: 'B$i', title: 'Belt $i', rawData: const {}));
    Future<Map<String, WarehouseStockLine>> fetchBalances(
            List<String> codes) async =>
        throw Exception('stock 403');

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: scopedResultsForTest(
          target: _target('Item'),
          query: 'belt',
          fetchPage: fetchPage,
          fetchBalances: fetchBalances,
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Belt 0'), findsOneWidget); // items shown despite balance failure
    expect(find.textContaining('Search failed'), findsNothing);
    expect(find.text('End of results'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsWidgets); // rows show chevron ("unknown"), not "0"
    expect(find.text('0'), findsNothing);
  });
}
