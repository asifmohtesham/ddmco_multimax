import 'dart:ui'; // Added
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

class PackingSlipItemCard extends StatelessWidget {
  final PackingSlipItem item;
  final int index;
  final PackingSlipFormController controller = Get.find();

  PackingSlipItemCard({super.key, required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final requiredQty = controller.getRequiredQty(item.dnDetail) ?? 0.0;
    final percent = (requiredQty > 0) ? (item.qty / requiredQty).clamp(0.0, 1.0) : 0.0;
    final isComplete = percent >= 1.0;

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
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: isComplete ? Colors.green.shade50 : Colors.orange.shade50,
                      child: Icon(
                        isComplete ? Icons.check : Icons.inventory_2_outlined,
                        size: 14,
                        color: isComplete ? Colors.green.shade700 : Colors.orange.shade700,
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
                              fontFeatures: [FontFeature.slashedZero()], // Added
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
                    if (item.customInvoiceSerialNumber != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Text(
                          '#${item.customInvoiceSerialNumber}',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontFeatures: [const FontFeature.slashedZero()], // Added
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (requiredQty > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Packed: ${NumberFormat('#,##0.##').format(item.qty)} / ${NumberFormat('#,##0.##').format(requiredQty)} ${item.uom}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${(percent * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isComplete ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearPercentIndicator(
                        lineHeight: 6.0,
                        percent: percent,
                        backgroundColor: Colors.grey.shade200,
                        progressColor: isComplete ? Colors.green : Colors.orange,
                        barRadius: const Radius.circular(3),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                    ],

                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        if (item.batchNo.isNotEmpty)
                          _buildBadge(Icons.qr_code, item.batchNo, Colors.purple),
                        if (item.netWeight > 0)
                          _buildBadge(Icons.scale, '${item.netWeight} kg', Colors.blueGrey),
                        if (item.customVariantOf != null)
                          _buildBadge(Icons.style, item.customVariantOf!, Colors.teal),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, MaterialColor color) {
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
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.shade900,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace', // Added
              fontFeatures: [const FontFeature.slashedZero()], // Added
            ),
          ),
        ],
      ),
    );
  }
}