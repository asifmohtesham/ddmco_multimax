import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../item_sheet_controller_base.dart';

/// Tappable pill badge that shows the active qty cap from [ItemSheetControllerBase.qtyInfoText].
/// Tapping it shows a breakdown dialog built from [ItemSheetControllerBase.qtyInfoTooltip].
/// Renders nothing when [qtyInfoText] returns null.
class QtyCapBadge extends StatelessWidget {
  final ItemSheetControllerBase controller;

  const QtyCapBadge({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final label = controller.qtyInfoText;
      if (label == null) return const SizedBox.shrink();

      // qtyInfoTooltip is an RxnString — the Rx object is never null;
      // inspect .value to decide whether the badge is tappable.
      final canTap = controller.qtyInfoTooltip.value != null;

      return GestureDetector(
        onTap: canTap ? () => _showBreakdown(context) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (canTap) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  void _showBreakdown(BuildContext context) {
    // Read the unwrapped String? value from the RxnString.
    final tooltip = controller.qtyInfoTooltip.value;
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
