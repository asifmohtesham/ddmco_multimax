import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';

/// Read-only tab rendering the BOM Explosion Item child table
/// (field: exploded_items). Shows the fully-flattened raw material
/// list — same columns as ERPNext’s Exploded Items tab.
///
/// No interaction is exposed; the tab is intentionally view-only.
class BomExplodedItemsTab extends StatelessWidget {
  final List<BomExplodedItem> items;
  const BomExplodedItemsTab({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.device_hub_outlined,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'No exploded items',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Enable “Use Multi-Level BOM” to populate this list',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ExplodedItemCard(item: items[index], index: index),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────

class _ExplodedItemCard extends StatelessWidget {
  final BomExplodedItem item;
  final int index;
  const _ExplodedItemCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final qtyStr    = _fmtQty(item.qty);
    final rateStr   = item.rate   != null ? _fmtAmt(item.rate!)   : '-';
    final amountStr = item.amount != null ? _fmtAmt(item.amount!) : '-';

    return Card(
      elevation: 0,
      // Slightly different surface to visually distinguish from Items tab.
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.6),
          style: BorderStyle.solid,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: index + item code + read-only badge ──
            Row(
              children: [
                _IndexBadge(index: index, colorScheme: cs),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemCode,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((item.itemName ?? '').isNotEmpty)
                        Text(
                          item.itemName!,
                          style: text.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Read-only lock indicator
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Info row: Qty | Rate | Amount ──
            Row(
              children: [
                Expanded(
                  child: InfoBlock(
                    label: 'Qty',
                    value: '$qtyStr ${item.uom ?? ''}',
                    icon: Icons.straighten_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InfoBlock(
                    label: 'Rate',
                    value: rateStr,
                    icon: Icons.sell_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InfoBlock(
                    label: 'Amount',
                    value: amountStr,
                    icon: Icons.calculate_outlined,
                  ),
                ),
              ],
            ),

            // ── Source warehouse (only if set) ──
            if ((item.sourceWarehouse ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoBlock(
                label: 'Source Warehouse',
                value: item.sourceWarehouse,
                icon: Icons.warehouse_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtQty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(3);

  String _fmtAmt(double v) => v.toStringAsFixed(2);
}

// ── Index badge (shared visual language with BomItemsTab) ──────────────────────

class _IndexBadge extends StatelessWidget {
  final int index;
  final ColorScheme colorScheme;
  const _IndexBadge({required this.index, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Secondary container to visually distinguish from Items tab badge.
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
