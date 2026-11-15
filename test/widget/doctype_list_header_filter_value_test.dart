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
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

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
}
