import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';
import 'package:multimax/app/modules/purchase_receipt/widgets/purchase_receipt_filter_bottom_sheet.dart';

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
    return GenericListPage(
      title: 'Purchase Receipts',
      isLoading: controller.isLoading,
      data: controller.purchaseReceipts,
      onRefresh: () => controller.fetchPurchaseReceipts(clear: true),
      scrollController: _scrollController,
      searchHint: 'Search...',
      onSearch: null, // Add search logic to controller if needed
      actions: [
        Obx(() {
          final count = controller.activeFilters.length;
          return IconButton(
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: Icon(
                Icons.filter_list,
                color: count > 0 ? Colors.amber : null,
              ),
            ),
            onPressed: () => Get.bottomSheet(
              const PurchaseReceiptFilterBottomSheet(),
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
            ),
          );
        }),
      ],
      emptyTitle: 'No Purchase Receipts',
      onClearFilters: controller.activeFilters.isNotEmpty ? controller.clearFilters : null,
      itemBuilder: (context, index) {
        if (index >= controller.purchaseReceipts.length) {
          return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
        }
        return _buildPurchaseReceiptCard(context, controller.purchaseReceipts[index]);
      },
      fab: FloatingActionButton.extended(
        onPressed: controller.openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
    );
  }

  Widget _buildPurchaseReceiptCard(BuildContext context, PurchaseReceipt receipt) {
    return Obx(() {
      final isExpanded = controller.expandedReceiptName.value == receipt.name;
      final isLoadingDetails = controller.isLoadingDetails.value && controller.detailedReceipt?.name != receipt.name;

      final List<Widget> stats = [
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
      ];

      if (receipt.docstatus == 1) {
        stats.add(GenericDocumentCard.buildIconStat(
          context,
          Icons.timer_outlined,
          FormattingHelper.getTimeTaken(receipt.creation, receipt.modified),
        ));
      }

      return GenericDocumentCard(
        title: receipt.name,
        subtitle: receipt.supplier,
        status: receipt.status,
        isExpanded: isExpanded,
        isLoadingDetails: isLoadingDetails && isExpanded,
        onTap: () => controller.toggleExpand(receipt.name),
        stats: stats,
        expandedContent: _buildExpandedContent(context, receipt),
      );
    });
  }

  Widget _buildExpandedContent(BuildContext context, PurchaseReceipt receipt) {
    return Obx(() {
      final detailed = controller.detailedReceipt;
      if (detailed == null || detailed.name != receipt.name) {
        return const SizedBox.shrink();
      }

      final colorScheme = Theme.of(context).colorScheme;
      final currencySymbol = FormattingHelper.getCurrencySymbol(detailed.currency);
      final grandTotal = NumberFormat('#,##0.00').format(detailed.grandTotal);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detailed.setWarehouse != null && detailed.setWarehouse!.isNotEmpty)
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
                  backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.status == 'Draft') ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {'name': receipt.name, 'mode': 'edit'}),
                  icon: Icon(detailed.docstatus == 0 ? Icons.edit : Icons.file_open, size: 18),
                  label: Text(detailed.docstatus == 0 ? 'Edit' : 'Open'),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {'name': receipt.name, 'mode': 'view'}),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View Details'),
                ),
              ]
            ],
          ),
        ],
      );
    });
  }
}