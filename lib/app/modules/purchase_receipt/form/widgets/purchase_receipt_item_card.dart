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
    final cs = Theme.of(context).colorScheme;

    // 1. Resolve Target Quantity via Controller Map
    double targetQty = controller.getOrderedQty(item.purchaseOrderItem);
    if (targetQty == 0) targetQty = item.purchaseOrderQty ?? 0.0;

    // 2. Calculate Progress
    final double currentQty = item.qty;
    final double percent =
        (targetQty > 0) ? (currentQty / targetQty).clamp(0.0, 1.0) : 0.0;
    final bool isCompleted = percent >= 1.0;
    final bool hasOverReceipt = currentQty > targetQty && targetQty > 0;

    return Obx(() {
      final isHighlighted =
          controller.recentlyAddedItemName.value == item.name;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isHighlighted
              ? cs.tertiaryContainer.withValues(alpha: 0.4)
              : cs.surface,
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: cs.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: InkWell(
            onTap: () => controller.editItem(item),
            child: Column(
              children: [
                // Header Section
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    border: Border(
                        bottom: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.itemCode,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: cs.onSurface,
                                fontFamily: 'monospace',
                                fontFeatures: const [
                                  FontFeature.slashedZero()
                                ],
                              ),
                            ),
                            if (item.itemName != null &&
                                item.itemName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  item.itemName!,
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit,
                                size: 20, color: cs.primary),
                            onPressed: () => controller.editItem(item),
                          ),
                          Obx(() {
                            if ((controller.purchaseReceipt.value
                                        ?.items.length ??
                                    0) >
                                1) {
                              return IconButton(
                                icon: Icon(Icons.delete,
                                    size: 20, color: cs.error),
                                onPressed: () {
                                  if (item.name != null) {
                                    controller.deleteItem(item.name!);
                                  }
                                },
                              );
                            }
                            return const SizedBox.shrink();
                          }),
                        ],
                      ),
                    ],
                  ),
                ),

                // Content Section
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8.0,
                              runSpacing: 8.0,
                              children: [
                                if (item.batchNo != null &&
                                    item.batchNo!.isNotEmpty)
                                  _buildBadge(
                                    context: context,
                                    icon: Icons.qr_code,
                                    label: item.batchNo!,
                                    color: cs.tertiary,
                                    containerColor: cs.tertiaryContainer,
                                    isMono: true,
                                  ),
                                if (item.rack != null &&
                                    item.rack!.isNotEmpty)
                                  _buildBadge(
                                    context: context,
                                    icon: Icons.shelves,
                                    label: item.rack!,
                                    color: cs.secondary,
                                    containerColor: cs.secondaryContainer,
                                  ),
                                if (item.warehouse.isNotEmpty)
                                  _buildBadge(
                                    context: context,
                                    icon: Icons.store,
                                    label: item.warehouse,
                                    color: cs.primary,
                                    containerColor: cs.primaryContainer,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            NumberFormat('#,##0.##').format(item.qty),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: cs.onSurface),
                          ),
                        ],
                      ),

                      if (targetQty > 0) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'PO Qty: ${NumberFormat('#,##0.##').format(targetQty)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(percent * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isCompleted
                                    ? cs.primary
                                    : cs.tertiary,
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
                          progressColor: hasOverReceipt
                              ? cs.error
                              : (isCompleted ? cs.primary : cs.tertiary),
                          backgroundColor: cs.surfaceContainerHighest,
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
    });
  }

  Widget _buildBadge({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Color containerColor,
    bool isMono = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: containerColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                fontFamily: isMono ? 'monospace' : null,
                fontFeatures:
                    isMono ? const [FontFeature.slashedZero()] : null,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
