import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';

Future<void> _pump(WidgetTester t, Widget child,
        {Brightness b = Brightness.light}) =>
    t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: child),
    ));

ActionableChipData _chip(String label, int count, VoidCallback? onTap) =>
    ActionableChipData(
        doctype: label, label: label, icon: Icons.circle, count: count, onTap: onTap);

ActionableChipData _chipSel(String label, int count, VoidCallback? onTap,
        {bool selected = false}) =>
    ActionableChipData(
        doctype: label,
        label: label,
        icon: Icons.circle,
        count: count,
        onTap: onTap,
        selected: selected);

SingleChildScrollView tester_scrollView(WidgetTester t) =>
    t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first);

void _stripTests() {
  group('DashboardActionableStrip', () {
    testWidgets('renders one chip per data entry', (t) async {
      await _pump(t, DashboardActionableStrip(isLoading: false, chips: [
        _chipSel('Purchase Order', 1, () {}),
        _chipSel('Delivery Note', 0, null),
      ]));
      expect(find.byType(ActionableCountChip), findsNWidgets(2));
    });

    testWidgets('scrolls horizontally and never wraps', (t) async {
      await _pump(t, DashboardActionableStrip(isLoading: false, chips: [
        for (final l in ['Tasks', 'Purchase Order', 'Purchase Receipt',
                         'Stock Entry', 'Delivery Note', 'Packing Slip'])
          _chipSel(l, 3, () {}),
      ]));
      expect(find.byType(Wrap), findsNothing);
      final sv = tester_scrollView(t);
      expect(sv.scrollDirection, Axis.horizontal);
    });

    testWidgets('isLoading shows placeholders, not chips', (t) async {
      await _pump(t, const DashboardActionableStrip(isLoading: true, chips: []));
      expect(find.byType(ActionableCountChip), findsNothing);
      expect(find.byKey(const ValueKey('actionable-strip-loading')), findsOneWidget);
    });
  });

  group('ActionableCountChip selection', () {
    testWidgets('selected chip reports its doctype on tap', (t) async {
      String? tapped;
      await _pump(t, ActionableCountChip(
          data: _chipSel('Stock Entry', 2, () => tapped = 'Stock Entry')));
      await t.tap(find.byType(ActionableCountChip));
      expect(tapped, 'Stock Entry');
    });

    testWidgets('muted chip is not selectable (no ink well)', (t) async {
      await _pump(t, ActionableCountChip(data: _chipSel('Purchase Receipt', 0, null)));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('selected renders differently from unselected', (t) async {
      await _pump(t, Column(children: [
        ActionableCountChip(data: _chipSel('A', 1, () {}, selected: true)),
        ActionableCountChip(data: _chipSel('B', 1, () {}, selected: false)),
      ]));
      final boxes = t.widgetList<Container>(find.descendant(
              of: find.byType(ActionableCountChip), matching: find.byType(Container)))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(boxes.first, isNot(equals(boxes.last)));
    });
  });
}

void main() {
  group('ActionableCountChip', () {
    testWidgets('renders label and count', (t) async {
      await _pump(t, ActionableCountChip(data: _chip('PO', 3, () {})));
      expect(find.text('PO'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('fires onTap when not muted', (t) async {
      var tapped = false;
      await _pump(t, ActionableCountChip(data: _chip('SE', 2, () => tapped = true)));
      await t.tap(find.byType(ActionableCountChip));
      expect(tapped, isTrue);
    });

    testWidgets('muted chip (count 0) has no ink well', (t) async {
      await _pump(t, ActionableCountChip(data: _chip('DN', 0, null)));
      expect(find.text('DN'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('renders in dark mode', (t) async {
      await _pump(t, ActionableCountChip(data: _chip('PR', 5, () {})),
          b: Brightness.dark);
      expect(find.text('PR'), findsOneWidget);
    });
  });

  group('ActionableScopeToggle', () {
    testWidgets('tapping Everyone reports the everyone scope', (t) async {
      ActionableScope? got;
      await _pump(t, ActionableScopeToggle(
          scope: ActionableScope.mine, onChanged: (s) => got = s));
      await t.tap(find.text('Everyone'));
      expect(got, ActionableScope.everyone);
    });

    testWidgets('tapping Mine reports the mine scope', (t) async {
      ActionableScope? got;
      await _pump(t, ActionableScopeToggle(
          scope: ActionableScope.everyone, onChanged: (s) => got = s));
      await t.tap(find.text('Mine'));
      expect(got, ActionableScope.mine);
    });
  });

  _stripTests();
}
