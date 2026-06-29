import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Sticky footer of in-stock / need / short totals over the filtered rows.
class BomStockTotalsFooter extends StatelessWidget {
  final Map<String, num>? totals;
  final bool hasDemand;
  const BomStockTotalsFooter({
    super.key,
    required this.totals,
    required this.hasDemand,
  });

  @override
  Widget build(BuildContext context) {
    final t = totals;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
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
              _cell(theme, cs, 'Stock', formatQty(t['in_stock'])),
              if (hasDemand) _cell(theme, cs, 'Need', formatQty(t['required'])),
              if (hasDemand) _cell(theme, cs, 'Short', formatQty(t['shortage'])),
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
