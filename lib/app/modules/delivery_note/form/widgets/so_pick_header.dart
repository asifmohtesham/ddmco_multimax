import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/delivery_note/form/so_pick.dart';

/// Top of the DN Items tab while picking against a Sales Order: which order,
/// for whom, how far along, and what to do next — readable at arm's length.
class SoPickHeader extends StatelessWidget {
  final SoPickContext order;
  final SoPickProgress progress;
  final bool isEditable;

  const SoPickHeader({
    super.key,
    required this.order,
    required this.progress,
    required this.isEditable,
  });

  static String _qty(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final done = progress.isComplete;
    final accent = done
        ? (isDark ? AppColors.green300 : AppColors.green700)
        : scheme.primary;
    final barFill = done ? AppColors.green500 : scheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: scheme.textSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                '${progress.completeLines}/${progress.totalLines} lines',
                key: const Key('so_pick_lines'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.customerName?.isNotEmpty == true
                ? order.customerName!
                : order.customer,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: scheme.text,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 8,
              backgroundColor: scheme.subtle,
              valueColor: AlwaysStoppedAnimation(barFill),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.qr_code_scanner_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !isEditable
                      ? 'Picked ${_qty(progress.pickedQty)} of ${_qty(progress.pendingQty)}'
                      : done
                          ? 'Everything on this order is picked'
                          : 'Scan an item from this order · '
                              '${_qty(progress.pickedQty)} of ${_qty(progress.pendingQty)} picked',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: done ? accent : scheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
