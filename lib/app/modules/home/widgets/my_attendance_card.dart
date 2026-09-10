import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';

/// "My attendance" on the Dashboard (spec §3.1, layout B): the viewer's own
/// status today, a dot per day of the month and the month tally. Public and
/// controller-free like DashboardAttendanceCard, so widget tests can pump
/// every state.
class MyAttendanceCard extends StatelessWidget {
  const MyAttendanceCard({
    super.key,
    required this.row,
    required this.shift,
    required this.now,
    this.strip,
    this.isLoading = false,
    this.onTap,
  });

  /// The viewer's own row; null while the first load is in flight.
  final EmployeeDayStatus? row;
  final ShiftRules shift;
  final DateTime now;

  /// Null when the month ledger could not be loaded: headline only.
  final MonthStrip? strip;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final r = row;
    final tappable = r != null && r.employee.isTracked;
    return Material(
      color: s.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: tappable ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: s.border),
          ),
          child: r == null ? _skeleton(s) : _content(context, r),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, EmployeeDayStatus r) {
    final s = context.scheme;
    final e = r.employee;

    // Not enrolled: single line only
    if (!e.isTracked) {
      return Row(
        children: [
          AppAvatar(initials: e.initials, image: employeeImage(e.image), size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're not enrolled on the attendance terminal",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: s.textMuted),
            ),
          ),
        ],
      );
    }

    final (h1, h2) = myAttendanceHeadline(r, shift, now);
    final st = strip;
    final showMonth = st != null && e.isTracked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppAvatar(initials: e.initials, image: employeeImage(e.image), size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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
                    style: TextStyle(fontSize: 12, color: s.textMuted),
                  ),
                ],
              ),
            ),
            if (e.isTracked) Icon(Icons.chevron_right, size: 18, color: s.textSubtle),
          ],
        ),
        if (showMonth) ...[
          const SizedBox(height: 10),
          MonthDotStrip(strip: st),
          const SizedBox(height: 8),
          Text(
            st.tallyLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: s.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  Widget _skeleton(AppScheme s) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: s.subtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: s.subtle, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(110, 15), const SizedBox(height: 6), bar(160, 11)],
            ),
          ],
        ),
        const SizedBox(height: 10),
        bar(double.infinity, 34),
      ],
    );
  }
}

/// Two rows of up to 16 dots (1st–16th, 17th–end). Colours come from the
/// StatusPill ramp so a dot always matches its pill; unknown and future days
/// are faint; today is outlined, and hollow until it has a status.
class MonthDotStrip extends StatelessWidget {
  const MonthDotStrip({super.key, required this.strip});
  final MonthStrip strip;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final b = Theme.of(context).brightness;
    final n = strip.days.length;

    Widget dot(int i) {
      final st = strip.days[i];
      final isToday = i == strip.todayIndex;
      final fill = st == null
          ? (isToday ? Colors.transparent : s.subtle)
          : StatusPill.colourForStatus(st.label, brightness: b).$2;
      return Padding(
        padding: const EdgeInsets.all(2),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(3),
              border: isToday ? Border.all(color: s.text, width: 1.5) : null,
            ),
          ),
        ),
      );
    }

    Widget line(int from) => Row(
          children: [
            for (var i = from; i < from + 16; i++)
              Expanded(child: i < n ? dot(i) : const SizedBox.shrink()),
          ],
        );

    return Semantics(
      label: strip.tallyLabel,
      child: ExcludeSemantics(
        child: Column(children: [line(0), line(16)]),
      ),
    );
  }
}
