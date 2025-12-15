import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/purchase_order/widgets/purchase_order_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Purchase Orders'),
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
      ),
      drawer: const AppNavDrawer(),
      body: Obx(() {
        if (controller.isLoading.value && controller.purchaseOrders.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.purchaseOrders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined, size: 64, color: colorScheme.outlineVariant),
                const SizedBox(height: 16),
                const Text('No Purchase Orders found.'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => controller.fetchPurchaseOrders(clear: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => controller.fetchPurchaseOrders(clear: true),
          child: ListView.builder(
            controller: _scrollController,
            itemCount: controller.purchaseOrders.length + (controller.hasMore.value ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= controller.purchaseOrders.length) {
                return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
              }
              final po = controller.purchaseOrders[index];
              return _buildPurchaseOrderCard(context, po);
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
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