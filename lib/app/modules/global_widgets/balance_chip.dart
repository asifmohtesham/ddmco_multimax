import 'package:flutter/material.dart';

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

  const BalanceChip({
    super.key,
    required this.balance,
    required this.isLoading,
    required this.color,
    this.prefix = 'Avail:',
    this.forceShow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 4.0, left: 4.0),
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

    if (!forceShow && balance <= 0) return const SizedBox.shrink();

    final label = balance % 1 == 0
        ? balance.toInt().toString()
        : balance.toString();

    return Padding(
      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          '$prefix $label',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
