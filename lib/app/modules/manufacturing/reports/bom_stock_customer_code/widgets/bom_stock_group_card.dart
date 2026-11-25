import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_fields.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart';

/// Collapsible Customer Code group, mirroring the POS Upload ItemGroupCard.
class BomStockGroupCard extends StatelessWidget {
  final BomStockGroup group;
  final bool expanded;
  final VoidCallback onToggle;
  final FieldsState? fields;
  final Widget Function(Widget)? anchorHeader;
  final Widget Function(int, Widget)? anchorLine;
  const BomStockGroupCard({
    super.key,
    required this.group,
    required this.expanded,
    required this.onToggle,
    this.fields,
    this.anchorHeader,
    this.anchorLine,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasStatus = group.anyShort || group.shortageMeasured;
    final accent = hasStatus
        ? coverageAccent(context, group.anyShort)
        : cs.outlineVariant;
    final count = '${group.itemCount} item${group.itemCount == 1 ? '' : 's'}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            start: 0,
            width: 4,
            top: 0,
            bottom: 0,
            child: ColoredBox(color: accent),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Column(
              children: [
                (anchorHeader ?? _header)(
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
                                Text(
                                  bomStockLabel('customer_code', fields),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  group.code.isEmpty ? 'No code' : group.code,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'ShureTechMono',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  count,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hasStatus)
                            StatusPill(shortage: group.totalShortage)
                          else
                            Text(
                              '—',
                              semanticsLabel:
                                  '${bomStockLabel('shortage_qty', fields)} unavailable',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          const SizedBox(width: 4),
                          AnimatedExpandIcon(isExpanded: expanded),
                        ],
                      ),
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
                            for (final (index, row) in group.rows.indexed)
                              (anchorLine ?? _line)(
                                index,
                                BomStockLineRow(row: row, fields: fields),
                              ),
                            const SizedBox(height: 4),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _header(Widget child) => child;
  static Widget _line(int index, Widget child) => child;
}
