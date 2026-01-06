import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart';

class PackingSlipScreen extends StatefulWidget {
  const PackingSlipScreen({super.key});

  @override
  State<PackingSlipScreen> createState() => _PackingSlipScreenState();
}

class _PackingSlipScreenState extends State<PackingSlipScreen> {
  final PackingSlipController controller = Get.find();
  final ScrollController _scrollController = ScrollController();

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
    // Only load more if not searching
    if (controller.searchQuery.value.isEmpty &&
        _isBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchPackingSlips(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterBottomSheet() {
    Get.bottomSheet(
      const PackingSlipFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GenericListPage(
      title: controller.docType,
      isLoading: controller.isLoading,
      data: controller.packingSlips,
      onRefresh: () async => controller.fetchPackingSlips(clear: true),
      onSearch: controller.onSearchChanged,
      searchHint: 'Search slips, customers...',
      scrollController: _scrollController,
      // Empty State Config
      emptyTitle: 'No ${controller.docType} Found',
      emptyMessage: 'Pull to refresh or create a new one.',
      emptyIcon: Icons.assignment_return_outlined,
      onClearFilters: controller.clearFilters,
      // Actions
      actions: [
        Obx(() => IconButton(
          icon: Icon(Icons.filter_list,
              color: controller.activeFilters.isNotEmpty
                  ? colorScheme.primary
                  : null),
          onPressed: _showFilterBottomSheet,
        )),
      ],
      // FAB
      fab: FloatingActionButton.extended(
        onPressed: controller.openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      // Grouped List Content
      sliverBody: Obx(() {
        // Access map length to ensure Obx listens to map updates
        // ignore: unused_local_variable
        final _dummyListener = controller.posCustomerMap.length;

        final grouped = controller.groupedPackingSlips;
        final groupKeys = grouped.keys.toList();

        // If search returns no groups, show message (GenericListPage handles main empty state)
        if (groupKeys.isEmpty && controller.packingSlips.isNotEmpty) {
          return const SliverFillRemaining(
            child: Center(child: Text('No results match your search.')),
          );
        }

        // Only show bottom loader if NOT searching and there is more data
        final bool showLoader =
            controller.searchQuery.value.isEmpty && controller.hasMore.value;

        return SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              if (index >= groupKeys.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final groupKey = groupKeys[index];
              final slips = grouped[groupKey]!;

              // Extract Customer Name logic
              String? customerName =
              slips.isNotEmpty ? slips.first.customer : null;
              if ((customerName == null || customerName.isEmpty) &&
                  slips.isNotEmpty) {
                customerName =
                    controller.getCustomerName(slips.first.customPoNo);
              }

              return Card(
                margin:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                elevation: 0,
                color: colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                            child: Icon(Icons.inventory_2_outlined,
                                size: 16,
                                color: colorScheme.onPrimaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  groupKey,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (customerName != null &&
                                    customerName.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      customerName,
                                      style:
                                      theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
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
                              borderRadius: BorderRadius.circular(12),
                              border:
                              Border.all(color: colorScheme.outlineVariant),
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

                    // Slips List
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: slips.length,
                      padding: EdgeInsets.zero,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color:
                        colorScheme.outlineVariant.withValues(alpha: 0.5),
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
            childCount: groupKeys.length + (showLoader ? 1 : 0),
          ),
        );
      }),
      // Unused because we use sliverBody, but required by widget
      itemBuilder: (_, __) => const SizedBox.shrink(),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}