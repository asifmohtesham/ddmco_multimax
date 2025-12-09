import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

class PurchaseReceiptItemCard extends StatelessWidget {
  final PurchaseReceiptItem item;
  final int index;
  final PurchaseReceiptFormController controller = Get.find();

  PurchaseReceiptItemCard({
    super.key,
    required this.item,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final double poQty = item.purchaseOrderQty ?? 0.0;
    final double currentQty = item.qty;

    final double percent = (poQty > 0) ? (currentQty / poQty).clamp(0.0, 1.0) : 0.0;
    final bool isCompleted = percent >= 1.0;
    final bool hasOverReceipt = currentQty > poQty && poQty > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: InkWell(
          onTap: () => controller.editItem(item),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Leading: Progress Indicator or Index
                if (poQty > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularPercentIndicator(
                          radius: 22.0,
                          lineWidth: 4.0,
                          percent: percent,
                          center: isCompleted && !hasOverReceipt
                              ? const Icon(Icons.check, size: 16, color: Colors.green)
                              : Text(
                            "${(percent * 100).toInt()}%",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: hasOverReceipt ? Colors.orange : Colors.black87,
                            ),
                          ),
                          progressColor: hasOverReceipt ? Colors.orange : Colors.green,
                          backgroundColor: Colors.grey.shade100,
                          circularStrokeCap: CircularStrokeCap.round,
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.blue.shade50,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(fontSize: 14, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                // Middle: Item Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: 'monospace',
                          fontFeatures: [FontFeature.slashedZero()],
                        ),
                      ),
                      if (item.itemName != null && item.itemName!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0, bottom: 6.0),
                          child: Text(
                            item.itemName!,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                      // Badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (item.batchNo != null && item.batchNo!.isNotEmpty)
                            _buildBadge(Icons.qr_code, item.batchNo!, Colors.purple, isMono: true),

                          if (item.rack != null && item.rack!.isNotEmpty)
                            _buildBadge(Icons.shelves, item.rack!, Colors.blueGrey),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade100),
                            ),
                            child: Text(
                              'Qty: ${NumberFormat('#,##0.##').format(item.qty)}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Trailing: Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                      onPressed: () => controller.editItem(item),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                    ),
                    // Conditional Delete
                    Obx(() {
                      if ((controller.purchaseReceipt.value?.items.length ?? 0) > 1) {
                        return IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                          onPressed: () {
                            if (item.name != null || item.name == null) { // Handle both
                              // Use the unique logic from controller
                              controller.deleteItem(item.name ?? '');
                            }
                          },
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text, MaterialColor color, {bool isMono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.shade800,
              fontFamily: isMono ? 'monospace' : null,
              fontFeatures: isMono ? [const FontFeature.slashedZero()] : null,
            ),
          ),
        ],
      ),
    );
  }
}