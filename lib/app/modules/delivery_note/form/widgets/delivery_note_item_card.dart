import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/models/delivery_note_model.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/animated_expand_icon.dart';

class DeliveryNoteItemCard extends StatelessWidget {
  final DeliveryNoteItem item;
  final DeliveryNoteFormController controller = Get.find();

  DeliveryNoteItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isExpanded = controller.expandedItemCode.value == item.itemCode;
      
      // Check if this item was recently added/updated to highlight it
      final isRecentlyAdded = controller.recentlyAddedItemCode.value == item.itemCode &&
          (controller.recentlyAddedSerial.value == (item.customInvoiceSerialNumber ?? '0') || 
           controller.recentlyAddedSerial.value.isEmpty);

      return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        // margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isRecentlyAdded ? Colors.yellow.shade100 : Colors.white,
          // borderRadius: BorderRadius.circular(4.0),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    TextSpan(
                      text: ': ${item.itemName ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              subtitle: Text(item.batchNo ?? '', style: const TextStyle(fontFamily: 'monospace')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
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
                                _buildInfoColumn('Rack', item.rack?.toString() ?? 'N/A'),
                                _buildInfoColumn('Quantity', NumberFormat('#,##0.##').format(item.qty)),
                                _buildInfoColumn('UoM', item.uom ?? 'N/A'),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
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

  Widget _buildInfoColumn(String title, String value) {
    // Apply monospace to Rack code
    final bool isMono = title == 'Rack'; 
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontFamily: isMono ? 'monospace' : null, // Conditionally apply monospace
          ),
        ),
      ],
    );
  }
}
