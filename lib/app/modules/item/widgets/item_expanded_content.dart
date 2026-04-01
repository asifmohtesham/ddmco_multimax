import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Expanded detail section shown beneath a list card or inside the grid
/// preview bottom sheet.
///
/// Renders:
///  - optional item description
///  - customer reference codes table
///  - per-warehouse stock balance rows
///  - a "View Full Details" button that navigates to ITEM_FORM
class ItemExpandedContent extends StatelessWidget {
  final Item item;
  final List<WarehouseStock>? stockList;
  final bool isLoading;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const ItemExpandedContent({
    super.key,
    required this.item,
    required this.stockList,
    required this.isLoading,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        if (item.description != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              item.description!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // Customer References
        if (item.customerItems.isNotEmpty) ...[
          Text(
            'Customer References',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ...item.customerItems.map(
            (ci) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(ci.customerName,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  Text(ci.refCode,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold, color: cs.onSurface)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 12),
        ],

        // Stock Balance header
        Text(
          'Stock Balance',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),

        // Stock rows
        if (isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          )
        else if (stockList == null || stockList!.isEmpty)
          Text(
            'No stock data available.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          ...stockList!.map(
            (stock) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${stock.warehouse}'
                      '${stock.rack != null ? " (${stock.rack})" : ""}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    '${stock.quantity.toStringAsFixed(2)} '
                    '${item.stockUom ?? ""}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      // cs.tertiary for positive stock; cs.error for zero/negative.
                      // Avoids hardcoded Colors.green.shade600.
                      color: stock.quantity > 0 ? cs.tertiary : cs.error,
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: () => Get.toNamed(
              AppRoutes.ITEM_FORM,
              arguments: {'itemCode': item.itemCode},
            ),
            child: const Text('View Full Details'),
          ),
        ),
      ],
    );
  }
}
