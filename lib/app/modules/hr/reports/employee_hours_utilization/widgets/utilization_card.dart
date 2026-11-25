import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_fields.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_logic.dart';

/// Segment fills — the report's own three hour buckets. Untracked is a
/// neutral, since it is the absence of logged time.
const Color kBilledFill = AppColors.blue500;
const Color kNonBilledFill = AppColors.purple500;

/// One employee of the utilisation report: utilisation %, a stacked bar of
/// billed / non-billed / untracked hours against the period's total, and the
/// hour figures behind it.
class UtilizationCard extends StatelessWidget {
  const UtilizationCard({super.key, required this.row, this.fields});

  final EmployeeUtilizationRow row;
  final FieldsState? fields;

  bool _shows(String key) => fields?.shows(key) ?? true;

  String _label(String key) =>
      fields?.label(key) ?? utilizationFields.label(key)!;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pctInk = row.belowTarget
        ? (isDark ? AppColors.red300 : AppColors.red700)
        : (isDark ? AppColors.green300 : AppColors.green700);
    final (billed, nonBilled, untracked) = row.shares;
    final showDepartment = _shows('department') && row.department != null;
    final utilization = formatPercent(row.utilization);
    final hours = [
      ('billed_hours', row.billedHours, kBilledFill),
      ('non_billed_hours', row.nonBilledHours, kNonBilledFill),
      ('untracked_hours', row.untrackedHours, s.borderStrong),
      ('total_hours', row.totalHours, null),
    ];
    final visibleHours = hours.where((entry) => _shows(entry.$1)).toList();
    final nameStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: s.text,
    );
    final detailStyle = TextStyle(fontSize: 11, color: s.textMuted);
    final percentStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: pctInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final billedText = _shows('per_util_billed_only')
        ? '${_label('per_util_billed_only')} '
              '${formatPercent(row.billedUtilization)}'
        : null;
    final billedCaption = billedText == null
        ? null
        : Text(billedText, textAlign: TextAlign.end, style: detailStyle);
    const avatarSize = 32.0;
    const avatarGap = 10.0;

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
          LayoutBuilder(
            builder: (context, constraints) {
              final available = math.max(
                0.0,
                constraints.maxWidth - avatarSize - avatarGap,
              );
              // Keep the employee name and ID readable when a returned
              // caption or the device's text scale needs more room.
              final identityWidth = billedText == null
                  ? 0.0
                  : math.max(
                      _textWidth(context, row.employeeName, nameStyle),
                      _textWidth(context, row.employee, detailStyle),
                    );
              final percentLimit = available / 2;
              final showBilledInline =
                  billedText != null &&
                  math.max(
                        _textWidth(context, billedText, detailStyle),
                        _textWidth(context, utilization, percentStyle),
                      ) <=
                      math.min(percentLimit, available - identityWidth);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      AppAvatar(
                        initials: _initials(row.employeeName),
                        size: avatarSize,
                      ),
                      const SizedBox(width: avatarGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.employeeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              [
                                row.employee,
                                if (showDepartment) row.department!,
                              ].join(' · '),
                              semanticsLabel: [
                                '${_label('employee')} ${row.employee}',
                                if (showDepartment)
                                  '${_label('department')} ${row.department}',
                              ].join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: detailStyle,
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: percentLimit),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              utilization,
                              semanticsLabel:
                                  '${_label('per_util')} $utilization, '
                                  '${row.belowTarget ? 'Below target' : 'At or above target'}',
                              textAlign: TextAlign.end,
                              style: percentStyle,
                            ),
                            if (showBilledInline) billedCaption!,
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (billedCaption != null && !showBilledInline) billedCaption,
                ],
              );
            },
          ),
          if (visibleHours.length == hours.length) ...[
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
          ],
          if (visibleHours.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final (key, value, color) in visibleHours)
                  _Legend(
                    color: color,
                    label: _label(key),
                    value: formatHours(value),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static double _textWidth(
    BuildContext context,
    String value,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
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
        Flexible(
          child: Text(
            '$label ',
            style: TextStyle(fontSize: 11, color: s.textMuted),
          ),
        ),
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
