import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

class DeliveryNoteItemCard extends StatelessWidget {
  final DeliveryNoteItem item;

  /// 0-based position within a POS Upload group. When provided, a numbered
  /// CircleAvatar badge is shown to the left of the item code to help
  /// operators identify and locate items at a glance inside a group.
  /// Pass null (default) in the flat / non-POS list to hide the badge.
  final int? index;

  final DeliveryNoteFormController controller = Get.find();

  DeliveryNoteItemCard({super.key, required this.item, this.index});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRecentlyAdded =
          controller.recentlyAddedItemCode.value == item.itemCode &&
              (controller.recentlyAddedSerial.value ==
                      (item.customInvoiceSerialNumber ?? '0') ||
                  controller.recentlyAddedSerial.value.isEmpty);

      final isThisItemLoading =
          controller.loadingForItemName.value != null &&
          controller.loadingForItemName.value == item.name;

      final hasBatch = item.batchNo != null && item.batchNo!.isNotEmpty;
      final hasRack  = item.rack   != null && item.rack!.isNotEmpty;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isRecentlyAdded ? Colors.yellow.shade100 : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: .15),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Optional index badge (POS grouped view only) ─────────────
              if (index != null) ...[
                CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.blue.shade50,
                  child: Text(
                    '${index! + 1}',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // ── Left: item identity + metadata ──────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item code + name
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: item.itemCode,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: 'ShureTechMono',
                              fontFeatures: [FontFeature.slashedZero()],
                            ),
                          ),
                          if (item.itemName != null &&
                              item.itemName!.isNotEmpty)
                            TextSpan(
                              text: ': ${item.itemName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFamily: 'ShureTechMono',
                              ),
                            ),
                        ],
                      ),
                    ),

                    // variant_of badge — prefixed so it reads naturally
                    if (item.customVariantOf != null &&
                        item.customVariantOf!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: Colors.blueGrey.shade200, width: 0.5),
                        ),
                        child: Text(
                          'Variant of: ${item.customVariantOf!}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade700,
                            fontFamily: 'ShureTechMono',
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 6),

                    // ── Inline metadata row: qty · batch · rack ─────────────
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Qty chip — explicit label removes all ambiguity
                        _MetaChip(
                          icon: Icons.numbers,
                          label: 'Qty: ${NumberFormat('#,##0.##').format(item.qty)}',
                          color: Colors.indigo,
                        ),

                        // Batch chip
                        if (hasBatch)
                          _MetaChip(
                            icon: Icons.label_outline,
                            label: 'Batch: ${item.batchNo!}',
                            color: Colors.blue,
                          ),

                        // Rack chip
                        if (hasRack)
                          _MetaChip(
                            icon: Icons.shelves,
                            label: 'Rack: ${item.rack!}',
                            color: Colors.teal,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ── Right: edit + delete ─────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Edit / loading spinner
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: isThisItemLoading
                        ? const Padding(
                            padding: EdgeInsets.all(7.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.edit,
                                color: Colors.blue, size: 20),
                            onPressed: controller.isLoadingItemEdit.value
                                ? null
                                : () => controller.editItem(item),
                          ),
                  ),
                  // Delete
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () => controller.confirmAndDeleteItem(item),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Compact icon+label chip used for qty, batch and rack metadata.
/// The [label] should always include a human-readable prefix
/// (e.g. 'Qty: 5', 'Batch: B-001') so the value is self-explanatory
/// without relying on the icon alone.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final MaterialColor color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade200, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.shade800,
              fontFamily: 'ShureTechMono',
              fontFeatures: const [FontFeature.slashedZero()],
            ),
          ),
        ],
      ),
    );
  }
}
