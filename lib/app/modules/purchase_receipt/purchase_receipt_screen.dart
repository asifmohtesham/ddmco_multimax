import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class PurchaseReceiptScreen extends StatefulWidget {
  const PurchaseReceiptScreen({super.key});

  @override
  State<PurchaseReceiptScreen> createState() => _PurchaseReceiptScreenState();
}

class _PurchaseReceiptScreenState extends State<PurchaseReceiptScreen> {
  final PurchaseReceiptController controller = Get.find();
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
      controller.fetchPurchaseReceipts(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasFilters = controller.activeFilters.isNotEmpty || controller.searchQuery.value.isNotEmpty;

      return GenericListPage(
        title: 'Purchase Receipts',
        isLoading: controller.isLoading,
        data: controller.purchaseReceipts,
        onRefresh: () => controller.fetchPurchaseReceipts(clear: true),
        scrollController: _scrollController,
        onSearch: controller.onSearchChanged,
        searchHint: 'Search ID, Supplier...',
        searchDoctype: 'Purchase Receipt',
        searchRoute: AppRoutes.PURCHASE_RECEIPT_FORM,
        emptyTitle: hasFilters ? 'No Matching Receipts' : 'No Purchase Receipts',
        emptyMessage: hasFilters
            ? 'Try adjusting your filters or search query.'
            : 'Pull to refresh or create a new one.',
        emptyIcon: hasFilters ? Icons.filter_alt_off_outlined : Icons.receipt_long_outlined,
        onClearFilters: hasFilters ? controller.clearFilters : null,
        itemBuilder: (context, index) => const SizedBox.shrink(),
        sliverBody: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index >= controller.purchaseReceipts.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final receipt = controller.purchaseReceipts[index];
              return Obx(() {
                final isExpanded = controller.expandedReceiptName.value == receipt.name;
                final isLoadingDetails = controller.isLoadingDetails.value && controller.detailedReceipt?.name != receipt.name;

                return GenericDocumentCard(
                  title: receipt.supplier,
                  subtitle: receipt.name,
                  status: receipt.status,
                  stats: [
                    GenericDocumentCard.buildIconStat(context, Icons.inventory_2_outlined,
                        '${receipt.totalQty.toStringAsFixed(2)} Items'),
                    GenericDocumentCard.buildIconStat(context, Icons.access_time,
                        FormattingHelper.getRelativeTime(receipt.creation)),
                  ],
                  isExpanded: isExpanded,
                  isLoadingDetails: isLoadingDetails && isExpanded,
                  onTap: () => controller.toggleExpand(receipt.name),
                  expandedContent: isExpanded ? _buildDetailedContent(context, receipt.name) : null,
                );
              });
            },
            childCount: controller.purchaseReceipts.length + (controller.hasMore.value ? 1 : 0),
          ),
        ),
      );
    });
  }

  Widget _buildDetailedContent(BuildContext context, String receiptName) {
    return Obx(() {
      final detailed = controller.detailedReceipt;
      if (detailed == null || detailed.name != receiptName) return const SizedBox.shrink();

      final cs = Theme.of(context).colorScheme;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDetailField(context, 'Supplier', detailed.supplier),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Grand Total',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      '${FormattingHelper.getCurrencySymbol(detailed.currency)} ${NumberFormat.decimalPatternDigits(decimalDigits: 2).format(detailed.grandTotal)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailField(context, 'Posting Date', detailed.postingDate),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM,
                    arguments: {'name': detailed.name}),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
              ),
            ],
          ),
        ],
      );
    });
  }

  Widget _buildDetailField(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
