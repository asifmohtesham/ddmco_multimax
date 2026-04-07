import 'package:flutter/material.dart';

/// Single source of truth for all shared app-bar visual values.
///
/// Using a constants class instead of scattering magic numbers across
/// [MainAppBar] and [DocTypeListHeader] means every future colour or
/// size adjustment is a one-line edit that propagates app-wide.
///
/// ## Usage
///
/// ```dart
/// backgroundColor: AppBarTokens.background(context),
/// foregroundColor: AppBarTokens.foreground(context),
/// iconTheme: IconThemeData(
///   color: AppBarTokens.foreground(context),
///   size:  AppBarTokens.iconSize,
/// ),
/// ```
///
/// ## Design rationale — Option 2 (surface background)
///
/// Both the Dashboard and all DocType list screens use
/// `colorScheme.surface` (white in light mode, dark surface in dark
/// mode) as their app-bar background.  This keeps the UI clean and
/// Material 3 idiomatic, and makes the title/icon colour `onSurface`
/// rather than `onPrimary`, matching the rest of the screen chrome.
abstract final class AppBarTokens {
  // ── Background / foreground ──────────────────────────────────────────

  /// Background for ALL app bars app-wide.
  ///
  /// Option 2 (surface): white in light mode, dark surface in dark mode.
  /// Keeps the UI clean and Material 3 idiomatic.
  static Color background(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  /// Icon + title foreground colour for all app bars.
  static Color foreground(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  /// Primary-tinted label colour for list-screen collapsed toolbar titles.
  ///
  /// Preserves the visible brand accent from the current design while
  /// keeping it expressed as a semantic token, not a hardcode.
  static Color titleAccent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  // ── Icon geometry ────────────────────────────────────────────────────

  /// Shared icon size for leading and action icons.
  static const double iconSize = 24.0;

  /// Minimum tap-target for all icon buttons (WCAG / Material touch targets).
  static const BoxConstraints iconConstraints =
      BoxConstraints(minWidth: 44, minHeight: 44);

  // ── Action density ───────────────────────────────────────────────────

  /// Maximum number of action icons shown inline in the toolbar.
  ///
  /// Any actions beyond this cap are collapsed into a trailing
  /// [PopupMenuButton] so the toolbar never overflows on narrow devices
  /// and the icon density stays visually balanced across all screens.
  static const int maxVisibleActions = 3;

  // ── Elevation ────────────────────────────────────────────────────────

  /// Shadow elevation applied when body content scrolls under the
  /// pinned bar, providing a depth cue without a persistent static shadow.
  static const double scrolledUnderElevation = 1.0;
}
