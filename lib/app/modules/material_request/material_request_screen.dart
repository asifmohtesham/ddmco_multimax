import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/modules/material_request/widgets/material_request_filter_bottom_sheet.dart';

class MaterialRequestScreen extends StatefulWidget {
  const MaterialRequestScreen({super.key});

  @override
  State<MaterialRequestScreen> createState() => _MaterialRequestScreenState();
}

/// [_MaterialRequestScreenState] uses [StatefulWidget] solely to own the
/// [ScrollController] lifecycle (attach/detach listeners, dispose).
/// ALL reactive state is held in [MaterialRequestController] observables and
/// consumed via [Obx] — no [setState] is ever called.
class _MaterialRequestScreenState extends State<MaterialRequestScreen> {
  final MaterialRequestController controller = Get.find();
  final _scrollController = ScrollController();

  /// Tracks whether the user has scrolled far enough to collapse the FAB.
  final _isFarFromTop = false.obs;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Scroll handling
  // ---------------------------------------------------------------------------

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current   = _scrollController.offset;

    if (current >= maxScroll * 0.9 &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchMaterialRequests(isLoadMore: true);
    }

    final far = current > 80;
    if (_isFarFromTop.value != far) _isFarFromTop.value = far;
  }

  // ---------------------------------------------------------------------------
  // Filter sheet
  // ---------------------------------------------------------------------------

  void _showFilterSheet(BuildContext context) {
    Get.bottomSheet(
      const MaterialRequestFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ---------------------------------------------------------------------------
  // Active filter chips
  // ---------------------------------------------------------------------------

  List<Widget> _buildActiveFilterChips(BuildContext context) {
    final chips   = <Widget>[];
    final filters = controller.activeFilters;

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(_filterChip(
        context,
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchMaterialRequests(clear: true);
        },
      ));
    }

    if (filters.containsKey('status')) {
      chips.add(_filterChip(
        context,
        icon: Icons.flag_outlined,
        label: 'Status: ${filters['status']}',
        onDeleted: () => controller.removeFilter('status'),
      ));
    }

    if (filters.containsKey('material_request_type')) {
      chips.add(_filterChip(
        context,
        icon: Icons.category_outlined,
        label: 'Type: ${filters['material_request_type']}',
        onDeleted: () => controller.removeFilter('material_request_type'),
      ));
    }

    if (filters.containsKey('set_warehouse')) {
      chips.add(_filterChip(
        context,
        icon: Icons.warehouse_outlined,
        label: 'Warehouse: ${filters['set_warehouse']}',
        onDeleted: () => controller.removeFilter('set_warehouse'),
      ));
    }

    if (filters.containsKey('owner') &&
        filters['owner'].toString().isNotEmpty) {
      chips.add(_filterChip(
        context,
        icon: Icons.person_outline,
        label: 'Created By: ${filters['owner']}',
        onDeleted: () => controller.removeFilter('owner'),
      ));
    }

    if (filters.containsKey('transaction_date')) {
      final f = filters['transaction_date'];
      if (f is List &&
          f.length >= 2 &&
          f[0] == 'between' &&
          f[1] is List &&
          (f[1] as List).length >= 2) {
        final dates = f[1] as List;
        chips.add(_filterChip(
          context,
          icon: Icons.date_range,
          label: '${dates[0]}  →  ${dates[1]}',
          onDeleted: () => controller.removeFilter('transaction_date'),
        ));
      }
    }

    return chips;
  }

  Widget _filterChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onDeleted,
  }) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list screen.
    return FilterChipWidget(icon: icon, label: label, onDeleted: onDeleted);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final colorScheme  = theme.colorScheme;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: Obx(() => RoleGuard(
            roles: controller.writeRoles.toList(),
            child: _isFarFromTop.value
                ? FloatingActionButton(
                    onPressed: controller.openCreateForm,
                    tooltip: 'New Material Request',
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    elevation: 4,
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                    onPressed: controller.openCreateForm,
                    tooltip: 'New Material Request',
                    icon: const Icon(Icons.add),
                    label: const Text('New Material Request'),
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    elevation: 4,
                  ),
          )),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchMaterialRequests(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── AppBar + search/filter icons + active-filter chip row ─────────
            DocTypeListHeader(
              title: 'Material Request',
              automaticallyImplyLeading: false,
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchMaterialRequests(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: () => _showFilterSheet(context),
              filterChipsBuilder: _buildActiveFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── Result count pill ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.materialRequests.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ResultCountPill(
                  count: controller.materialRequests.length,
                  hasMore: controller.hasMore.value,
                  hasActiveFilters: controller.activeFilters.isNotEmpty ||
                      controller.searchQuery.value.isNotEmpty,
                  noun: 'request',
                  icon: Icons.assignment_outlined,
                );
              }),
            ),

            // ── List content ────────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.materialRequests.isEmpty) {
                return const SliverToBoxAdapter(child: DocCardSkeletonList());
              }

              if (controller.materialRequests.isEmpty) {
                final hasFiltersOrSearch =
                    controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ListEmptyState(
                    hasActiveFilters: hasFiltersOrSearch,
                    emptyIcon: Icons.assignment_outlined,
                    emptyTitle: 'No Material Requests',
                    emptyMessage: 'Pull to refresh or create a new request.',
                    filteredTitle: 'No Matching Requests',
                    filteredMessage:
                        'Try adjusting your filters or search query.',
                    onClearFilters: controller.clearFilters,
                    onReload: () =>
                        controller.fetchMaterialRequests(clear: true),
                  ),
                );
              }

              final requests   = controller.materialRequests;
              final baseCount  = requests.length;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= baseCount) {
                      return ListEndFooter(
                        hasMore: controller.hasMore.value,
                        bottomPadding: navBarHeight,
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
                            Icons.inventory_2_outlined,
                            '${req.customTotalQty.toStringAsFixed(0)} qty',
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
                        auditStats: [
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.person_outline,
                            _abbreviateOwner(req.owner ?? '—'),
                          ),
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.edit_outlined,
                            FormattingHelper.getRelativeTime(req.modified),
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
    );
  }

  // ---------------------------------------------------------------------------
  // Expanded card content
  // ---------------------------------------------------------------------------

  Widget _buildExpandedContent(BuildContext context, String reqName) {
    return Obx(() {
      final detailed = controller.detailedRequest;
      if (detailed == null || detailed.name != reqName) {
        return const SizedBox.shrink();
      }

      final theme       = Theme.of(context);
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

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _infoCell(
                    context,
                    label: 'TRANSACTION DATE',
                    value: detailed.transactionDate,
                    icon: Icons.calendar_today_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _infoCell(
                    context,
                    label: 'REQUIRED BY',
                    value: detailed.scheduleDate.isNotEmpty
                        ? detailed.scheduleDate
                        : '—',
                    icon: Icons.event_outlined,
                    valueColor: colorScheme.primary,
                    alignRight: true,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),

          if (detailed.items.isNotEmpty)
            InfoBlock(
              label: 'Items',
              icon: Icons.inventory_2_outlined,
              child: _buildItemsSummary(context, detailed),
            ),

          const SizedBox(height: 12),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),

          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _abbreviateOwner(detailed.owner ?? '—'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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

  // ---------------------------------------------------------------------------
  // Item summary row
  // ---------------------------------------------------------------------------

  Widget _buildItemsSummary(BuildContext context, MaterialRequest detailed) {
    final totalQty = detailed.items.fold(0.0, (sum, i) => sum + i.qty);
    final orderedQty =
        detailed.items.fold(0.0, (sum, i) => sum + i.orderedQty);
    final fulfilledCount =
        detailed.items.where((i) => i.orderedQty >= i.qty).length;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _miniStat(context, '${detailed.items.length}', 'Lines'),
              const SizedBox(width: 16),
              _miniStat(context, totalQty.toStringAsFixed(0), 'Total Qty'),
              const SizedBox(width: 16),
              _miniStat(
                context,
                '$fulfilledCount',
                'Ordered',
                color: fulfilledCount == detailed.items.length
                    ? Colors.green
                    : colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: totalQty > 0
                  ? (orderedQty / totalQty).clamp(0.0, 1.0)
                  : 0.0,
              minHeight: 4,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                orderedQty >= totalQty ? Colors.green : colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  Widget _infoCell(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
    bool alignRight = false,
  }) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!alignRight) ...[
              Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
            if (alignRight) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: valueColor ?? colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignRight ? TextAlign.end : TextAlign.start,
        ),
      ],
    );
  }

  String _abbreviateOwner(String email) {
    if (email == '—') return '—';
    return email.split('@').first;
  }

  Widget _miniStat(BuildContext context, String value, String label,
      {Color? color}) {
    final theme       = Theme.of(context);
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
