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
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final borderColor = Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: label + info badge ──────────────────────────────────
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

        // ── Input row ─────────────────────────────────────────────────
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: isReadOnly
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
                  controller: controller,
                  readOnly: isReadOnly,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color:
                        isReadOnly ? Colors.grey.shade600 : Colors.black87,
                  ),
                  onChanged: onChanged,
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

              // ── Decrement / Increment buttons ────────────────────
              if (!isReadOnly) ...[
                Container(
                    width: 1, height: 32, color: Colors.grey.shade200),
                _QtyActionButton(
                  tag: '${hashCode}_dec',
                  icon: Icons.remove,
                  action: onDecrement,
                  color: Colors.grey.shade700,
                ),
                Container(
                    width: 1, height: 32, color: Colors.grey.shade200),
                _QtyActionButton(
                  tag: '${hashCode}_inc',
                  icon: Icons.add,
                  action: onIncrement,
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

// ──────────────────────────────────────────────────────────────────────────────
// Private press-and-hold button — no StatefulWidget
// ──────────────────────────────────────────────────────────────────────────────

class _QtyActionButton extends StatelessWidget {
  final String tag;
  final IconData icon;
  final VoidCallback action;
  final Color color;
  final BorderRadius? borderRadius;

  const _QtyActionButton({
    required this.tag,
    required this.icon,
    required this.action,
    required this.color,
    this.borderRadius,
  });

  QuantityInputController get _ctrl =>
      Get.put(QuantityInputController(), tag: tag, permanent: false);

  @override
  Widget build(BuildContext context) {
    // GetBuilder with autoRemove:true ensures the controller is deleted
    // and its timer cancelled as soon as the button leaves the tree.
    return GetBuilder<QuantityInputController>(
      tag: tag,
      init: QuantityInputController(),
      autoRemove: true,
      builder: (ctrl) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius ?? BorderRadius.zero,
          onTapDown: (_) => ctrl.startRepeat(action),
          onTapUp: (_) => ctrl.stopRepeat(),
          onTapCancel: ctrl.stopRepeat,
          child: SizedBox(
            width: 56,
            height: double.infinity,
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}
