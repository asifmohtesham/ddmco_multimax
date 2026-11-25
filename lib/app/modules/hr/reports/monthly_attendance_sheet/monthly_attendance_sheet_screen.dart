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
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_controller.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_fields.dart';
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
        onTap: () => _openFilters(context, focusKey: entry.key),
      ),
  ];

  void _openFilters(BuildContext context, {String? focusKey}) =>
      showReportFilterSheet(
        context: context,
        focusKey: focusKey,
        title: 'Monthly Attendance Sheet',
        fields: controller.filterFields,
        titleOwner: controller.fields,
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
        final summarized = controller.resultSummarized;
        final resultMonth = controller.resultMonth;
        final monthMode = resultMonth != null;
        final employees = controller.employees.toList(growable: false);
        final summaries = controller.summaries.toList(growable: false);
        final expanded = controller.expanded.toSet();
        final fields = controller.fields.state.value;
        final groupIds = <int, Object>{};
        final rowIds = <Object>[];
        final childIds = <int, List<Object>>{};
        final parents = <Object, Object>{};
        final occurrenceIds = <Object>[];
        final rowCount = summarized ? summaries.length : employees.length;
        String? groupAt(int i) =>
            summarized ? summaries[i].group : employees[i].group;
        String? previousGroup(int i) => i == 0 ? null : groupAt(i - 1);
        for (var i = 0; i < rowCount; i++) {
          final group = groupAt(i);
          if (group != null && group.isNotEmpty && group != previousGroup(i)) {
            final id = ('group', summarized, group, i);
            groupIds[i] = id;
            occurrenceIds.add(id);
          }
          final employee = summarized
              ? summaries[i].employee
              : employees[i].employee;
          final id = ('employee', summarized, group, employee, i);
          rowIds.add(id);
          occurrenceIds.add(id);
          if (!summarized && monthMode && expanded.contains(employee)) {
            final shifts = [
              for (final (j, shift) in employees[i].shifts.indexed)
                (id, shift.shift, j),
            ];
            childIds[i] = shifts;
            occurrenceIds.addAll(shifts);
            parents.addEntries(shifts.map((shift) => MapEntry(shift, id)));
          }
        }
        final indices = {
          for (final (index, id) in occurrenceIds.indexed) id: index,
        };

        return ReportFieldsResults(
          controller: controller.fields,
          scrollController: controller.scrollController,
          result: (controller.resultRevision.value, summarized, monthMode),
          occurrenceIds: occurrenceIds,
          fallbacks: (id) => [if (parents[id] case final parent?) parent],
          builder: (_, anchors) => Obx(() {
            Widget anchor(Object id, Widget child) =>
                anchors.row(id, indices[id]!, child);
            Widget grouped(int i, Widget child) => _Grouped(
              group: groupAt(i),
              previousGroup: previousGroup(i),
              anchorHeading: groupIds[i] == null
                  ? null
                  : (heading) => anchor(groupIds[i]!, heading),
              child: child,
            );
            return RefreshIndicator(
              onRefresh: controller.runReport,
              color: cs.primary,
              child: CustomScrollView(
                controller: controller.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  anchors.header(
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
                        ReportFieldsAction(controller: controller.fields),
                        AsyncIconButton(
                          busy: controller.isRunning,
                          onPressed: controller.runReport,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Run report',
                        ),
                      ],
                    ),
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
                      itemCount: summaries.length,
                      itemBuilder: (_, i) => grouped(
                        i,
                        anchor(
                          rowIds[i],
                          SheetSummaryCard(
                            summary: summaries[i],
                            leaveTypes: controller.leaveTypes,
                            fields: fields,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: employees.length,
                      itemBuilder: (_, i) {
                        final employee = employees[i];
                        return grouped(
                          i,
                          SheetEmployeeCard(
                            employee: employee,
                            days: controller.days,
                            month: resultMonth ?? controller.month.value,
                            canExpand: monthMode,
                            expanded: expanded.contains(employee.employee),
                            onTap: () =>
                                controller.toggleExpanded(employee.employee),
                            fields: fields,
                            anchorParent: (card) => anchor(rowIds[i], card),
                            anchorShift: (j, shift) =>
                                anchor(childIds[i]![j], shift),
                          ),
                        );
                      },
                    ),

                  if (controller.hasRun.value &&
                      !controller.isRunning.value &&
                      controller.errorMessage.value == null)
                    SliverToBoxAdapter(
                      child: ListEndFooter(
                        hasMore: false,
                        bottomPadding: bottomInset,
                        label: summarized
                            ? _summaryTotals(summaries, fields)
                            : totalsLabel(employees),
                      ),
                    ),
                ],
              ),
            );
          }),
        );
      }),
    );
  }

  /// Summarized totals: day counts only — summing a rate column is meaningless,
  /// and this view has none.
  static String _summaryTotals(List<SheetSummary> rows, FieldsState fields) {
    if (rows.isEmpty) return 'End of list';
    num sum(String field) =>
        rows.fold<num>(0, (total, row) => total + row[field]);
    return [
      'End of list',
      '${rows.length} employee${rows.length == 1 ? '' : 's'}',
      for (final key in const [
        'total_present',
        'total_absent',
        'total_leaves',
        'unmarked_days',
      ])
        '${fields.label(key) ?? monthlySummaryHeaders[key]!} ${sum(key).round()}',
    ].join(' · ');
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
      final monthMode = controller.resultMonthMode;
      final count = controller.resultSummarized
          ? controller.summaries.length
          : controller.employees.length;

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            if (monthMode)
              IconButton(
                onPressed: controller.isRunning.value
                    ? null
                    : controller.previousMonth,
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
                    controller.isRunning.value || controller.isCurrentMonth
                    ? null
                    : controller.nextMonth,
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
    this.anchorHeading,
  });

  final String? group;
  final String? previousGroup;
  final Widget child;
  final Widget Function(Widget child)? anchorHeading;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final show = group != null && group!.isNotEmpty && group != previousGroup;
    if (!show) return child;

    final heading = Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Text(
        group!.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: s.textMuted,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [anchorHeading?.call(heading) ?? heading, child],
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
