import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('unfiltered + emptyAction shows the action, not Reload',
      (tester) async {
    await tester.pumpWidget(wrap(ListEmptyState(
      hasActiveFilters: false,
      emptyIcon: Icons.percent,
      emptyTitle: 'No rows',
      emptyMessage: 'msg',
      filteredTitle: 'No matches',
      filteredMessage: 'msg2',
      onClearFilters: () {},
      onReload: () {},
      emptyAction: const Text('Custom CTA'),
    )));

    expect(find.text('Custom CTA'), findsOneWidget);
    expect(find.text('Reload'), findsNothing);
  });

  testWidgets('unfiltered + no emptyAction shows Reload', (tester) async {
    await tester.pumpWidget(wrap(ListEmptyState(
      hasActiveFilters: false,
      emptyIcon: Icons.percent,
      emptyTitle: 'No rows',
      emptyMessage: 'msg',
      filteredTitle: 'No matches',
      filteredMessage: 'msg2',
      onClearFilters: () {},
      onReload: () {},
    )));

    expect(find.text('Reload'), findsOneWidget);
  });

  testWidgets('filtered variant always shows Clear Filters, even with emptyAction set',
      (tester) async {
    await tester.pumpWidget(wrap(ListEmptyState(
      hasActiveFilters: true,
      emptyIcon: Icons.percent,
      emptyTitle: 'No rows',
      emptyMessage: 'msg',
      filteredTitle: 'No matches',
      filteredMessage: 'msg2',
      onClearFilters: () {},
      onReload: () {},
      emptyAction: const Text('Custom CTA'),
    )));

    expect(find.text('Clear Filters'), findsOneWidget);
    expect(find.text('Custom CTA'), findsNothing);
  });
}
