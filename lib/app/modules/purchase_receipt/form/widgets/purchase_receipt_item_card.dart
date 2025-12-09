import 'dart:ui'; // Added
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
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => controller.editItem(item),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (poQty > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularPercentIndicator(
                            radius: 24.0,
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
                          const SizedBox(height: 4),
                          Text(
                            "of ${NumberFormat.compact().format(poQty)}",
                            style: const TextStyle(fontSize: 9, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey.shade100,
                        child: Text(
                          '#${index + 1}',
                          style: const TextStyle(fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.itemCode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  fontFamily: 'monospace',
                                  fontFeatures: [FontFeature.slashedZero()], // Added
                                ),
                              ),
                            ),
                            if (item.rate != null)
                              Text(
                                '\$${item.rate!.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.black87),
                              ),
                          ],
                        ),
                        if (item.itemName != null && item.itemName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0, bottom: 6.0),
                            child: Text(
                              item.itemName!,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (item.batchNo != null && item.batchNo!.isNotEmpty)
                              _buildMiniBadge(Icons.qr_code, item.batchNo!, Colors.purple),

                            if (item.rack != null && item.rack!.isNotEmpty)
                              _buildMiniBadge(Icons.shelves, item.rack!, Colors.blueGrey),

                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
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

                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String text, MaterialColor color) {
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
              fontFamily: 'monospace',
              fontFeatures: [const FontFeature.slashedZero()], // Added
            ),
          ),
        ],
      ),
    );
  }
}