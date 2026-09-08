import 'package:flutter/material.dart';

/// Trailing sentinel for a paginated DocType List View, rendered as the last
/// child of the [SliverList].
///
/// * [hasMore] `true`  → centred [CircularProgressIndicator] (loading the next
///   page).
/// * [hasMore] `false` → a muted "End of results" label.
///
/// [bottomPadding] should carry the safe-area / nav-bar inset so the final row
/// clears the bottom system UI.
class ListEndFooter extends StatelessWidget {
  const ListEndFooter({
    super.key,
    required this.hasMore,
    this.bottomPadding = 0,
    this.label,
  });

  final bool hasMore;
  final double bottomPadding;

  /// Replaces "End of results" — report lists put their count summary here.
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (hasMore) {
      return Padding(
        padding: EdgeInsets.only(top: 16, bottom: 16 + bottomPadding),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 16, bottom: 16 + bottomPadding),
      child: Center(
        child: Text(
          label ?? 'End of results',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
