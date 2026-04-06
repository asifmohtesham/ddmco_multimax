import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class PackingSlipScreen extends StatefulWidget {
  const PackingSlipScreen({super.key});

  @override
  State<PackingSlipScreen> createState() => _PackingSlipScreenState();
}

class _PackingSlipScreenState extends State<PackingSlipScreen> {
  final PackingSlipController controller = Get.find();
  final _scrollController = ScrollController();
  final _isFarFromTop = false.obs;

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
    if (controller.searchQuery.value.isEmpty &&
        _isBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchPackingSlips(isLoadMore: true);
    }
    final far = _scrollController.hasClients && _scrollController.offset > 80;
    if (_isFarFromTop.value != far) _isFarFromTop.value = far;
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterSheet() {
    Get.bottomSheet(
      const PackingSlipFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  /// Builds dismissible filter chips for every active filter + search query.
  /// Called inside [DocTypeListHeader.filterChipsBuilder] which is wrapped
  /// in [Obx], so all Rx reads here are tracked automatically.
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
          controller.fetchPackingSlips(clear: true);
        },
      ));
    }

    if (filters.containsKey('docstatus')) {
      const labels = {0: 'Draft', 1: 'Submitted', 2: 'Cancelled'};
      final label = labels[filters['docstatus']] ?? '${filters['docstatus']}';
      chips.add(_chip(
        context,
        icon: Icons.flag_outlined,
        label: 'Status: $label',
        onDeleted: () => controller.removeFilter('docstatus'),
      ));
    }

    if (filters.containsKey('delivery_note')) {
      chips.add(_chip(
        context,
        icon: Icons.local_shipping_outlined,
        label: 'DN: ${filters['delivery_note']}',
        onDeleted: () => controller.removeFilter('delivery_note'),
      ));
    }

    if (filters.containsKey('custom_po_no')) {
      chips.add(_chip(
        context,
        icon: Icons.tag,
        label: 'PO: ${filters['custom_po_no']}',
        onDeleted: () => controller.removeFilter('custom_po_no'),
      ));
    }

    if (filters.containsKey('posting_date')) {
      final f = filters['posting_date'];
      if (f is List &&
          f.length >= 2 &&
          f[0] == 'between' &&
          f[1] is List &&
          (f[1] as List).length >= 2) {
        final dates = f[1] as List;
        chips.add(_chip(
          context,
          icon: Icons.date_range,
          label: '${dates[0]}  →  ${dates[1]}',
          onDeleted: () => controller.removeFilter('posting_date'),
        ));
      }
    }

    if (filters.containsKey('_sort')) {
      chips.add(_chip(
        context,
        icon: Icons.sort,
        label: 'Sort: ${filters['_sort']}',
        onDeleted: () {
          controller.removeFilter('_sort');
          controller.setSort('creation', 'desc');
        },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: Obx(() => RoleGuard(
            roles: controller.writeRoles.toList(),
            child: _isFarFromTop.value
                ? FloatingActionButton(
                    onPressed: controller.openCreateDialog,
                    tooltip: 'New Packing Slip',
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 4,
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                    onPressed: controller.openCreateDialog,
                    tooltip: 'New Packing Slip',
                    icon: const Icon(Icons.add),
                    label: const Text('New Packing Slip'),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 4,
                  ),
          )),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchPackingSlips(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header: AppBar + search + filter chips ──────────────
            DocTypeListHeader(
              title: 'Packing Slip',
              automaticallyImplyLeading: false,
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchPackingSlips(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── Result count pill ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.packingSlips.isEmpty) {
                  return const SizedBox.shrink();
                }
                final count = controller.packingSlips.length;
                final hasMore = controller.hasMore.value;
                final hasFilters = controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.assignment_return_outlined,
                                size: 14,
                                color: colorScheme.onSecondaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              hasMore
                                  ? '$count+ slips'
                                  : '$count slip${count == 1 ? '' : 's'}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (hasFilters) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.filter_alt,
                                  size: 12,
                                  color: colorScheme.onSecondaryContainer
                                      .withValues(alpha: 0.7)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),

            // ── List content ──────────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.packingSlips.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.packingSlips.isEmpty) {
                final bool hasFilters =
                    controller.activeFilters.isNotEmpty ||
                        controller.searchQuery.value.isNotEmpty;
                String emptySubtitle;
                if (hasFilters) {
                  final parts = <String>[];
                  final af = controller.activeFilters;
                  if (af.containsKey('docstatus')) {
                    const labels = {
                      0: 'Draft',
                      1: 'Submitted',
                      2: 'Cancelled'
                    };
                    parts.add(
                        'Status: ${labels[af['docstatus']] ?? af['docstatus']}');
                  }
                  if (af.containsKey('delivery_note')) {
                    parts.add('DN: ${af['delivery_note']}');
                  }
                  if (af.containsKey('custom_po_no')) {
                    parts.add('PO: ${af['custom_po_no']}');
                  }
                  if (controller.searchQuery.value.isNotEmpty) {
                    parts.add('Search: "${controller.searchQuery.value}"');
                  }
                  emptySubtitle = parts.isNotEmpty
                      ? 'No slips found for ${parts.join(' + ')}.'
                      : 'Try adjusting your filters or search query.';
                } else {
                  emptySubtitle = 'Pull to refresh or create a new one.';
                }

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
                                : Icons.assignment_return_outlined,
                            size: 64,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching Slips'
                                : 'No Packing Slips Found',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            emptySubtitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant),
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
                                  controller.fetchPackingSlips(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // Touch map length so Obx listens to customer map updates
              // ignore: unused_local_variable
              final _dummyListener = controller.posCustomerMap.length;

              final grouped = controller.groupedPackingSlips;
              final groupKeys = grouped.keys.toList();

              if (groupKeys.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                      child: Text('No results match your search.')),
                );
              }

              final bool showLoader =
                  controller.searchQuery.value.isEmpty &&
                      controller.hasMore.value;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= groupKeys.length) {
                      if (showLoader) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.only(
                            top: 16, bottom: 16 + navBarHeight),
                        child: Center(
                          child: Text(
                            'End of results',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      );
                    }

                    final groupKey = groupKeys[index];
                    final slips = grouped[groupKey]!;

                    String? customerName =
                        slips.isNotEmpty ? slips.first.customer : null;
                    if ((customerName == null || customerName.isEmpty) &&
                        slips.isNotEmpty) {
                      customerName =
                          controller.getCustomerName(slips.first.customPoNo);
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      elevation: 0,
                      color: colorScheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Group Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 12.0),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh,
                              border: Border(
                                  bottom: BorderSide(
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.5))),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                      Icons.inventory_2_outlined,
                                      size: 16,
                                      color:
                                          colorScheme.onPrimaryContainer),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        groupKey,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (customerName != null &&
                                          customerName.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 2.0),
                                          child: Text(
                                            customerName,
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                              color: colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                        color: colorScheme.outlineVariant),
                                  ),
                                  child: Text(
                                    '${slips.length}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Slips list
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: slips.length,
                            padding: EdgeInsets.zero,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                            itemBuilder: (context, slipIndex) {
                              final slip = slips[slipIndex];
                              return PackingSlipListTile(slip: slip);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: groupKeys.length + 1,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PackingSlipListTile — preserved intact; replaced by GenericDocumentCard
// in Commit 6
// ---------------------------------------------------------------------------

class PackingSlipListTile extends StatelessWidget {
  final dynamic slip;

  const PackingSlipListTile({super.key, required this.slip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () => Get.toNamed(AppRoutes.PACKING_SLIP_FORM,
          arguments: {'name': slip.name, 'mode': 'view'}),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          slip.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        FormattingHelper.getRelativeTime(slip.creation),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.filter_none,
                          size: 14, color: colorScheme.secondary),
                      const SizedBox(width: 6),
                      Text(
                        'Pkg: ${slip.fromCaseNo ?? "?"} - ${slip.toCaseNo ?? "?"}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.secondary,
                        ),
                      ),
                      if (slip.docstatus == 1) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.check_circle_outline,
                            size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Submitted',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (slip.status != 'Submitted')
              StatusPill(status: slip.status)
            else
              Icon(Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
