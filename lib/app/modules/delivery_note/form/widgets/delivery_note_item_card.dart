import 'dart:ui'; // Added
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
    final theme = Theme.of(context);

    return Obx(() {
      final isExpanded = controller.expandedItemCode.value == item.itemCode;

      final isRecentlyAdded = controller.recentlyAddedItemCode.value == item.itemCode &&
          (controller.recentlyAddedSerial.value == (item.customInvoiceSerialNumber ?? '0') ||
              controller.recentlyAddedSerial.value.isEmpty);

      return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isRecentlyAdded
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: .2),
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
                    TextSpan(
                      text: ': ${item.itemName ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'ShureTechMono',
                      ),
                    ),
                  ],
                ),
              ),
              subtitle: Text(
                item.batchNo ?? '',
                style: const TextStyle(
                  fontFamily: 'ShureTechMono',
                  fontFeatures: [FontFeature.slashedZero()],
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: theme.colorScheme.primary),
                    onPressed: () => controller.editItem(item),
                  ),
                  AnimatedExpandIcon(isExpanded: isExpanded),
                ],
              ),
              onTap: () => controller.toggleExpand(item.itemCode),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Container(
                child: !isExpanded
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                        child: Column(
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildInfoColumn(context, 'Rack', item.rack?.toString() ?? 'N/A'),
                                _buildInfoColumn(context, 'Quantity', NumberFormat('#,##0.##').format(item.qty)),
                                _buildInfoColumn(context, 'UOM', item.uom ?? 'N/A'),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.delete, color: theme.colorScheme.error),
                                  onPressed: () => controller.confirmAndDeleteItem(item),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildInfoColumn(BuildContext context, String title, String value) {
    final theme = Theme.of(context);
    final bool isMono = title == 'Rack';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontFamily: isMono ? 'monospace' : null,
            fontFeatures: isMono ? [const FontFeature.slashedZero()] : null,
          ),
        ),
      ],
    );
  }
}
