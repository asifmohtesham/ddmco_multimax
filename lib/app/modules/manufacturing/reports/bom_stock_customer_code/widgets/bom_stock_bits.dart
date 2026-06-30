import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Green (covered) / red (short) accent. Green is the design-system success
/// token, theme-aware; red is the scheme error color.
Color coverageAccent(BuildContext context, bool short) {
  if (short) return Theme.of(context).colorScheme.error;
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.green300
      : AppColors.green500;
}

/// Demand status pill: green "Covered" or red "Short N".
class StatusPill extends StatelessWidget {
  final num shortage;
  const StatusPill({super.key, required this.shortage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final short = shortage > 0;
    final accent = coverageAccent(context, short);
    final bg = short ? cs.errorContainer : accent.withValues(alpha: 0.14);
    final fg = short ? cs.onErrorContainer : accent;
    final icon = short ? Icons.warning_amber_rounded : Icons.check_circle_outline;
    final label = short ? 'Short ${formatQty(shortage)}' : 'Covered';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// Label-over-value stat cell. `alert` paints the value in the error color.
class StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const StatCell({super.key, required this.label, required this.value, this.alert = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'ShureTechMono',
              color: alert ? cs.error : null,
            )),
      ],
    );
  }
}
