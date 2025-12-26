import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/purchase_order/widgets/purchase_order_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';

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
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return GenericListPage(
      title: 'Purchase Orders',
      isLoading: controller.isLoading,
      data: controller.purchaseOrders,
      onRefresh: () => controller.fetchPurchaseOrders(clear: true),
      scrollController: _scrollController,
      // Global API Search Configuration
      searchDoctype: 'Purchase Order',
      searchRoute: AppRoutes.PURCHASE_ORDER_FORM,

      searchHint: 'Search Supplier or ID...',
      // Assuming controller has search logic, passing null if not implemented yet
      // or implement onSearchChanged in controller similar to others
      onSearch: null,
      actions: [
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: () {
            Get.bottomSheet(
              const PurchaseOrderFilterBottomSheet(),
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
            );
          },
        ),
      ],
      emptyTitle: 'No Purchase Orders',
      onClearFilters: controller.activeFilters.isNotEmpty ? controller.clearFilters : null,
      itemBuilder: (context, index) {
        if (index >= controller.purchaseOrders.length) {
          return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
        }
        return _buildPurchaseOrderCard(context, controller.purchaseOrders[index]);
      },
      fab: FloatingActionButton.extended(
        onPressed: controller.createNewPO,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
    );
  }

  Widget _buildPurchaseOrderCard(BuildContext context, PurchaseOrder po) {
    return Obx(() {
      final isExpanded = controller.expandedPoName.value == po.name;
      final isLoadingDetails = controller.isLoadingDetails.value && controller.detailedPo?.name != po.name;

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
                  backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.docstatus == 0)
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.PURCHASE_ORDER_FORM, arguments: {'name': po.name, 'mode': 'edit'}),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.PURCHASE_ORDER_FORM, arguments: {'name': po.name, 'mode': 'view'}),
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