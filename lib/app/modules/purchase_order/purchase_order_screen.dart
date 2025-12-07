import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/modules/purchase_order/purchase_order_controller.dart';
import 'package:ddmco_multimax/app/data/models/purchase_order_model.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';
import 'package:ddmco_multimax/app/data/utils/formatting_helper.dart';
import 'package:ddmco_multimax/app/modules/purchase_order/widgets/purchase_order_filter_bottom_sheet.dart';

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
    return Scaffold(
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
      body: Obx(() {
        if (controller.isLoading.value && controller.purchaseOrders.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.purchaseOrders.isEmpty) {
          return const Center(child: Text('No Purchase Orders found.'));
        }

        return RefreshIndicator(
          onRefresh: () async => controller.fetchPurchaseOrders(clear: true),
          child: ListView.builder(
            controller: _scrollController,
            itemCount: controller.purchaseOrders.length + (controller.hasMore.value ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= controller.purchaseOrders.length) {
                return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()));
              }
              final po = controller.purchaseOrders[index];
              return PurchaseOrderCard(po: po);
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.createNewPO,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class PurchaseOrderCard extends StatelessWidget {
  final PurchaseOrder po;
  final PurchaseOrderController controller = Get.find();

  PurchaseOrderCard({super.key, required this.po});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => controller.toggleExpand(po.name),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      po.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  StatusPill(status: po.status),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(po.supplier, style: const TextStyle(fontSize: 14))),
                  Text(FormattingHelper.getRelativeTime(po.transactionDate), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.monetization_on_outlined, size: 16, color: Colors.grey[700]),
                  const SizedBox(width: 4),
                  Text(
                    '${FormattingHelper.getCurrencySymbol(po.currency)} ${NumberFormat('#,##0.00').format(po.grandTotal)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Obx(() {
                    final isExpanded = controller.expandedPoName.value == po.name;
                    return Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey);
                  }),
                ],
              ),
              Obx(() {
                final isExpanded = controller.expandedPoName.value == po.name;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: !isExpanded
                      ? const SizedBox.shrink()
                      : Obx(() {
                    final detailed = controller.detailedPo;
                    if (controller.isLoadingDetails.value && detailed?.name != po.name) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    if (detailed != null && detailed.name == po.name) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (detailed.docstatus == 0)
                                  OutlinedButton.icon(
                                    onPressed: () => Get.toNamed(AppRoutes.PURCHASE_ORDER_FORM, arguments: {'name': po.name, 'mode': 'edit'}),
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Edit'),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: () => Get.toNamed(AppRoutes.PURCHASE_ORDER_FORM, arguments: {'name': po.name, 'mode': 'view'}),
                                    icon: const Icon(Icons.visibility, size: 16),
                                    label: const Text('View Details'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}