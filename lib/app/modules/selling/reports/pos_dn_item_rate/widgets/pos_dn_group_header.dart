import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';

/// Collapsible group header for the report. Primary headers read bold on a
/// tinted surface; secondary headers are indented and lighter. Theme-aware
/// only — no hardcoded surfaces/inks.
class PosDnGroupHeader extends StatelessWidget {
  final GroupNode node;
  final bool isSecondary;
  final bool isExpanded;
  final VoidCallback onToggle;

  const PosDnGroupHeader({
    super.key,
    required this.node,
    required this.isSecondary,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg =
        isSecondary ? cs.surfaceContainerLow : cs.surfaceContainerHighest;

    return Padding(
      padding: EdgeInsets.only(left: isSecondary ? 16 : 0, bottom: 6, top: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedExpandIcon(isExpanded: isExpanded),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.key,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          isSecondary ? FontWeight.w600 : FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                _CountBadge(count: node.count),
                const SizedBox(width: 10),
                _QtyTotals(posQty: node.posQty, dnQty: node.dnQty),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary),
      ),
    );
  }
}

class _QtyTotals extends StatelessWidget {
  final num posQty;
  final num dnQty;
  const _QtyTotals({required this.posQty, required this.dnQty});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 12,
      fontFamily: 'ShureTechMono',
      color: cs.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('POS ${formatQty(posQty)}', style: style),
        Text('DN ${formatQty(dnQty)}', style: style),
      ],
    );
  }
}
