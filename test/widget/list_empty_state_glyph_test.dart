import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';

Widget _host({required bool filtered}) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: ListEmptyState(
          hasActiveFilters: filtered,
          emptyIcon: Icons.inbox_outlined,
          emptyTitle: 'No notes',
          emptyMessage: 'Nothing here yet.',
          filteredTitle: 'No matches',
          filteredMessage: 'Try clearing filters.',
          onClearFilters: () {},
          onReload: () {},
        ),
      ),
    );

void main() {
  testWidgets('renders a 56x56 subtle glyph circle around the icon', (tester) async {
    await tester.pumpWidget(_host(filtered: false));
    final glyph = tester.widget<Container>(
      find.ancestor(of: find.byIcon(Icons.inbox_outlined), matching: find.byType(Container)).first,
    );
    expect(glyph.constraints?.maxWidth, 56);
    expect(glyph.constraints?.maxHeight, 56);
    final deco = glyph.decoration as BoxDecoration;
    expect(deco.color, AppScheme.light.subtle);
    expect(deco.shape, BoxShape.circle);
  });

  testWidgets('empty title uses 17/600 in scheme text color', (tester) async {
    await tester.pumpWidget(_host(filtered: false));
    final title = tester.widget<Text>(find.text('No notes'));
    expect(title.style?.fontSize, 17);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(title.style?.color, AppScheme.light.text);
  });

  testWidgets('filtered state still shows the clear-filters action', (tester) async {
    await tester.pumpWidget(_host(filtered: true));
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Clear Filters'), findsOneWidget);
  });
}
