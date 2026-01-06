import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:multimax/app/modules/delivery_note/widgets/filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/modules/global_widgets/info_block.dart';

class DeliveryNoteScreen extends GetView<DeliveryNoteController> {
  const DeliveryNoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GenericListPage(
      title: controller.docType,
      isLoading: controller.isLoading,
      data: controller.deliveryNotes,
      onRefresh: () async => controller.fetchDeliveryNotes(clear: true),
      scrollController: controller.scrollController,
      onSearch: controller.onSearch,
      searchHint: 'Search ID...',
      searchDoctype: controller.docType,
      searchRoute: AppRoutes.DELIVERY_NOTE_FORM,
      emptyTitle: 'No delivery notes found',
      emptyMessage: 'Pull to refresh to load data.',

      // Header Actions
      actions: [
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: () => Get.bottomSheet(
            const FilterBottomSheet(),
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
          ),
        ),
      ],

      // Create Button
      fab: FloatingActionButton.extended(
        onPressed: controller.openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),

      // List Item Builder
      itemBuilder: (context, index) {
        final note = controller.deliveryNotes[index];
        return Obx(() {
          final isExpanded = controller.expandedNoteName.value == note.name;
          final isLoadingDetails = controller.isLoadingDetails.value &&
              controller.detailedNote?.name != note.name;

          // Logic to determine title/subtitle
          final bool hasPo = note.poNo != null && note.poNo!.isNotEmpty;
          final String title = hasPo ? note.poNo! : note.name;
          final String subtitle = hasPo
              ? '${note.name} • ${note.customer}'
              : note.customer;

          return GenericDocumentCard(
            title: title,
            subtitle: subtitle,
            status: note.status,
            isExpanded: isExpanded,
            isLoadingDetails: isLoadingDetails && isExpanded,
            onTap: () => controller.toggleExpand(note.name),
            stats: [
              GenericDocumentCard.buildIconStat(
                context,
                Icons.inventory_2_outlined,
                '${note.totalQty.toStringAsFixed(0)} Items',
              ),
              GenericDocumentCard.buildIconStat(
                context,
                Icons.access_time,
                FormattingHelper.getRelativeTime(note.creation),
              ),
              if (note.docstatus == 1) // Submitted
                GenericDocumentCard.buildIconStat(
                  context,
                  Icons.timer_outlined,
                  FormattingHelper.getTimeTaken(note.creation, note.modified),
                ),
            ],
            expandedContent: _buildExpandedContent(context, note),
          );
        });
      },
    );
  }

  Widget _buildExpandedContent(BuildContext context, DeliveryNote note) {
    return Obx(() {
      final detailed = controller.detailedNote;
      // Double check matches to avoid stale data display
      if (detailed == null || detailed.name != note.name) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final currencySymbol =
      FormattingHelper.getCurrencySymbol(detailed.currency);
      final grandTotal = NumberFormat('#,##0.00').format(detailed.grandTotal);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Block (Warehouse)
          if (detailed.setWarehouse != null &&
              detailed.setWarehouse!.isNotEmpty)
            InfoBlock(
              label: 'Source Warehouse',
              value: detailed.setWarehouse!,
              icon: Icons.store_outlined,
            ),

          if (detailed.setWarehouse != null &&
              detailed.setWarehouse!.isNotEmpty)
            const SizedBox(height: 12),

          // Details Grid (Using InfoBlock for uniformity)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InfoBlock(
                  label: 'Posting Date',
                  value: detailed.postingDate,
                  icon: Icons.calendar_today_outlined,
                  backgroundColor: colorScheme.surfaceContainer,
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

          const SizedBox(height: 24),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.status == 'Draft') ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
                      arguments: {'name': note.name, 'mode': 'edit'}),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
                      arguments: {'name': note.name, 'mode': 'view'}),
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