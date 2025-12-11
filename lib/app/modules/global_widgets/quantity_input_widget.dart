import 'package:flutter/material.dart';

class QuantityInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String label;
  final bool isReadOnly;
  final String? helperText;
  final Color color;
  final Function(String)? onChanged;

  const QuantityInputWidget({
    super.key,
    required this.controller,
    required this.onIncrement,
    required this.onDecrement,
    this.label = 'Quantity',
    this.isReadOnly = false,
    this.helperText,
    this.color = Colors.black87,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.grey.shade50 : Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  readOnly: isReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: '0',
                    helperText: helperText,
                    helperStyle: TextStyle(
                      fontSize: 11,
                      color: (helperText != null && helperText!.contains('Available'))
                          ? Colors.orange
                          : Colors.grey,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    final qty = double.tryParse(value);
                    if (qty == null || qty <= 0) return 'Invalid';
                    return null;
                  },
                ),
              ),

              if (!isReadOnly) ...[
                // Vertical Divider
                Container(
                  height: 48,
                  width: 1,
                  color: Colors.grey.shade300,
                ),
                _buildButton(
                  icon: Icons.remove,
                  onPressed: onDecrement,
                ),
                // Vertical Divider between buttons
                Container(
                  height: 48,
                  width: 1,
                  color: Colors.grey.shade300,
                ),
                _buildButton(
                  icon: Icons.add,
                  onPressed: onIncrement,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButton({required IconData icon, required VoidCallback onPressed}) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(0), // Squared corners for middle buttons if needed, or keeping default
          onTap: onPressed,
          child: Icon(icon, color: Colors.grey.shade700),
        ),
      ),
    );
  }
}