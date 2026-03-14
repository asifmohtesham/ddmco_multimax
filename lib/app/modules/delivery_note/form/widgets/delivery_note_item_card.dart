import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';

class DeliveryNoteItemCard extends StatelessWidget {
  final DeliveryNoteItem item;
  final DeliveryNoteFormController controller = Get.find();

  DeliveryNoteItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isExpanded = controller.expandedItemCode.value == item.itemCode;
      final isRecentlyAdded =
          controller.recentlyAddedItemCode.value == item.itemCode &&
              (controller.recentlyAddedSerial.value ==
                      (item.customInvoiceSerialNumber ?? '0') ||
                  controller.recentlyAddedSerial.value.isEmpty);

      // Show a loading spinner on this card's edit button while the controller
      // is fetching batch/rack data specifically for THIS item.
      // We use loadingForItemName (set before the async fetch begins) rather
      // than currentItemCode (set only after the fetch completes inside
      // initBottomSheet) so the spinner appears immediately on tap and never
      // leaks onto a previously-edited card.
      final isThisItemLoading =
          controller.loadingForItemName.value != null &&
          controller.loadingForItemName.value == item.name;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isRecentlyAdded ? Colors.yellow.shade100 : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: .2),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            ListTile(
              title: RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(
                      text: item.itemCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'ShureTechMono',
                        fontFeatures: [FontFeature.slashedZero()],
                      ),
                    ),
                    if (item.itemName != null && item.itemName!.isNotEmpty)
                      TextSpan(
                        text: ': ${item.itemName}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ShureTechMono'),
                      ),
                  ],
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.batchNo != null && item.batchNo!.isNotEmpty)
                    Text(
                      item.batchNo!,
                      style: const TextStyle(
                        fontFamily: 'ShureTechMono',
                        fontFeatures: [FontFeature.slashedZero()],
                      ),
                    ),
                  // variant_of badge
                  if (item.customVariantOf != null &&
                      item.customVariantOf!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: Colors.blueGrey.shade200, width: 0.5),
                        ),
                        child: Text(
                          item.customVariantOf!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade700,
                            fontFamily: 'ShureTechMono',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Edit button — shows spinner while loading batch data for
                  // this specific item. Disabled during loading to prevent
                  // double-taps.
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: isThisItemLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: controller.isLoadingItemEdit.value
                                ? null  // disable all edit buttons while any load is in progress
                                : () => controller.editItem(item),
                          ),
                  ),
                  AnimatedExpandIcon(isExpanded: isExpanded),
                ],
              ),
              onTap: () => controller.toggleExpand(item.itemCode),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: !isExpanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                      child: Column(
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInfoColumn('Rack',
                                  item.rack?.toString() ?? 'N/A'),
                              _buildInfoColumn(
                                  'Quantity',
                                  NumberFormat('#,##0.##')
                                      .format(item.qty)),
                              _buildInfoColumn('UOM', item.uom ?? 'N/A'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                onPressed: () =>
                                    controller.confirmAndDeleteItem(item),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildInfoColumn(String title, String value) {
    final bool isMono = title == 'Rack';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontFamily: isMono ? 'monospace' : null,
            fontFeatures:
                isMono ? [const FontFeature.slashedZero()] : null,
          ),
        ),
      ],
    );
  }
}
