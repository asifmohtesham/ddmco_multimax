import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Sticky footer showing the report's server-computed total row.
class BomStockTotalsFooter extends StatelessWidget {
  final Map<String, dynamic>? total;
  const BomStockTotalsFooter({super.key, required this.total});

  @override
  Widget build(BuildContext context) {
    final t = total;
    if (t == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      color: cs.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text('Total',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              _cell(theme, cs, 'In Stock', formatQty(t['in_stock_qty'] as num?)),
              _cell(theme, cs, 'Required', formatQty(t['required_qty'] as num?)),
              _cell(theme, cs, 'Running', formatQty(t['running_total'] as num?)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(ThemeData theme, ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
