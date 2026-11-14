import 'package:flutter/material.dart';

/// A read-only `label ───── value` row for DocType form detail sections, with
/// an optional copy-to-clipboard affordance on the value.
///
/// Extracted from the Item form's private `_buildDetailRow`. Pair it with
/// [DocSectionCard] and a [Divider] between rows, mirroring the original usage.
class DocDetailRow extends StatelessWidget {
  const DocDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isCopyable = false,
    this.onCopy,
  });

  final String label;
  final String value;

  /// When true (and [onCopy] is set) a small copy icon trails the value.
  final bool isCopyable;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                if (isCopyable && onCopy != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onCopy,
                    child: Icon(Icons.copy, size: 14, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
