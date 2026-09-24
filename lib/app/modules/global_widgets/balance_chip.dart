import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A small chip that displays an available-balance figure below a field.
///
/// Renders a loading spinner while [isLoading] is true.  When loading is
/// done, renders nothing if [balance] <= 0 and [forceShow] is false;
/// otherwise renders a pill with the balance value.
///
/// This widget is intentionally stateless and free of Rx / GetX so that
/// callers can wrap it in their own `Obx` with precisely-scoped reactivity.
///
/// Example:
/// ```dart
/// Obx(() => BalanceChip(
///   balance: controller.bsBatchBalance.value,
///   isLoading: controller.isLoadingBatchBalance.value,
///   color: Colors.purple,
///   prefix: 'Batch Qty:',
///   forceShow: controller.bsIsBatchValid.value,
/// ))
/// ```
class BalanceChip extends StatelessWidget {
  /// The balance value to display.
  final double balance;

  /// When true, a spinner is shown instead of the chip.
  final bool isLoading;

  /// Accent colour used for both the spinner and the chip border/text.
  final Color color;

  /// Label prepended to the balance figure, e.g. `'Batch Qty:'`.
  final String prefix;

  /// When true the chip is shown even if [balance] is 0 or negative.
  /// Useful while a validation round-trip is in progress and the
  /// balance has not yet been populated.
  final bool forceShow;

  /// Margin around the chip.
  final EdgeInsetsGeometry margin;

  /// Optional callback for tapping the chip. If provided, an info icon is shown.
  final VoidCallback? onTap;

  /// Optional tooltip message. If provided, an info icon is shown and the chip is wrapped in a Tooltip.
  final String? tooltipMessage;

  /// If provided, this text is rendered directly, ignoring [balance] and [prefix].
  final String? textOverride;

  const BalanceChip({
    super.key,
    this.balance = 0,
    required this.isLoading,
    required this.color,
    this.prefix = 'Avail:',
    this.forceShow = false,
    this.margin = const EdgeInsets.only(top: 4.0, left: 4.0),
    this.onTap,
    this.tooltipMessage,
    this.textOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (isLoading) {
      return Padding(
        padding: margin,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              'Fetching balance...',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      );
    }

    if (textOverride == null && !forceShow && balance <= 0) return const SizedBox.shrink();

    final label = textOverride ?? (balance % 1 == 0
        ? '${prefix} ${balance.toInt()}'
        : '${prefix} $balance');

    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onTap != null || tooltipMessage != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 12,
              color: color,
            ),
          ],
        ],
      ),
    );

    if (tooltipMessage != null) {
      chip = GestureDetector(
        onTap: () {
          Get.dialog(
            AlertDialog(
              title: const Text('Details'),
              content: Text(tooltipMessage!),
              actions: [
                TextButton(
                  onPressed: Get.back,
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        },
        child: chip,
      );
    }

    if (onTap != null) {
      chip = GestureDetector(
        onTap: onTap,
        child: chip,
      );
    }

    return Padding(
      padding: margin,
      child: chip,
    );
  }
}
