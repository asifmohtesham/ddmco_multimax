import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/camera_scan_overlay.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/home/widgets/performance_timeline_card.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_todo_card.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_preview.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_attendance_card.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_detail_sheet.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      // Approach A — the persistent barcode field stays the actual scan input;
      // the hero card up top is the discoverable entry point that opens it.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
          ),
          child: Obx(() => BarcodeInputWidget(
            onScan: controller.onScan,
            controller: controller.barcodeController,
            isLoading: controller.isScanning.value,
            hintText: 'Scan Item / Batch / Rack',
            activeRoute: AppRoutes.HOME,
          )),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await controller.fetchDashboardData();
          await controller.fetchPerformanceData();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            DocTypeListHeader(
              title: 'Dashboard',
              automaticallyImplyLeading: false,
              extraActions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search documents',
                  onPressed: () => showSearch(
                    context: context,
                    delegate: GlobalDocumentSearchDelegate(),
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 1 ── Greeting + context chip ──────────────────────────────
                  _buildGreeting(context),
                  const SizedBox(height: 18),

                  // 2 ── Hero scan ────────────────────────────────────────────
                  ScanHeroCard(onTap: () => _openScanner(context)),
                  const SizedBox(height: 18),

                  // 3-5 ── Quick Create / Needs attention / Upcoming tasks ────
                  // Manager persona (manager role + open ToDos) leads with
                  // Upcoming tasks; everyone else keeps Quick Create first.
                  // Only the tasks section moves — the middle block keeps
                  // today's internal order in both modes.
                  Obx(() => DashboardSectionOrder(
                        tasksFirst: controller.tasksFirst.value,
                        tasks: _buildUpcomingActionable(context),
                        middle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              'Quick Create',
                              trailing: Obx(() => DashboardColumnsToggle(
                                    columns: controller.dashboardColumns.value,
                                    onChanged: controller.setDashboardColumns,
                                  )),
                            ),
                            const SizedBox(height: 12),
                            _buildQuickAccessGrid(context),
                            const SizedBox(height: 18),
                            _buildNeedsAttention(context),
                            _buildTodayAttendance(context),
                          ],
                        ),
                      )),

                  // 6 ── Today's pulse ────────────────────────────────────────
                  _buildSectionHeader(context, "Today's pulse"),
                  const SizedBox(height: 12),
                  Obx(() {
                    if (controller.isLoadingStats.value || controller.isLoadingUsers.value) {
                      return const PulseSkeleton();
                    }
                    return _buildPulse(context);
                  }),
                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the camera scanner — the SAME entry point used by the persistent
  /// [BarcodeInputWidget]'s camera button — and routes the result through the
  /// existing [HomeController.onScan] plumbing. No new scan logic.
  Future<void> _openScanner(BuildContext context) async {
    final result = await CameraScanOverlay.show(context);
    if (result != null && result.isNotEmpty) {
      controller.onScan(result);
    }
  }

  // ---------------------------------------------------------------------------
  // Greeting + context chip (replaces the old full-width user-context card)
  // ---------------------------------------------------------------------------

  Widget _buildGreeting(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;

    return Obx(() {
      final user = controller.selectedFilterUser.value;
      final fullName = user?.name ?? 'Select User';
      final firstName = fullName.split(' ').first;
      final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U';

      return Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: cs.primary,
            child: Text(
              initial,
              style: TextStyle(
                color: cs.onPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, $firstName',
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _ContextChip(
                  name: fullName,
                  onTap: () => _showUserSearchModal(context),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Section header — major section label with optional count badge + rule
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(BuildContext context, String label,
      {int? count, Widget? trailing}) {
    final cs = Theme.of(context).colorScheme;
    final scheme = context.scheme;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.text,
            letterSpacing: -0.1,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(child: Divider(color: scheme.border, height: 1)),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing,
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Needs attention
  // ---------------------------------------------------------------------------
  //
  // Only rows with a REAL controller-backed source are rendered:
  //   • Resume Job Card — gated on activeWipJcName (live WIP for the session).
  //   • Work Orders in process — activeWorkOrdersCount (status "In Process").
  //   • Open Job Cards — activeJobCardsCount (status "Open").
  // The "Deliveries to pack" and "Purchase Receipts pending QC" rows from the
  // design are intentionally omitted until the controller exposes those counts
  // — per the handoff, rows with no real data source are hidden, not faked.
  Widget _buildNeedsAttention(BuildContext context) {
    return Obx(() {
      final wip = controller.activeWipJcName.value;
      final wo = controller.activeWorkOrdersCount.value;
      final jc = controller.activeJobCardsCount.value;

      final rows = <Widget>[];

      if (wip != null) {
        rows.add(ResumeJobCard(
          jcName: wip,
          operation: controller.activeWipJcOperation.value,
        ));
      }
      if (wo > 0) {
        rows.add(AttentionRow(
          icon: Icons.precision_manufacturing_outlined,
          color: Colors.indigo,
          title: 'Work Orders in process',
          subtitle: 'Active manufacturing orders',
          count: wo,
          onTap: controller.goToWorkOrder,
        ));
      }
      if (jc > 0) {
        rows.add(AttentionRow(
          icon: Icons.assignment_ind_outlined,
          color: Colors.deepOrange,
          title: 'Open Job Cards',
          subtitle: 'Awaiting start',
          count: jc,
          onTap: controller.goToJobCard,
        ));
      }

      if (rows.isEmpty) return const SizedBox.shrink();

      // Interleave the rows with 9px gaps, matching the design's tight stack.
      final stacked = <Widget>[];
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) stacked.add(const SizedBox(height: 9));
        stacked.add(rows[i]);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, 'Needs attention', count: rows.length),
          const SizedBox(height: 11),
          ...stacked,
          const SizedBox(height: 18),
        ],
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Today's attendance — site-wide summary of the HR attendance monitor.
  // Hidden (SizedBox.shrink) for users without Attendance access, so operator
  // Dashboards are unchanged. Does NOT follow the "Viewing {user}" chip: the
  // terminal is one site, and the "Me" line is always the logged-in employee.
  // ---------------------------------------------------------------------------
  Widget _buildTodayAttendance(BuildContext context) {
    return Obx(() {
      if (!controller.attendanceVisible) return const SizedBox.shrink();
      final loading = controller.isLoadingAttendance.value;
      final rows = controller.attendanceRows;
      if (!loading && rows.isEmpty) return const SizedBox.shrink();
      final now = DateTime.now();
      final selfId = controller.myAttendance?.employee.name;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            "Today's attendance",
            trailing: TextButton(
              onPressed: controller.goToAttendance,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text('Open',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 11),
          DashboardAttendanceCard(
            counts: controller.attendanceCounts,
            shift: controller.attendanceShift.value,
            now: now,
            isHoliday: controller.attendanceIsHoliday,
            beforeCutoff: controller.beforeAttendanceCutoff,
            looksOffline: controller.attendanceLooksOffline,
            latestPunch: controller.attendanceLatestPunch.value?.time,
            highlights: dashboardAttendanceHighlights(rows, selfEmployee: selfId),
            myRow: controller.myAttendance,
            loadedAt: controller.attendanceLoadedAt.value,
            isLoading: loading,
            onViewAll: controller.goToAttendance,
            onRowTap: (EmployeeDayStatus row) => showEmployeeDetailSheet(
              context,
              row: row,
              day: dateOnly(now),
              shift: controller.attendanceShift.value,
              loadedAt: controller.attendanceLoadedAt.value,
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Upcoming & actionable — a horizontal DocType chip slider (Draft counts
  // across PO/PR/SE/DN/PS + open ToDos) driving a 3-document preview.
  // ---------------------------------------------------------------------------
  Widget _buildUpcomingActionable(BuildContext context) {
    return Obx(() {
      final chips = _actionableChips(context);
      final loading = controller.isLoadingActionable.value;
      final selected = controller.selectedActionable.value;
      final todos = controller.upcomingTodos;

      // Nothing to show and nothing loading → collapse entirely.
      if (chips.isEmpty && !loading) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Upcoming & actionable',
            trailing: ActionableScopeToggle(
              scope: controller.actionableScope.value,
              onChanged: controller.setActionableScope,
            ),
          ),
          const SizedBox(height: 11),
          DashboardActionableStrip(chips: chips, isLoading: loading),
          if (selected == 'ToDo' && todos.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var i = 0; i < todos.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              DashboardTodoCard(
                todo: todos[i],
                onTap: () => Get.toNamed(
                  AppRoutes.TODO_FORM,
                  arguments: {'name': todos[i].name, 'mode': 'view'},
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.goToToDo,
                child: const Text('View All'),
              ),
            ),
          ] else if (selected != null && selected != 'ToDo') ...[
            const SizedBox(height: 14),
            ActionableDocPreview(
              rows: controller.previewDocs.toList(),
              isLoading: controller.isLoadingPreview.value,
              onViewAll: () => controller.openActionableList(selected),
            ),
          ],
          const SizedBox(height: 6),
        ],
      );
    });
  }

  /// Chip data in slider order: Tasks first (personal, gated on ToDo access),
  /// then one per accessible document DocType present in [actionableCounts].
  /// A zero count → null onTap, so the chip is muted and cannot be selected.
  List<ActionableChipData> _actionableChips(BuildContext context) {
    final chips = <ActionableChipData>[];
    final selected = controller.selectedActionable.value;

    if (Get.find<PermissionService>().hasAccess('ToDo') == true) {
      final count = controller.openTodoCount.value;
      chips.add(ActionableChipData(
        doctype: 'ToDo',
        label: 'Tasks',
        icon: Icons.check_circle_outline,
        count: count,
        selected: selected == 'ToDo',
        onTap: count == 0 ? null : () => controller.selectActionable('ToDo'),
      ));
    }

    for (final cfg in kActionableDocConfigs) {
      if (!controller.actionableCounts.containsKey(cfg.doctype)) continue;
      final count = controller.actionableCounts[cfg.doctype] ?? 0;
      chips.add(ActionableChipData(
        doctype: cfg.doctype,
        label: cfg.label,
        icon: cfg.icon,
        count: count,
        selected: selected == cfg.doctype,
        onTap: count == 0 ? null : () => controller.selectActionable(cfg.doctype),
      ));
    }
    return chips;
  }

  // ---------------------------------------------------------------------------
  // Today's pulse
  // ---------------------------------------------------------------------------

  Widget _buildPulse(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: PulseStat(
                  title: 'Work Orders',
                  icon: Icons.precision_manufacturing_outlined,
                  actual: controller.activeWorkOrdersCount.value,
                  target: controller.targetWorkOrders,
                  onTap: controller.goToWorkOrder,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PulseStat(
                  title: 'Job Cards',
                  icon: Icons.assignment_ind_outlined,
                  actual: controller.activeJobCardsCount.value,
                  target: controller.targetJobCards,
                  onTap: controller.goToJobCard,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Obx(() => PerformanceTimelineCard(
              viewMode: controller.timelineViewMode.value,
              onToggleView: controller.toggleTimelineView,
              data: controller.timelineData,
              isLoading: controller.isLoadingTimeline.value,
              selectedDate: controller.timelineViewMode.value != 'Weekly'
                  ? controller.selectedDailyDate.value
                  : null,
              selectedRange: controller.timelineViewMode.value == 'Weekly'
                  ? controller.selectedWeeklyRange.value
                  : null,
              onDateChanged: controller.onDailyDateChanged,
              onRangeChanged: controller.onWeeklyRangeChanged,
            )),
        const SizedBox(height: 12),
        BomCountCard(
          count: controller.activeBomCount.value,
          onTap: controller.goToBOM,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Quick Create Grid
  // ---------------------------------------------------------------------------

  /// Configuration-driven quick action — adding a new tile is a one-line change
  /// in each section list below. Satisfies OCP: open for extension, no inline
  /// mutation of the builder method.
  Widget _buildQuickAccessGrid(BuildContext context) {
    return Obx(() {
      final int columns = controller.dashboardColumns.value;
      return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;

        // ── Operations row ────────────────────────────────────────────────────
        final operationItems = [
          _QuickActionConfig(
            label: 'Stock Entry',
            icon: Icons.compare_arrows_outlined,
            color: Colors.orange,
            doctype: 'Stock Entry',
            onTap: () => Get.toNamed(AppRoutes.STOCK_ENTRY, arguments: {'openCreate': true}),
          ),
          _QuickActionConfig(
            label: 'Delivery Note',
            icon: Icons.local_shipping_outlined,
            color: Colors.blue,
            doctype: 'Delivery Note',
            onTap: () {
              controller.setFulfillmentPrefixFilter(['KA', 'ML']);
              _showFulfillmentSelectionSheet(context, title: 'Select Delivery Note');
            },
          ),
          _QuickActionConfig(
            label: 'Purchase Receipt',
            icon: Icons.receipt_long_outlined,
            color: Colors.green,
            doctype: 'Purchase Receipt',
            onTap: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT, arguments: {'openCreate': true}),
          ),
          _QuickActionConfig(
            label: 'Packing Slip',
            icon: Icons.assignment_return_outlined,
            color: Colors.purple,
            doctype: 'Packing Slip',
            onTap: () => Get.toNamed(AppRoutes.PACKING_SLIP, arguments: {'openCreate': true}),
          ),
          _QuickActionConfig(
            label: 'POS Upload',
            icon: Icons.shopping_bag_outlined,
            color: Colors.deepPurple,
            doctype: 'POS Upload',
            onTap: () {
              controller.setFulfillmentPrefixFilter([]);
              _showFulfillmentSelectionSheet(context, title: 'Select POS Upload');
            },
          ),
        ];

        // ── Manufacturing row ────────────────────────────────────────────────
        final manufacturingItems = [
          _QuickActionConfig(
            label: 'BOM',
            icon: Icons.account_tree_outlined,
            color: Colors.teal,
            doctype: 'BOM',
            onTap: () => Get.toNamed(
              AppRoutes.BOM,
              arguments: {'filters': {'is_active': 1}, 'pageTitle': 'Active BOMs'},
            ),
          ),
          _QuickActionConfig(
            label: 'Work Order',
            icon: Icons.precision_manufacturing_outlined,
            color: Colors.indigo,
            doctype: 'Work Order',
            onTap: controller.goToWorkOrder,
          ),
          _QuickActionConfig(
            label: 'Job Card',
            icon: Icons.assignment_ind_outlined,
            color: Colors.deepOrange,
            doctype: 'Job Card',
            onTap: controller.goToJobCard,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionDivider('Operations'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: operationItems.map((cfg) {
                final tile = _buildQuickActionItem(context, cfg, itemWidth,
                    horizontal: columns == 1);
                if (cfg.doctype == null) return tile;
                return DocTypeGuard(
                  doctype: cfg.doctype!,
                  child: tile,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _buildSectionDivider('Manufacturing'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: manufacturingItems.map((cfg) {
                final tile = _buildQuickActionItem(context, cfg, itemWidth,
                    horizontal: columns == 1);
                if (cfg.doctype == null) return tile;
                return DocTypeGuard(
                  doctype: cfg.doctype!,
                  child: tile,
                );
              }).toList(),
            ),
          ],
        );
      },
      );
    });
  }

  /// Slim labelled divider between quick-create sections.
  Widget _buildSectionDivider(String label) {
    return Builder(builder: (context) {
      final scheme = context.scheme;
      return Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.textMuted,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: scheme.border, height: 1)),
        ],
      );
    });
  }

  Widget _buildQuickActionItem(
    BuildContext context,
    _QuickActionConfig cfg,
    double width, {
    bool horizontal = false,
  }) {
    final scheme = context.scheme;

    // 1-column layout — full-width row: accent bar, icon, label, "+" affordance.
    if (horizontal) {
      return SizedBox(
        width: width,
        child: Material(
          color: scheme.fg,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: cfg.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cfg.color.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cfg.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(cfg.icon, color: cfg.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cfg.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: scheme.subtle,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add, size: 11, color: scheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      child: Material(
        color: scheme.fg,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: cfg.onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.border),
            ),
            child: Stack(
              children: [
                // 3px top accent bar in the tile colour.
                Positioned(
                  top: 0,
                  left: 14,
                  right: 14,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: cfg.color.withValues(alpha: 0.9),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
                // "+" create affordance, top-right.
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: scheme.subtle,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add, size: 11, color: scheme.textMuted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cfg.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(cfg.icon, color: cfg.color, size: 23),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cfg.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: scheme.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Fulfillment bottom sheet
  // ---------------------------------------------------------------------------

  void _showFulfillmentSelectionSheet(BuildContext context, {String title = 'Select POS Upload'}) {
    controller.fetchFulfillmentPosUploads();
    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            final scheme = context.scheme;
            return Container(
              decoration: BoxDecoration(
                color: scheme.fg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleLarge),
                        IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      onChanged: controller.filterFulfillmentList,
                      decoration: const InputDecoration(
                        hintText: 'Search uploads...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingFulfillmentList.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (controller.fulfillmentPosUploads.isEmpty) {
                        return const Center(child: Text('No Pending/In Progress Uploads found.'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: controller.fulfillmentPosUploads.length,
                        separatorBuilder: (c, i) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final pos = controller.fulfillmentPosUploads[index];
                          return ListTile(
                            title: Text(pos.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pos.customer),
                                Text(
                                  FormattingHelper.getRelativeTime(pos.modified),
                                  style: TextStyle(fontSize: 11, color: scheme.textMuted),
                                ),
                              ],
                            ),
                            trailing: StatusPill(status: pos.status),
                            onTap: () => controller.handleFulfillmentSelection(pos),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }

  // ---------------------------------------------------------------------------
  // User search modal (unchanged)
  // ---------------------------------------------------------------------------

  void _showUserSearchModal(BuildContext context) {
    final TextEditingController searchController = TextEditingController();
    final RxList<User> filteredUsers = RxList<User>(controller.userList);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Select User",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search users...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) {
                      filteredUsers.assignAll(
                        controller.userList.where((user) {
                          final name = user.name.toLowerCase();
                          final email = user.email.toLowerCase();
                          return name.contains(val.toLowerCase()) || email.contains(val.toLowerCase());
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(
                      () => ListView.separated(
                        controller: scrollController,
                        itemCount: filteredUsers.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final isSelected =
                              user.email == controller.selectedFilterUser.value?.email;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(user.name.isNotEmpty ? user.name[0] : 'U'),
                            ),
                            title: Text(
                              user.name,
                              style: TextStyle(
                                fontWeight:
                                    isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(user.email),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: Theme.of(context).primaryColor)
                                : null,
                            onTap: () => controller.onUserFilterChanged(user),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// =============================================================================
// _QuickActionConfig — data class to drive the quick-create grid (DRY/OCP)
// =============================================================================

class _QuickActionConfig {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// When non-null the tile is wrapped in a [DocTypeGuard] and is only
  /// rendered if the current user has read access to this DocType.
  final String? doctype;

  const _QuickActionConfig({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.doctype,
  });
}

// =============================================================================
// _ContextChip — compact "Viewing {user}" pill that opens the user switcher
// =============================================================================

class _ContextChip extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _ContextChip({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 3, 8, 3),
        decoration: BoxDecoration(
          color: scheme.subtle,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: scheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 13, color: scheme.textSubtle),
            const SizedBox(width: 5),
            Flexible(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                text: TextSpan(
                  style: TextStyle(fontSize: 12, color: scheme.textMuted),
                  children: [
                    const TextSpan(text: 'Viewing '),
                    TextSpan(
                      text: name,
                      style: TextStyle(
                        color: scheme.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down, size: 14, color: scheme.textSubtle),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DashboardColumnsToggle — 1↔2 column switch for the Quick Create grid
// =============================================================================

/// Segmented two-icon pill. Public (like the other dashboard widgets) so it
/// can be exercised in widget tests without the full HomeController DI graph.
class DashboardColumnsToggle extends StatelessWidget {
  /// Current layout — 1 or 2.
  final int columns;
  final ValueChanged<int> onChanged;

  const DashboardColumnsToggle({
    super.key,
    required this.columns,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scheme = context.scheme;

    Widget option(int value, IconData icon, String tooltip) {
      final selected = columns == value;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary.withValues(alpha: 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Icon(
              icon,
              size: 15,
              color: selected ? cs.primary : scheme.textSubtle,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.subtle,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: scheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(1, Icons.view_agenda_outlined, 'Single column'),
          const SizedBox(width: 2),
          option(2, Icons.grid_view_rounded, 'Two columns'),
        ],
      ),
    );
  }
}

// =============================================================================
// ScanHeroCard — discoverable "Scan to start" entry point (maroon gradient)
// =============================================================================

class ScanHeroCard extends StatelessWidget {
  final VoidCallback onTap;

  const ScanHeroCard({super.key, required this.onTap});

  // The hero is an intentional brand banner. colorScheme.primary lightens to a
  // pink (#D9707C) on dark surfaces — fine for small accents, but it washes out
  // a large filled slab — so the gradient is pinned to the canonical maroon in
  // BOTH themes (matching Dashboard Revamp.html) with white content for contrast.
  static const Color _brand = Color(0xFF870E18); // AppScheme.light.primary
  static const Color _brandDark = Color(0xFF5F0F1A); // ds.css maroon-700

  @override
  Widget build(BuildContext context) {
    const primary = _brand;
    const primaryDark = _brandDark;
    const onTint = Colors.white;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primary, primaryDark],
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.32),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: onTint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.qr_code_scanner, color: onTint, size: 26),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan to start',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: onTint,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Item, batch or rack — look up or add stock',
                        style: TextStyle(
                          fontSize: 12,
                          color: onTint.withValues(alpha: 0.82),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: onTint.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.photo_camera_outlined, color: onTint, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ResumeJobCard — brand-tinted "Resume Job Card" attention item (live WIP)
// =============================================================================

class ResumeJobCard extends StatelessWidget {
  final String jcName;
  final String? operation;

  const ResumeJobCard({super.key, required this.jcName, this.operation});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scheme = context.scheme;
    final op = (operation ?? '').trim();
    final title = op.isNotEmpty ? '$jcName · $op' : jcName;

    return Material(
      color: Color.alphaBlend(cs.primary.withValues(alpha: 0.09), scheme.fg),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: () => Get.toNamed(
          AppRoutes.JOB_CARD_FORM,
          arguments: {'name': jcName},
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: Color.alphaBlend(cs.primary.withValues(alpha: 0.22), scheme.border),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow_rounded, color: cs.onPrimary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RESUME JOB CARD',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AttentionRow — actionable "what to do now" row with a count badge
// =============================================================================

class AttentionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  const AttentionRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Material(
      color: scheme.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: scheme.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: scheme.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 30),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: scheme.textSubtle, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PulseStat — compact actual/target progress stat (replaces the KPI gauges)
// =============================================================================

class PulseStat extends StatelessWidget {
  final String title;
  final IconData icon;
  final int actual;
  final int target;
  final VoidCallback onTap;

  const PulseStat({
    super.key,
    required this.title,
    required this.icon,
    required this.actual,
    required this.target,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final pct = target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;
    final stateColor = pct < 0.4
        ? AppColors.red500
        : (pct < 0.8 ? AppColors.orange500 : AppColors.green500);

    return Material(
      color: scheme.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: scheme.textSubtle),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: actual),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        color: scheme.text,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '/ $target target',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: Container(
                  height: 6,
                  color: scheme.border,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: pct == 0 ? 0.001 : pct),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: Container(color: stateColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      // No "due today" source on the controller; show the honest,
                      // derivable distance-to-target instead (spec's footer intent).
                      actual >= target ? 'Target met' : '${target - actual} to target',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: stateColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(pct * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BomCountCard — flat count card for active BOMs
// =============================================================================

class BomCountCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const BomCountCard({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_tree_outlined, color: Colors.teal, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active BOMs',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Submitted & active bills of materials',
                      style: TextStyle(fontSize: 11, color: scheme.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: count),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: scheme.textSubtle, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PulseSkeleton — shimmer placeholder while stats are loading
// =============================================================================

class PulseSkeleton extends StatefulWidget {
  const PulseSkeleton({super.key});

  @override
  State<PulseSkeleton> createState() => PulseSkeletonState();
}

class PulseSkeletonState extends State<PulseSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _box(BuildContext context, {double w = double.infinity, double h = 14, double r = 12}) {
    final scheme = context.scheme;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Color.lerp(scheme.subtle, scheme.border, _anim.value),
          borderRadius: BorderRadius.circular(r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _box(context, h: 112)),
            const SizedBox(width: 10),
            Expanded(child: _box(context, h: 112)),
          ],
        ),
        const SizedBox(height: 12),
        _box(context, h: 190),
        const SizedBox(height: 12),
        _box(context, h: 64),
      ],
    );
  }
}

// =============================================================================
// DashboardSectionOrder — persona-aware Tasks ↔ Quick-Create ordering
// =============================================================================

/// Places [tasks] above [middle] (manager persona: manager role + open
/// ToDos) or below it (everyone else — exactly today's layout). Public and
/// controller-free (like the other dashboard widgets) so widget tests can
/// assert the flip without the full HomeController DI graph.
class DashboardSectionOrder extends StatelessWidget {
  const DashboardSectionOrder({
    super.key,
    required this.tasksFirst,
    required this.tasks,
    required this.middle,
  });

  /// True when Upcoming tasks lead.
  final bool tasksFirst;

  /// The Upcoming-tasks section (hides itself when there are no ToDos).
  final Widget tasks;

  /// The Quick Create + Needs attention block, kept in its existing
  /// internal order in both modes.
  final Widget middle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tasksFirst ? [tasks, middle] : [middle, tasks],
    );
  }
}
