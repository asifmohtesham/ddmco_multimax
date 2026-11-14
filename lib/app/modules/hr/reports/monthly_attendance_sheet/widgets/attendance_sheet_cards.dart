import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/month/attendance_month_screen.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_logic.dart';

/// Day keys the report uses for both column fieldnames and row keys.
final DateFormat kSheetDayKey = DateFormat('dd-MM-yyyy');

/// Status ramp triple `(base500, text700, text300)`, following the StatusPill
/// convention: `500` fills, `700`/`300` inks. Desk paints Half Day / Other Half
/// Present purple, which the app ramp also carries.
(Color, Color, Color) sheetStatusRamp(SheetStatus status) => switch (status) {
      SheetStatus.present =>
        (AppColors.green500, AppColors.green700, AppColors.green300),
      SheetStatus.absent =>
        (AppColors.red500, AppColors.red700, AppColors.red300),
      SheetStatus.halfDayAbsent =>
        (AppColors.orange500, AppColors.orange700, AppColors.orange300),
      SheetStatus.halfDayPresent =>
        (AppColors.yellow500, AppColors.yellow700, AppColors.yellow300),
      SheetStatus.workFromHome =>
        (AppColors.purple500, AppColors.purple700, AppColors.purple300),
      SheetStatus.onLeave =>
        (AppColors.blue500, AppColors.blue700, AppColors.blue300),
      SheetStatus.holiday || SheetStatus.weeklyOff =>
        (AppColors.gray400, AppColors.gray600, AppColors.gray400),
      SheetStatus.unmarked =>
        (AppColors.gray400, AppColors.gray600, AppColors.gray400),
    };

/// Fill colour for a strip cell / dot.
Color sheetStatusFill(SheetStatus status) => sheetStatusRamp(status).$1;

/// Ink colour for status text, resolved for the active brightness.
Color sheetStatusInk(SheetStatus status, bool isDark) {
  final (_, light, dark) = sheetStatusRamp(status);
  return isDark ? dark : light;
}

/// The app's live-derived status that best represents a reported one, so the
/// existing [AttendanceCalendarGrid] can render the report's data unchanged.
AttendanceStatus? toAttendanceStatus(SheetStatus status) => switch (status) {
      SheetStatus.present => AttendanceStatus.present,
      SheetStatus.absent => AttendanceStatus.absent,
      SheetStatus.halfDayAbsent || SheetStatus.halfDayPresent =>
        AttendanceStatus.halfDay,
      SheetStatus.workFromHome => AttendanceStatus.workFromHome,
      SheetStatus.onLeave => AttendanceStatus.onLeave,
      SheetStatus.holiday || SheetStatus.weeklyOff => AttendanceStatus.holiday,
      SheetStatus.unmarked => null,
    };

// ---------------------------------------------------------------------------
// Day strip
// ---------------------------------------------------------------------------

/// One cell per day of the reported period, in server order. Too narrow for
/// text at month length — the cards expand to a calendar for the dates.
class SheetDayStrip extends StatelessWidget {
  const SheetDayStrip({
    super.key,
    required this.days,
    required this.statusOn,
    this.height = 18,
  });

  final List<SheetDay> days;
  final SheetStatus Function(String dayKey) statusOn;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: Tooltip(
                message: '${day.label} — ${statusOn(day.key).label}',
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: statusOn(day.key) == SheetStatus.unmarked
                        ? s.subtle
                        : sheetStatusFill(statusOn(day.key)),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: statusOn(day.key) == SheetStatus.unmarked
                        ? Border.all(color: s.border)
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// `P 12` count chips, attention first, zero counts omitted.
class SheetCountChips extends StatelessWidget {
  const SheetCountChips({super.key, required this.counts});

  final Map<SheetStatus, int> counts;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final entry in counts.entries)
          if (entry.value > 0 && entry.key != SheetStatus.unmarked)
            _CountChip(
              label: entry.key.abbr.isEmpty ? entry.key.label : entry.key.abbr,
              count: entry.value,
              base: sheetStatusFill(entry.key),
              ink: sheetStatusInk(entry.key, isDark),
            ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.base,
    required this.ink,
  });

  final String label;
  final int count;
  final Color base;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detailed view card
// ---------------------------------------------------------------------------

/// One employee of the detailed view: the merged day strip plus counts, and on
/// tap a calendar per shift. The server emits one row per (employee, shift), so
/// a two-shift employee expands into two calendars.
class SheetEmployeeCard extends StatelessWidget {
  const SheetEmployeeCard({
    super.key,
    required this.employee,
    required this.days,
    required this.month,
    required this.expanded,
    required this.onTap,
    this.canExpand = true,
  });

  final SheetEmployee employee;
  final List<SheetDay> days;

  /// The month the calendars render; only meaningful when [canExpand].
  final DateTime month;

  final bool expanded;
  final VoidCallback onTap;

  /// A Date Range run can span months, which the month calendar cannot show —
  /// the strip stands alone there.
  final bool canExpand;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final merged = employee.merged;
    final shiftNames = [
      for (final shift in employee.shifts)
        if (shift.shift.isNotEmpty) shift.shift,
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: s.fg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: s.border),
      ),
      child: Material(
        // A colour-painted container needs its own Material for ink and to keep
        // the framework from asserting on tappable children.
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: canExpand ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppAvatar(initials: _initials(employee.employeeName), size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            employee.employeeName,
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
                            shiftNames.isEmpty
                                ? employee.employee
                                : '${employee.employee} · ${shiftNames.join(" / ")}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: s.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (canExpand)
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: s.textSubtle,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SheetDayStrip(
                  days: days,
                  statusOn: (key) => merged[key] ?? SheetStatus.unmarked,
                ),
                const SizedBox(height: 10),
                SheetCountChips(counts: employee.counts),
                if (expanded && canExpand) ...[
                  const SizedBox(height: 12),
                  for (final shift in employee.shifts) ...[
                    if (employee.hasMultipleShifts || shift.shift.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          shift.shift.isEmpty ? 'No shift' : shift.shift,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: s.textSubtle,
                          ),
                        ),
                      ),
                    AttendanceCalendarGrid(
                      month: month,
                      statusOn: (date) =>
                          toAttendanceStatus(shift.statusOn(kSheetDayKey.format(date))),
                      isHoliday: (date) {
                        final status = shift.statusOn(kSheetDayKey.format(date));
                        return status == SheetStatus.holiday ||
                            status == SheetStatus.weeklyOff;
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summarized view card
// ---------------------------------------------------------------------------

/// One employee of the summarized view: the fixed totals, then whatever Leave
/// Type columns the site defines (zero counts omitted).
class SheetSummaryCard extends StatelessWidget {
  const SheetSummaryCard({
    super.key,
    required this.summary,
    required this.leaveTypes,
  });

  final SheetSummary summary;
  final List<SheetSummaryColumn> leaveTypes;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final metrics = <(String, num, Color)>[
      ('Present', summary['total_present'], sheetStatusFill(SheetStatus.present)),
      ('Leaves', summary['total_leaves'], sheetStatusFill(SheetStatus.onLeave)),
      ('Absent', summary['total_absent'], sheetStatusFill(SheetStatus.absent)),
      ('Holidays', summary['total_holidays'], sheetStatusFill(SheetStatus.holiday)),
      ('Unmarked', summary['unmarked_days'], AppColors.gray400),
      ('Late in', summary['total_late_entries'], AppColors.orange500),
      ('Early out', summary['total_early_exits'], AppColors.yellow500),
    ];

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
              AppAvatar(initials: _initials(summary.employeeName), size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: s.text,
                      ),
                    ),
                    Text(
                      summary.employee,
                      style: TextStyle(fontSize: 11, color: s.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, value, base) in metrics)
                _CountChip(
                  label: label,
                  count: value.round(),
                  base: base,
                  ink: s.text,
                ),
            ],
          ),
          if (leaveTypes.any((type) => summary[type.fieldname] > 0)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final type in leaveTypes)
                  if (summary[type.fieldname] > 0)
                    _CountChip(
                      label: type.label,
                      count: summary[type.fieldname].round(),
                      base: AppColors.blue500,
                      ink: isDark ? AppColors.blue300 : AppColors.blue700,
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Legend
// ---------------------------------------------------------------------------

/// The report's own legend, rebuilt from [SheetStatus] rather than parsing the
/// HTML the server sends in `message`.
class SheetLegend extends StatelessWidget {
  const SheetLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final status in SheetStatus.values)
            if (status != SheetStatus.unmarked)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: sheetStatusFill(status),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${status.abbr} · ${status.label}',
                    style: TextStyle(fontSize: 10.5, color: s.textMuted),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// Same rule as `TrackedEmployee.initials` — the report has only the name.
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((part) => part.isEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
