import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

class StockEntryItemCard extends StatelessWidget {
  final StockEntryItem item;
  final int index;
  final StockEntryFormController controller = Get.find();

  StockEntryItemCard({super.key, required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
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
          onTap: () => controller.editItem(item, index),
          child: Column(
            children: [
              // Header Section: Code, Name, Actions
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
                          if (item.itemName != null)
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
                    // Actions: Edit and Delete
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                          onPressed: () => controller.editItem(item, index),
                          tooltip: 'Edit Item',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                          onPressed: () => controller.deleteItem(index),
                          tooltip: 'Remove Item',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content Section: Badges & Flow & Qty
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Wrap(
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
                            if (item.customVariantOf != null && item.customVariantOf!.isNotEmpty)
                              _buildBadge(
                                  icon: Icons.style,
                                  label: item.customVariantOf!,
                                  color: Colors.teal
                              ),
                          ],
                        ),
                        Text(
                          item.qty.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black),
                        ),
                      ],
                    ),


                    const SizedBox(height: 12),

                    // Visual Warehouse Flow
                    Obx(() {
                      final type = controller.selectedStockEntryType.value;
                      final showSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
                      final showTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

                      if (!showSource && !showTarget) return const SizedBox.shrink();

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              if (showSource)
                                Expanded(
                                  child: _buildLocationBlock(
                                    label: 'FROM',
                                    warehouse: item.sWarehouse,
                                    rack: item.rack,
                                    color: Colors.orange,
                                    icon: Icons.outbond,
                                  ),
                                ),

                              if (showSource && showTarget)
                                Container(
                                  width: 1,
                                  color: Colors.grey.shade200,
                                  child: Center(
                                    child: Container(
                                      decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.grey.shade300)
                                      ),
                                      child: const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                                    ),
                                  ),
                                ),

                              if (showTarget)
                                Expanded(
                                  child: _buildLocationBlock(
                                    label: 'TO',
                                    warehouse: item.tWarehouse,
                                    rack: item.toRack,
                                    color: Colors.green,
                                    icon: Icons.move_to_inbox,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
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
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.shade900,
              fontWeight: FontWeight.w600,
              fontFamily: isMono ? 'monospace' : null,
              fontFeatures: isMono ? [const FontFeature.slashedZero()] : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBlock({
    required String label,
    required String? warehouse,
    required String? rack,
    required MaterialColor color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color.shade700),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.shade700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (warehouse != null)
            Text(
              warehouse,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (rack != null && rack.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.shade200),
              ),
              child: Text(
                rack,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: color.shade900,
                  fontFeatures: [const FontFeature.slashedZero()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}