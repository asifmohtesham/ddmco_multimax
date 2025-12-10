import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
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
    // Progress Calculation
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
          child: Column(
            children: [
              // 1. Header Section (Standardized)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.blue.shade50,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(color: Colors.blue.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.itemCode,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                              fontFeatures: [FontFeature.slashedZero()],
                            ),
                          ),
                          if (item.itemName != null && item.itemName!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                item.itemName!,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                          onPressed: () => controller.editItem(item),
                          tooltip: 'Edit Item',
                        ),
                        Obx(() {
                          // Only show delete if there is more than 1 item
                          if ((controller.purchaseReceipt.value?.items.length ?? 0) > 1) {
                            return IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                              onPressed: () {
                                if (item.name != null || item.name == null) {
                                  controller.deleteItem(item.name ?? '');
                                }
                              },
                              tooltip: 'Remove Item',
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ],
                    ),
                  ],
                ),
              ),

              // 2. Content Section
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Badges
                        Expanded(
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: [
                              if (item.batchNo != null && item.batchNo!.isNotEmpty)
                                _buildBadge(
                                    icon: Icons.qr_code,
                                    label: item.batchNo!,
                                    color: Colors.purple,
                                    isMono: true
                                ),
                              if (item.rack != null && item.rack!.isNotEmpty)
                                _buildBadge(
                                    icon: Icons.shelves,
                                    label: item.rack!,
                                    color: Colors.blueGrey
                                ),
                              if (item.warehouse.isNotEmpty)
                                _buildBadge(
                                    icon: Icons.store,
                                    label: item.warehouse,
                                    color: Colors.orange
                                ),
                            ],
                          ),
                        ),
                        // Large Quantity Display
                        Text(
                          NumberFormat('#,##0.##').format(item.qty),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black),
                        ),
                      ],
                    ),

                    // 3. PO Progress Indicator
                    if (poQty > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'PO Qty: ${NumberFormat('#,##0.##').format(poQty)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            "${(percent * 100).toInt()}%",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCompleted ? Colors.green : Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearPercentIndicator(
                        lineHeight: 6.0,
                        percent: percent,
                        padding: EdgeInsets.zero,
                        barRadius: const Radius.circular(3),
                        // Orange if over-received, Green if complete, Blue if partial
                        progressColor: hasOverReceipt ? Colors.orange : (isCompleted ? Colors.green : Colors.blue),
                        backgroundColor: Colors.grey.shade100,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({required IconData icon, required String label, required MaterialColor color, bool isMono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.shade700),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.shade900,
                fontWeight: FontWeight.w600,
                fontFamily: isMono ? 'monospace' : null,
                fontFeatures: isMono ? [const FontFeature.slashedZero()] : null,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}