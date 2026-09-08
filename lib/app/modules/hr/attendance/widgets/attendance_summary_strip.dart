import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

/// Four count tiles under the date row. A tapped tile becomes the active
/// status filter (selected state); "—" marks a count that does not apply to
/// the selected day (Absent before the cut-off, everything but Holiday on a
/// holiday).
class AttendanceSummaryStrip extends StatelessWidget {
  const AttendanceSummaryStrip({
    super.key,
    required this.counts,
    required this.isHoliday,
    required this.beforeCutoff,
    required this.selectedKey,
    required this.onToggle,
    this.loading = false,
  });

  final AttendanceCounts counts;
  final bool isHoliday;
  final bool beforeCutoff;
  final String? selectedKey;
  final ValueChanged<String> onToggle;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final tiles = isHoliday
        ? [
            _spec('Present', AppColors.green500, null),
            _spec('Late', AppColors.orange500, null),
            _spec('Not in yet', AppColors.gray500, null, label: 'Not in'),
            _spec('Holiday', AppColors.blue500, counts.holiday),
          ]
        : [
            _spec('Present', AppColors.green500, counts.present),
            _spec('Late', AppColors.orange500, counts.late),
            _spec('Not in yet', AppColors.gray500, counts.notIn, label: 'Not in'),
            _spec('Absent', AppColors.red500, beforeCutoff ? null : counts.absent),
          ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: BoxDecoration(
        color: s.fg,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: AttendanceSummaryTile(
                label: tiles[i].label,
                dot: tiles[i].dot,
                value: tiles[i].value,
                loading: loading,
                selected: selectedKey == tiles[i].key,
                onTap: tiles[i].value == null ? null : () => onToggle(tiles[i].key),
              ),
            ),
          ],
        ],
      ),
    );
  }

  ({String key, String label, Color dot, int? value}) _spec(
          String key, Color dot, int? value, {String? label}) =>
      (key: key, label: label ?? key, dot: dot, value: value);
}

class AttendanceSummaryTile extends StatelessWidget {
  const AttendanceSummaryTile({
    super.key,
    required this.label,
    required this.dot,
    required this.value,
    this.selected = false,
    this.loading = false,
    this.onTap,
  });

  final String label;
  final Color dot;

  /// `null` renders as "—" (not applicable today).
  final int? value;
  final bool selected;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDash = value == null;
    final isZero = value == 0;
    final valueColor = isDash || isZero ? s.textSubtle : s.text;

    return Material(
      color: selected ? Color.alphaBlend(s.primary.withValues(alpha: 0.08), s.fg) : s.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? s.primary : s.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isDash ? AppColors.gray400 : dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected ? s.primary : s.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: loading && !isDash
                    ? Container(
                        width: 24,
                        height: 20,
                        decoration: BoxDecoration(
                          color: s.subtle,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      )
                    : Text(
                        isDash ? '—' : '$value',
                        style: TextStyle(
                          fontSize: 22,
                          height: 1,
                          letterSpacing: -0.4,
                          fontWeight: isDash
                              ? FontWeight.w500
                              : isZero
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                          color: valueColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
