import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

void main() {
  testWidgets('DocTypeListHeader stays pinned after scroll',
      (WidgetTester tester) async {
    // 1. Setup reactive state
    final searchQuery = ''.obs;
    final activeFilters = <String, dynamic>{}.obs;

    // 2. Build the widget inside a CustomScrollView with enough content to scroll
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeListHeader(
                title: 'Test DocType Name',
                searchQuery: searchQuery,
                activeFilters: activeFilters,
                filterChipsBuilder: (context) => [
                  const Chip(label: Text('Filter 1')),
                ],
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ListTile(title: Text('Item $index')),
                  childCount: 50,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 3. Verify initial state (Expanded)
    expect(find.text('Test DocType Name'), findsOneWidget);

    // 4. Simulate scroll gesture (300 dp down)
    final gesture = await tester.startGesture(const Offset(0, 300));
    await gesture.moveBy(const Offset(0, -300));
    await tester.pumpAndSettle();

    // 5. Assert the header title is still in the widget tree and visible
    final titleFinder = find.text('Test DocType Name');
    expect(titleFinder, findsWidgets);

    // Verify visibility: It should have a non-zero size and be within the viewport
    final RenderBox renderBox = tester.renderObject(titleFinder.first);
    expect(renderBox.size.height, greaterThan(0));
    expect(renderBox.localToGlobal(Offset.zero).dy, greaterThanOrEqualTo(0));
  });

  testWidgets('filter button renders without crash when activeFilters is null',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          DocTypeListHeader(
            title: 'Test',
            onFilterTap: () {}, // onFilterTap set but activeFilters omitted
          ),
          const SliverFillRemaining(),
        ]),
      ),
    ));
    expect(find.byIcon(Icons.filter_list), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leading hamburger renders without crash when no Scaffold drawer',
      (tester) async {
    // Scaffold without drawer — hamburger should degrade gracefully
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // No drawer property set — this would crash pre-guard
        body: CustomScrollView(slivers: [
          DocTypeListHeader(
            title: 'Test',
            automaticallyImplyLeading: false, // request hamburger
          ),
          const SliverFillRemaining(),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    // Hamburger icon should still render (though tapping it degrades to back nav)
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('back arrow renders without crash when no Navigator',
      (tester) async {
    // Wrapping in a widget that has no Navigator (no MaterialApp) to simulate
    // the bare-context scenario.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: CustomScrollView(slivers: [
            DocTypeListHeader(title: 'Test'),
            const SliverFillRemaining(),
          ]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no crash when filterChipsBuilder returns empty list',
      (tester) async {
    final filters = <String, dynamic>{}.obs;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          DocTypeListHeader(
            title: 'Test',
            activeFilters: filters,
            filterChipsBuilder: (_) => [], // empty — chips row should be hidden
          ),
          const SliverFillRemaining(),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    // Add a filter — chip row must appear without crashing
    filters['status'] = 'Open';
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('no crash when searchQuery and activeFilters are both null',
      (tester) async {
    // Edge case: both observables are null — maxExtent must not throw
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          const DocTypeListHeader(
            title: 'Test',
            // searchQuery: null, activeFilters: null — both omitted
          ),
          const SliverFillRemaining(),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('expandProgress clamp guards against extreme scroll offsets',
      (tester) async {
    // This test ensures the Opacity widget never receives NaN or out-of-bounds
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            DocTypeListHeader(title: 'Test'),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => SizedBox(height: 100, child: Text('$index')),
                childCount: 100,
              ),
            ),
          ],
        ),
      ),
    ));

    // Extreme fling gesture to test large shrinkOffset
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -5000), // very large negative offset
      5000, // very fast velocity
    );
    await tester.pumpAndSettle();

    // No crash should occur — Opacity clamp prevents assert
    expect(tester.takeException(), isNull);
  });
}
