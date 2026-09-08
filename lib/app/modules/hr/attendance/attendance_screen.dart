import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_controller.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/attendance_summary_strip.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/date_context_row.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_detail_sheet.dart';

/// Attendance monitor: who is in, who came late, who has not turned up.
/// Today is derived from Employee Checkin punches; past days read the
/// Attendance ledger. See docs/attendance_backend_handoff.md.
class AttendanceScreen extends GetView<AttendanceController> {
  const AttendanceScreen({super.key});

  static const _doctype = 'Attendance';

  List<Widget> _filterChips(BuildContext context) => [
        for (final e in controller.activeFilters.entries)
          FilterChipWidget(
            icon: e.key == 'department' ? Icons.apartment_outlined : Icons.flag_outlined,
            label: '${e.value}',
            onDeleted: () => controller.clearFilter(e.key),
          ),
      ];

  void _openFilterSheet(BuildContext context) => showReportFilterSheet(
        context: context,
        title: 'Filter attendance',
        fields: const [],
        controllers: controller.filterControllers,
        onRun: controller.applyFilters,
        onClear: controller.clearFilters,
        chipGroups: [
          ReportFilterChipGroup(
            key: 'department',
            label: 'Department',
            options: [
              for (final d in controller.departments)
                ReportFilterChipOption(value: d, label: d),
            ],
          ),
          ReportFilterChipGroup(
            key: 'status',
            label: 'Status',
            options: [
              for (final k in kStatusFilterOptions.keys)
                ReportFilterChipOption(value: k, label: k),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: RefreshIndicator(
        onRefresh: () => controller.loadDay(silent: true),
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: Scrollbar(
          controller: controller.scrollController,
          child: CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              Obx(() {
                final canRead = Get.find<PermissionService>().hasAccess(_doctype) == true;
                return DocTypeListHeader(
                  title: 'Attendance',
                  automaticallyImplyLeading: false,
                  extraActions: canRead
                      ? [
                          AsyncIconButton(
                            busy: controller.isRefreshing,
                            onPressed: controller.reload,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh',
                          ),
                        ]
                      : null,
                  extraActionsKey: canRead,
                  searchDoctype: canRead ? 'Employee' : null,
                  searchQuery: canRead ? controller.searchQuery : null,
                  onSearchChanged: controller.onSearchChanged,
                  onSearchClear: () => controller.onSearchChanged(''),
                  activeFilters: canRead ? controller.activeFilters : null,
                  onFilterTap: canRead ? () => _openFilterSheet(context) : null,
                  filterChipsBuilder: _filterChips,
                  onClearAllFilters: controller.clearFilters,
                );
              }),
              DocTypeGuard(
                doctype: _doctype,
                loading: const SliverToBoxAdapter(child: DocCardSkeletonList(count: 4)),
                fallback: SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoAccess(),
                ),
                child: SliverMainAxisGroup(slivers: [
                  // ── Date row + summary strip ────────────────────────────
                  SliverToBoxAdapter(
                    child: Obx(() => DateContextRow(
                          date: controller.selectedDate.value,
                          onPrevious: controller.previousDay,
                          onNext: controller.isToday ? null : controller.nextDay,
                          onPick: () => controller.pickDate(context),
                          loadedAt: controller.loadedAt.value,
                          now: controller.now,
                          updating: controller.isLoading.value || controller.isRefreshing.value,
                        )),
                  ),
                  SliverToBoxAdapter(
                    child: Obx(() {
                      final offline = controller.looksOffline;
                      return AttendanceSummaryStrip(
                        counts: offline ? const AttendanceCounts() : controller.counts,
                        isHoliday: controller.isHoliday,
                        beforeCutoff: controller.beforeCutoff || offline,
                        // Read the Rx map so a tile tap (which rewrites
                        // activeFilters) rebuilds the selected state.
                        selectedKey: controller.activeFilters.containsKey('status')
                            ? controller.selectedStatusKey
                            : null,
                        onToggle: controller.toggleStatusFilter,
                        loading: controller.isLoading.value,
                      );
                    }),
                  ),
                  // ── Body ────────────────────────────────────────────────
                  Obx(() {
                    if (controller.isLoading.value) {
                      return const SliverToBoxAdapter(child: DocCardSkeletonList(count: 5));
                    }
                    if (controller.loadError.value != null && controller.employees.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: ListEmptyState(
                          hasActiveFilters: false,
                          emptyIcon: Icons.cloud_off_outlined,
                          emptyTitle: "Couldn't load attendance",
                          emptyMessage: controller.loadError.value!,
                          filteredTitle: '',
                          filteredMessage: '',
                          onClearFilters: controller.clearFilters,
                          onReload: controller.loadDay,
                        ),
                      );
                    }
                    if (controller.looksOffline) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _TerminalOffline(latest: controller.latestPunch.value),
                      );
                    }
                    return _buildList(context, bottomInset);
                  }),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, double bottomInset) {
    final all = controller.visibleRows;
    final tracked = all.where((r) => r.status != AttendanceStatus.untracked).toList();
    final untracked = all.where((r) => r.status == AttendanceStatus.untracked).toList();
    final counts = controller.counts;
    final total = controller.rows.where((r) => r.status != AttendanceStatus.untracked).length;

    if (all.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ListEmptyState(
          hasActiveFilters: controller.hasFilters,
          emptyIcon: Icons.people_outline,
          emptyTitle: 'No employees',
          emptyMessage: 'No active employees were returned for this site.',
          filteredTitle: 'Nobody matches',
          filteredMessage: 'No employee matches the current search or filters.',
          onClearFilters: controller.clearFilters,
          onReload: controller.loadDay,
        ),
      );
    }

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: ResultCountPill(
          count: tracked.length,
          hasMore: false,
          hasActiveFilters: controller.hasFilters,
          noun: 'employee',
          icon: Icons.people_outline,
        ),
      ),
      if (controller.isHoliday)
        _Banner(
          icon: Icons.wb_sunny_outlined,
          calm: false,
          child: const Text.rich(TextSpan(children: [
            TextSpan(text: 'Weekly off / holiday. ', style: TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: 'No shift scheduled; nobody is counted late or absent.'),
          ])),
        )
      else if (controller.beforeCutoff)
        _Banner(
          icon: Icons.schedule,
          calm: true,
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Shift starts '),
            TextSpan(text: controller.shift.value.startLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            const TextSpan(text: '. Anyone not in by '),
            TextSpan(text: controller.shift.value.cutoffLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            const TextSpan(text: ' will show as late or absent.'),
          ])),
        ),
      for (final r in tracked) _card(context, r),
      if (untracked.isNotEmpty) ...[
        AttendanceGroupHeader(
          icon: Icons.person_off_outlined,
          text: 'Not tracked · ${untracked.length} · no terminal ID',
        ),
        for (final r in untracked) _card(context, r),
      ],
      ListEndFooter(
        hasMore: false,
        bottomPadding: bottomInset + 64,
        label: controller.hasFilters
            ? '${tracked.length} of $total employees shown'
            : controller.isHoliday
                ? '${counts.holiday} on holiday'
                : '${counts.present} present · ${counts.late} late · '
                    '${controller.beforeCutoff ? '${counts.notIn} not in yet' : '${counts.absent} absent${controller.isToday ? ' so far' : ''}'}',
      ),
    ];

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: children[i]),
          childCount: children.length,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, EmployeeDayStatus r) => EmployeeAttendanceCard(
        row: r,
        onTap: () => showEmployeeDetailSheet(
          context,
          row: r,
          day: controller.selectedDate.value,
          shift: controller.shift.value,
          loadedAt: controller.loadedAt.value,
        ),
      );
}

/// Info banner (blue) or calm banner (neutral) above the rows.
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.child, required this.calm});
  final IconData icon;
  final Widget child;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = calm ? s.textMuted : (dark ? AppColors.blue300 : AppColors.blue700);
    final bg = calm ? s.subtle : Color.alphaBlend(AppColors.blue500.withValues(alpha: 0.10), s.fg);
    final border = calm ? s.border : Color.alphaBlend(AppColors.blue500.withValues(alpha: 0.25), s.border);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle(
              style: TextStyle(fontSize: 12.5, height: 1.35, color: fg),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalOffline extends StatelessWidget {
  const _TerminalOffline({required this.latest});
  final EmployeeCheckin? latest;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final c = Get.find<AttendanceController>();
    final since = latest == null ? '' : ' since ${latest!.time.day} ${_mon(latest!.time.month)}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ListEmptyState(
          hasActiveFilters: false,
          emptyIcon: Icons.cloud_off_outlined,
          emptyTitle: 'No punches$since',
          emptyMessage:
              "The attendance terminal may be offline. Employee statuses can't be worked out until it reconnects.",
          filteredTitle: '',
          filteredMessage: '',
          onClearFilters: c.clearFilters,
          onReload: c.loadDay,
        ),
        if (latest != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Text(
              'Last punch · ${latest!.time.day} ${_mon(latest!.time.month)}, ${kHHmm.format(latest!.time)}',
              style: TextStyle(fontSize: 12, color: s.textSubtle),
            ),
          ),
      ],
    );
  }

  static String _mon(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

class _NoAccess extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: s.subtle, shape: BoxShape.circle),
              child: Icon(Icons.lock_outline, size: 26, color: s.textSubtle),
            ),
            const SizedBox(height: 12),
            Text("You don't have access",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: s.text)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 14, color: s.textMuted, height: 1.45),
                children: const [
                  TextSpan(text: 'Attendance needs the '),
                  TextSpan(text: 'HR User', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' role. Ask your administrator to grant it, then reload.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () => Get.offAllNamed(AppRoutes.HOME),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
