import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

/// Resolves a Frappe `image` path (`/files/...`) against the active instance.
ImageProvider? employeeImage(String? path) {
  final p = (path ?? '').trim();
  if (p.isEmpty) return null;
  if (p.startsWith('http')) return NetworkImage(p);
  try {
    return NetworkImage('${Get.find<ApiProvider>().baseUrl}$p');
  } catch (_) {
    return null;
  }
}

/// One employee row: avatar · name / department / In–Out · status pill + flag.
/// Untracked rows drop the time row and render dimmed.
class EmployeeAttendanceCard extends StatelessWidget {
  const EmployeeAttendanceCard({super.key, required this.row, required this.onTap});

  final EmployeeDayStatus row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final untracked = row.status == AttendanceStatus.untracked;
    final e = row.employee;

    return Opacity(
      opacity: untracked ? 0.62 : 1,
      child: Material(
        color: s.fg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: s.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar(initials: e.initials, image: employeeImage(e.image), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.employeeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600, color: s.text, height: 1.25),
                      ),
                      if (e.department.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(e.department, style: TextStyle(fontSize: 12, color: s.textMuted)),
                      ],
                      if (!untracked) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 14,
                          runSpacing: 2,
                          children: [
                            InOutStat(label: 'In', time: row.inTime),
                            InOutStat(label: 'Out', time: row.outTime),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(status: row.status.label),
                    if (row.flag != null) ...[
                      const SizedBox(height: 7),
                      AttendanceFlag(text: row.flag!, warning: row.flagIsWarning),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "In 08:31" / "Out —". A blank time is a normal state, never an error.
class InOutStat extends StatelessWidget {
  const InOutStat({super.key, required this.label, required this.time});
  final String label;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 12, color: s.textMuted),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: time == null ? '—' : kHHmm.format(time!),
            style: TextStyle(
              color: time == null ? s.textSubtle : s.text,
              fontWeight: time == null ? FontWeight.w500 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small icon + text under the pill: orange for late-entry / early-exit,
/// neutral grey for informational flags such as "Punched on holiday".
class AttendanceFlag extends StatelessWidget {
  const AttendanceFlag({super.key, required this.text, this.warning = true});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = warning ? (dark ? AppColors.orange300 : AppColors.orange700) : s.textMuted;
    final icon = text.contains('Early')
        ? Icons.logout
        : text.contains('Punched')
            ? Icons.login
            : Icons.schedule;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

/// "NOT TRACKED · 10 · NO TERMINAL ID ────────" section divider.
class AttendanceGroupHeader extends StatelessWidget {
  const AttendanceGroupHeader({super.key, required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: s.textSubtle),
            const SizedBox(width: 8),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: s.textSubtle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(height: 1, color: s.border)),
        ],
      ),
    );
  }
}
