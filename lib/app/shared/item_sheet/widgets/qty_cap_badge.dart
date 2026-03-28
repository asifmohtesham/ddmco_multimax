import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../item_sheet_controller_base.dart';

/// Displays a live "Max: N pcs" pill badge next to the Qty field label.
/// Tapping it shows a breakdown dialog from [controller.qtyInfoTooltip].
/// Returns [SizedBox.shrink] when no cap is active ([qtyInfoText] is null).
class QtyCapBadge extends StatelessWidget {
  final ItemSheetControllerBase controller;

  const QtyCapBadge({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final label = controller.qtyInfoText;
      if (label == null) return const SizedBox.shrink();

      final hasTooltip = controller.qtyInfoTooltip != null;

      return GestureDetector(
        onTap: hasTooltip ? () => _showBreakdown(context) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withOpacity(0.85),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                  Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasTooltip) ...[
                const SizedBox(width: 3),
                Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimaryContainer
                      .withOpacity(0.7),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  void _showBreakdown(BuildContext context) {
    final tooltip = controller.qtyInfoTooltip;
    if (tooltip == null) return;

    Get.dialog(
      AlertDialog(
        title: const Text('Qty Cap Breakdown'),
        content: Text(tooltip),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}