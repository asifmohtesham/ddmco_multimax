import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_logic.dart';

/// Segment fills — the report's own three hour buckets. Untracked is a
/// neutral, since it is the absence of logged time.
const Color kBilledFill = AppColors.blue500;
const Color kNonBilledFill = AppColors.purple500;

/// One employee of the utilisation report: utilisation %, a stacked bar of
/// billed / non-billed / untracked hours against the period's total, and the
/// hour figures behind it.
class UtilizationCard extends StatelessWidget {
  const UtilizationCard({super.key, required this.row});

  final EmployeeUtilizationRow row;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pctInk = row.belowTarget
        ? (isDark ? AppColors.red300 : AppColors.red700)
        : (isDark ? AppColors.green300 : AppColors.green700);
    final (billed, nonBilled, untracked) = row.shares;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.fg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: s.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(initials: _initials(row.employeeName), size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: s.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      [
                        row.employee,
                        if (row.department != null) row.department!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: s.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatPercent(row.utilization),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: pctInk,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'billed ${formatPercent(row.billedUtilization)}',
                    style: TextStyle(fontSize: 11, color: s.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  _segment(billed, kBilledFill),
                  _segment(nonBilled, kNonBilledFill),
                  _segment(untracked, s.borderStrong),
                  _segment(1 - billed - nonBilled - untracked, s.subtle),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Legend(
                color: kBilledFill,
                label: 'Billed',
                value: formatHours(row.billedHours),
              ),
              _Legend(
                color: kNonBilledFill,
                label: 'Non-billed',
                value: formatHours(row.nonBilledHours),
              ),
              _Legend(
                color: s.borderStrong,
                label: 'Untracked',
                value: formatHours(row.untrackedHours),
              ),
              _Legend(label: 'of', value: formatHours(row.totalHours)),
            ],
          ),
        ],
      ),
    );
  }

  /// Flex needs integers; thousandths keep thin segments visible.
  Widget _segment(double share, Color color) {
    final flex = (share * 1000).round();
    if (flex <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: flex,
      child: ColoredBox(color: color),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _Legend extends StatelessWidget {
  const _Legend({this.color, required this.label, required this.value});

  final Color? color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text('$label ', style: TextStyle(fontSize: 11, color: s.textMuted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: s.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
