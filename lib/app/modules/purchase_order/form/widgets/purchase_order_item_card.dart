import 'dart:ui'; // Added
import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';

class PurchaseOrderItemCard extends StatelessWidget {
  final PurchaseOrderItem item;

  const PurchaseOrderItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final percent = (item.qty > 0) ? (item.receivedQty / item.qty).clamp(0.0, 1.0) : 0.0;
    final isReceived = percent >= 1.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
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
                      fontFamily: 'monospace',
                      fontFeatures: [FontFeature.slashedZero()], // Added
                    ),
                  ),
                ),
                Text(
                  '${item.qty.toStringAsFixed(2)} ${item.uom ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (item.itemName.isNotEmpty)
              Text(item.itemName, style: TextStyle(color: Colors.grey[600], fontSize: 13)),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Received: ${item.receivedQty.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                Text('${(percent * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            LinearPercentIndicator(
              lineHeight: 6.0,
              percent: percent,
              backgroundColor: Colors.grey.shade200,
              progressColor: isReceived ? Colors.green : Colors.orange,
              barRadius: const Radius.circular(3),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Rate: ${item.rate.toStringAsFixed(2)} | Amt: ${item.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}