import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

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

  void _showFilterSheet() {
    // TODO: replace with JobCardFilterBottomSheet when created
    Get.snackbar('Filters', 'Filter sheet coming soon',
        duration: const Duration(seconds: 2));
  }

  // ── Per-key filter chips ────────────────────────────────────────────────────

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final filters = controller.activeFilters;

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(_chip(
        context,
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchJobCards(clear: true);
        },
      ));
    }

    if (filters.containsKey('status')) {
      chips.add(_chip(
        context,
        icon: Icons.flag_outlined,
        label: 'Status: ${filters['status']}',
        onDeleted: () => controller.removeFilter('status'),
      ));
    }

    if (filters.containsKey('operation')) {
      chips.add(_chip(
        context,
        icon: Icons.build_outlined,
        label: 'Operation: ${filters['operation']}',
        onDeleted: () => controller.removeFilter('operation'),
      ));
    }

    if (filters.containsKey('workstation')) {
      chips.add(_chip(
        context,
        icon: Icons.precision_manufacturing_outlined,
        label: 'Workstation: ${filters['workstation']}',
        onDeleted: () => controller.removeFilter('workstation'),
      ));
    }

    if (filters.containsKey('work_order')) {
      chips.add(_chip(
        context,
        icon: Icons.receipt_long_outlined,
        label: 'Work Order: ${filters['work_order']}',
        onDeleted: () => controller.removeFilter('work_order'),
      ));
    }

    return chips;
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onDeleted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
      backgroundColor: colorScheme.secondaryContainer,
      deleteIconColor: colorScheme.onSecondaryContainer,
      onDeleted: onDeleted,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchJobCards(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header: AppBar + search + filter chips ──────────
            DocTypeListHeader(
              title: 'Job Cards',
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchJobCards(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── Shop floor stats strip ──────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.jobCards.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _buildShopFloorStats(context);
              }),
            ),

            // ── List content ────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.jobCards.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.jobCards.isEmpty) {
                final hasFilters =
                    controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            hasFilters
                                ? Icons.filter_alt_off_outlined
                                : Icons.build_circle_outlined,
                            size: 64,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching Job Cards'
                                : 'No Job Cards Found',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 24),
                          if (hasFilters)
                            FilledButton.tonalIcon(
                              onPressed: controller.clearFilters,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear Filters'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  controller.fetchJobCards(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final baseCount = controller.jobCards.length;
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= baseCount) {
                        return controller.hasMore.value
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : const SizedBox(height: 24);
                      }
                      final jc = controller.jobCards[index];
                      final bool isOpen = jc.status == 'Open' ||
                          jc.status == 'Work In Progress';
                      final color =
                          _statusColor(jc.status, colorScheme);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: colorScheme.surfaceContainerLowest,
                          elevation: isOpen ? 1 : 0,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () {},
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    height: 50,
                                    width: 50,
                                    decoration: BoxDecoration(
                                      color:
                                          color.withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.build,
                                        color: color),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          jc.operation,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${jc.workstation ?? "Unassigned"} • ${jc.totalCompletedQty.toInt()}/${jc.forQuantity.toInt()} units',
                                          style: TextStyle(
                                              color: colorScheme
                                                  .onSurfaceVariant,
                                              fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isOpen)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'START',
                                        style: TextStyle(
                                          color: colorScheme.onPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: baseCount + 1,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildShopFloorStats(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(
              context, 'Pending', '${controller.openCards}', Colors.orange),
          _statItem(context, 'Completed',
              '${controller.completedCards}', Colors.green),
          _statItem(context, 'Total', '${controller.totalCards}',
              colorScheme.primary),
        ],
      ),
    );
  }

  Widget _statItem(
      BuildContext context, String label, String val, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(val,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: color)),
        ],
      ),
    );
  }

  Color _statusColor(String status, ColorScheme colorScheme) {
    switch (status) {
      case 'Open':
        return Colors.orange;
      case 'Work In Progress':
        return colorScheme.primary;
      case 'Completed':
        return Colors.green;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }
}
