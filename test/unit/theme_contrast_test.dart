import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/main.dart' show buildAppTheme;

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppAccent contrast', () {
    for (final accent in AppAccent.all) {
      test('${accent.name}: onPrimary vs primary passes AA (4.5) in light',
          () {
        expect(
          contrast(accent.lightOnPrimary, accent.lightPrimary),
          greaterThanOrEqualTo(4.5),
          reason:
              '${accent.name} light onPrimary-on-primary must be readable at '
              'normal text size (AppBar actions, filled buttons, FABs)',
        );
      });

      test('${accent.name}: onPrimary vs primary passes AA (4.5) in dark', () {
        expect(
          contrast(accent.darkOnPrimary, accent.darkPrimary),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('${accent.name}: primary as text on white card passes AA-large (3)',
          () {
        // primary is also used as tinted label/link text on light cards
        // (drawer selected item, date chips, TextButtons).
        expect(
          contrast(accent.lightPrimary, AppScheme.light.fg),
          greaterThanOrEqualTo(3.0),
        );
      });
    }
  });

  group('text role contrast', () {
    for (final b in Brightness.values) {
      final s = AppScheme.of(b);
      test('textMuted passes AA (4.5) on card surface [$b]', () {
        expect(contrast(s.textMuted, s.fg), greaterThanOrEqualTo(4.5));
      });
      test('textSubtle passes 3:1 (large text / icons) on card surface [$b]',
          () {
        expect(contrast(s.textSubtle, s.fg), greaterThanOrEqualTo(3.0));
      });
    }
  });

  group('buildAppTheme component contrast', () {
    for (final b in Brightness.values) {
      final scheme = AppScheme.of(b);
      final theme = buildAppTheme(scheme, b);

      test('snackbar text vs snackbar background passes AA (4.5) [$b]', () {
        final snack = theme.snackBarTheme;
        final bg = snack.backgroundColor!;
        final fg = snack.contentTextStyle!.color!;
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(snack.actionTextColor!, bg),
            greaterThanOrEqualTo(4.5));
      });

      test('FAB foreground vs background passes 3:1 (graphical) [$b]', () {
        final fab = theme.floatingActionButtonTheme;
        expect(contrast(fab.foregroundColor!, fab.backgroundColor!),
            greaterThanOrEqualTo(3.0));
      });
    }
  });
}
