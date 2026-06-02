import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/material_request_model.dart';

/// Upgraded M3 item card for Material Request.
/// Preserves all existing props (item, onTap, onDelete) — zero breaking changes.
/// Visual upgrades:
///   • colorScheme tokens instead of hard-coded colours
///   • Animated LinearProgressIndicator with semantic colours
///   • Stat pills using surfaceContainerHighest
///   • Warehouse badge row at the bottom
class MaterialRequestItemCard extends StatelessWidget {
  final MaterialRequestItem item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const MaterialRequestItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final double progress =
        (item.qty > 0) ? (item.orderedQty / item.qty).clamp(0.0, 1.0) : 0.0;
    final bool isComplete = progress >= 1.0;
    final bool hasStarted = progress > 0;

    // Semantic progress colour: green = done, amber = partial, primary = not started
    final Color progressColor = isComplete
        ? Colors.green.shade600
        : hasStarted
            ? Colors.amber.shade700
            : colorScheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isComplete
              ? Colors.green.shade200
              : colorScheme.outlineVariant,
        ),
      ),
      color: isComplete
          ? Colors.green.shade50
          : colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: item code / name + delete ─────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.itemCode,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold),
                        ),
                        if (item.itemName != null &&
                            item.itemName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.itemName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline,
                            size: 20, color: colorScheme.error),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),
              Divider(height: 1, color: colorScheme.outlineVariant),
              const SizedBox(height: 10),

              // ── Progress bar ──────────────────────────────────────────────
              if (item.qty > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor:
                              colorScheme.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(progressColor),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: progressColor),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // ── Stat pills row ────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStat(context, 'Qty',
                      '${item.qty} ${item.uom ?? ''}',
                      isPrimary: true),
                  _buildStat(context, 'Ordered',
                      '${item.orderedQty}',
                      color: hasStarted ? progressColor : null),
                  if (item.receivedQty > 0)
                    _buildStat(context, 'Received',
                        '${item.receivedQty}'),
                  if (item.actualQty > 0)
                    _buildStat(context, 'In Stock',
                        '${item.actualQty}'),
                ],
              ),

              // ── Warehouse badge ───────────────────────────────────────────
              if (item.warehouse != null &&
                  item.warehouse!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store_outlined,
                          size: 13,
                          color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item.warehouse!,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, String value,
      {bool isPrimary = false, Color? color}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color:
                color ?? (isPrimary ? colorScheme.primary : colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}
