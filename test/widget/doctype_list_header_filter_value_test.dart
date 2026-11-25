// Regression test for a stale filter chip in the shared list/report header
// (seen on-device in 2.36.0+117 on the Item Variant Details report, 15/11/2026).
//
// Picking Item A, then reopening the filter and running the report for Item B
// left the chip reading "Item: A" until the header next rebuilt (e.g. a
// scroll collapsing it). The filter count stayed at one, and the delegate's
// shouldRebuild compared filters by count only, so SliverPersistentHeader
// kept its cached child even though a new delegate had been built.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';

List<Widget> _chips(RxMap<String, String> filters) => [
      for (final label in filters.values) Chip(label: Text(label)),
    ];

void main() {
  testWidgets(
      'chip text follows a filter value change when the count is unchanged '
      '(RxMap passed straight through)', (tester) async {
    final filters = <String, String>{'item_code': 'Item: A'}.obs;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          DocTypeListHeader(
            title: 'Item Variant Details',
            automaticallyImplyLeading: false,
            activeFilters: filters,
            onFilterTap: () {},
            filterChipsBuilder: (_) => _chips(filters),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 2000)),
        ]),
      ),
    ));
    expect(find.text('Item: A'), findsOneWidget);

    // What the report controller does on Run Report: clear, then refill.
    filters.clear();
    filters['item_code'] = 'Item: B';
    await tester.pump();

    expect(find.text('Item: B'), findsOneWidget);
    expect(find.text('Item: A'), findsNothing);
  });

  testWidgets(
      'chip text follows a filter value change when the count is unchanged '
      '(screen passes a fresh .obs copy on each build)', (tester) async {
    // Mirrors item_variant_details_screen and the other report screens, which
    // pass `controller.activeFilters.map(...).obs` from inside their own Obx.
    final filters = <String, String>{'item_code': 'Item: A'}.obs;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Obx(() => CustomScrollView(slivers: [
              DocTypeListHeader(
                title: 'Item Variant Details',
                automaticallyImplyLeading: false,
                activeFilters:
                    filters.map((k, v) => MapEntry(k, v as dynamic)).obs,
                onFilterTap: () {},
                filterChipsBuilder: (_) => _chips(filters),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ])),
      ),
    ));
    expect(find.text('Item: A'), findsOneWidget);

    filters.clear();
    filters['item_code'] = 'Item: B';
    await tester.pump();

    expect(find.text('Item: B'), findsOneWidget);
    expect(find.text('Item: A'), findsNothing);
  });

  testWidgets('delegate does not ask to rebuild when filter content is equal',
      (tester) async {
    // Guards against the fix rebuilding on every Obx run: list-valued filters
    // (e.g. ['like', '%x%']) are usually reassigned as fresh lists, so they
    // must compare by content, not identity.
    final filters = <String, dynamic>{
      'name': ['like', '%x%'],
    }.obs;
    final tick = 0.obs;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Obx(() {
          tick.value; // lets the test force a header rebuild
          return CustomScrollView(slivers: [
            DocTypeListHeader(
              title: 'Delivery Note',
              automaticallyImplyLeading: false,
              activeFilters: <String, dynamic>{
                'name': List<dynamic>.of(filters['name'] as List),
              }.obs,
              filterChipsBuilder: (_) => const [Chip(label: Text('x'))],
            ),
          ]);
        }),
      ),
    ));
    final first = tester
        .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
        .delegate;

    tick.value++;
    await tester.pump();
    final second = tester
        .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
        .delegate;

    expect(identical(first, second), isFalse);
    expect(second.shouldRebuild(first), isFalse);
  });

  testWidgets('same field twice rebuilds earlier changed chip with no scroll', (
    tester,
  ) async {
    final conditions = ['Item: A', 'Item: B'].obs;
    final filters = <String, dynamic>{'item': 'Item: B'}.obs;
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeListHeader(
                title: 'Item',
                activeFilters: filters,
                onFilterTap: () {},
                filterChipsBuilder: (_) => [
                  for (final condition in conditions)
                    FilterChipWidget(
                      icon: Icons.label_outline,
                      label: condition,
                      onDeleted: () {
                        log.add(condition);
                        conditions.remove(condition);
                      },
                      onTap: () => log.add('Edit $condition'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    conditions[0] = 'Item: C';
    await tester.pumpAndSettle();
    expect(find.text('Item: A'), findsNothing);
    expect(find.text('Item: C'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Item: C')).dx,
      lessThan(tester.getCenter(find.text('Item: B')).dx),
    );
    expect(find.byTooltip('Filters, 1 active'), findsOneWidget);

    final earlier = find.widgetWithText(FilterChipWidget, 'Item: C');
    final reset = find.descendant(
      of: earlier,
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(log, ['Item: C']);
    expect(filters, {'item': 'Item: B'});
    expect(find.text('Item: C'), findsNothing);
    await tester.tap(find.text('Item: B'));
    expect(log, ['Item: C', 'Edit Item: B']);
  });

  testWidgets(
    'header invalidates live slots, callbacks and the search source',
    (tester) async {
      final first = 'bolts'.obs;
      final second = 'bolts'.obs;
      final version = ValueNotifier<int>(0);
      addTearDown(version.dispose);
      final calls = <int>[];
      final filters = <String, dynamic>{'group': 'Fasteners'}.obs;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: version,
              builder: (context, value, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(value >= 4 ? 2 : 1)),
                child: CustomScrollView(
                  slivers: [
                    DocTypeListHeader(
                      title: 'Item',
                      activeFilters: filters,
                      searchDoctype: 'Item',
                      searchQuery: value >= 2 ? second : first,
                      onSearchChanged: (_) {},
                      onFilterTap: value >= 3 ? null : () => calls.add(value),
                      filtersEnabled: value < 2,
                      bottom: PreferredSize(
                        preferredSize: Size.fromHeight(value < 2 ? 48 : 52),
                        child: const SizedBox.expand(key: ValueKey('bottom')),
                      ),
                      quickChips: [
                        if (value < 2)
                          const Chip(label: Text('Previous'))
                        else
                          const Chip(label: Text('Updated')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final add = find.byType(AddFilterChip);
      await tester.tap(add);
      version.value = 1;
      await tester.pumpAndSettle();
      await tester.tap(add);
      expect(calls, [0, 1]);

      version.value = 2;
      await tester.pumpAndSettle();
      await tester.tap(add);
      expect(calls, [0, 1]);
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Previous'), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('bottom'))).height, 52);
      expect(
        find.byTooltip('Search Item, current query: bolts'),
        findsOneWidget,
      );
      first.value = 'stale';
      second.value = 'fresh';
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Search Item, current query: fresh'),
        findsOneWidget,
      );

      version.value = 3;
      await tester.pumpAndSettle();
      expect(add, findsNothing);
      expect(find.byType(CountBadge), findsNothing);
      final old = tester
          .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
          .delegate;
      version.value = 4;
      await tester.pumpAndSettle();
      final updated = tester
          .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
          .delegate;
      expect(updated.minExtent, greaterThan(old.minExtent));
    },
  );
}
