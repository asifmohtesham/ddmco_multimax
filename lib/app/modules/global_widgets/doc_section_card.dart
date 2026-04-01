import 'package:flutter/material.dart';

/// A zero-elevation, titled section card used to visually group related
/// fields in DocType form screens.
///
/// Mirrors the private `_buildSectionCard` pattern used in [BatchFormScreen]
/// and equivalent form screens across the app. Centralising it here means
/// any update to padding, radius, or colour tokens propagates everywhere.
///
/// The widget is intentionally free of Rx / GetX. Callers wrap it in `Obx`
/// at whatever granularity their reactivity requires.
///
/// ## Tokens used (M3 ColorScheme)
/// | Token                     | Role                         |
/// |---------------------------|------------------------------|
/// | `surfaceContainerLow`     | card background fill         |
/// | `outlineVariant` α 0.5    | card border                  |
/// | `primary`                 | section title colour         |
/// | `titleSmall` bold         | section title text style     |
///
/// ## Usage
///
/// ```dart
/// DocSectionCard(
///   title: 'General Information',
///   headerAction: StatusPill(status: controller.batchStatus),
///   children: [
///     TextFormField(...),
///     const SizedBox(height: 16),
///     TextFormField(...),
///   ],
/// )
/// ```
class DocSectionCard extends StatelessWidget {
  /// Section heading displayed at the top-left of the card.
  final String title;

  /// Widgets rendered inside the card, below the title row.
  ///
  /// Callers are responsible for inter-widget spacing (e.g.
  /// `SizedBox(height: 16)` between fields) just as in the
  /// original `_buildSectionCard` usage.
  final List<Widget> children;

  /// Optional widget placed at the trailing edge of the header row.
  ///
  /// Typical use: a [StatusPill] or a small [IconButton].
  final Widget? headerAction;

  const DocSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (headerAction != null) headerAction!,
              ],
            ),
            const SizedBox(height: 16),
            // ── Section content ───────────────────────────────────────────
            ...children,
          ],
        ),
      ),
    );
  }
}
