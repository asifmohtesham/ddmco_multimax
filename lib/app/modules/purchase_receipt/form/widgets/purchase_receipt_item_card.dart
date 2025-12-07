import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/models/purchase_receipt_model.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey.shade200,
              child: Text(
                '${index + 1}',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.batchNo != null && item.batchNo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Batch: ${item.batchNo}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                if (item.purchaseOrderQty != null && item.purchaseOrderQty! > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (item.qty / item.purchaseOrderQty!).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                        item.qty > item.purchaseOrderQty! ? Colors.red : Colors.green
                    ),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.qty} / ${item.purchaseOrderQty} Received',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ]
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              constraints: const BoxConstraints(),
              onPressed: () => controller.editItem(item),
            ),
          ),
          Padding(
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String title, String value) {
    final bool isMono = title == 'Rack' || title == 'Quantity';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFamily: isMono ? 'monospace' : null,
          ),
        ),
      ],
    );
  }
}