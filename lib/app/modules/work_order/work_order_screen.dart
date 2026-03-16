import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/work_order/work_order_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
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

  void _showFilterSheet() {
    Get.snackbar('Filters', 'Filter sheet coming soon',
        duration: const Duration(seconds: 2));
  }

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
          controller.fetchWorkOrders(clear: true);
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
    if (filters.containsKey('production_item')) {
      chips.add(_chip(
        context,
        icon: Icons.inventory_2_outlined,
        label: 'Item: ${filters['production_item']}',
        onDeleted: () => controller.removeFilter('production_item'),
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
    final cs = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: cs.onSecondaryContainer),
      label: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
      backgroundColor: cs.secondaryContainer,
      deleteIconColor: cs.onSecondaryContainer,
      onDeleted: onDeleted,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      drawer: const AppNavDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(
          AppRoutes.WORK_ORDER_FORM,
          arguments: {'name': '', 'mode': 'new'},
        ),
        label: const Text('New Order'),
        icon: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchWorkOrders(clear: true),
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            DocTypeListHeader(
              title: 'Work Orders',
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchWorkOrders(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),
            Obx(() {
              if (controller.isLoading.value &&
                  controller.workOrders.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.workOrders.isEmpty) {
                final hasFilters = controller.activeFilters.isNotEmpty ||
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
                                  controller.fetchWorkOrders(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
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
                                  child: CircularProgressIndicator(),
                                ))
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
                              side: BorderSide(color: cs.outlineVariant),
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
                                        MainAxisAlignment.spaceBetween,
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
                                                color: cs.onSurfaceVariant),
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
                                              text: TextSpan(children: [
                                                TextSpan(
                                                  text:
                                                      '${wo.producedQty.toInt()}',
                                                  style: TextStyle(
                                                      color: cs.primary,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                        const Icon(Icons.check_circle,
                                            color: Colors.green, size: 32),
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
                                              color: cs.onSurfaceVariant),
                                          const SizedBox(width: 4),
                                          Text(
                                            wo.plannedStartDate,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color:
                                                        cs.onSurfaceVariant),
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
}
