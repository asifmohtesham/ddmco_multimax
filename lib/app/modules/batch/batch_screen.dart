import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/theme/frappe_theme.dart';
import 'package:intl/intl.dart';

class BatchScreen extends GetView<BatchController> {
  const BatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Scroll controller to handle pagination in GenericListPage
    final scrollController = ScrollController();
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent * 0.9 &&
          controller.hasMore.value &&
          !controller.isFetchingMore.value) {
        controller.fetchBatches(isLoadMore: true);
      }
    });

    return GenericListPage(
      title: 'Batch List',
      isLoading: controller.isLoading,
      data: controller.filteredList,
      onRefresh: () async => controller.fetchBatches(clear: true),
      scrollController: scrollController,

      // Search Configuration
      onSearch: controller.onSearchChanged,
      searchHint: 'Filter by ID...',
      searchDoctype: 'Batch',

      // FAB
      fab: FloatingActionButton(
        backgroundColor: FrappeTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => controller.openBatchForm(null),
      ),

      itemBuilder: (context, index) {
        // Handle pagination spinner at bottom
        if (index == controller.filteredList.length) {
          return controller.hasMore.value
              ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              : const SizedBox.shrink();
        }

        final Batch batch = controller.filteredList[index];
        return _buildBatchCard(context, batch);
      },
    );
  }

  Widget _buildBatchCard(BuildContext context, Batch batch) {
    // Logic for Status Label
    String status = 'Active';
    bool isExpired = false;
    if (batch.expiryDate != null) {
      final expiry = DateTime.tryParse(batch.expiryDate!);
      if (expiry != null && expiry.isBefore(DateTime.now())) {
        status = 'Expired';
        isExpired = true;
      }
    }

    return Obx(() {
      final isExpanded = controller.expandedBatchName.value == batch.name;

      return GenericDocumentCard(
        title: batch.name,
        subtitle: batch.item,
        status: status,
        isExpanded: isExpanded,
        onTap: () => controller.toggleExpand(batch.name),

        // Custom Leading Icon
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: isExpired ? Colors.red.withOpacity(0.1) : FrappeTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
              Icons.qr_code_2,
              color: isExpired ? Colors.red : FrappeTheme.primary,
              size: 22
          ),
        ),

        // Quick Stats
        stats: [
          if (batch.manufacturingDate != null)
            GenericDocumentCard.buildIconStat(
                context,
                Icons.precision_manufacturing_outlined,
                _formatDate(batch.manufacturingDate)
            ),
          if (batch.expiryDate != null)
            GenericDocumentCard.buildIconStat(
                context,
                Icons.event_busy_outlined,
                _formatDate(batch.expiryDate)
            ),
          GenericDocumentCard.buildIconStat(
              context,
              Icons.layers_outlined,
              'Qty: ${batch.customPackagingQty}'
          ),
        ],

        // Expanded Details
        expandedContent: isExpanded ? _buildExpandedDetails(context, batch) : null,
      );
    });
  }

  Widget _buildExpandedDetails(BuildContext context, Batch batch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Purchase Order
        _buildDetailRow("Purchase Order", batch.customPurchaseOrder ?? "Not Linked", Icons.receipt_long),
        const SizedBox(height: 12),

        // Variant Info (Async loaded)
        Obx(() {
          final variant = controller.itemVariants[batch.item];
          final isLoading = controller.isLoadingDetails.value && variant == null;

          if (isLoading) {
            return const Row(
              children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text("Loading details...", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            );
          }
          return _buildDetailRow("Variant Of", variant ?? "N/A", Icons.style_outlined);
        }),

        const SizedBox(height: 16),

        // Edit Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: FrappeTheme.surface,
                foregroundColor: FrappeTheme.primary,
                elevation: 0,
                side: const BorderSide(color: FrappeTheme.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FrappeTheme.radius))
            ),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text("Edit Batch Details"),
            onPressed: () => controller.openBatchForm(batch.name),
          ),
        )
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: FrappeTheme.textLabel),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: FrappeTheme.textLabel)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: FrappeTheme.textBody)),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return "-";
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}