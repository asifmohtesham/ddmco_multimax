import 'package:flutter/material.dart';

/// A `label ───── value` summary row for DocType form totals sections
/// (e.g. Total Quantity, Grand Total).
///
/// Consolidates the private `_buildSummaryRow` helpers that were copy-pasted
/// across Delivery Note, Material Request and Purchase Receipt. The latter two
/// hard-coded `Colors.grey` / `Colors.black87`, which broke in dark mode — this
/// canonical version is token-based ([ColorScheme]) and themes correctly.
class DocSummaryRow extends StatelessWidget {
  const DocSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.isBold = false,
  });

  final String label;
  final String value;

  /// Emphasised row (e.g. Grand Total): larger, bolder, full-contrast value.
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
              // onSurfaceVariant, not onSurface @ 0.6 alpha — the alpha
              // composite fell to 3.99:1 (sub-AA) on DocSectionCard's
              // surfaceContainerLow fill in light mode.
              color: isBold ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
