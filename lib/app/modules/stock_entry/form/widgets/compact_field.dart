import 'package:flutter/material.dart';

/// Generic compact icon + label + value tile used on the Details tab.
/// Step 2 — extracted from StockEntryFormScreen._buildCompactField().
class CompactField extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback? onTap;

  const CompactField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(value ?? '-',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: content,
    );
  }
}
