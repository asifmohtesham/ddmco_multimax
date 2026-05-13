import 'dart:ui' as ui show FontFeature, TextDirection;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/modules/global_widgets/search_highlight.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/job_card/job_card_form_controller.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, TextDirection;

class JobCardScreen extends StatefulWidget {
  const JobCardScreen({super.key});

  @override
  State<JobCardScreen> createState() => _JobCardScreenState();
}

class _JobCardScreenState extends State<JobCardScreen> {
  final JobCardController controller = Get.find();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
    if (atBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchJobCards(isLoadMore: true);
    }
  }

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final cs = Theme.of(context).colorScheme;

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onDeleted,
    }) =>
        Chip(
          avatar: Icon(icon, size: 16, color: cs.onSecondaryContainer),
          label: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600)),
          backgroundColor: cs.secondaryContainer,
          deleteIconColor: cs.onSecondaryContainer,
          onDeleted: onDeleted,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(chip(
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchJobCards(clear: true);
        },
      ));
    }
    if (controller.activeFilters.containsKey('status')) {
      chips.add(chip(
        icon: Icons.flag_outlined,
        label: 'Status: ${controller.activeFilters['status']}',
        onDeleted: () => controller.removeFilter('status'),
      ));
    }

    // Assigned Employee
    if (controller.activeFilters.containsKey('Job Card Time Log') &&
        controller.assignedEmployeeLabel.value.isNotEmpty) {
      chips.add(chip(
        icon: Icons.badge_outlined,
        label: 'Employee: ${controller.assignedEmployeeLabel.value}',
        onDeleted: () => controller.setAssignedToFilter(null, null),
      ));
    }

    // Created By
    if (controller.activeFilters.containsKey('owner') &&
        controller.createdByUserLabel.value.isNotEmpty) {
      chips.add(chip(
        icon: Icons.person_add_alt_1_outlined,
        label: 'Created By: ${controller.createdByUserLabel.value}',
        onDeleted: () => controller.setCreatedByFilter(null, null),
      ));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      body: RefreshIndicator(
        onRefresh: () => controller.fetchJobCards(clear: true),
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            DocTypeListHeader(
              title: 'Job Cards',
              automaticallyImplyLeading: false,
              searchDoctype:      'Job Card',
              searchQuery:        controller.searchQuery,
              onSearchChanged:    controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchJobCards(clear: true);
              },
              activeFilters:      controller.activeFilters,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters:  controller.clearFilters,
              onFilterTap: () => _showFilterSheet(context),
            ),

            Obx(() {
              if (controller.isLoading.value &&
                  controller.jobCards.isEmpty) {
                return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()));
              }

              if (controller.jobCards.isEmpty) {
                final hasFilters =
                    controller.activeFilters.isNotEmpty ||
                        controller.searchQuery.value.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            hasFilters
                                ? Icons.filter_alt_off_outlined
                                : Icons.assignment_ind_outlined,
                            size: 64,
                            color: cs.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching Job Cards'
                                : 'No Job Cards',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: hasFilters
                                ? controller.clearFilters
                                : () => controller.fetchJobCards(
                                    clear: true),
                            icon: Icon(hasFilters
                                ? Icons.clear_all
                                : Icons.refresh),
                            label: Text(
                                hasFilters ? 'Clear Filters' : 'Reload'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // Capture query once — passed into each tile to avoid extra Obx.
              final query = controller.searchQuery.value;
              final cards = controller.jobCards;

              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: _JobCardKpiStrip(controller: controller),
                  ),
                  SliverToBoxAdapter(
                    child: _JobCardProductionChart(
                      data: controller.dailyProductionData,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= cards.length) {
                            return controller.hasMore.value
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child:
                                          CircularProgressIndicator()))
                                : const SizedBox(height: 80);
                          }
                          final jc = cards[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _JobCardTile(
                              jc: jc,
                              searchQuery: query,
                              onTap: () => Get.toNamed(
                                AppRoutes.JOB_CARD_FORM,
                                arguments: {'name': jc.name},
                              ),
                            ),
                          );
                        },
                        childCount: cards.length + 1,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _JobCardFilterSheet(controller: controller),
    );
  }
}

// ── Filter bottom sheet ────────────────────────────────────────────────

class _JobCardFilterSheet extends StatelessWidget {
  final JobCardController controller;
  const _JobCardFilterSheet({required this.controller});

  static const List<String> _statuses = [
    'Open',
    'Work In Progress',
    'Material Transferred',
    'Completed',
    'On Hold',
    'Cancelled',
  ];

  /// Opens a bottom-sheet employee picker that draws from
  /// [JobCardFormController]'s availableEmployees cache (Active employees).
  /// Falls back to a direct provider fetch if the cache is empty.
  void _openEmployeePicker(
      BuildContext context, {
        required void Function(String empId, String displayName) onSelected,
      }) {
    // Reuse the already-loaded employee list from any open JobCardFormController,
    // or load from JobCardProvider directly.
    final searchCtrl = TextEditingController();
    // Fetch employees via the provider directly — avoids coupling to the form controller.
    final employees  = RxList<Map<String, dynamic>>([]);
    final isLoading  = true.obs;

    // Fire-and-forget load
    Get.find<JobCardProvider>().getActiveEmployees().then((res) {
      if (res.statusCode == 200 && res.data['data'] != null) {
        employees.assignAll(
          (res.data['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
      isLoading.value = false;
    }).catchError((_) => isLoading.value = false);

    final filtered = RxList<Map<String, dynamic>>([]);
    // Mirror employees into filtered once loaded.
    ever(employees, (list) => filtered.assignAll(list));

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) {
            final cs = Theme.of(ctx).colorScheme;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Employee',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: Get.back),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search employees...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) {
                      final q = val.toLowerCase();
                      filtered.assignAll(
                        q.isEmpty
                            ? employees
                            : employees.where((e) =>
                        (e['name'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(q) ||
                            (e['employee_name'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(q)),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (isLoading.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (filtered.isEmpty) {
                        return const Center(child: Text('No employees found'));
                      }
                      return ListView.separated(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e       = filtered[i];
                          final empId   = (e['name'] ?? '').toString();
                          final empName = (e['employee_name'] ?? '').toString();
                          final display = empName.isNotEmpty ? empName : empId;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(display.isNotEmpty
                                  ? display[0].toUpperCase()
                                  : '?'),
                            ),
                            title: Text(display),
                            subtitle: Text(empId),
                            onTap: () {
                              Get.back();
                              onSelected(empId, display);
                            },
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

  void _openUserPicker(
      BuildContext context, {
        required String title,
        required void Function(String userId, String displayName) onSelected,
      }) {
    final searchCtrl = TextEditingController();
    final filtered   = RxList<User>(controller.users);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) {
            final cs = Theme.of(ctx).colorScheme;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: Get.back,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search users...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (val) {
                      final q = val.toLowerCase();
                      filtered.assignAll(
                        q.isEmpty
                            ? controller.users
                            : controller.users.where((u) =>
                        u.name.toLowerCase().contains(q) ||
                            u.email.toLowerCase().contains(q)),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingUsers.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (filtered.isEmpty) {
                        return const Center(child: Text('No users found'));
                      }
                      return ListView.separated(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final u       = filtered[i];
                          final userId  = u.email;
                          final display = u.name.isNotEmpty ? u.name : userId;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(display[0].toUpperCase()),
                            ),
                            title: Text(display),
                            subtitle: Text(userId),
                            onTap: () {
                              Get.back();
                              onSelected(userId, display);
                            },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filters',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () {
                    controller.clearFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Status chips (unchanged)
            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Obx(() {
              final active = controller.activeFilters['status'] as String?;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _statuses.map((s) {
                  final selected = active == s;
                  return ChoiceChip(
                    label: Text(s),
                    selected: selected,
                    onSelected: (_) {
                      controller.setFilter('status', selected ? null : s);
                    },
                  );
                }).toList(),
              );
            }),
            const SizedBox(height: 16),

            // Assigned Employee (backed by employee child table)
            Obx(() {
              final label = controller.assignedEmployeeLabel.value;
              return TextFormField(
                readOnly: true,
                onTap: () => _openEmployeePicker(
                  context,
                  onSelected: (empId, display) =>
                      controller.setAssignedToFilter(empId, display),
                ),
                decoration: InputDecoration(
                  labelText: 'Assigned Employee',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.badge_outlined),
                  suffixIcon: label.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear',
                    onPressed: () => controller.setAssignedToFilter(null, null),
                  )
                      : const Icon(Icons.arrow_drop_down),
                  isDense: true,
                ),
                controller: TextEditingController(text: label),
              );
            }),
            const SizedBox(height: 16),

            // Created By (backed by owner)
            Obx(() {
              final label = controller.createdByUserLabel.value;
              return TextFormField(
                readOnly: true,
                onTap: () => _openUserPicker(
                  context,
                  title: 'Select Created By',
                  onSelected: (userId, display) =>
                      controller.setCreatedByFilter(userId, display),
                ),
                decoration: InputDecoration(
                  labelText: 'Created By',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
                  suffixIcon: label.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear',
                    onPressed: () => controller.setCreatedByFilter(null, null),
                  )
                      : const Icon(Icons.arrow_drop_down),
                  isDense: true,
                ),
                controller: TextEditingController(text: label),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── KPI strip ───────────────────────────────────────────────────────────

// ── Production quantity chart ────────────────────────────────────────────

class _JobCardProductionChart extends StatefulWidget {
  final List<DailyProduction> data;
  const _JobCardProductionChart({required this.data});

  @override
  State<_JobCardProductionChart> createState() =>
      _JobCardProductionChartState();
}

class _JobCardProductionChartState extends State<_JobCardProductionChart> {
  bool _expanded = true;

  static const double _barWidth    = 18;
  static const double _groupGap    = 28;
  static const double _chartHeight = 130;
  static const double _labelArea   = 36;

  void _onBarTap(BuildContext context, DailyProduction d) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${d.date}  •  Planned: ${_fmt(d.planned)}  •  Completed: ${_fmt(d.completed)}',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final data  = widget.data;
    final empty = data.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Production Qty by Day',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Legend
              if (!empty && _expanded) ...[
                _LegendDot(color: cs.primary,  label: 'Planned'),
                const SizedBox(width: 10),
                _LegendDot(color: cs.tertiary, label: 'Completed'),
                const SizedBox(width: 6),
              ],
              // Toggle
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // ── Chart body ───────────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: empty
                ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No date data available',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            )
                : _ChartBody(
              data: data,
              barWidth: _barWidth,
              groupGap: _groupGap,
              chartHeight: _chartHeight,
              labelArea: _labelArea,
              colorPlanned:   cs.primary,
              colorCompleted: cs.tertiary,
              colorGrid:      cs.outlineVariant.withValues(alpha: 0.3),
              colorLabel:     cs.onSurfaceVariant,
              onTap: (d) => _onBarTap(context, d),
            ),
            secondChild: const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }
}

// ── Chart body (scrollable) ──────────────────────────────────────────────

class _ChartBody extends StatelessWidget {
  final List<DailyProduction> data;
  final double barWidth, groupGap, chartHeight, labelArea;
  final Color colorPlanned, colorCompleted, colorGrid, colorLabel;
  final void Function(DailyProduction) onTap;

  const _ChartBody({
    required this.data,
    required this.barWidth,
    required this.groupGap,
    required this.chartHeight,
    required this.labelArea,
    required this.colorPlanned,
    required this.colorCompleted,
    required this.colorGrid,
    required this.colorLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = data.fold<double>(
      0,
          (m, d) => d.planned > m ? d.planned : m,
    );
    final groupWidth  = barWidth * 2 + 6; // two bars + inner gap
    final totalWidth  = data.length * (groupWidth + groupGap);
    final canvasWidth = totalWidth.clamp(0.0, double.infinity);

    return SizedBox(
      height: chartHeight + labelArea,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: GestureDetector(
          onTapUp: (details) {
            final localX = details.localPosition.dx;
            final idx    = (localX / (groupWidth + groupGap)).floor();
            if (idx >= 0 && idx < data.length) onTap(data[idx]);
          },
          child: CustomPaint(
            size: Size(canvasWidth, chartHeight + labelArea),
            painter: _BarPainter(
              data:           data,
              maxVal:         maxVal == 0 ? 1 : maxVal,
              barWidth:       barWidth,
              groupGap:       groupGap,
              chartHeight:    chartHeight,
              labelArea:      labelArea,
              colorPlanned:   colorPlanned,
              colorCompleted: colorCompleted,
              colorGrid:      colorGrid,
              colorLabel:     colorLabel,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bar painter ──────────────────────────────────────────────────────────

class _BarPainter extends CustomPainter {
  final List<DailyProduction> data;
  final double maxVal, barWidth, groupGap, chartHeight, labelArea;
  final Color colorPlanned, colorCompleted, colorGrid, colorLabel;

  _BarPainter({
    required this.data,
    required this.maxVal,
    required this.barWidth,
    required this.groupGap,
    required this.chartHeight,
    required this.labelArea,
    required this.colorPlanned,
    required this.colorCompleted,
    required this.colorGrid,
    required this.colorLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintPlanned   = Paint()..color = colorPlanned.withValues(alpha: 0.85);
    final paintCompleted = Paint()..color = colorCompleted.withValues(alpha: 0.85);
    final paintGrid      = Paint()
      ..color       = colorGrid
      ..strokeWidth = 0.5;

    final groupWidth = barWidth * 2 + 6;
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);

    // Grid lines at 0%, 50%, 100%
    for (final pct in [0.0, 0.5, 1.0]) {
      final y = chartHeight - chartHeight * pct;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    for (int i = 0; i < data.length; i++) {
      final d     = data[i];
      final xBase = i * (groupWidth + groupGap);

      // Planned bar
      final plannedH  = (d.planned   / maxVal) * chartHeight;
      final completedH = (d.completed / maxVal) * chartHeight;

      final rrPlanned = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          xBase, chartHeight - plannedH, barWidth, plannedH,
        ),
        topLeft:  const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      final rrCompleted = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          xBase + barWidth + 6, chartHeight - completedH, barWidth, completedH,
        ),
        topLeft:  const Radius.circular(3),
        topRight: const Radius.circular(3),
      );

      canvas.drawRRect(rrPlanned,   paintPlanned);
      canvas.drawRRect(rrCompleted, paintCompleted);

      // Date label (MMM d)
      final rawDate = d.date; // 'YYYY-MM-DD'
      String label = rawDate;
      try {
        final parts = rawDate.split('-');
        if (parts.length == 3) {
          final dt   = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          final mons = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          label = '${mons[dt.month - 1]} ${dt.day}';
        }
      } catch (_) {}

      tp
        ..text = TextSpan(
          text: label,
          style: TextStyle(color: colorLabel, fontSize: 9),
        )
        ..layout();
      tp.paint(
        canvas,
        Offset(
          xBase + (groupWidth - tp.width) / 2,
          chartHeight + 6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.data != data || old.maxVal != maxVal;
}

// ── Legend dot ───────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── KPI strip ───────────────────────────────────────────────────────────

class _JobCardKpiStrip extends StatelessWidget {
  final JobCardController controller;
  const _JobCardKpiStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _Kpi('Pending',   '${controller.openCards}',      cs.secondary),
          const SizedBox(width: 8),
          _Kpi('Completed', '${controller.completedCards}', cs.tertiary),
          const SizedBox(width: 8),
          _Kpi('Submitted', '${controller.submittedCards}', cs.primary),
          const SizedBox(width: 8),
          _Kpi('Total',     '${controller.totalCards}',     cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── Job Card tile ──────────────────────────────────────────────────────────────

class _JobCardTile extends StatelessWidget {
  final JobCard jc;
  final VoidCallback onTap;
  /// Current search query — passed from the parent Obx to avoid extra rebuilds.
  final String searchQuery;

  const _JobCardTile({
    required this.jc,
    required this.onTap,
    required this.searchQuery,
  });

  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (jc.status) {
      JobCard.statusWorkInProgress      => cs.primary,
      JobCard.statusCompleted           => cs.tertiary,
      JobCard.statusMaterialTransferred => cs.secondary,
      JobCard.statusCancelled           => cs.error,
      JobCard.statusOnHold              => cs.outline,
      _                                 => cs.onSurfaceVariant,
    };
  }

  /// Label passed into [StatusPill] for consistent coloring.
  /// Maps ERP's 'Work In Progress' to the existing 'In Progress' token.
  String _statusLabelForPill() {
    switch (jc.status) {
      case JobCard.statusWorkInProgress:
        return 'In Progress';
      default:
        return jc.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs          = Theme.of(context).colorScheme;
    final theme       = Theme.of(context);
    final clr         = _statusColor(context);
    final hasProgress = jc.forQuantity > 0;

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: jc.name));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied: ${jc.name}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Material(
        color: cs.surface,
        elevation: (jc.isOpen || jc.isWorkInProgress) ? 2 : 0,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: clr.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(Icons.build_outlined, color: clr, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Operation — highlighted
                          SearchHighlight(
                            text: jc.operation,
                            query: searchQuery,
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          // Document name — e.g. PO-JOB-00042
                          SearchHighlight(
                            text: jc.name,
                            query: searchQuery,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          // Workstation + qty row — workstation part highlighted
                          SearchHighlight(
                            text: '${jc.workstation ?? 'Unassigned'} • '
                                '${_fmtQty(jc.totalCompletedQty)}/'
                                '${_fmtQty(jc.forQuantity)} units',
                            query: searchQuery,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          // Work Order linkage
                          SearchHighlight(
                            text: 'Work Order: ${jc.workOrder}',
                            query: searchQuery,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(status: _statusLabelForPill()),
                  ],
                ),
                if (hasProgress) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: jc.progress,
                            minHeight: 5,
                            backgroundColor:
                                cs.outlineVariant.withValues(alpha: 0.5),
                            color: clr,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(jc.progress * 100).toInt()}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(1);
}
