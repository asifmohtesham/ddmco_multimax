import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_card.dart';
import 'package:multimax/main.dart' show buildAppTheme;

/// WCAG 2.x contrast ratio between two opaque colours.
/// Each contrast test file declares its own — the helper is not shared
/// (see status_ink_contrast_test.dart, which does the same).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  Widget app(Brightness b, Widget child) => MaterialApp(
        theme: buildAppTheme(AppScheme.of(b), b),
        home: Scaffold(body: child),
      );

  const rule = ItemReorder(
    warehouseGroup: 'Finished Goods - KA',
    warehouse: 'WH-DXB1 - KA',
    warehouseReorderLevel: 2400,
    warehouseReorderQty: 2400,
    materialRequestType: 'Purchase',
  );

  testWidgets('renders group, warehouse, levels and type', (tester) async {
    await tester.pumpWidget(
      app(Brightness.light, const ReorderRuleCard(rule: rule, index: 0)),
    );

    expect(find.text('Finished Goods - KA'), findsOneWidget);
    expect(find.text('WH-DXB1 - KA'), findsOneWidget);
    expect(find.text('Re-order at 2,400 · Order 2,400'), findsOneWidget);
    expect(find.text('Purchase'), findsOneWidget);
  });

  testWidgets('shows the warehouse as the group when the group is blank',
      (tester) async {
    // item.py:508-509 — a blank group behaves as the warehouse itself.
    await tester.pumpWidget(app(
      Brightness.light,
      const ReorderRuleCard(
        rule: ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase'),
        index: 0,
      ),
    ));
    expect(find.text('WH-A'), findsNWidgets(2));
  });

  testWidgets('renders a placeholder when the type is unset', (tester) async {
    await tester.pumpWidget(app(
      Brightness.light,
      const ReorderRuleCard(
        rule: ItemReorder(warehouse: 'WH-A'),
        index: 0,
      ),
    ));
    expect(find.text('No request type'), findsOneWidget);
  });

  testWidgets('hides the overflow menu when not editable', (tester) async {
    await tester.pumpWidget(
      app(Brightness.light, const ReorderRuleCard(rule: rule, index: 0)),
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('shows the overflow menu when editable', (tester) async {
    await tester.pumpWidget(app(
      Brightness.light,
      ReorderRuleCard(rule: rule, index: 0, onEdit: () {}, onDelete: () {}),
    ));
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('warehouse ink is readable (>=4.5) on the card [$b]',
        (tester) async {
      await tester.pumpWidget(
        app(b, const ReorderRuleCard(rule: rule, index: 0)),
      );

      final scheme = AppScheme.of(b);
      final text = tester.widget<Text>(find.text('WH-DXB1 - KA'));
      // The card sits on scheme.subtle, so measure the ink against that.
      expect(
        _contrast(text.style!.color!, scheme.subtle),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  testWidgets('uses the themed surface, not a hardcoded white', (tester) async {
    final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      home: const Scaffold(body: ReorderRuleCard(rule: rule, index: 0)),
    ));

    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('WH-DXB1 - KA'),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, isNot(Colors.white));
    expect(deco.color, AppScheme.dark.subtle);
  });
}
