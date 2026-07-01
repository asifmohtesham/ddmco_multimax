import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/purchase_order/widgets/purchase_order_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';

class PurchaseOrderScreen extends StatefulWidget {
  const PurchaseOrderScreen({super.key});

  @override
  State<PurchaseOrderScreen> createState() => _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends State<PurchaseOrderScreen> {
  final PurchaseOrderController controller = Get.find();
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
    if (_isBottom && controller.hasMore.value && !controller.isFetchingMore.value) {
      controller.fetchPurchaseOrders(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
  }

  void _showFilterSheet() {
    Get.bottomSheet(
      const PurchaseOrderFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
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
          controller.fetchPurchaseOrders(clear: true);
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

    if (filters.containsKey('supplier')) {
      chips.add(_chip(
        context,
        icon: Icons.business_outlined,
        label: 'Supplier: ${filters['supplier']}',
        onDeleted: () => controller.removeFilter('supplier'),
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
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list screen.
    return FilterChipWidget(icon: icon, label: label, onDeleted: onDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppShellScaffold(
      floatingActionButton: Obx(() => DocTypeGuard(
        doctype: 'Purchase Order',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: controller.openCreateDialog,
          tooltip: 'New Purchase Order',
          icon: const Icon(Icons.add),
          label: const Text('New Purchase Order'),
        ),
      )),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchPurchaseOrders(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header: AppBar + filter chips ──────────────────────
            DocTypeListHeader(
              title: 'Purchase Order',
              automaticallyImplyLeading: false,
              searchDoctype: 'Purchase Order',
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchPurchaseOrders(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── Result count pill ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.purchaseOrders.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ResultCountPill(
                  count: controller.purchaseOrders.length,
                  hasMore: controller.hasMore.value,
                  hasActiveFilters: controller.activeFilters.isNotEmpty ||
                      controller.searchQuery.value.isNotEmpty,
                  noun: 'order',
                  icon: Icons.shopping_cart_outlined,
                );
              }),
            ),

            // ── List content ───────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value && controller.purchaseOrders.isEmpty) {
                return const SliverToBoxAdapter(child: DocCardSkeletonList());
              }

              if (controller.purchaseOrders.isEmpty) {
                final hasFilters = controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ListEmptyState(
                    hasActiveFilters: hasFilters,
                    emptyIcon: Icons.shopping_cart_outlined,
                    emptyTitle: 'No Purchase Orders',
                    emptyMessage: 'Pull to refresh or create a new one.',
                    filteredTitle: 'No Matching Orders',
                    filteredMessage:
                        'Try adjusting your filters or search query.',
                    onClearFilters: controller.clearFilters,
                    onReload: () =>
                        controller.fetchPurchaseOrders(clear: true),
                  ),
                );
              }

              final baseCount = controller.purchaseOrders.length;
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= baseCount) {
                      return ListEndFooter(hasMore: controller.hasMore.value);
                    }
                    return _buildCard(context, controller.purchaseOrders[index]);
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

  Widget _buildCard(BuildContext context, PurchaseOrder po) {
    return Obx(() {
      final isExpanded = controller.expandedPoName.value == po.name;
      final isLoadingDetails =
          controller.isLoadingDetails.value &&
          controller.detailedPo?.name != po.name;

      final currencySymbol = FormattingHelper.getCurrencySymbol(po.currency);
      final grandTotal = NumberFormat('#,##0.00').format(po.grandTotal);

      return GenericDocumentCard(
        title: po.name,
        subtitle: po.supplier,
        status: po.status,
        isExpanded: isExpanded,
        isLoadingDetails: isLoadingDetails && isExpanded,
        onTap: () => controller.toggleExpand(po.name),
        stats: [
          GenericDocumentCard.buildIconStat(
            context,
            Icons.calendar_today,
            FormattingHelper.getRelativeTime(po.transactionDate),
          ),
          GenericDocumentCard.buildIconStat(
            context,
            Icons.attach_money,
            '$currencySymbol $grandTotal',
          ),
        ],
        expandedContent: _buildExpandedContent(context, po),
      );
    });
  }

  Widget _buildExpandedContent(BuildContext context, PurchaseOrder po) {
    return Obx(() {
      final detailed = controller.detailedPo;
      if (detailed == null || detailed.name != po.name) {
        return const SizedBox.shrink();
      }

      final colorScheme = Theme.of(context).colorScheme;
      final currencySymbol = FormattingHelper.getCurrencySymbol(detailed.currency);
      final grandTotal = NumberFormat('#,##0.00').format(detailed.grandTotal);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InfoBlock(
                  label: 'Date',
                  value: detailed.transactionDate,
                  icon: Icons.event,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InfoBlock(
                  label: 'Total',
                  value: '$currencySymbol $grandTotal',
                  icon: Icons.account_balance_wallet_outlined,
                  valueColor: colorScheme.primary,
                  backgroundColor:
                      colorScheme.primaryContainer.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.docstatus == 0)
                DocTypeGuard(
                  doctype: 'Purchase Order',
                  permType: 'write',
                  fallback: FilledButton.tonalIcon(
                    onPressed: () => Get.toNamed(
                      AppRoutes.PURCHASE_ORDER_FORM,
                      arguments: {'name': po.name, 'mode': 'view'},
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View Details'),
                  ),
                  child: FilledButton.tonalIcon(
                    onPressed: () => Get.toNamed(
                      AppRoutes.PURCHASE_ORDER_FORM,
                      arguments: {'name': po.name, 'mode': 'edit'},
                    ),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(
                    AppRoutes.PURCHASE_ORDER_FORM,
                    arguments: {'name': po.name, 'mode': 'view'},
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View Details'),
                ),
            ],
          ),
        ],
      );
    });
  }
}
