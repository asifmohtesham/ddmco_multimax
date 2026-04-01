import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/work_order/work_order_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class WorkOrderScreen extends StatefulWidget {
  const WorkOrderScreen({super.key});

  @override
  State<WorkOrderScreen> createState() => _WorkOrderScreenState();
}

class _WorkOrderScreenState extends State<WorkOrderScreen> {
  final WorkOrderController controller = Get.find();
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
      controller.fetchWorkOrders(isLoadMore: true);
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
          controller.fetchWorkOrders(clear: true);
        },
      ));
    }
    if (controller.activeFilters.containsKey('status')) {
      final statusVal = controller.activeFilters['status'];
      chips.add(chip(
        icon: Icons.flag_outlined,
        label: 'Status: $statusVal',
        onDeleted: () => controller.removeFilter('status'),
      ));
    }
    if (controller.activeFilters.containsKey('production_item')) {
      chips.add(chip(
        icon: Icons.inventory_2_outlined,
        label: 'Item: ${controller.activeFilters['production_item']}',
        onDeleted: () => controller.removeFilter('production_item'),
      ));
    }
    if (controller.activeFilters.containsKey('owner')) {
      chips.add(chip(
        icon: Icons.person_outline,
        label: 'Owner: ${controller.activeFilters['owner']}',
        onDeleted: () => controller.removeFilter('owner'),
      ));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Use injected page title (from dashboard args) or fall back to default
    final screenTitle = controller.pageTitle ?? 'Work Orders';

    return AppShellScaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(
          AppRoutes.WORK_ORDER_FORM,
          arguments: {'name': '', 'mode': 'new'},
        ),
        tooltip: 'New Work Order',
        icon: const Icon(Icons.add),
        label: const Text('New Work Order'),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchWorkOrders(clear: true),
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header ─────────────────────────────────────────
            DocTypeListHeader(
              title: screenTitle,
              automaticallyImplyLeading: false,
              searchDoctype:      'Work Order',
              searchQuery:        controller.searchQuery,
              onSearchChanged:    controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchWorkOrders(clear: true);
              },
              activeFilters:      controller.activeFilters,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters:  controller.clearFilters,
              onFilterTap:        () => _showFilterSheet(context),
            ),

            // ── List content ─────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.workOrders.isEmpty) {
                return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()));
              }

              if (controller.workOrders.isEmpty) {
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
                                : Icons.precision_manufacturing_outlined,
                            size: 64,
                            color: cs.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching Work Orders'
                                : 'No Active Orders',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasFilters
                                ? 'Try clearing the active filter to see all Work Orders.'
                                : 'No Work Orders found. Tap "+ New Work Order" to create one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 13),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: hasFilters
                                ? controller.clearFilters
                                : () => controller.fetchWorkOrders(
                                    clear: true),
                            icon: Icon(hasFilters
                                ? Icons.filter_alt_off
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

              final baseCount = controller.workOrders.length;
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= baseCount) {
                        return controller.hasMore.value
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator()))
                            : const SizedBox(height: 80);
                      }
                      final wo = controller.workOrders[index];
                      final double pct = (wo.qty > 0)
                          ? (wo.producedQty / wo.qty).clamp(0.0, 1.0)
                          : 0.0;
                      final bool done = wo.status == 'Completed';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Get.toNamed(
                            AppRoutes.WORK_ORDER_FORM,
                            arguments: {
                              'name': wo.name,
                              'mode': 'view',
                            },
                          ),
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                  color: cs.outlineVariant),
                            ),
                            color: cs.surfaceContainerLowest,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .spaceBetween,
                                    children: [
                                      StatusPill(status: wo.status),
                                      Text(wo.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                  color: cs
                                                      .onSurfaceVariant)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    wo.itemName,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  if (wo.bomNo.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'BOM: ${wo.bomNo}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                                color:
                                                    cs.onSurfaceVariant),
                                      ),
                                    ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('Produced',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                        color: cs
                                                            .onSurfaceVariant)),
                                            const SizedBox(height: 4),
                                            RichText(
                                              text:
                                                  TextSpan(children: [
                                                TextSpan(
                                                  text:
                                                      '${wo.producedQty.toInt()}',
                                                  style: TextStyle(
                                                      color: cs.primary,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold,
                                                      fontSize: 16),
                                                ),
                                                TextSpan(
                                                  text:
                                                      ' / ${wo.qty.toInt()}',
                                                  style: TextStyle(
                                                      color: cs
                                                          .onSurfaceVariant,
                                                      fontSize: 14),
                                                ),
                                              ]),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!done)
                                        CircularProgressIndicator(
                                          value: pct,
                                          backgroundColor:
                                              cs.surfaceContainerHighest,
                                          color: cs.primary,
                                          strokeWidth: 4,
                                        ),
                                      if (done)
                                        const Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 32),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 6,
                                      backgroundColor:
                                          cs.surfaceContainerHighest,
                                      color: done
                                          ? Colors.green
                                          : cs.primary,
                                    ),
                                  ),
                                  if (wo.plannedStartDate.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: [
                                          Icon(
                                              Icons
                                                  .calendar_today_outlined,
                                              size: 12,
                                              color:
                                                  cs.onSurfaceVariant),
                                          const SizedBox(width: 4),
                                          Text(
                                            wo.plannedStartDate,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: cs
                                                        .onSurfaceVariant),
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

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _WorkOrderFilterSheet(controller: controller),
    );
  }
}

// ── Filter bottom sheet ────────────────────────────────────────────────────────

class _WorkOrderFilterSheet extends StatelessWidget {
  final WorkOrderController controller;
  const _WorkOrderFilterSheet({required this.controller});

  static const List<String> _statuses = [
    'Not Started',
    'In Process',
    'Completed',
    'Stopped',
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
                  'Filter Work Orders',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: () {
                    controller.clearFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
