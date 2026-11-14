import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

/// Delivered / Billed progress bars for a submitted Sales Order. Public so
/// the form screen (Task 4) can reuse it alongside the list card.
///
/// Colours follow the AppColors x700 (light) / x300 (dark) ink ramp — never
/// hard-coded white/grey. Delivered = green, Billed = blue.
class SoProgressRow extends StatelessWidget {
  const SoProgressRow({
    super.key,
    required this.perDelivered,
    required this.perBilled,
  });

  final double perDelivered;
  final double perBilled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deliveredColor = isDark ? AppColors.green300 : AppColors.green700;
    final billedColor = isDark ? AppColors.blue300 : AppColors.blue700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _bar(context, 'Delivered ${perDelivered.toStringAsFixed(0)}%',
            progressFraction(perDelivered), deliveredColor),
        const SizedBox(height: 6),
        _bar(context, 'Billed ${perBilled.toStringAsFixed(0)}%',
            progressFraction(perBilled), billedColor),
      ],
    );
  }

  Widget _bar(BuildContext context, String label, double value, Color color) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.textMuted)),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: scheme.subtle,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
