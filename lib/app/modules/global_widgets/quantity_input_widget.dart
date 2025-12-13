import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QuantityInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String label;
  final bool isReadOnly;
  /// Additional context like "Available: 50" or "Ordered: 10"
  final String? infoText;
  final Color color;
  final Function(String)? onChanged;

  const QuantityInputWidget({
    super.key,
    required this.controller,
    required this.onIncrement,
    required this.onDecrement,
    this.label = 'Quantity',
    this.isReadOnly = false,
    this.infoText,
    this.color = Colors.black87,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final borderColor = Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row: Label + Info Badge
        if (label.isNotEmpty || (infoText != null && infoText!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (infoText != null && infoText!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      infoText!,
                      style: TextStyle(
                        fontSize: 11,
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // Input Control Container
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: isReadOnly ? [] : [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Text Field (Left Side)
              Expanded(
                child: TextFormField(
                  controller: controller,
                  readOnly: isReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isReadOnly ? Colors.grey.shade600 : Colors.black87,
                  ),
                  onChanged: onChanged,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    hintText: '0',
                    isDense: true,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final qty = double.tryParse(value);
                    if (qty == null || qty < 0) return 'Invalid';
                    return null;
                  },
                ),
              ),

              // Buttons Group (Right Side)
              if (!isReadOnly) ...[
                // Vertical Divider
                Container(width: 1, height: 32, color: Colors.grey.shade200),

                // Decrement Button
                _buildActionButton(
                  icon: Icons.remove,
                  onPressed: onDecrement,
                  color: Colors.grey.shade700,
                ),

                // Vertical Divider between buttons
                Container(width: 1, height: 32, color: Colors.grey.shade200),

                // Increment Button
                _buildActionButton(
                  icon: Icons.add,
                  onPressed: onIncrement,
                  color: primaryColor,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(11)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    BorderRadius? borderRadius,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius ?? BorderRadius.zero,
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: SizedBox(
          width: 56,
          height: double.infinity,
          child: Icon(
            icon,
            color: color,
            size: 22,
          ),
        ),
      ),
    );
  }
}