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

  group('DashboardActionableStrip', () {
    testWidgets('renders one chip per data entry', (t) async {
      await _pump(t, DashboardActionableStrip(isLoading: false, chips: [
        _chip('PO', 1, () {}),
        _chip('DN', 0, null),
      ]));
      expect(find.byType(ActionableCountChip), findsNWidgets(2));
    });

    testWidgets('isLoading shows placeholders, not chips', (t) async {
      await _pump(t, const DashboardActionableStrip(isLoading: true, chips: []));
      expect(find.byType(ActionableCountChip), findsNothing);
      expect(find.byKey(const ValueKey('actionable-strip-loading')), findsOneWidget);
    });
  });
}
