import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

class BomScreen extends StatefulWidget {
  const BomScreen({super.key});

  @override
  State<BomScreen> createState() => _BomScreenState();
}

class _BomScreenState extends State<BomScreen> {
  final BomController controller = Get.find();
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
      controller.fetchBOMs(isLoadMore: true);
    }
  }

  void _showFilterSheet() {
    // TODO: replace with BomFilterBottomSheet when created
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
          controller.fetchBOMs(clear: true);
        },
      ));
    }

    if (filters.containsKey('item')) {
      chips.add(_chip(
        context,
        icon: Icons.inventory_2_outlined,
        label: 'Item: ${filters['item']}',
        onDeleted: () => controller.removeFilter('item'),
      ));
    }

    if (filters.containsKey('is_active')) {
      final val = filters['is_active'];
      chips.add(_chip(
        context,
        icon: Icons.toggle_on_outlined,
        label: val == 1 ? 'Active Only' : 'Inactive Only',
        onDeleted: () => controller.removeFilter('is_active'),
      ));
    }

    if (filters.containsKey('currency')) {
      chips.add(_chip(
        context,
        icon: Icons.attach_money,
        label: 'Currency: ${filters['currency']}',
        onDeleted: () => controller.removeFilter('currency'),
      ));
    }

    if (filters.containsKey('project')) {
      chips.add(_chip(
        context,
        icon: Icons.folder_outlined,
        label: 'Project: ${filters['project']}',
        onDeleted: () => controller.removeFilter('project'),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchBOMs(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header: AppBar + search + filter chips ──────────
            DocTypeListHeader(
              title: 'Bill of Materials',
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchBOMs(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── KPI summary strip ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value && controller.boms.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _buildHeaderSummary(context);
              }),
            ),

            // ── List content ────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value && controller.boms.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.boms.isEmpty) {
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
                                : Icons.layers_outlined,
                            size: 64,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching BOMs'
                                : 'No BOMs Found',
                            style: theme.textTheme.titleMedium?.copyWith(
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
                                  controller.fetchBOMs(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final baseCount = controller.boms.length;
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                      final bom = controller.boms[index];
                      final bool isActive = bom.isActive == 1;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {},
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isActive
                                      ? colorScheme.primary
                                          .withValues(alpha: 0.25)
                                      : colorScheme.outlineVariant,
                                ),
                              ),
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: isActive
                                      ? colorScheme.primaryContainer
                                      : colorScheme
                                          .surfaceContainerHighest,
                                  child: Icon(
                                    Icons.layers,
                                    color: isActive
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                title: Text(
                                  bom.itemName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                subtitle: Text(
                                  bom.name,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant),
                                ),
                                trailing: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${FormattingHelper.getCurrencySymbol(bom.currency)} ${NumberFormat("#,##0").format(bom.totalCost)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? colorScheme.primaryContainer
                                                .withValues(alpha: 0.5)
                                            : colorScheme
                                                .surfaceContainerHighest,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isActive ? 'Active' : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isActive
                                              ? colorScheme
                                                  .onPrimaryContainer
                                              : colorScheme
                                                  .onSurfaceVariant,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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

  Widget _buildHeaderSummary(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _kpi(context, 'Total BOMs', '${controller.totalBoms}',
              colorScheme.primary),
          _kpi(context, 'Active',
              '${(controller.activeRate * 100).toInt()}%', Colors.green),
          _kpi(
            context,
            'Avg Cost',
            NumberFormat.compactSimpleCurrency()
                .format(controller.averageCost),
            Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _kpi(
      BuildContext context, String label, String value, Color color) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
