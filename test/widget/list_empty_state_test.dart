import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

ListEmptyState _build({required bool hasActiveFilters}) => ListEmptyState(
      hasActiveFilters: hasActiveFilters,
      emptyIcon: Icons.inventory_2_outlined,
      emptyTitle: 'No Items Found',
      emptyMessage: 'Pull to refresh to load items.',
      filteredTitle: 'No Matching Items',
      filteredMessage: 'Try adjusting your filters.',
      onClearFilters: () {},
      onReload: () {},
    );

void main() {
  group('ListEmptyState', () {
    testWidgets('empty variant shows reload action and empty copy',
        (tester) async {
      await tester.pumpWidget(_wrap(_build(hasActiveFilters: false)));
      expect(find.text('No Items Found'), findsOneWidget);
      expect(find.text('Reload'), findsOneWidget);
      expect(find.text('Clear Filters'), findsNothing);
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('filtered variant shows clear action and filter icon',
        (tester) async {
      await tester.pumpWidget(_wrap(_build(hasActiveFilters: true)));
      expect(find.text('No Matching Items'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);
      expect(find.text('Reload'), findsNothing);
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
    });

    testWidgets('clear action fires onClearFilters', (tester) async {
      var cleared = false;
      await tester.pumpWidget(_wrap(ListEmptyState(
        hasActiveFilters: true,
        emptyIcon: Icons.inventory_2_outlined,
        emptyTitle: 'e',
        emptyMessage: 'e',
        filteredTitle: 'f',
        filteredMessage: 'f',
        onClearFilters: () => cleared = true,
        onReload: () {},
      )));
      await tester.tap(find.text('Clear Filters'));
      expect(cleared, isTrue);
    });
  });
}
