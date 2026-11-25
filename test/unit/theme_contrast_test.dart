import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/header_choice_row.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
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
  for (final accent in AppAccent.all) {
    for (final brightness in Brightness.values) {
      test(
        'wrapped report controls resolve contrasting ink in every state [${brightness.name}, ${accent.name}]',
        () {
          final theme = buildAppTheme(
            AppScheme.of(brightness),
            brightness,
            accent: accent,
          );
          final palette = HeaderPalette(theme);
          const interactions = [
            WidgetState.hovered,
            WidgetState.focused,
            WidgetState.pressed,
          ];
          for (var pattern = 0; pattern < 8; pattern++) {
            for (final enabled in [true, false]) {
              final states = <WidgetState>{
                if (!enabled) WidgetState.disabled,
                for (final (i, interaction) in interactions.indexed)
                  if (pattern & (1 << i) != 0) interaction,
              };
              for (final (active, command) in [
                (false, false),
                (true, false),
                (false, true),
              ]) {
                final quickFill = palette.quickFill(states, selected: active);
                final quickInk = palette.quickInk(
                  selected: active,
                  enabled: enabled,
                  command: command,
                );
                expect(
                  contrast(quickInk, quickFill),
                  greaterThanOrEqualTo(4.5),
                );
                expect(
                  contrast(palette.muted, quickFill),
                  greaterThanOrEqualTo(3),
                );
                if (!enabled) expect(quickFill, palette.surface);
              }
              final addFill = palette.addFill(states);
              final bulkFill = palette.bulkFill(states);
              final appliedFill = palette.appliedFillFor(enabled);
              expect(
                contrast(palette.muted, addFill),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrast(enabled ? palette.error : palette.muted, bulkFill),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                contrast(palette.muted, bulkFill),
                greaterThanOrEqualTo(3),
              );
              expect(
                contrast(palette.appliedInkFor(enabled), appliedFill),
                greaterThanOrEqualTo(4.5),
              );
              final perimeter = palette.appliedPerimeterFor(enabled);
              expect(contrast(perimeter, appliedFill), greaterThanOrEqualTo(3));
              expect(
                contrast(perimeter, palette.surface),
                greaterThanOrEqualTo(3),
              );
              expect(
                contrast(palette.muted, palette.surface),
                greaterThanOrEqualTo(3),
              );
              if (!enabled) expect(headerContourWidth(states), 0);
            }
          }
        },
      );
    }
  }

  _headerContrast();
  _headerChoiceContrast();
  group('AppAccent contrast', () {
    for (final accent in AppAccent.all) {
      test('${accent.name}: onPrimary vs primary passes AA (4.5) in light', () {
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

      test(
        '${accent.name}: primary as text on white card passes AA-large (3)',
        () {
          // primary is also used as tinted label/link text on light cards
          // (drawer selected item, date chips, TextButtons).
          expect(
            contrast(accent.lightPrimary, AppScheme.light.fg),
            greaterThanOrEqualTo(3.0),
          );
        },
      );
    }
  });

  group('text role contrast', () {
    for (final b in Brightness.values) {
      final s = AppScheme.of(b);
      test('textMuted passes AA (4.5) on card surface [$b]', () {
        expect(contrast(s.textMuted, s.fg), greaterThanOrEqualTo(4.5));
      });
      test(
        'textSubtle passes 3:1 (large text / icons) on card surface [$b]',
        () {
          expect(contrast(s.textSubtle, s.fg), greaterThanOrEqualTo(3.0));
        },
      );
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
        expect(contrast(snack.actionTextColor!, bg), greaterThanOrEqualTo(4.5));
      });

      test('FAB foreground vs background passes 3:1 (graphical) [$b]', () {
        final fab = theme.floatingActionButtonTheme;
        expect(
          contrast(fab.foregroundColor!, fab.backgroundColor!),
          greaterThanOrEqualTo(3.0),
        );
      });
    }
  });
}

void _headerChoiceContrast() {
  const variables = [
    WidgetState.hovered,
    WidgetState.focused,
    WidgetState.pressed,
    WidgetState.disabled,
  ];
  for (final brightness in Brightness.values) {
    for (final accent in AppAccent.all) {
      final palette = HeaderPalette(
        buildAppTheme(AppScheme.of(brightness), brightness, accent: accent),
      );
      test(
        'header selectable choices meet text, edge, check and focus contrast '
        '[${brightness.name} ${accent.name}]',
        () {
          for (final selected in [false, true]) {
            for (var mask = 0; mask < 1 << variables.length; mask++) {
              final states = {
                for (final (bit, state) in variables.indexed)
                  if (mask & (1 << bit) != 0) state,
              };
              final paint = resolveHeaderChoicePaint(
                palette,
                states,
                selected: selected,
              );
              final disabled = states.contains(WidgetState.disabled);
              final applied = selected && !disabled;
              final pointer =
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed);
              final reason = 'selected $selected, states $states';
              final expectedFill = applied
                  ? palette.appliedFill
                  : pointer && !disabled
                  ? Color.alphaBlend(
                      palette.colors.onSurface.withAlpha(20),
                      palette.surface,
                    )
                  : palette.surface;
              expect(paint.fill, expectedFill, reason: reason);
              expect(paint.dashed, disabled, reason: reason);
              expect(
                paint.check,
                applied ? palette.ink : palette.muted,
                reason: reason,
              );
              expect(paint.caption.a, 1, reason: reason);
              expect(paint.check.a, 1, reason: reason);
              expect(
                contrast(paint.caption, paint.fill),
                greaterThanOrEqualTo(4.5),
                reason: reason,
              );
              expect(
                contrast(paint.check, paint.fill),
                greaterThanOrEqualTo(3),
                reason: reason,
              );
              expect(
                contrast(paint.perimeter, paint.fill),
                greaterThanOrEqualTo(3),
                reason: reason,
              );
              expect(
                contrast(paint.perimeter, palette.surface),
                greaterThanOrEqualTo(3),
                reason: reason,
              );
              expect(paint.contour, headerContourWidth(states), reason: reason);
              if (disabled) expect(paint.contour, 0, reason: reason);
            }
          }
          expect(
            contrast(palette.muted, palette.surface),
            greaterThanOrEqualTo(3),
          );
        },
      );
    }
  }
}

void _headerContrast() {
  const rest = <WidgetState>{};
  const hover = {WidgetState.hovered};
  const focus = {WidgetState.focused};
  const press = {WidgetState.pressed};
  const combined = {
    WidgetState.hovered,
    WidgetState.focused,
    WidgetState.pressed,
  };
  const disabled = {...combined, WidgetState.disabled};

  for (final brightness in Brightness.values) {
    for (final accent in AppAccent.all) {
      final label = '${brightness.name} ${accent.name}';
      final theme = buildAppTheme(
        AppScheme.of(brightness),
        brightness,
        accent: accent,
      );
      final palette = HeaderPalette(theme);
      final scheme = palette.scheme;
      final roles = theme.colorScheme;
      final surface = palette.surface;

      void passes(
        Color foreground,
        Color background,
        double minimum,
        String state,
      ) {
        expect(
          contrast(foreground, background),
          greaterThanOrEqualTo(minimum),
          reason: '$label $state: $foreground on $background',
        );
      }

      test('applied filter ink and perimeter pass in every state [$label]', () {
        final expectedFill = Color.alphaBlend(
          scheme.primary.withValues(alpha: .12),
          surface,
        );
        for (final state in [rest, hover, focus, press, combined, disabled]) {
          final enabled = !state.contains(WidgetState.disabled);
          final ink = palette.appliedInkFor(enabled);
          final fill = palette.appliedFillFor(enabled);
          final perimeter = palette.appliedPerimeterFor(enabled);
          expect(ink.a, 1);
          expect(perimeter.a, 1);
          expect(fill, enabled ? expectedFill : surface);
          passes(ink, fill, 4.5, 'caption $state');
          passes(ink, fill, 3, 'leading and close $state');
          passes(perimeter, surface, 3, 'outside perimeter $state');
          passes(perimeter, fill, 3, 'inside perimeter $state');
        }
      });

      test(
        'filter actions have visible focus, hover and press contours [$label]',
        () {
          final native = ListHeaderQuickChipTheme.resolve(theme).chipTheme;
          for (final (states, width) in [
            (rest, 0),
            (hover, 1),
            (focus, 2),
            (press, 3),
            (combined, 3),
            (disabled, 0),
          ]) {
            expect(headerContourWidth(states), width);
            final side = WidgetStateProperty.resolveAs<BorderSide?>(
              native.side,
              states,
            );
            if (states == disabled) {
              expect(side, isNull);
            } else {
              expect(side!.color, palette.muted);
              expect(side.width, width == 0 ? 1 : width);
              passes(
                side.color,
                surface,
                3,
                'surface-separated contour $states',
              );
            }
          }
          expect(
            WidgetStateProperty.resolveAs<BorderSide?>(native.side, {
              WidgetState.selected,
            }),
            isNull,
          );
        },
      );

      test(
        'add and bulk reset use exactly one bounded state layer [$label]',
        () {
          for (final state in [rest, hover, focus, press, combined]) {
            final pressed = state.contains(WidgetState.pressed);
            final hovered = state.contains(WidgetState.hovered);
            final layered = pressed || hovered;
            final add = palette.addFill(state);
            final bulk = palette.bulkFill(state);
            expect(
              add,
              layered
                  ? Color.alphaBlend(roles.onSurface.withAlpha(20), surface)
                  : surface,
            );
            expect(
              bulk,
              layered
                  ? Color.alphaBlend(
                      roles.error.withAlpha(pressed ? 26 : 20),
                      surface,
                    )
                  : surface,
            );
            passes(palette.muted, add, 4.5, 'Add label $state');
            passes(
              palette.muted,
              add,
              3,
              'Add plus and inner perimeter $state',
            );
            passes(palette.muted, surface, 3, 'Add outer perimeter $state');
            passes(palette.error, bulk, 4.5, 'Reset filters label $state');
            passes(palette.error, bulk, 3, 'Reset filters graphic $state');
          }
        },
      );

      test(
        'quick labels checks and saving progress survive combined input states [$label]',
        () {
          final native = ListHeaderQuickChipTheme.resolve(theme);
          expect(native.splashFactory, NoSplash.splashFactory);
          expect(native.splashColor, Colors.transparent);
          expect(native.focusColor, Colors.transparent);
          expect(native.hoverColor, Colors.transparent);
          expect(native.highlightColor, roles.onSurface.withAlpha(20));
          for (final state in [rest, hover, focus, press, combined]) {
            final pressed = state.contains(WidgetState.pressed);
            final unselected = pressed
                ? Color.alphaBlend(native.highlightColor, surface)
                : surface;
            final selected = pressed
                ? Color.alphaBlend(
                    native.highlightColor,
                    roles.secondaryContainer,
                  )
                : roles.secondaryContainer;
            passes(
              roles.onSurfaceVariant,
              unselected,
              4.5,
              'choice label $state',
            );
            passes(
              roles.onSecondaryContainer,
              selected,
              4.5,
              'selected label $state',
            );
            passes(
              roles.onSecondaryContainer,
              selected,
              3,
              'native check $state',
            );
            passes(roles.onSurface, unselected, 4.5, 'View label $state');
            passes(roles.primary, unselected, 3, 'Saving View spinner $state');
            passes(
              palette.muted,
              unselected,
              3,
              'unselected inner perimeter $state',
            );
            passes(
              palette.muted,
              surface,
              3,
              'unselected outer perimeter $state',
            );
          }
        },
      );

      test(
        'native and wrapped selectable chip paints pass contrast in every state [$label]',
        () {
          final native = ListHeaderQuickChipTheme.resolve(theme);
          const focusAndPress = {WidgetState.focused, WidgetState.pressed};
          for (final selected in [false, true]) {
            for (final enabled in [false, true]) {
              for (final input in [
                rest,
                hover,
                focus,
                press,
                focusAndPress,
                combined,
              ]) {
                final states = {
                  ...input,
                  if (selected) WidgetState.selected,
                  if (!enabled) WidgetState.disabled,
                };
                final base = palette.choiceFill(selected, enabled);
                final ink = palette.choiceInk(selected, enabled);
                final fill = enabled && states.contains(WidgetState.pressed)
                    ? Color.alphaBlend(native.highlightColor, base)
                    : base;
                final side = WidgetStateProperty.resolveAs<BorderSide?>(
                  native.chipTheme.side,
                  states,
                );
                final width = headerContourWidth(states);
                final wrapped = resolveHeaderChoicePaint(
                  palette,
                  states,
                  selected: selected,
                  solidSelection: true,
                );
                expect(wrapped.fill, fill);
                expect(wrapped.caption, ink);
                expect(wrapped.check, ink);
                expect(wrapped.perimeter, selected ? fill : palette.muted);
                expect(wrapped.contour, width);
                expect(base.a, 1.0);
                expect(ink.a, 1.0);
                passes(ink, fill, 4.5, 'selectable caption $states');
                passes(
                  ink,
                  fill,
                  3,
                  'selectable check and status dot rim $states',
                );

                if (!enabled) {
                  expect(width, 0);
                  expect(side, isNull);
                  expect(fill, base);
                } else if (width > 0) {
                  expect(side?.width, width);
                  expect(side?.color, palette.muted);
                  passes(
                    side!.color,
                    surface,
                    3,
                    'selectable separator $states',
                  );
                } else if (selected) {
                  expect(side, isNull);
                } else {
                  expect(side?.width, 1);
                  expect(side?.color, palette.muted);
                }

                for (final host in [surface, scheme.bg, scheme.subtle]) {
                  passes(
                    wrapped.perimeter,
                    host,
                    3,
                    'wrapped choice outer boundary $states',
                  );
                  if (selected) {
                    passes(
                      fill,
                      host,
                      3,
                      'selectable selected boundary $states',
                    );
                  } else {
                    passes(
                      palette.muted,
                      host,
                      3,
                      'selectable outer border $states',
                    );
                    passes(
                      palette.muted,
                      fill,
                      3,
                      'selectable inner border $states',
                    );
                  }
                  if (width > 0) {
                    passes(
                      side!.color,
                      host,
                      3,
                      'selectable outer contour $states',
                    );
                  }
                }
              }
            }
          }
          passes(palette.ink, surface, 3, 'selectable strip progress');
        },
      );

      test(
        'badge separates from surface and funnel at rest and during press [$label]',
        () {
          for (final states in [rest, press, combined]) {
            passes(
              palette.toolbarBadgeInk,
              palette.toolbarBadgeFill,
              4.5,
              'badge numeral $states',
            );
            passes(
              palette.toolbarBadgeFill,
              palette.toolbarBadgeRing,
              3,
              'badge inside ring $states',
            );
            passes(
              palette.toolbarBadgeRing,
              scheme.primary,
              3,
              'badge outside ring $states',
            );
            passes(
              palette.toolbarBadgeFill,
              surface,
              3,
              'badge on toolbar $states',
            );
            passes(scheme.onPrimary, scheme.primary, 3, 'funnel glyph $states');
            passes(palette.muted, surface, 3, 'funnel contour $states');
            passes(roles.error, surface, 3, 'search active dot $states');
          }
        },
      );

      test(
        'toolbar and search inks pass for normal, active and busy states [$label]',
        () {
          passes(
            palette.ink,
            surface,
            4.5,
            'title, input, toolbar glyphs and search actions',
          );
          passes(palette.muted, surface, 4.5, 'search hint');
          passes(scheme.primary, surface, 3, 'toolbar busy indicator');
          final selection = palette.searchSelection;
          passes(
            palette.ink,
            selection.selectionColor!,
            4.5,
            'selected query ink',
          );
          passes(selection.cursorColor!, surface, 3, 'cursor');
          passes(
            selection.selectionHandleColor!,
            selection.selectionColor!,
            3,
            'selection handle',
          );
          final tooltipLayer = brightness == Brightness.light
              ? Colors.grey[700]!.withAlpha(230)
              : Colors.white.withAlpha(230);
          passes(
            brightness == Brightness.light ? Colors.white : Colors.black,
            Color.alphaBlend(tooltipLayer, surface),
            4.5,
            'tooltip',
          );
          var residual = surface;
          for (var count = 1; count <= 3; count++) {
            residual = Color.alphaBlend(scheme.primary.withAlpha(26), residual);
            passes(
              scheme.primary,
              residual,
              3,
              'Item image override with $count residual layers',
            );
          }
        },
      );

      test(
        'keyboard range mark and selected query text pass contrast [$label]',
        () {
          final selection = palette.searchSelection;
          passes(palette.ink, surface, 3, 'keyboard selection range mark');
          passes(
            palette.ink,
            selection.selectionColor!,
            4.5,
            'selected query text and underline',
          );
          passes(
            selection.selectionHandleColor!,
            surface,
            3,
            'selection handle on the input surface',
          );
        },
      );

      test(
        'disabled actions are distinguishable and cannot activate [$label]',
        () {
          expect(palette.addFill(disabled), surface);
          expect(palette.bulkFill(disabled), surface);
          expect(palette.appliedFillFor(false), surface);
          expect(palette.appliedInkFor(false), palette.muted);
          expect(palette.appliedPerimeterFor(false), palette.muted);
          expect(headerContourWidth(disabled), 0);
          passes(palette.muted, surface, 4.5, 'disabled caption');
        },
      );
    }
  }

  test('applied filter ink falls back for a custom non-app primary', () {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    final palette = HeaderPalette(
      theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: Colors.yellow),
      ),
    );
    expect(palette.appliedInk, palette.ink);
    expect(
      contrast(palette.appliedInk, palette.appliedFill),
      greaterThanOrEqualTo(4.5),
    );
  });
}
