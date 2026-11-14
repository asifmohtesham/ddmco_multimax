import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

/// One `Item.reorder_levels` row.
///
/// Reads as: *check stock across `warehouseGroup`, raise the request against
/// `warehouse`* — which is exactly what the ERPNext reorder engine does.
///
/// [onEdit]/[onDelete] null → read-only (no overflow menu). The Re-order tab
/// passes null when the user lacks `Item:write`.
class ReorderRuleCard extends StatelessWidget {
  const ReorderRuleCard({
    super.key,
    required this.rule,
    required this.index,
    this.onEdit,
    this.onDelete,
  });

  final ItemReorder rule;

  /// Zero-based position; rendered 1-based to match the server's "Row #N".
  final int index;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final editable = onEdit != null || onDelete != null;

    // A blank group behaves as the warehouse itself (item.py:508-509), so show
    // that rather than an empty arrow.
    final group = (rule.warehouseGroup == null || rule.warehouseGroup!.isEmpty)
        ? rule.warehouse
        : rule.warehouseGroup!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.textMuted),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward,
                          size: 14, color: scheme.textSubtle),
                    ),
                    Flexible(
                      child: Text(
                        rule.warehouse,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Re-order at '
                  '${FormattingHelper.formatQtyGrouped(rule.warehouseReorderLevel)}'
                  ' · Order '
                  '${FormattingHelper.formatQtyGrouped(rule.warehouseReorderQty)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  rule.materialRequestType.isEmpty
                      ? 'No request type'
                      : rule.materialRequestType,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.textSubtle),
                ),
              ],
            ),
          ),
          if (editable)
            PopupMenuButton<String>(
              tooltip: 'Rule ${index + 1} actions',
              icon: Icon(Icons.more_vert, color: scheme.textSubtle),
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }
}
