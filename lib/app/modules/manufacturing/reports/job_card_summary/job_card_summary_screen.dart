import 'dart:ui' as ui show FontFeature;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/job_card_summary/job_card_summary_controller.dart';

class JobCardSummaryScreen extends GetView<JobCardSummaryController> {
  const JobCardSummaryScreen({super.key});

  // ── Filter field descriptors ──────────────────────────────────────────────
  // No FocusNodes needed — none of these fields are barcode-scannable.
  // Using static const because ReportFilterField has no runtime objects here.

  static const _fields = <ReportFilterField>[
    ReportFilterField(
      key:        'from_date',
      label:      'From Date *',
      prefixIcon: Icons.calendar_today_outlined,
      type:       ReportFilterType.datePicker,
      required:   true,
    ),
    ReportFilterField(
      key:        'to_date',
      label:      'To Date *',
      prefixIcon: Icons.event_outlined,
      type:       ReportFilterType.datePicker,
      required:   true,
    ),
    ReportFilterField(
      key:         'work_order',
      label:       'Work Order',
      prefixIcon:  Icons.assignment_outlined,
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Work Order',
    ),
    ReportFilterField(
      key:         'production_item',
      label:       'Production Item',
      prefixIcon:  Icons.category_outlined,
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Item',
    ),
    ReportFilterField(
      key: 'workstation',
      label: 'Workstation',
      type: ReportFilterType.doctypeLink,
      linkDoctype: 'Workstation',
    ),
  ];

  static const _sectionLabels = <String, String>{};

  // ── Filter chip builder ───────────────────────────────────────────────────
  // Direct copy of BomSearchScreen._buildFilterChips — same chip style,
  // same controller.activeFilters.forEach loop, same onDeleted callback.

  List<Widget> _buildFilterChips(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    Widget chip(String key, String label) => Chip(
      avatar: Icon(Icons.filter_alt_outlined,
          size: 14, color: cs.onSecondaryContainer),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSecondaryContainer,
            fontWeight: FontWeight.w600),
      ),
      backgroundColor: cs.secondaryContainer,
      deleteIconColor: cs.onSecondaryContainer,
      onDeleted: () => controller.clearFilter(key),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );

    controller.activeFilters.forEach((key, label) {
      chips.add(chip(key, label));
    });
    return chips;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Obx(() {
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header (title + filter chips + filter button) ─────────────
              DocTypeListHeader(
                title: 'Job Card Summary',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap: () => showReportFilterSheet(
                  context:       context,
                  title:         'Job Card Summary Filters',
                  fields:        _fields,
                  controllers:   controller.filterControllers,
                  onRun:         controller.runReport,
                  onClear:       controller.clearFilters,
                  sectionLabels: _sectionLabels,
                ),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters:  controller.clearFilters,
              ),

              // ── Loading ───────────────────────────────────────────────────
              if (controller.isLoading.value)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )

              // ── Empty state ───────────────────────────────────────────────
              else if (controller.reportData.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.summarize_outlined,
                              size: 64, color: cs.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No Job Cards found for the selected date range.\nAdjust filters and tap Run Report.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => showReportFilterSheet(
                              context:       context,
                              title:         'Job Card Summary Filters',
                              fields:        _fields,
                              controllers:   controller.filterControllers,
                              onRun:         controller.runReport,
                              onClear:       controller.clearFilters,
                              sectionLabels: _sectionLabels,
                            ),
                            icon:  const Icon(Icons.filter_alt_outlined),
                            label: const Text('Set Filters'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )

              // ── Chart ─────────────────────────────────────────────────────────────────
              else ...[
                  SliverToBoxAdapter(
                    child: _ProductionChart(
                      data: controller.dailyProductionData,
                    ),
                  ),

                  // ── Results ─────────────────────────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final row = controller.reportData[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _JobCardSummaryTile(row: row),
                          );
                        },
                        childCount: controller.reportData.length,
                      ),
                    ),
                  ),
                ],
            ],
          ),
        );
      }),
    );
  }
}

// ── Result tile ───────────────────────────────────────────────────────────────
//
// ERPNext Job Card Summary report row fields (from api.txt):
//   name               – Job Card ID  e.g. "JC-00001"
//   work_order         – linked Work Order
//   production_item    – Item Code
//   item_name          – Item display name
//   operation          – Operation name
//   workstation        – Workstation name
//   posting_date       – date string  "YYYY-MM-DD"
//   status             – "Open" | "Work In Progress" | "Completed"
//   total_completed_qty – double
//   total_time_in_mins  – double

class _JobCardSummaryTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _JobCardSummaryTile({required this.row});

  // Status → color mapping
  Color _statusColor(String status, ColorScheme cs) => switch (status) {
    'Completed'          => Colors.green.shade600,
    'Work In Progress'   => cs.primary,
    'Open'               => Colors.orange.shade700,
    _                    => cs.outline,
  };

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final name          = row['name']?.toString()               ?? '—';
    final workOrder     = row['work_order']?.toString()         ?? '—';
    final productionItem = row['production_item']?.toString()   ?? '';
    final itemName      = row['item_name']?.toString()          ?? '';
    final operation     = row['operation']?.toString()          ?? '';
    final workstation   = row['workstation']?.toString()        ?? '';
    final postingDate   = row['posting_date']?.toString()       ?? '';
    final status        = row['status']?.toString()             ?? '';
    final completedQty  = row['total_completed_qty'];
    final timeInMins    = row['total_time_in_mins'];

    final qtyText  = completedQty != null
        ? completedQty.toString()
        : '—';
    final timeText = timeInMins != null
        ? '${(timeInMins as num).toStringAsFixed(2)} min'
        : '—';

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Get.toNamed(
          AppRoutes.JOB_CARD_FORM,
          arguments: {'name': name},
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: icon + job card name + status chip ─────────────────
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.assignment_ind_outlined,
                        size: 20, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (status.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(status, cs).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _statusColor(status, cs),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // ── Row 2: Work Order + date ───────────────────────────────────
              Row(
                children: [
                  Icon(Icons.precision_manufacturing_outlined,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      workOrder,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  if (postingDate.isNotEmpty)
                    Text(
                      postingDate,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),

              // ── Row 3: Production item ────────────────────────────────────
              if (productionItem.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.category_outlined,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        itemName.isNotEmpty
                            ? '$productionItem · $itemName'
                            : productionItem,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // ── Row 4: Operation + Workstation ────────────────────────────
              if (operation.isNotEmpty || workstation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.build_outlined,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      [if (operation.isNotEmpty) operation,
                        if (workstation.isNotEmpty) workstation]
                          .join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // ── Row 5: Completed qty + time ───────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatBadge(
                    icon:  Icons.check_circle_outline_rounded,
                    label: 'Qty Completed',
                    value: qtyText,
                    color: Colors.green.shade600,
                  ),
                  _StatBadge(
                    icon:  Icons.timer_outlined,
                    label: 'Time',
                    value: timeText,
                    color: cs.primary,
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

// ── Small stat badge used in the tile footer ──────────────────────────────────

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Production chart
// ══════════════════════════════════════════════════════════════════════════════

class _ProductionChart extends StatefulWidget {
  final List<DailyProduction> data;
  const _ProductionChart({required this.data});

  @override
  State<_ProductionChart> createState() => _ProductionChartState();
}

class _ProductionChartState extends State<_ProductionChart> {
  bool _expanded = true;

  static const double _barWidth    = 22;
  static const double _groupGap    = 24;
  static const double _chartHeight = 130;
  static const double _labelArea   = 32;

  void _onTap(BuildContext context, DailyProduction d) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${d.date}  •  Completed: ${_fmt(d.completed)}'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _fmt(double v) => v == v.truncateToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final data = widget.data;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'Completed Qty by Day',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (data.isNotEmpty && _expanded) ...[
                _LegendDot(color: cs.primary, label: 'Completed'),
                const SizedBox(width: 6),
              ],
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
          // Chart body
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: data.isEmpty
                ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No date data available',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            )
                : _ChartBody(
              data:           data,
              barWidth:       _barWidth,
              groupGap:       _groupGap,
              chartHeight:    _chartHeight,
              labelArea:      _labelArea,
              colorBar:       cs.primary,
              colorGrid:      cs.outlineVariant.withValues(alpha: 0.3),
              colorLabel:     cs.onSurfaceVariant,
              onTap: (d) => _onTap(context, d),
            ),
            secondChild: const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }
}

// ── Scrollable bar body ───────────────────────────────────────────────────────

class _ChartBody extends StatelessWidget {
  final List<DailyProduction> data;
  final double barWidth, groupGap, chartHeight, labelArea;
  final Color  colorBar, colorGrid, colorLabel;
  final void Function(DailyProduction) onTap;

  const _ChartBody({
    required this.data,
    required this.barWidth,
    required this.groupGap,
    required this.chartHeight,
    required this.labelArea,
    required this.colorBar,
    required this.colorGrid,
    required this.colorLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal     = data.fold<double>(0, (m, d) => d.completed > m ? d.completed : m);
    final totalWidth = data.length * (barWidth + groupGap);

    return SizedBox(
      height: chartHeight + labelArea,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: GestureDetector(
          onTapUp: (details) {
            final idx = (details.localPosition.dx / (barWidth + groupGap)).floor();
            if (idx >= 0 && idx < data.length) onTap(data[idx]);
          },
          child: CustomPaint(
            size: Size(totalWidth, chartHeight + labelArea),
            painter: _BarPainter(
              data:        data,
              maxVal:      maxVal == 0 ? 1 : maxVal,
              barWidth:    barWidth,
              groupGap:    groupGap,
              chartHeight: chartHeight,
              labelArea:   labelArea,
              colorBar:    colorBar,
              colorGrid:   colorGrid,
              colorLabel:  colorLabel,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _BarPainter extends CustomPainter {
  final List<DailyProduction> data;
  final double maxVal, barWidth, groupGap, chartHeight, labelArea;
  final Color  colorBar, colorGrid, colorLabel;

  _BarPainter({
    required this.data,
    required this.maxVal,
    required this.barWidth,
    required this.groupGap,
    required this.chartHeight,
    required this.labelArea,
    required this.colorBar,
    required this.colorGrid,
    required this.colorLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintBar  = Paint()..color = colorBar.withValues(alpha: 0.85);
    final paintGrid = Paint()
      ..color       = colorGrid
      ..strokeWidth = 0.5;

    // Grid lines at 0 %, 50 %, 100 %
    for (final pct in [0.0, 0.5, 1.0]) {
      final y = chartHeight - chartHeight * pct;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < data.length; i++) {
      final d     = data[i];
      final xBase = i * (barWidth + groupGap);
      final barH  = (d.completed / maxVal) * chartHeight;

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(xBase, chartHeight - barH, barWidth, barH),
          topLeft:  const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        paintBar,
      );

      // Date label
      String label = d.date;
      try {
        final parts = d.date.split('-');
        if (parts.length == 3) {
          final dt   = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          const mons = ['Jan','Feb','Mar','Apr','May','Jun',
            'Jul','Aug','Sep','Oct','Nov','Dec'];
          label = '${mons[dt.month - 1]} ${dt.day}';
        }
      } catch (_) {}

      tp.text = TextSpan(
        text: label,
        style: TextStyle(color: colorLabel, fontSize: 9),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(xBase + (barWidth - tp.width) / 2, chartHeight + 6),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.data != data || old.maxVal != maxVal;
}

// ── Legend dot ────────────────────────────────────────────────────────────────

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
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
