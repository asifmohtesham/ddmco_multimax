import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/purchase_receipt/widgets/purchase_receipt_filter_bottom_sheet.dart';

class PurchaseReceiptScreen extends StatefulWidget {
  const PurchaseReceiptScreen({super.key});

  @override
  State<PurchaseReceiptScreen> createState() => _PurchaseReceiptScreenState();
}

class _PurchaseReceiptScreenState extends State<PurchaseReceiptScreen> {
  final PurchaseReceiptController controller = Get.find();
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
    if (!_scrollController.hasClients) return;
    final far = _scrollController.offset > 80;
    if (_isFarFromTop.value != far) _isFarFromTop.value = far;
    if (_isBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchPurchaseReceipts(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
  }

  void _showFilterSheet() {
    Get.bottomSheet(
      const PurchaseReceiptFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ---------------------------------------------------------------------------
  // Active filter chips
  // ---------------------------------------------------------------------------
  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final f = controller.activeFilters;

    if (f.containsKey('status')) {
      chips.add(_chip(context,
          icon: Icons.flag_outlined,
          label: 'Status: ${f['status']}',
          onDeleted: () => controller.removeFilter('status')));
    }
    if (f.containsKey('supplier') && f['supplier'].toString().isNotEmpty) {
      chips.add(_chip(context,
          icon: Icons.business_outlined,
          label: 'Supplier: ${f['supplier']}',
          onDeleted: () => controller.removeFilter('supplier')));
    }
    if (f.containsKey('set_warehouse')) {
      chips.add(_chip(context,
          icon: Icons.warehouse_outlined,
          label: 'Warehouse: ${f['set_warehouse']}',
          onDeleted: () => controller.removeFilter('set_warehouse')));
    }
    if (f.containsKey('posting_date')) {
      final val = f['posting_date'];
      if (val is List && val.length >= 2 && val[0] == 'between' &&
          val[1] is List && (val[1] as List).length >= 2) {
        final dates = val[1] as List;
        chips.add(_chip(context,
            icon: Icons.date_range,
            label: '${dates[0]}  →  ${dates[1]}',
            onDeleted: () => controller.removeFilter('posting_date')));
      }
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: Obx(() => _isFarFromTop.value
          ? FloatingActionButton(
              onPressed: controller.openCreateDialog,
              tooltip: 'New Purchase Receipt',
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 4,
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: controller.openCreateDialog,
              tooltip: 'New Purchase Receipt',
              icon: const Icon(Icons.add),
              label: const Text('New Purchase Receipt'),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 4,
            )),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchPurchaseReceipts(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header: AppBar + filter chips ──────────────────────
            DocTypeListHeader(
              title: 'Purchase Receipt',
              automaticallyImplyLeading: false,
              searchDoctype: 'Purchase Receipt',
              searchRoute: AppRoutes.PURCHASE_RECEIPT_FORM,
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── Result count pill ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.purchaseReceipts.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ResultCountPill(
                  count: controller.purchaseReceipts.length,
                  hasMore: controller.hasMore.value,
                  hasActiveFilters: controller.activeFilters.isNotEmpty,
                  noun: 'receipt',
                  icon: Icons.receipt_long_outlined,
                );
              }),
            ),

            // ── List content ───────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.purchaseReceipts.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.purchaseReceipts.isEmpty) {
                final hasFilters = controller.activeFilters.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ListEmptyState(
                    hasActiveFilters: hasFilters,
                    emptyIcon: Icons.receipt_long_outlined,
                    emptyTitle: 'No Purchase Receipts',
                    emptyMessage: 'Pull to refresh or create a new one.',
                    filteredTitle: 'No Matching Receipts',
                    filteredMessage: 'Try adjusting your filters.',
                    onClearFilters: controller.clearFilters,
                    onReload: () =>
                        controller.fetchPurchaseReceipts(clear: true),
                  ),
                );
              }

              final baseCount = controller.purchaseReceipts.length;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= baseCount) {
                      return ListEndFooter(
                        hasMore: controller.hasMore.value,
                        bottomPadding: navBarHeight,
                      );
                    }
                    return _buildCard(
                        context, controller.purchaseReceipts[index]);
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
  // Card
  // ---------------------------------------------------------------------------
  Widget _buildCard(BuildContext context, PurchaseReceipt receipt) {
    return Obx(() {
      final isExpanded =
          controller.expandedReceiptName.value == receipt.name;
      final isLoadingDetails = controller.isLoadingDetails.value &&
          controller.detailedReceipt?.name != receipt.name;

      return GenericDocumentCard(
        title: receipt.name,
        subtitle: receipt.supplier,
        status: receipt.status,
        isExpanded: isExpanded,
        isLoadingDetails: isLoadingDetails && isExpanded,
        onTap: () => controller.toggleExpand(receipt.name),
        stats: [
          GenericDocumentCard.buildIconStat(
            context,
            Icons.inventory_2_outlined,
            '${NumberFormat.decimalPattern().format(receipt.totalQty)} Items',
          ),
          GenericDocumentCard.buildIconStat(
            context,
            Icons.access_time,
            FormattingHelper.getRelativeTime(receipt.creation),
          ),
          if (receipt.docstatus == 1)
            GenericDocumentCard.buildIconStat(
              context,
              Icons.timer_outlined,
              FormattingHelper.getTimeTaken(
                  receipt.creation, receipt.modified),
            ),
        ],
        expandedContent: _buildExpandedContent(context, receipt),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Expanded content
  // ---------------------------------------------------------------------------
  Widget _buildExpandedContent(
      BuildContext context, PurchaseReceipt receipt) {
    return Obx(() {
      final detailed = controller.detailedReceipt;
      if (detailed == null || detailed.name != receipt.name) {
        return const SizedBox.shrink();
      }

      final colorScheme = Theme.of(context).colorScheme;
      final currencySymbol =
          FormattingHelper.getCurrencySymbol(detailed.currency);
      final grandTotal =
          NumberFormat('#,##0.00').format(detailed.grandTotal);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detailed.setWarehouse != null &&
              detailed.setWarehouse!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: InfoBlock(
                label: 'Accepted Warehouse',
                value: detailed.setWarehouse,
                icon: Icons.store_outlined,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: InfoBlock(
                  label: 'Posting Date',
                  value: detailed.postingDate,
                  icon: Icons.calendar_today,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InfoBlock(
                  label: 'Grand Total',
                  value: '$currencySymbol $grandTotal',
                  icon: Icons.attach_money,
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
              if (detailed.status == 'Draft')
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(
                    AppRoutes.PURCHASE_RECEIPT_FORM,
                    arguments: {
                      'name': receipt.name,
                      'mode': detailed.docstatus == 0 ? 'edit' : 'open',
                    },
                  ),
                  icon: Icon(
                    detailed.docstatus == 0 ? Icons.edit : Icons.file_open,
                    size: 18,
                  ),
                  label:
                      Text(detailed.docstatus == 0 ? 'Edit' : 'Open'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(
                    AppRoutes.PURCHASE_RECEIPT_FORM,
                    arguments: {'name': receipt.name, 'mode': 'view'},
                  ),
                  icon:
                      const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View Details'),
                ),
            ],
          ),
        ],
      );
    });
  }
}
