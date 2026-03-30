import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

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
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.zero,
        child: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 0,
          elevation: 0,
        ),
      ),
      body: AppShellScaffold(
        body: RefreshIndicator(
          onRefresh: () => controller.fetchJobCards(clear: true),
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Unified header ─────────────────────────────────────────────
              DocTypeListHeader(
                title: 'Job Cards',
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

              // ── KPI strip + list ──────────────────────────────────────────
              Obx(() {
                // ─ loading splash ────────────────────────────────
                if (controller.isLoading.value &&
                    controller.jobCards.isEmpty) {
                  return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()));
                }

                // ─ empty state ──────────────────────────────────
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
                              label: Text(hasFilters
                                  ? 'Clear Filters'
                                  : 'Reload'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // ─ KPI strip + list ─────────────────────────────────
                final cards = controller.jobCards;
                return SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _JobCardKpiStrip(controller: controller),
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
                                        child: CircularProgressIndicator()))
                                  : const SizedBox(height: 80);
                            }
                            final jc = cards[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _JobCardTile(
                                jc: jc,
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

// ── Filter bottom sheet ───────────────────────────────────────────────────

class _JobCardFilterSheet extends StatelessWidget {
  final JobCardController controller;
  const _JobCardFilterSheet({required this.controller});

  // Added 'Submitted' to the filter list so users can filter by docstatus==1
  // cards whose ERPNext status may still show 'Completed' or 'Open'.
  static const List<String> _statuses = [
    'Open',
    'Work In Progress',
    'Material Transferred',
    'Completed',
    'On Hold',
    'Cancelled',
  ];

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter by Status',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: () {
                    controller.removeFilter('status');
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() {
              final active =
                  controller.activeFilters['status'] as String?;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _statuses.map((s) {
                  final selected = active == s;
                  return ChoiceChip(
                    label: Text(s),
                    selected: selected,
                    onSelected: (_) {
                      controller.setFilter(
                          'status', selected ? null : s);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── KPI strip ────────────────────────────────────────────────────────

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
  final Color color;
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

// ── Job Card tile ──────────────────────────────────────────────────────

class _JobCardTile extends StatelessWidget {
  final JobCard jc;
  final VoidCallback onTap;
  const _JobCardTile({required this.jc, required this.onTap});

  // ── Single status→color helper used by both the icon bg and progress bar.
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

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final theme   = Theme.of(context);
    final clr     = _statusColor(context);
    final hasProgress = jc.forQuantity > 0;

    return Material(
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
                  // ── Status icon badge ──
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: clr.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.build_outlined, color: clr, size: 22),
                  ),
                  const SizedBox(width: 12),

                  // ── Operation + workstation + status pill ──
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jc.operation,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${jc.workstation ?? 'Unassigned'} • '
                          '${_fmtQty(jc.totalCompletedQty)}/'
                          '${_fmtQty(jc.forQuantity)} units',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 5),
                        StatusPill(status: jc.status),
                      ],
                    ),
                  ),

                  // ── Action / state badge (right-side) ──
                  const SizedBox(width: 8),
                  _ActionBadge(jc: jc),
                ],
              ),

              // ── Progress bar — only when forQuantity > 0 ─────────────
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
    );
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(1);
}

/// Right-side badge on each tile showing the actionable state.
///
/// Priority (high → low):
///   1. docstatus == 1  → 'SUBMITTED' (tertiaryContainer tint)
///   2. Work In Progress → 'IN PROGRESS' pill (primaryContainer tint)
///   3. Open            → 'START' CTA  (primary filled)
///   4. anything else   → empty SizedBox
class _ActionBadge extends StatelessWidget {
  final JobCard jc;
  const _ActionBadge({required this.jc});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (jc.docstatus == 1) {
      return _badge(
        context,
        label: 'SUBMITTED',
        bg:    cs.tertiaryContainer,
        fg:    cs.onTertiaryContainer,
        theme: theme,
      );
    }

    if (jc.isWorkInProgress) {
      return _badge(
        context,
        label: 'IN PROGRESS',
        bg:    cs.primaryContainer,
        fg:    cs.onPrimaryContainer,
        theme: theme,
      );
    }

    if (jc.isOpen) {
      return _badge(
        context,
        label: 'START',
        bg:    cs.primary,
        fg:    cs.onPrimary,
        theme: theme,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _badge(
    BuildContext context, {
    required String label,
    required Color bg,
    required Color fg,
    required ThemeData theme,
  }) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );
}
