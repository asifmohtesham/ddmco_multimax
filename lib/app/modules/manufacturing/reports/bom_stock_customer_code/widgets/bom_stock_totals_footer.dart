import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_fields.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Sticky footer of in-stock / need / short totals over the filtered rows.
class BomStockTotalsFooter extends StatelessWidget {
  final Map<String, num>? totals;
  final bool hasDemand;
  final bool shortageMeasured;
  final FieldsState? fields;
  const BomStockTotalsFooter({
    super.key,
    required this.totals,
    required this.hasDemand,
    this.shortageMeasured = true,
    this.fields,
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
              Text(
                'Total',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _cell(theme, cs, 'in_stock_qty', t['in_stock']),
              if (hasDemand) _cell(theme, cs, 'required_qty', t['required']),
              if (hasDemand)
                _cell(
                  theme,
                  cs,
                  'shortage_qty',
                  shortageMeasured ? t['shortage'] : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(ThemeData theme, ColorScheme cs, String key, num? value) {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              bomStockLabel(key, fields),
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              formatQty(value),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFamily: 'ShureTechMono',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
