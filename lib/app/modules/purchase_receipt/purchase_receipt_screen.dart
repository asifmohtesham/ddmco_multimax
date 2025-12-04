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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No purchase receipts found.'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => controller.fetchPurchaseReceipts(clear: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => controller.fetchPurchaseReceipts(clear: true),
          child: Scrollbar(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: controller.purchaseReceipts.length + (controller.hasMore.value ? 1 : 0),
              // separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
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

  String _getRelativeTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      // margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => controller.toggleExpand(receipt.name),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Name + Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      receipt.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: receipt.status),
                ],
              ),
              const SizedBox(height: 6),
              
              // Row 2: Supplier + Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      receipt.supplier,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _getRelativeTime(receipt.creation), // Using creation for consistency if available, or modified
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Row 3: Total
              Text(
                '${_getCurrencySymbol(receipt.currency)}${receipt.grandTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),

              // Expansion Content
              Obx(() {
                final isCurrentlyExpanded = controller.expandedReceiptName.value == receipt.name;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Container(
                    child: !isCurrentlyExpanded
                        ? const SizedBox.shrink()
                        : Obx(() {
                            final detailed = controller.detailedReceipt;
                            if (controller.isLoadingDetails.value && detailed?.name != receipt.name) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                                );
                            }

                            if (detailed != null && detailed.name == receipt.name) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),
                                    Text('Posting Date: ${detailed.postingDate}', style: const TextStyle(color: Colors.grey)),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (detailed.status == 'Draft') ...[
                                          OutlinedButton.icon(
                                            onPressed: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {'name': receipt.name, 'mode': 'edit'}),
                                            icon: const Icon(Icons.edit, size: 18),
                                            label: const Text('Edit'),
                                            style: OutlinedButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              side: const BorderSide(color: Colors.blue),
                                            ),
                                          ),
                                        ] else ...[
                                          TextButton(
                                            onPressed: () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {'name': receipt.name, 'mode': 'view'}),
                                            child: const Text('View'),
                                          ),
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
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
