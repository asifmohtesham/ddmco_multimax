import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_fields.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_logic.dart';

/// One Attendance record of the Shift Attendance report: who, which shift,
/// in → out against the shift window, hours worked, and what is off about it
/// (late, early, a missing punch).
class ShiftAttendanceCard extends StatelessWidget {
  const ShiftAttendanceCard({super.key, required this.row, this.fields});

  final ShiftAttendanceRow row;
  final FieldsState? fields;

  bool _shows(String key) => fields?.shows(key) ?? true;

  String _label(String key) =>
      fields?.label(key) ?? shiftAttendanceFields.label(key)!;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warnInk = isDark ? AppColors.orange300 : AppColors.orange700;
    final (showStart, showEnd) = (_shows('shift_start'), _shows('shift_end'));
    final window = row.shiftWindow == null
        ? null
        : switch ((showStart, showEnd)) {
            (true, true) => row.shiftWindow,
            (true, false) =>
              '${_label('shift_start')} ${displayTime(row.shiftStart)}',
            (false, true) =>
              '${_label('shift_end')} ${displayTime(row.shiftEnd)}',
            (false, false) => null,
          };
    final inTime = _shows('in_time') ? displayTime(row.inTime) : null;
    final outTime = _shows('out_time') ? displayTime(row.outTime) : null;
    final late = _shows('late_entry_hrs') && row.lateBy != null
        ? '${_label('late_entry_hrs')} ${row.lateBy}'
        : null;
    final early = _shows('early_exit_hrs') && row.earlyBy != null
        ? '${_label('early_exit_hrs')} ${row.earlyBy}'
        : null;
    final lateCue =
        row.isLate && late == null && (inTime == null || row.lateBy != null);
    final earlyCue =
        row.isEarly &&
        early == null &&
        (outTime == null || row.earlyBy != null);
    final showUnavailable =
        row.missingPunch == MissingPunch.none &&
        (row.inTime == null || row.outTime == null) &&
        inTime != '—' &&
        outTime != '—';
    final punches = <Widget>[
      if (inTime != null || late != null || lateCue)
        _Punch(
          label: _label('in_time'),
          time: inTime,
          note: late ?? (lateCue ? 'Late entry' : null),
          warning: row.isLate ? 'Late entry' : null,
          warnInk: warnInk,
        ),
      if (outTime != null || early != null || earlyCue)
        _Punch(
          label: _label('out_time'),
          time: outTime,
          note: early ?? (earlyCue ? 'Early exit' : null),
          warning: row.isEarly ? 'Early exit' : null,
          warnInk: warnInk,
        ),
      if (_shows('working_hours'))
        _Hours(hours: row.workingHours, label: _label('working_hours')),
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
                        if (row.shift.isNotEmpty) row.shift,
                        if (window != null) window,
                        if (row.shift.isEmpty && window == null) row.employee,
                      ].join(' · '),
                      semanticsLabel: [
                        if (row.shift.isNotEmpty)
                          '${_label('shift')} ${row.shift}',
                        if (window != null && showStart)
                          '${_label('shift_start')} ${displayTime(row.shiftStart)}',
                        if (window != null && showEnd)
                          '${_label('shift_end')} ${displayTime(row.shiftEnd)}',
                        if (row.shift.isEmpty && window == null)
                          '${_label('employee')} ${row.employee}',
                      ].join(', '),
                      style: TextStyle(fontSize: 11, color: s.textMuted),
                    ),
                  ],
                ),
              ),
              if (row.status.isNotEmpty) StatusPill(status: row.status),
            ],
          ),
          if (punches.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final punch in punches)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: punch,
                    ),
                  ),
              ],
            ),
          ],
          if (showUnavailable) Text('—', style: TextStyle(color: s.textMuted)),
          if (row.missingPunch != MissingPunch.none) ...[
            const SizedBox(height: 8),
            _MissingPunchChip(missing: row.missingPunch),
          ],
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _Punch extends StatelessWidget {
  const _Punch({
    required this.label,
    required this.time,
    required this.note,
    required this.warning,
    required this.warnInk,
  });

  final String label;
  final String? time;
  final String? note;
  final String? warning;
  final Color warnInk;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (time != null) ...[
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: s.textMuted,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            time!,
            semanticsLabel: warning == null ? null : '$time, $warning',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: warning != null ? warnInk : s.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (note != null)
          Text(note!, style: TextStyle(fontSize: 11, color: warnInk)),
      ],
    );
  }
}

class _Hours extends StatelessWidget {
  const _Hours({required this.hours, required this.label});

  final double hours;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: s.textMuted,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          formatHours(hours),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: hours > 0 ? s.text : s.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Yellow tint (StatusPill convention): the hours are understated until the
/// missing punch is corrected.
class _MissingPunchChip extends StatelessWidget {
  const _MissingPunchChip({required this.missing});

  final MissingPunch missing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.yellow300 : AppColors.yellow700;
    final text = switch (missing) {
      MissingPunch.checkIn => 'No check-in',
      MissingPunch.checkOut => 'No check-out',
      MissingPunch.both => 'No check-ins',
      MissingPunch.none => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.yellow500.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.yellow500.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 13, color: ink),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
