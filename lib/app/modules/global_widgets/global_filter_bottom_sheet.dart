import 'package:flutter/material.dart';

class SortOption {
  final String label;
  final String field;
  const SortOption(this.label, this.field);
}

class GlobalFilterBottomSheet extends StatelessWidget {
  final String title;

  // Sort Configuration
  final List<SortOption> sortOptions;
  final String currentSortField;
  final String currentSortOrder;
  final Function(String field, String order) onSortChanged;

  // Filter Configuration
  final List<Widget> filterWidgets;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final int activeFilterCount;

  const GlobalFilterBottomSheet({
    super.key,
    this.title = 'Sort & Filter',
    required this.sortOptions,
    required this.currentSortField,
    required this.currentSortOrder,
    required this.onSortChanged,
    required this.filterWidgets,
    required this.onApply,
    required this.onClear,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 1. Get System Top Padding (Status Bar)
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    final bottomPadding = mediaQuery.viewPadding.bottom;

    return Container(
      // 2. Apply explicit margin to push sheet down from status bar
      margin: EdgeInsets.only(top: topPadding + 48),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      // 3. Clip ensures content scrolls cleanly under the rounded corners
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle Area
          Container(
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            alignment: Alignment.center,
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ),
          const Divider(),

          // Scrollable Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sortOptions.isNotEmpty) ...[
                    Text(
                      'Sort By',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: sortOptions.map((option) {
                          final isSelected = currentSortField == option.field;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(option.label),
                                  if (isSelected) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      currentSortOrder == 'desc'
                                          ? Icons.arrow_downward
                                          : Icons.arrow_upward,
                                      size: 16,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ],
                                ],
                              ),
                              selected: isSelected,
                              onSelected: (bool selected) {
                                String newOrder = 'desc';
                                if (isSelected) {
                                  newOrder = currentSortOrder == 'desc' ? 'asc' : 'desc';
                                }
                                onSortChanged(option.field, newOrder);
                              },
                              showCheckmark: false,
                              selectedColor: colorScheme.secondaryContainer,
                              labelStyle: TextStyle(
                                color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isSelected ? Colors.transparent : colorScheme.outline,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  Text(
                    'Filter Options',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  // const SizedBox(height: 16),
                  ...filterWidgets.map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 0.0),
                    child: w,
                  )),
                ],
              ),
            ),
          ),

          // Bottom Action Bar (Sticky)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding + 16),
            child: FilledButton(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                activeFilterCount > 0
                    ? 'Show $activeFilterCount Result${activeFilterCount > 1 ? 's' : ''}'
                    : 'Show Results',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}