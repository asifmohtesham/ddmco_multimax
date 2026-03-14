import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_controller.dart';

/// A quantity input row with press-and-hold increment / decrement buttons.
///
/// Implemented as a pure [GetView]-style [StatelessWidget].  All mutable
/// state (the repeat [Timer]) lives inside [QuantityInputController], which
/// is scoped per button via a unique tag and deleted automatically when the
/// widget leaves the tree.
class QuantityInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String label;
  final bool isReadOnly;

  /// Additional context shown as a badge, e.g. "Available: 50".
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
  State<QuantityInputWidget> createState() => _QuantityInputWidgetState();
}

class _QuantityInputWidgetState extends State<QuantityInputWidget> {
  Timer? _repeatTimer;

  void _startRepeat(VoidCallback action) {
    // Immediate feedback on press
    action();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 150), (_) => action());
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final borderColor = Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row: Label + Info Badge
        if (widget.label.isNotEmpty || (widget.infoText != null && widget.infoText!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (widget.infoText != null && widget.infoText!.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.infoText!,
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

        // ── Input row ─────────────────────────────────────────────────
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: widget.isReadOnly ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: widget.isReadOnly
                ? []
                : [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // ── Text field ──────────────────────────────────────────
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  readOnly: widget.isReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: widget.isReadOnly ? Colors.grey.shade600 : Colors.black87,
                  ),
                  onChanged: widget.onChanged,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16),
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
              if (!widget.isReadOnly) ...[
                // Vertical Divider
                Container(width: 1, height: 32, color: Colors.grey.shade200),

                // Decrement Button
                _buildActionButton(
                  icon: Icons.remove,
                  onPressed: widget.onDecrement,
                  color: Colors.grey.shade700,
                ),
                Container(
                    width: 1, height: 32, color: Colors.grey.shade200),
                _QtyActionButton(
                  tag: '${hashCode}_inc',
                  icon: Icons.add,
                  onPressed: widget.onIncrement,
                  color: primaryColor,
                  borderRadius:
                      const BorderRadius.horizontal(right: Radius.circular(11)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
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
        onTapDown: (_) {
          HapticFeedback.lightImpact();
          _startRepeat(onPressed);
        },
        onTapUp: (_) => _stopRepeat(),
        onTapCancel: _stopRepeat,
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
