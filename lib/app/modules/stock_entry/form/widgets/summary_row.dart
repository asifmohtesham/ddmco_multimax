import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A simple label / value row used in the Details tab summary card.
/// Step 2 — extracted from StockEntryFormScreen._buildSummaryRow().
class SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: scheme.textMuted, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
              color: isBold ? scheme.text : scheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
