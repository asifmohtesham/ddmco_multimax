import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';

/// Bottom sheet for one employee on the selected day: status, shift window as
/// context, every punch as a timeline, and a "View month" action.
Future<void> showEmployeeDetailSheet(
  BuildContext context, {
  required EmployeeDayStatus row,
  required DateTime day,
  required ShiftRules shift,
  required DateTime? loadedAt,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EmployeeDetailSheet(row: row, day: day, shift: shift, loadedAt: loadedAt),
  );
}

class EmployeeDetailSheet extends StatelessWidget {
  const EmployeeDetailSheet({
    super.key,
    required this.row,
    required this.day,
    required this.shift,
    required this.loadedAt,
  });

  final EmployeeDayStatus row;
  final DateTime day;
  final ShiftRules shift;
  final DateTime? loadedAt;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final e = row.employee;
    final isToday = dateOnly(day) == dateOnly(DateTime.now());
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: s.fg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                decoration: BoxDecoration(
                    color: s.borderStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                AppAvatar(initials: e.initials, image: employeeImage(e.image), size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.employeeName,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700, color: s.text)),
                      Text(
                        [if (e.department.isNotEmpty) e.department, e.name].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: s.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: Icon(Icons.close, size: 18, color: s.textMuted),
                  style: IconButton.styleFrom(backgroundColor: s.subtle),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                StatusPill(status: row.status.label),
                if (row.flag != null) ...[
                  const SizedBox(width: 8),
                  AttendanceFlag(text: row.flag!, warning: row.flagIsWarning),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _ShiftContext(shift: shift),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isToday ? 'PUNCHES TODAY' : 'PUNCHES',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: s.textSubtle),
                ),
                Text(
                  '${row.punches.length} · ${freshnessLabel(loadedAt, DateTime.now())}',
                  style: TextStyle(fontSize: 11, color: s.textSubtle),
                ),
              ],
            ),
            const SizedBox(height: 6),
            PunchTimeline(row: row, shift: shift, showGhost: isToday),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Get.toNamed(AppRoutes.ATTENDANCE_MONTH, arguments: {
                    'employee': e,
                    'month': DateTime(day.year, day.month),
                    'today': row,
                  });
                },
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('View month'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftContext extends StatelessWidget {
  const _ShiftContext({required this.shift});
  final ShiftRules shift;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final bold = TextStyle(
        fontWeight: FontWeight.w600, color: s.text, fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: s.subtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: s.border),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, size: 15, color: s.textSubtle),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: s.textMuted),
                children: [
                  const TextSpan(text: 'Shift '),
                  TextSpan(text: shift.name, style: bold),
                  TextSpan(text: '  ·  ', style: TextStyle(color: s.borderStrong)),
                  TextSpan(text: '${shift.startLabel}–${shift.endLabel}', style: bold),
                  TextSpan(text: '  ·  ', style: TextStyle(color: s.borderStrong)),
                  const TextSpan(text: 'late after '),
                  TextSpan(text: shift.cutoffLabel, style: bold),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical list of punches. Alternating IN/OUT by index (the shift rule);
/// the first punch is tinted orange when it caused the late flag. A ghost row
/// closes the list when the last punch was an IN and the day is still open.
class PunchTimeline extends StatelessWidget {
  const PunchTimeline({super.key, required this.row, required this.shift, this.showGhost = true});
  final EmployeeDayStatus row;
  final ShiftRules shift;
  final bool showGhost;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final punches = row.punches;
    if (punches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('No punches recorded.', style: TextStyle(fontSize: 13, color: s.textSubtle)),
      );
    }
    final needsGhost = showGhost && punches.length.isOdd;
    return Column(
      children: [
        for (var i = 0; i < punches.length; i++)
          _PunchRow(
            time: kHHmm.format(punches[i].time),
            isIn: i.isEven,
            late: i == 0 && row.lateBy != null,
            device: punches[i].deviceId.isEmpty ? 'Terminal' : 'Terminal ${punches[i].deviceId}',
            last: i == punches.length - 1 && !needsGhost,
          ),
        if (needsGhost)
          _PunchRow(
            time: '—',
            isIn: false,
            ghost: true,
            title: 'No out punch yet',
            device: 'Shift ends ${shift.endLabel}',
            last: true,
          ),
      ],
    );
  }
}

class _PunchRow extends StatelessWidget {
  const _PunchRow({
    required this.time,
    required this.isIn,
    required this.device,
    this.late = false,
    this.ghost = false,
    this.title,
    this.last = false,
  });

  final String time;
  final bool isIn;
  final bool late;
  final bool ghost;
  final String? title;
  final String device;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final orange = dark ? AppColors.orange300 : AppColors.orange700;
    final green = dark ? AppColors.green300 : AppColors.green700;

    final Color dotBg;
    final Color dotFg;
    BoxBorder? dotBorder;
    if (ghost) {
      dotBg = Colors.transparent;
      dotFg = s.textSubtle;
      dotBorder = Border.all(color: s.borderStrong, width: 1);
    } else if (late) {
      dotBg = Color.alphaBlend(AppColors.orange500.withValues(alpha: 0.14), s.fg);
      dotFg = orange;
    } else if (isIn) {
      dotBg = Color.alphaBlend(AppColors.green500.withValues(alpha: 0.14), s.fg);
      dotFg = green;
    } else {
      dotBg = s.subtle;
      dotFg = s.textMuted;
      dotBorder = Border.all(color: s.border);
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                time,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: ghost ? FontWeight.w500 : FontWeight.w600,
                  color: ghost ? s.textSubtle : late ? orange : s.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle, border: dotBorder),
                  child: Icon(isIn ? Icons.login : Icons.logout, size: 14, color: dotFg),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: s.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 3, 0, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? (isIn ? 'In' : 'Out'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: ghost ? FontWeight.w500 : FontWeight.w600,
                      color: ghost ? s.textSubtle : s.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(device, style: TextStyle(fontSize: 12, color: s.textMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
