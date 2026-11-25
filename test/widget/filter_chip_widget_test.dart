import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/main.dart';

// Pump under the real app theme so context.scheme.primary resolves to the
// brand maroon (the default accent), as it does in the running app.
Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: buildAppTheme(AppScheme.of(brightness), brightness),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('renders label, icon and a close affordance', (tester) async {
    await tester.pumpWidget(
      _host(
        brightness: Brightness.light,
        child: FilterChipWidget(
          icon: Icons.label,
          label: 'Status: Draft',
          onDeleted: () {},
        ),
      ),
    );
    expect(find.text('Status: Draft'), findsOneWidget);
    expect(find.byIcon(Icons.label), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('tapping the close icon calls onDeleted', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      _host(
        brightness: Brightness.light,
        child: FilterChipWidget(
          icon: Icons.label,
          label: 'x',
          onDeleted: () => deleted = true,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.close));
    expect(deleted, isTrue);
  });

  testWidgets('tapping the chip body calls onTap, not onDeleted', (
    tester,
  ) async {
    var tapped = 0, deleted = 0;
    await tester.pumpWidget(
      _host(
        brightness: Brightness.light,
        child: FilterChipWidget(
          icon: Icons.label,
          label: 'Ranges: 360, 720',
          onDeleted: () => deleted++,
          onTap: () => tapped++,
        ),
      ),
    );
    await tester.tap(find.text('Ranges: 360, 720'));
    expect((tapped, deleted), (1, 0));

    // The × still only clears.
    await tester.tap(find.byIcon(Icons.close));
    expect((tapped, deleted), (1, 1));
  });

  testWidgets('active style: maroon-tinted fill + primary text in light', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        brightness: Brightness.light,
        child: FilterChipWidget(
          icon: Icons.label,
          label: 'x',
          onDeleted: () {},
        ),
      ),
    );
    final scheme = AppScheme.light;
    // Label text uses primary.
    final text = tester.widget<Text>(find.text('x'));
    expect(text.style?.color, scheme.primary);
    final pill = tester.widget<HeaderPill>(find.byType(HeaderPill));
    expect(
      pill.fill,
      Color.alphaBlend(scheme.primary.withValues(alpha: .12), scheme.fg),
    );
    expect(pill.perimeter, scheme.primary);
    expect(tester.getSize(find.byType(HeaderPill)).height, 34);
  });

  testWidgets('resolves against dark scheme when brightness is dark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        brightness: Brightness.dark,
        child: FilterChipWidget(
          icon: Icons.label,
          label: 'x',
          onDeleted: () {},
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('x'));
    expect(text.style?.color, AppColors.red300);
    expect(text.style?.color, isNot(AppScheme.light.primary));
  });

  group('split action rectangles', () {
    for (final (label, cap) in <(String, double?)>[
      ('x', null),
      ('Status: Draft', null),
      ('Search: bolts', null),
      ('Long value for an applied filter caption', null),
      ('A value wider than its explicit width cap', 60),
      ('First line\nSecond line\nThird line', null),
    ]) {
      testWidgets(
        'edit and reset have disjoint 48 dp hit and semantic rectangles [$label]',
        (tester) async {
          var edits = 0;
          var resets = 0;
          await tester.pumpWidget(
            _host(
              brightness: Brightness.dark,
              child: FilterChipWidget(
                icon: Icons.label,
                label: label,
                maxLabelWidth: cap,
                onTap: () => edits++,
                onDeleted: () => resets++,
              ),
            ),
          );
          final edit = find.byType(TextButton).first;
          final reset = find.byType(TextButton).last;
          final editRect = tester.getRect(edit);
          final resetRect = tester.getRect(reset);
          expect(editRect.right, resetRect.left);
          expect(editRect.overlaps(resetRect), isFalse);
          for (final (finder, name) in [
            (edit, 'Edit $label'),
            (reset, 'Reset $label'),
          ]) {
            final rect = tester.getRect(finder);
            final node = tester.getSemantics(finder);
            final data = node.getSemanticsData();
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(node.rect.size, rect.size);
            expect(data.label, name);
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.flagsCollection.isEnabled, Tristate.isTrue);
            expect(data.flagsCollection.isSelected, Tristate.none);
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            expect(data.hasAction(SemanticsAction.dismiss), isFalse);
            expect(data.hint, isEmpty);
            for (final point in [
              rect.center,
              rect.topLeft + const Offset(1, 1),
              rect.topRight + const Offset(-1, 1),
              rect.bottomLeft + const Offset(1, -1),
              rect.bottomRight + const Offset(-1, -1),
            ]) {
              await tester.tapAt(point);
              await tester.pump();
            }
            expect((edits, resets), finder == edit ? (5, 0) : (5, 5));
          }
        },
      );
    }
  });

  testWidgets('read-only, disabled and dismissal semantics stay distinct', (
    tester,
  ) async {
    var resets = 0;
    var edits = 0;

    Future<void> mount({bool enabled = true, bool editable = false}) =>
        tester.pumpWidget(
          _host(
            brightness: Brightness.light,
            child: FilterChipWidget(
              icon: Icons.label,
              label: 'Status: Draft',
              resetSemanticLabel: 'Remove Status filter',
              dismissesChip: true,
              enabled: enabled,
              onTap: editable ? () => edits++ : null,
              onDeleted: () => resets++,
            ),
          ),
        );

    await mount();
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Draft'), findsOneWidget);
    final reset = tester.getSemantics(find.byType(TextButton));
    expect(reset.getSemanticsData().label, 'Remove Status filter');
    expect(reset.getSemanticsData().hasAction(SemanticsAction.dismiss), isTrue);
    reset.owner!.performAction(reset.id, SemanticsAction.dismiss);
    expect(resets, 1);

    await mount(enabled: false, editable: true);
    final pill = tester.widget<HeaderPill>(find.byType(HeaderPill));
    expect(pill.disabled, isTrue);
    for (final finder in [
      find.byType(TextButton).first,
      find.byType(TextButton).last,
    ]) {
      final data = tester.getSemantics(finder).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.dismiss), isFalse);
      await tester.tapAt(tester.getCenter(finder));
    }
    expect((edits, resets), (0, 1));
  });
}
