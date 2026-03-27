import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';

/// Renders the BOM Items child table (field: items) as a
/// scrollable list of read-only cards.
///
/// Each card mirrors the columns visible in the ERPNext BOM Items
/// child table: item code, item name, qty × uom, rate, amount,
/// source warehouse, and sub-assembly flag.
class BomItemsTab extends StatelessWidget {
  final List<BomItem> items;
  const BomItemsTab({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No items found'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _BomItemCard(item: items[index], index: index),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────

class _BomItemCard extends StatelessWidget {
  final BomItem item;
  final int index;
  const _BomItemCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final qtyStr    = _fmtQty(item.qty);
    final rateStr   = _fmtAmt(item.rate);
    final amountStr = item.amount != null ? _fmtAmt(item.amount!) : '-';

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: index badge + item code + sub-assembly tag ──
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
                if (item.isSubAssemblyItem == 1)
                  _SubAssemblyChip(colorScheme: cs),
              ],
            ),
            const SizedBox(height: 12),

            // ── Info row 1: Qty | Rate | Amount ──────────────────────────
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

            // ── Source warehouse (only if set) ─────────────────────────────
            if ((item.sourceWarehouse ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoBlock(
                label: 'Source Warehouse',
                value: item.sourceWarehouse,
                icon: Icons.warehouse_outlined,
              ),
            ],

            // ── Sub-assembly BOM link (no navigation — per spec) ──────────
            if ((item.bomNo ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoBlock(
                label: 'Sub-Assembly BOM',
                value: item.bomNo,
                icon: Icons.account_tree_outlined,
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

// ── Small reusable sub-widgets ───────────────────────────────────────────────────────────

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
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _SubAssemblyChip extends StatelessWidget {
  final ColorScheme colorScheme;
  const _SubAssemblyChip({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Sub-assembly',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}
