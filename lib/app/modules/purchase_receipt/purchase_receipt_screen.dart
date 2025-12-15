import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_controller.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Purchase Receipts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      drawer: const AppNavDrawer(),
      body: Obx(() {
        if (controller.isLoading.value && controller.purchaseReceipts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.purchaseReceipts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: colorScheme.outlineVariant),
                const SizedBox(height: 16),
                const Text('No purchase receipts found.'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
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
          child: ListView.builder(
            controller: _scrollController,
            itemCount: controller.purchaseReceipts.length + (controller.hasMore.value ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= controller.purchaseReceipts.length) {
                return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
              }
              final receipt = controller.purchaseReceipts[index];
              return _buildPurchaseReceiptCard(context, receipt);
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
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