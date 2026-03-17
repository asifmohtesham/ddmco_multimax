import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Step 1 — extracted from the static `_balanceChip()` method.
/// Displays a stock/batch balance below a validated field.
/// Shows a spinner while [isLoading] is true, hides when [balance] <= 0.
class BalanceChip extends StatelessWidget {
  final RxDouble balance;
  final RxBool isLoading;
  final String label;
  final Color color;

  const BalanceChip({
    super.key,
    required this.balance,
    required this.isLoading,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (isLoading.value) {
        return Padding(
          padding: const EdgeInsets.only(top: 6.0, left: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: color),
              ),
              const SizedBox(width: 6),
              Text(
                'Fetching $label...',
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
        );
      }
      if (balance.value <= 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6.0, left: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              '$label: ${balance.value % 1 == 0 ? balance.value.toInt() : balance.value.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    });
  }
}
