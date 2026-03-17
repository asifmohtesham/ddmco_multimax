import 'package:flutter/material.dart';

/// A single FROM or TO warehouse column inside [EntryTypeCard].
/// Step 3 — eliminates the duplicated FROM / TO inline blocks.
class WarehouseColumn extends StatelessWidget {
  final String label;
  final String? selectedValue;
  final String fallbackText;
  final bool isActive;
  final bool isEditable;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment labelAlignment;
  final VoidCallback? onTap;

  const WarehouseColumn({
    super.key,
    required this.label,
    required this.selectedValue,
    required this.fallbackText,
    required this.isActive,
    required this.isEditable,
    required this.crossAxisAlignment,
    required this.labelAlignment,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: isActive ? 1.0 : 0.4,
        child: IgnorePointer(
          ignoring: !(isEditable && isActive),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: (isEditable && isActive) ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Column(
                crossAxisAlignment: crossAxisAlignment,
                children: [
                  Row(
                    mainAxisAlignment: labelAlignment,
                    children: [
                      if (isEditable && isActive && labelAlignment == MainAxisAlignment.end) ...[
                        Icon(Icons.edit, size: 10, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.bold),
                      ),
                      if (isEditable && isActive && labelAlignment == MainAxisAlignment.start) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.edit, size: 10, color: Colors.grey.shade500),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedValue ?? fallbackText,
                    textAlign: crossAxisAlignment == CrossAxisAlignment.end
                        ? TextAlign.end
                        : TextAlign.start,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.black87 : Colors.grey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
