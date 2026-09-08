import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/month/attendance_month_controller.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';

/// Pushed month view for one employee: calendar grid with a status dot per
/// day, then the ledger rows for the month.
class AttendanceMonthScreen extends GetView<AttendanceMonthController> {
  const AttendanceMonthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.scheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Scrollbar(
        controller: controller.scrollController,
        child: CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            Obx(() => DocTypeListHeader(
                  title: DateFormat('MMMM yyyy').format(controller.month.value),
                  extraActions: [
                    IconButton(
                      onPressed: controller.previousMonth,
                      tooltip: 'Previous month',
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      onPressed: controller.isCurrentMonth ? null : controller.nextMonth,
                      tooltip: 'Next month',
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                  extraActionsKey: controller.isCurrentMonth,
                )),
            SliverToBoxAdapter(
              child: Container(
                color: s.fg,
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                child: Row(
                  children: [
                    AppAvatar(
                        initials: controller.employee.initials,
                        image: employeeImage(controller.employee.image),
                        size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(controller.employee.employeeName,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: s.text)),
                          if (controller.employee.department.isNotEmpty)
                            Text(controller.employee.department,
                                style: TextStyle(fontSize: 12, color: s.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Obx(() {
              if (controller.isLoading.value) {
                return const SliverToBoxAdapter(child: DocCardSkeletonList(count: 4));
              }
              final rows = [...controller.records]..sort((a, b) => b.date.compareTo(a.date));
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    AttendanceCalendarGrid(
                      month: controller.month.value,
                      statusOn: controller.statusOn,
                      isHoliday: controller.isHoliday,
                    ),
                    const SizedBox(height: 8),
                    const _Legend(),
                    const SizedBox(height: 8),
                    AttendanceGroupHeader(text: controller.summary),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            controller.isCurrentMonth
                                ? 'No attendance rows yet this month.\nRows appear the morning after each shift.'
                                : 'No attendance rows for this month.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: s.textMuted, height: 1.4),
                          ),
                        ),
                      ),
                    for (final r in rows) ...[
                      _LedgerRow(record: r, employee: controller.employee, shift: controller.shift),
                      const SizedBox(height: 8),
                    ],
                    ListEndFooter(
                      hasMore: false,
                      bottomPadding: bottomInset + 48,
                      label: '${rows.length} day${rows.length == 1 ? '' : 's'} recorded',
                    ),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

Color _dotColor(AttendanceStatus s) => switch (s) {
      AttendanceStatus.present || AttendanceStatus.workFromHome => AppColors.green500,
      AttendanceStatus.late => AppColors.orange500,
      AttendanceStatus.absent || AttendanceStatus.absentSoFar => AppColors.red500,
      AttendanceStatus.halfDay => AppColors.yellow500,
      AttendanceStatus.holiday || AttendanceStatus.onLeave => AppColors.blue500,
      AttendanceStatus.notInYet || AttendanceStatus.untracked => AppColors.gray400,
    };

/// Mon-first grid, 44px cells, one 6px status dot per day. Today is filled
/// with the primary colour; future days and holidays read subtle.
class AttendanceCalendarGrid extends StatelessWidget {
  const AttendanceCalendarGrid({
    super.key,
    required this.month,
    required this.statusOn,
    required this.isHoliday,
  });

  final DateTime month;
  final AttendanceStatus? Function(DateTime) statusOn;
  final bool Function(DateTime) isHoliday;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final today = dateOnly(DateTime.now());
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = (DateTime(month.year, month.month, 1).weekday + 6) % 7; // Mon=0
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox(),
      for (var d = 1; d <= daysInMonth; d++) _cell(context, DateTime(month.year, month.month, d), today),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: s.fg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: s.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: s.textSubtle),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var r = 0; r < cells.length ~/ 7; r++)
            Row(children: [for (var c = 0; c < 7; c++) Expanded(child: cells[r * 7 + c])]),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, DateTime d, DateTime today) {
    final s = context.scheme;
    final isToday = d == today;
    final future = d.isAfter(today);
    final status = future ? null : statusOn(d);
    final muted = future || isHoliday(d);
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: isToday
          ? BoxDecoration(color: s.primary, borderRadius: BorderRadius.circular(AppRadius.md))
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${d.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? s.onPrimary : muted ? s.textSubtle : s.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: status == null
                  ? Colors.transparent
                  : isToday
                      ? s.onPrimary
                      : _dotColor(status),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    Widget item(String label, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, color: s.textMuted)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          item('Present', AppColors.green500),
          item('Late', AppColors.orange500),
          item('Absent', AppColors.red500),
          item('Half day', AppColors.yellow500),
          item('Leave / holiday', AppColors.blue500),
        ],
      ),
    );
  }
}

/// One ledger day: date block · pill + In/Out + flags · hours.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.record, required this.employee, required this.shift});
  final AttendanceRecord record;
  final TrackedEmployee employee;
  final ShiftRules shift;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final row = deriveDayStatus(
      employee: employee,
      day: record.date,
      now: DateTime.now(),
      shift: shift,
      isHoliday: false,
      ledger: record,
    );
    final hasHours = record.workingHours > 0;
    final h = record.workingHours.floor();
    final m = ((record.workingHours - h) * 60).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: s.fg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: s.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Text(record.date.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, height: 1, color: s.text,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 2),
                Text(DateFormat('EEE').format(record.date).toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: s.textSubtle)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(status: row.status.label),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    InOutStat(label: 'In', time: row.inTime),
                    InOutStat(label: 'Out', time: row.outTime),
                  ],
                ),
                if (row.flag != null) ...[
                  const SizedBox(height: 4),
                  AttendanceFlag(text: row.flag!, warning: row.flagIsWarning),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasHours ? '${h}h ${m.toString().padLeft(2, '0')}m' : '—',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasHours ? FontWeight.w600 : FontWeight.w500,
                  color: hasHours ? s.text : s.textSubtle,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text('hours', style: TextStyle(fontSize: 12, color: s.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
