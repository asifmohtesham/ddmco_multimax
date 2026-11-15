import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_widgets.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_controller.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_logic.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/widgets/shift_attendance_card.dart';

/// The HRMS **Shift Attendance** report: one card per Attendance record —
/// in and out against the shift window, hours worked, late / early and
/// missing punches — grouped by day, newest first, under the server's own
/// summary cards.
class ShiftAttendanceScreen extends GetView<ShiftAttendanceController> {
  const ShiftAttendanceScreen({super.key});

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
    title: 'Shift Attendance',
    fields: controller.filterFields,
    controllers: controller.filterControllers,
    sectionLabels: controller.filterSectionLabels,
    toggles: controller.filterToggles,
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
        final rows = controller.rows;
        controller.period.value; // repaint the period bar on date change

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
                  title: 'Shift Attendance',
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
                SliverToBoxAdapter(
                  child: ReportPeriodBar(
                    label: controller.periodText,
                    presets: ShiftAttendanceController.periods,
                    selected: controller.selectedPeriod,
                    onPreset: controller.applyPeriod,
                    count: controller.isRunning.value ? null : rows.length,
                  ),
                ),
                if (!controller.isRunning.value &&
                    controller.errorMessage.value == null)
                  SliverToBoxAdapter(
                    child: ReportSummaryStrip(items: controller.summary),
                  ),
                if (controller.isRunning.value)
                  const SliverToBoxAdapter(child: DocCardSkeletonList())
                else if (controller.errorMessage.value != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ReportMessage(
                      icon: Icons.error_outline,
                      text: controller.errorMessage.value!,
                    ),
                  )
                else if (rows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ReportMessage(
                      icon: Icons.event_busy_outlined,
                      text: controller.hasRun.value
                          ? 'No shift attendance for ${controller.periodText}.'
                          : 'Set filters and run the report.',
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      final newDay = i == 0 || rows[i - 1].date != row.date;
                      final card = ShiftAttendanceCard(row: row);
                      if (!newDay) return card;
                      final dayCount = rows
                          .where((r) => r.date == row.date)
                          .length;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ReportGroupHeading(
                            title: dayHeading(row.date),
                            trailing: '$dayCount',
                          ),
                          card,
                        ],
                      );
                    },
                  ),
                SliverToBoxAdapter(
                  child: ListEndFooter(
                    hasMore: false,
                    bottomPadding: bottomInset,
                    label: controller.totals.label,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
