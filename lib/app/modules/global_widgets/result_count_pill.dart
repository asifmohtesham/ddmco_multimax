import 'package:flutter/material.dart';

/// Standard "N items" result-count pill shown at the top of every DocType
/// List View, directly below the [DocTypeListHeader].
///
/// Previously this markup was copy-pasted verbatim into each list screen
/// (Item, Delivery Note, …) with per-screen noun and icon. It is now a single
/// widget so spacing, colours and the filter indicator never drift.
///
/// The caller keeps the reactive [Obx]; this widget receives already-resolved
/// values:
///
/// ```dart
/// SliverToBoxAdapter(
///   child: Obx(() {
///     if (controller.isLoading.value && controller.items.isEmpty) {
///       return const SizedBox.shrink();
///     }
///     return ResultCountPill(
///       count: controller.items.length,
///       hasMore: controller.hasMore.value,
///       hasActiveFilters: controller.hasFilters,
///       noun: 'item',
///       icon: Icons.inventory_2_outlined,
///     );
///   }),
/// );
/// ```
class ResultCountPill extends StatelessWidget {
  const ResultCountPill({
    super.key,
    required this.count,
    required this.hasMore,
    required this.hasActiveFilters,
    required this.noun,
    required this.icon,
    this.pluralNoun,
  });

  /// Number of rows currently loaded.
  final int count;

  /// Whether more pages remain (renders the count as `N+`).
  final bool hasMore;

  /// Whether any filter or search query is active (renders the filter dot).
  final bool hasActiveFilters;

  /// Singular noun for the row type, e.g. `'item'`, `'note'`. The plural form
  /// is derived by appending `s` unless [pluralNoun] is supplied.
  final String noun;

  /// Leading icon, typically the DocType's representative icon.
  final IconData icon;

  /// Explicit plural for irregular nouns (e.g. `'entries'` for `'entry'`).
  /// Defaults to `'${noun}s'`.
  final String? pluralNoun;

  String get _plural => pluralNoun ?? '${noun}s';

  String get _label =>
      hasMore ? '$count+ $_plural' : '$count ${count == 1 ? noun : _plural}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: cs.onSecondaryContainer),
                const SizedBox(width: 6),
                Text(
                  _label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasActiveFilters) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.filter_alt,
                    size: 12,
                    color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
