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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow, // M3 Surface
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const Divider(),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sortOptions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Sort By',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: sortOptions.map((option) {
                          final isSelected = currentSortField == option.field;
                          return FilterChip(
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
                          );
                        }).toList(),
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
                    const SizedBox(height: 16),
                    ...filterWidgets.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: w,
                    )),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Actions
            FilledButton(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Show Results'),
            ),
          ],
        ),
      ),
    );
  }
}