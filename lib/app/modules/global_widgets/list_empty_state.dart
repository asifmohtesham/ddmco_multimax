import 'package:flutter/material.dart';

/// Standard empty-state panel for a DocType List View.
///
/// Two variants, selected by [hasActiveFilters]:
/// * **filtered** — search/filters are active but matched nothing. Shows a
///   `filter_alt_off` icon and a "Clear Filters" action.
/// * **empty** — no rows exist at all. Shows [emptyIcon] and a "Reload" action.
///
/// This consolidates the empty-state markup that was copy-pasted (with drift —
/// e.g. `Icons.clear_all` vs `Icons.filter_alt_off`, differing button labels)
/// across Item, Delivery Note and Work Order.
///
/// Returns a plain (box) widget; wrap it in a sliver at the call site, e.g.
/// `SliverFillRemaining(hasScrollBody: false, child: ListEmptyState(...))`.
class ListEmptyState extends StatelessWidget {
  const ListEmptyState({
    super.key,
    required this.hasActiveFilters,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.filteredTitle,
    required this.filteredMessage,
    required this.onClearFilters,
    required this.onReload,
  });

  /// Whether any filter or search query is active.
  final bool hasActiveFilters;

  /// Icon shown when the list is genuinely empty (no filters).
  final IconData emptyIcon;

  final String emptyTitle;
  final String emptyMessage;
  final String filteredTitle;
  final String filteredMessage;

  final VoidCallback onClearFilters;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final icon = hasActiveFilters ? Icons.filter_alt_off_outlined : emptyIcon;
    final title = hasActiveFilters ? filteredTitle : emptyTitle;
    final message = hasActiveFilters ? filteredMessage : emptyMessage;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (hasActiveFilters)
              FilledButton.tonalIcon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Clear Filters'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: onReload,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload'),
              ),
          ],
        ),
      ),
    );
  }
}
