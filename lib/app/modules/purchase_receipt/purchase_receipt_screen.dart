import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';

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

  void _showFilterDialog(BuildContext context) {
    final supplierController = TextEditingController(text: controller.activeFilters['supplier']);
    String? selectedStatus = controller.activeFilters['status'];

    Get.dialog(
      AlertDialog(
        title: const Text('Filter Purchase Receipts'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: supplierController,
              decoration: const InputDecoration(labelText: 'Supplier'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: ['Draft', 'Submitted', 'Completed', 'Cancelled']
                  .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                  .toList(),
              onChanged: (value) => selectedStatus = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.clearFilters();
              Get.back();
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              final filters = {
                if (supplierController.text.isNotEmpty) 'supplier': supplierController.text,
                if (selectedStatus != null) 'status': selectedStatus,
              };
              controller.applyFilters(filters);
              Get.back();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Receipts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.purchaseReceipts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.purchaseReceipts.isEmpty) {
          return const Center(child: Text('No purchase receipts found.'));
        }

        return Scrollbar(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: controller.purchaseReceipts.length + (controller.hasMore.value ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= controller.purchaseReceipts.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final receipt = controller.purchaseReceipts[index];
              return PurchaseReceiptCard(receipt: receipt);
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {'name': '', 'mode': 'new'});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class PurchaseReceiptCard extends StatelessWidget {
  final dynamic receipt;
  final PurchaseReceiptController controller = Get.find();

  PurchaseReceiptCard({super.key, required this.receipt});

  String _getCurrencySymbol(String currency) {
    final format = NumberFormat.simpleCurrency(name: currency);
    return format.currencySymbol;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final isCurrentlyExpanded = controller.expandedReceiptName.value == receipt.name;
        return Column(
          children: [
            ListTile(
              title: Text(receipt.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${receipt.supplier} - ${_getCurrencySymbol(receipt.currency)}${receipt.grandTotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  StatusPill(status: receipt.status),
                ],
              ),
              trailing: AnimatedRotation(
                turns: isCurrentlyExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.expand_more),
              ),
              onTap: () => controller.toggleExpand(receipt.name),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Container(
                child: !isCurrentlyExpanded
                    ? const SizedBox.shrink()
                    : Obx(() {
                        final detailed = controller.detailedReceipt;
                        if (controller.isLoadingDetails.value && detailed?.name != receipt.name) {
                          return const LinearProgressIndicator();
                        }

                        if (detailed != null && detailed.name == receipt.name) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                                  child: Text('Posting Date: ${detailed.postingDate}'),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (detailed.status == 'Draft') ...[
                                      TextButton(
                                        onPressed: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {'name': receipt.name, 'mode': 'edit'}),
                                        child: const Text('Edit'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () => Get.snackbar('TODO', 'Submit document'),
                                        child: const Text('Submit'),
                                      ),
                                    ] else ...[
                                      TextButton(
                                        onPressed: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {'name': receipt.name, 'mode': 'view'}),
                                        child: const Text('View'),
                                      ),
                                      if (detailed.status == 'Submitted') ...[
                                        const SizedBox(width: 8),
                                        TextButton(
                                          onPressed: () => Get.snackbar('TODO', 'Cancel document'),
                                          child: const Text('Cancel'),
                                        ),
                                      ]
                                    ]
                                  ],
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
              ),
            ),
          ],
        );
      }),
    );
  }
}
