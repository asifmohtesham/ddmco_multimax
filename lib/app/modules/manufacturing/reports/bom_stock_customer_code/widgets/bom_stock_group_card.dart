import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart';

/// Collapsible Customer Code group, mirroring the POS Upload ItemGroupCard.
class BomStockGroupCard extends StatelessWidget {
  final BomStockGroup group;
  final bool expanded;
  final VoidCallback onToggle;
  const BomStockGroupCard({
    super.key,
    required this.group,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = coverageAccent(context, group.anyShort);
    final title = group.code.isEmpty ? 'No code' : 'Code ${group.code}';
    final count = '${group.itemCount} item${group.itemCount == 1 ? '' : 's'}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Column(
                children: [
                  InkWell(
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    style: theme.textTheme.bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(count,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          StatusPill(shortage: group.totalShortage),
                          const SizedBox(width: 4),
                          AnimatedExpandIcon(isExpanded: expanded),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: !expanded
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              Divider(height: 1, color: cs.outlineVariant),
                              const SizedBox(height: 4),
                              ...group.rows.map((r) => BomStockLineRow(row: r)),
                              const SizedBox(height: 4),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
