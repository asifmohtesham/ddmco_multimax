import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/attendance_summary_strip.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';

/// "Today's attendance" summary on the Dashboard — headline, four count
/// tiles, up to three attention-first employee rows and
/// a View all link. Public and controller-free (like the other dashboard
/// widgets) so widget tests can pump it in every state.
///
/// Everything inside is reused from the Attendance screen; the only decision
/// made here is which headline / tile / row set fits the day:
/// holiday › beforeCutoff › looksOffline › counts. The viewer's own status
/// lives in MyAttendanceCard, and only a System Manager is told the terminal
/// may be offline.
class DashboardAttendanceCard extends StatelessWidget {
  const DashboardAttendanceCard({
    super.key,
    required this.counts,
    required this.shift,
    required this.now,
    required this.onViewAll,
    required this.onRowTap,
    this.isHoliday = false,
    this.beforeCutoff = false,
    this.looksOffline = false,
    this.latestPunch,
    this.highlights = const [],
    this.isSystemManager = false,
    this.loadedAt,
    this.isLoading = false,
  });

  final AttendanceCounts counts;
  final ShiftRules shift;
  final DateTime now;
  final bool isHoliday;
  final bool beforeCutoff;
  final bool looksOffline;
  final DateTime? latestPunch;
  final List<EmployeeDayStatus> highlights;

  /// Only a System Manager sees the terminal diagnosis (spec §3.3).
  final bool isSystemManager;
  final DateTime? loadedAt;
  final bool isLoading;
  final VoidCallback onViewAll;
  final ValueChanged<EmployeeDayStatus> onRowTap;

  bool get _skeleton => isLoading && loadedAt == null;

  /// With zero punches for anyone, every tracked row derives as Absent so
  /// far — rows nobody can act on, so the card hides them and dashes the tiles.
  bool get _showRows => !_skeleton && !looksOffline;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final rows = _showRows ? highlights : const <EmployeeDayStatus>[];

    return Material(
      color: s.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: s.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeadline(context),
            const SizedBox(height: 12),
            _buildTiles(),
            for (var i = 0; i < rows.length; i++) ...[
              SizedBox(height: i == 0 ? 12 : 9),
              EmployeeAttendanceCard(row: rows[i], onTap: () => onRowTap(rows[i])),
            ],
            if (!_skeleton) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 16),
                  label: const Text('View all',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Headline ──────────────────────────────────────────────────────────────

  (String, String) _copy() {
    final inCount = counts.present + counts.late;
    if (isHoliday) {
      return ('Holiday today', '${DateFormat('EEEE').format(now)} · no attendance expected');
    }
    if (beforeCutoff) {
      return ('Shift starts ${shift.startLabel}',
          '$inCount in so far · late after ${shift.cutoffLabel}');
    }
    if (looksOffline) {
      if (!isSystemManager) {
        return ('No check-ins recorded yet', 'Statuses will appear as check-ins arrive');
      }
      final last = latestPunch == null
          ? 'terminal may be offline'
          : 'Last punch ${DateFormat('d MMM HH:mm').format(latestPunch!)} · terminal may be offline';
      return ('No punches yet today', last);
    }
    return ('$inCount of ${counts.tracked} in',
        '${counts.late} late · ${counts.absent} absent so far');
  }

  Widget _buildHeadline(BuildContext context) {
    final s = context.scheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stale = isStale(loadedAt, now);
    final freshColor = stale ? (dark ? AppColors.orange300 : AppColors.orange700) : s.textMuted;
    final (h1, h2) = _skeleton ? ('', '') : _copy();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg),
            borderRadius: BorderRadius.circular(AppRadius.md + 2),
          ),
          child: Icon(Icons.how_to_reg_rounded, size: 21, color: s.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _skeleton
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBar(width: 110, height: 15, color: s.subtle),
                    const SizedBox(height: 6),
                    _SkeletonBar(width: 150, height: 11, color: s.subtle),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.15,
                        height: 1.2,
                        color: s.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      h2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: s.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(stale ? Icons.warning_amber_rounded : Icons.schedule,
                  size: 13, color: freshColor),
              const SizedBox(width: 4),
              Text(
                freshnessLabel(loadedAt, now),
                style: TextStyle(fontSize: 11.5, color: freshColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tiles ─────────────────────────────────────────────────────────────────

  Widget _buildTiles() {
    // Same "—" rules as AttendanceSummaryStrip, plus all-dashed when offline.
    final int? present, late, notIn;
    final (String, Color, int?) last;
    if (_skeleton) {
      (present, late, notIn) = (0, 0, 0);
      last = ('Absent', AppColors.red500, 0);
    } else if (isHoliday) {
      (present, late, notIn) = (null, null, null);
      last = ('Holiday', AppColors.blue500, counts.holiday);
    } else if (looksOffline) {
      (present, late, notIn) = (null, null, null);
      last = ('Absent', AppColors.red500, null);
    } else {
      (present, late, notIn) = (counts.present, counts.late, counts.notIn);
      last = ('Absent', AppColors.red500, beforeCutoff ? null : counts.absent);
    }
    final tiles = [
      ('Present', AppColors.green500, present),
      ('Late', AppColors.orange500, late),
      ('Not in', AppColors.gray500, notIn),
      last,
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: AttendanceSummaryTile(
              label: tiles[i].$1,
              dot: tiles[i].$2,
              value: tiles[i].$3,
              loading: _skeleton,
            ),
          ),
        ],
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height, required this.color});
  final double width, height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      );
}
