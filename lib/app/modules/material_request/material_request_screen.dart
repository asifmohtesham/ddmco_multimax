import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/modules/material_request/widgets/material_request_filter_bottom_sheet.dart';

class MaterialRequestScreen extends StatefulWidget {
  const MaterialRequestScreen({super.key});

  @override
  State<MaterialRequestScreen> createState() => _MaterialRequestScreenState();
}

class _MaterialRequestScreenState extends State<MaterialRequestScreen> {
  final MaterialRequestController controller = Get.find();
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
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    if (current >= maxScroll * 0.9 &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchMaterialRequests(isLoadMore: true);
    }
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MaterialRequestFilterBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchMaterialRequests(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── AppBar (no actions — identical to Stock Entry) ────────────────
            const SliverAppBar.large(
              title: Text('Material Requests'),
            ),

            // ── Search Bar + Filter suffix ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                // Identical padding to Stock Entry
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search ID, Type, Warehouse...',
                    // Identical to Stock Entry
                    prefixIcon: Icon(
                      Icons.search,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    // Filter button as suffixIcon inside the pill field
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.filter_list,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Sort & Filter',
                      onPressed: () => _showFilterSheet(context),
                    ),
                    // Identical styling to Stock Entry
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                  ),
                ),
              ),
            ),

            // ── Active filter / search chips ───────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                final hasFilters = controller.activeFilters.isNotEmpty;
                final hasSearch = controller.searchQuery.value.isNotEmpty;
                if (!hasFilters && !hasSearch) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (hasSearch)
                        Chip(
                          label: Text(
                              'Search: ${controller.searchQuery.value}'),
                          avatar: const Icon(Icons.search, size: 18),
                          onDeleted: () {
                            controller.searchQuery.value = '';
                            controller.fetchMaterialRequests(clear: true);
                          },
                        ),
                      if (hasFilters)
                        Chip(
                          label: Text(
                              '${controller.activeFilters.length} filter${controller.activeFilters.length > 1 ? 's' : ''} applied'),
                          avatar: const Icon(Icons.filter_alt, size: 18),
                          onDeleted: controller.clearFilters,
                        ),
                    ],
                  ),
                );
              }),
            ),

            // ── List body ─────────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.materialRequests.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.materialRequests.isEmpty) {
                final hasFiltersOrSearch =
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
                            hasFiltersOrSearch
                                ? Icons.filter_alt_off_outlined
                                : Icons.assignment_outlined,
                            size: 64,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFiltersOrSearch
                                ? 'No Matching Requests'
                                : 'No Material Requests',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasFiltersOrSearch
                                ? 'Try adjusting your filters or search query.'
                                : 'Pull to refresh or create a new request.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          if (hasFiltersOrSearch)
                            FilledButton.tonalIcon(
                              onPressed: controller.clearFilters,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear Filters'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: () => controller
                                  .fetchMaterialRequests(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final requests = controller.materialRequests;
              final showLoader = controller.hasMore.value;
              final baseCount = requests.length;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= baseCount) {
                      if (showLoader) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(
                          child: Text(
                            'End of results',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    final req = requests[index];

                    return Obx(() {
                      final isExpanded =
                          controller.expandedRequestId.value == req.name;
                      final isLoadingDetails =
                          controller.isLoadingDetails.value &&
                          controller.detailedRequest?.name != req.name;

                      return GenericDocumentCard(
                        title: req.materialRequestType,
                        subtitle: req.name,
                        status: req.status,
                        stats: [
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.assignment_outlined,
                            req.materialRequestType,
                          ),
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.access_time,
                            FormattingHelper.getRelativeTime(
                                req.transactionDate),
                          ),
                          if (req.scheduleDate.isNotEmpty)
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.event_outlined,
                              'Due ${FormattingHelper.getRelativeTime(req.scheduleDate)}',
                            ),
                        ],
                        isExpanded: isExpanded,
                        isLoadingDetails: isLoadingDetails && isExpanded,
                        onTap: () => controller.toggleExpand(req.name),
                        expandedContent: isExpanded
                            ? _buildExpandedContent(context, req.name)
                            : null,
                      );
                    });
                  },
                  childCount: baseCount + 1,
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: Obx(() => RoleGuard(
            roles: controller.writeRoles.toList(),
            child: FloatingActionButton.extended(
              onPressed: controller.openCreateForm,
              icon: const Icon(Icons.add),
              label: const Text('Create'),
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              elevation: 4,
            ),
          )),
    );
  }

  // ── Expanded card detail ──────────────────────────────────────────────
  Widget _buildExpandedContent(BuildContext context, String reqName) {
    return Obx(() {
      final detailed = controller.detailedRequest;
      if (detailed == null || detailed.name != reqName) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detailed.setWarehouse != null &&
              detailed.setWarehouse!.isNotEmpty) ...[
            InfoBlock(
              label: 'Target Warehouse',
              value: detailed.setWarehouse!,
              icon: Icons.warehouse_outlined,
            ),
            const SizedBox(height: 12),
          ],

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InfoBlock(
                  label: 'Transaction Date',
                  value: detailed.transactionDate,
                  icon: Icons.calendar_today_outlined,
                  backgroundColor: colorScheme.surfaceContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InfoBlock(
                  label: 'Required By',
                  value: detailed.scheduleDate.isNotEmpty
                      ? detailed.scheduleDate
                      : '—',
                  icon: Icons.event_outlined,
                  backgroundColor:
                      colorScheme.primaryContainer.withValues(alpha: 0.3),
                  valueColor: colorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (detailed.items.isNotEmpty)
            InfoBlock(
              label: 'Items',
              icon: Icons.inventory_2_outlined,
              child: _buildItemsSummary(context, detailed),
            ),

          const SizedBox(height: 16),

          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline,
                    size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detailed.owner ?? '—',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  FormattingHelper.getRelativeTime(detailed.modified),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.docstatus == 0) ...[
                RoleGuard(
                  roles: controller.writeRoles.toList(),
                  child: IconButton.filled(
                    onPressed: () =>
                        controller.deleteMaterialRequest(detailed.name),
                    icon: const Icon(Icons.delete_outline),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                    ),
                    tooltip: 'Delete',
                  ),
                ),
                const SizedBox(width: 8),
                RoleGuard(
                  roles: controller.writeRoles.toList(),
                  fallback: FilledButton.tonalIcon(
                    onPressed: () => Get.toNamed(
                        AppRoutes.MATERIAL_REQUEST_FORM,
                        arguments: {
                          'name': detailed.name,
                          'mode': 'view',
                        }),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                  ),
                  child: FilledButton.tonalIcon(
                    onPressed: () => Get.toNamed(
                        AppRoutes.MATERIAL_REQUEST_FORM,
                        arguments: {
                          'name': detailed.name,
                          'mode': 'edit',
                        }),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(
                      AppRoutes.MATERIAL_REQUEST_FORM,
                      arguments: {
                        'name': detailed.name,
                        'mode': 'view',
                      }),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View Details'),
                ),
              ],
            ],
          ),
        ],
      );
    });
  }

  Widget _buildItemsSummary(
      BuildContext context, MaterialRequest detailed) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalQty = detailed.items.fold(0.0, (sum, i) => sum + i.qty);
    final fulfilledCount =
        detailed.items.where((i) => i.orderedQty >= i.qty).length;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          _buildMiniStat(context, '${detailed.items.length}', 'Lines'),
          const SizedBox(width: 16),
          _buildMiniStat(
              context, totalQty.toStringAsFixed(0), 'Total Qty'),
          const SizedBox(width: 16),
          _buildMiniStat(context, '$fulfilledCount', 'Ordered',
              color: fulfilledCount == detailed.items.length
                  ? Colors.green
                  : colorScheme.primary),
        ],
      ),
    );
  }

  Widget _buildMiniStat(BuildContext context, String value, String label,
      {Color? color}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
