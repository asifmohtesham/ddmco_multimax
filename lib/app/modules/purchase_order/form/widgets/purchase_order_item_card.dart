import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class PurchaseOrderItemCard extends StatelessWidget {
  final PurchaseOrderItem item;
  final int index;
  // Access controller if needed for future edit actions
  final PurchaseOrderFormController controller = Get.find();

  PurchaseOrderItemCard({
    super.key,
    required this.item,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate Reception Progress
    final double orderedQty = item.qty;
    final double receivedQty = item.receivedQty;
    final double percent = (orderedQty > 0) ? (receivedQty / orderedQty).clamp(0.0, 1.0) : 0.0;
    final bool isReceived = percent >= 1.0;

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
        child: Column(
          children: [
            // 1. Header Section
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                        if (item.itemName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              item.itemName,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Placeholder for future actions (Edit/Delete) if implemented in Controller
                ],
              ),
            ),

            // 2. Content Section
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quantity and Amount Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rate: ${NumberFormat('#,##0.00').format(item.rate)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Amt: ${NumberFormat('#,##0.00').format(item.amount)}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade700),
                          ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            NumberFormat('#,##0.##').format(item.qty),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.uom ?? '',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Progress Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isReceived ? 'Fully Received' : 'Received: ${NumberFormat('#,##0.##').format(receivedQty)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: isReceived ? Colors.green : Colors.grey.shade600,
                            fontWeight: FontWeight.w600
                        ),
                      ),
                      Text(
                        "${(percent * 100).toInt()}%",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isReceived ? Colors.green : Colors.orange,
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
                    progressColor: isReceived ? Colors.green : Colors.orange,
                    backgroundColor: Colors.grey.shade100,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}