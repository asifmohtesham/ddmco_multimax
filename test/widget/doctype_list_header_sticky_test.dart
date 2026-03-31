import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

void main() {
  testWidgets('DocTypeListHeader stays pinned after scroll', (WidgetTester tester) async {
    // 1. Setup reactive state
    final searchQuery = ''.obs;
    final activeFilters = {}.obs;

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
    expect(titleFinder, findsOneWidget);
    
    // Verify visibility: It should have a non-zero size and be within the viewport
    final RenderBox renderBox = tester.renderObject(titleFinder);
    expect(renderBox.size.height, greaterThan(0));
    expect(renderBox.localToGlobal(Offset.zero).dy, greaterThanOrEqualTo(0));
  });
}
