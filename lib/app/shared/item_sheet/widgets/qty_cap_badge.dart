import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../qty_cap_delegate.dart';
import '../../../modules/global_widgets/balance_chip.dart';

/// Tappable pill badge that shows the active qty cap from [QtyCapDelegate.qtyInfoText].
/// Tapping it shows a breakdown dialog built from [QtyCapDelegate.qtyInfoTooltip].
/// Renders nothing when [qtyInfoText] returns null.
class QtyCapBadge extends StatelessWidget {
  final QtyCapDelegate controller;
  final Color color;

  const QtyCapBadge({
    super.key,
    required this.controller,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final label = controller.qtyInfoText;
      if (label == null) return const SizedBox.shrink();

      // qtyInfoTooltip is an RxnString — the Rx object is never null;
      // inspect .value to decide whether the badge is tappable.
      final canTap = controller.qtyInfoTooltip.value != null;

      // Extract the balance number from the label (e.g. "PO Qty: 600")
      // Since BalanceChip expects a double, we'll parse it. If parsing fails,
      // we'll just fall back to 0 and not use BalanceChip directly, OR
      // wait, BalanceChip expects a double and formats it.
      // QtyCapBadge receives a fully formatted string like "PO Qty: 600".
      // It might be easier to just change QtyCapBadge to use BalanceChip but wait,
      // BalanceChip expects `double balance` and `String prefix`.
      // The `qtyInfoText` is already formatted. 
      // Let's modify BalanceChip to accept an optional `String? textOverride`.
      
      // But actually, it's easier to just style QtyCapBadge identical to BalanceChip!
      // I'll just change QtyCapBadge to use the exact same styling as the new BalanceChip.
      
      return BalanceChip(
        isLoading: false,
        color: color,
        textOverride: label,
        margin: EdgeInsets.zero,
        onTap: canTap ? () => _showBreakdown(context) : null,
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
