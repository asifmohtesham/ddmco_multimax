import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
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
      backgroundColor: cs.surfaceContainerLow,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchJobCards(clear: true),
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header ──────────────────────────────────────────────
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
            ),

            // ── KPI strip ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() => _JobCardKpiStrip(
                  controller: controller)),
            ),

            // ── List content ──────────────────────────────────────────────
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

              final cards = controller.jobCards;
              return SliverPadding(
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
                          onTap: () {},
                        ),
                      );
                    },
                    childCount: cards.length + 1,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── KPI strip ───────────────────────────────────────────────────────────────────────

class _JobCardKpiStrip extends StatelessWidget {
  final JobCardController controller;
  const _JobCardKpiStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (controller.jobCards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _Kpi('Pending',  '${controller.openCards}',      cs.secondary),
          const SizedBox(width: 8),
          _Kpi('Completed','${controller.completedCards}', cs.tertiary),
          const SizedBox(width: 8),
          _Kpi('Total',    '${controller.totalCards}',     cs.primary),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Job Card tile ─────────────────────────────────────────────────────────────────

class _JobCardTile extends StatelessWidget {
  final dynamic jc;   // JobCard model
  final VoidCallback onTap;
  const _JobCardTile({required this.jc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final bool isOpen =
        jc.status == 'Open' || jc.status == 'Work In Progress';

    return Material(
      color: cs.surface,
      elevation: isOpen ? 2 : 0,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: _statusColor(context, jc.status)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.build,
                    color: _statusColor(context, jc.status)),
              ),
              const SizedBox(width: 16),
              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jc.operation,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${jc.workstation ?? 'Unassigned'} • '
                      '${jc.totalCompletedQty.toInt()}/${jc.forQuantity.toInt()} units',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    StatusPill(status: jc.status),
                  ],
                ),
              ),
              // START badge
              if (isOpen)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'START',
                    style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'Open':             return scheme.secondary;
      case 'Work In Progress': return scheme.primary;
      case 'Completed':        return scheme.tertiary;
      default:                 return scheme.onSurfaceVariant;
    }
  }
}
