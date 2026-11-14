import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_controller.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_logic.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/widgets/attendance_sheet_cards.dart';

/// The HRMS **Monthly Attendance Sheet** report.
///
/// Detailed view is one card per employee — a day strip that expands into a
/// calendar per shift. Summarized view swaps the strip for the report's totals
/// plus the site's Leave Type columns.
class MonthlyAttendanceSheetScreen
    extends GetView<MonthlyAttendanceSheetController> {
  const MonthlyAttendanceSheetScreen({super.key});

  /// The period is not a chip — the period bar below the header owns it.
  List<Widget> _buildFilterChips(BuildContext context) => [
        for (final entry in controller.activeFilters.entries)
          FilterChipWidget(
            icon: Icons.filter_alt_outlined,
            label: entry.value,
            onDeleted: () => controller.clearFilter(entry.key),
          ),
      ];

  void _openFilters(BuildContext context) => showReportFilterSheet(
        context: context,
        title: 'Monthly Attendance Sheet',
        fields: controller.filterFields,
        controllers: controller.filterControllers,
        sectionLabels: controller.filterSectionLabels,
        chipGroups: controller.filterChipGroups,
        onRun: controller.runReport,
        onClear: controller.clearFilters,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Obx(() {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        final summarized = controller.isSummarized;

        return Scrollbar(
          controller: controller.scrollController,
          child: RefreshIndicator(
            onRefresh: controller.runReport,
            color: cs.primary,
            child: CustomScrollView(
              controller: controller.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                DocTypeListHeader(
                  title: 'Monthly Attendance Sheet',
                  automaticallyImplyLeading: false,
                  activeFilters: controller.activeFilters
                      .map((k, v) => MapEntry(k, v as dynamic))
                      .obs,
                  onFilterTap: () => _openFilters(context),
                  filterChipsBuilder: _buildFilterChips,
                  onClearAllFilters: controller.clearFilters,
                  extraActionsKey: controller.isRunning.value,
                  extraActions: [
                    AsyncIconButton(
                      busy: controller.isRunning,
                      onPressed: controller.runReport,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Run report',
                    ),
                  ],
                ),

                const SliverToBoxAdapter(child: _PeriodBar()),

                if (!summarized && controller.employees.isNotEmpty)
                  const SliverToBoxAdapter(child: SheetLegend()),

                if (controller.isRunning.value)
                  const SliverToBoxAdapter(child: DocCardSkeletonList())
                else if (controller.errorMessage.value != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Message(
                      icon: Icons.error_outline,
                      text: controller.errorMessage.value!,
                    ),
                  )
                else if (controller.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Message(
                      icon: Icons.event_busy_outlined,
                      text: controller.hasRun.value
                          ? 'No attendance records for ${controller.periodLabel}.'
                          : 'Set filters and run the report.',
                    ),
                  )
                else if (summarized)
                  SliverList.builder(
                    itemCount: controller.summaries.length,
                    itemBuilder: (_, i) => _Grouped(
                      group: controller.summaries[i].group,
                      previousGroup:
                          i == 0 ? null : controller.summaries[i - 1].group,
                      child: SheetSummaryCard(
                        summary: controller.summaries[i],
                        leaveTypes: controller.leaveTypes,
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: controller.employees.length,
                    itemBuilder: (_, i) {
                      final employee = controller.employees[i];
                      return _Grouped(
                        group: employee.group,
                        previousGroup:
                            i == 0 ? null : controller.employees[i - 1].group,
                        child: Obx(() => SheetEmployeeCard(
                              employee: employee,
                              days: controller.days,
                              month: controller.month.value,
                              canExpand: controller.isMonthMode,
                              expanded:
                                  controller.expanded.contains(employee.employee),
                              onTap: () =>
                                  controller.toggleExpanded(employee.employee),
                            )),
                      );
                    },
                  ),

                SliverToBoxAdapter(
                  child: ListEndFooter(
                    hasMore: false,
                    bottomPadding: bottomInset,
                    label: summarized
                        ? _summaryTotals(controller.summaries)
                        : totalsLabel(controller.employees),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Summarized totals: day counts only — summing a rate column is meaningless,
  /// and this view has none.
  static String _summaryTotals(List<SheetSummary> rows) {
    if (rows.isEmpty) return 'End of results';
    num sum(String field) =>
        rows.fold<num>(0, (total, row) => total + row[field]);
    return '${rows.length} employee${rows.length == 1 ? '' : 's'} · '
        '${sum('total_present').round()} present · '
        '${sum('total_absent').round()} absent · '
        '${sum('total_leaves').round()} on leave · '
        '${sum('unmarked_days').round()} unmarked';
  }
}

/// Month stepper for the `Month` period, or the chosen range read-only.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MonthlyAttendanceSheetController>();
    final s = context.scheme;

    return Obx(() {
      final monthMode = controller.isMonthMode;
      final count = controller.isSummarized
          ? controller.summaries.length
          : controller.employees.length;

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            if (monthMode)
              IconButton(
                onPressed: controller.previousMonth,
                icon: const Icon(Icons.chevron_left),
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous month',
              ),
            Expanded(
              child: Text(
                controller.periodLabel,
                textAlign: monthMode ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: s.text,
                ),
              ),
            ),
            if (monthMode)
              IconButton(
                onPressed:
                    controller.isCurrentMonth ? null : controller.nextMonth,
                icon: const Icon(Icons.chevron_right),
                visualDensity: VisualDensity.compact,
                tooltip: 'Next month',
              ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: s.textMuted,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Draws the `group_by` bucket heading when it changes between rows.
class _Grouped extends StatelessWidget {
  const _Grouped({
    required this.group,
    required this.previousGroup,
    required this.child,
  });

  final String? group;
  final String? previousGroup;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final show = group != null && group!.isNotEmpty && group != previousGroup;
    if (!show) return child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Text(
            group!.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: s.textSubtle,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: s.textSubtle),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: s.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
