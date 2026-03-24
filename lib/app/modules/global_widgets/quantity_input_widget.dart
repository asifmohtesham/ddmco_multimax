import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// A quantity input row with press-and-hold increment / decrement buttons.
///
/// [QuantityInputWidget] is a pure [StatelessWidget]; mutable repeat-timer
/// state lives in a [_QtyRepeatController] that is scoped per button via
/// [GetWidget].  GetWidget ties the controller lifecycle to its own
/// [UniqueKey], so the controller is created once and deleted automatically
/// when the button leaves the tree — regardless of how many times the
/// parent rebuilds.
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

  // Stable UniqueKeys — created once per QuantityInputWidget instance.
  // Because these are final fields (not computed in build()), the same
  // key objects survive every rebuild, keeping GetWidget's tag stable.
  final UniqueKey _decKey = UniqueKey();
  final UniqueKey _incKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final borderColor  = Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header Row: Label + Info Badge ────────────────────────────
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
                    color: isReadOnly
                        ? Colors.grey.shade600
                        : Colors.black87,
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

              // ── Buttons Group (Right Side) ───────────────────────────
              if (!isReadOnly) ...[
                Container(
                    width: 1, height: 32, color: Colors.grey.shade200),

                _QtyActionButton(
                  key: _decKey,
                  icon: Icons.remove,
                  onPressed: onDecrement,
                  color: Colors.grey.shade700,
                ),
                Container(
                    width: 1, height: 32, color: Colors.grey.shade200),

                _QtyActionButton(
                  key: _incKey,
                  icon: Icons.add,
                  onPressed: onIncrement,
                  color: primaryColor,
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(11)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// GetxController: owns the repeat Timer for a single button.
// ---------------------------------------------------------------------------
class _QtyRepeatController extends GetxController {
  Timer? _repeatTimer;

  void startRepeat(VoidCallback action) {
    action();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(
        const Duration(milliseconds: 150), (_) => action());
  }

  void stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void onClose() {
    _repeatTimer?.cancel();
    super.onClose();
  }
}

// ---------------------------------------------------------------------------
// GetWidget-based press-and-hold button.
//
// GetWidget<T> is the correct GetX idiom for widget-scoped controllers:
//   • It calls Get.put() exactly once, keyed on instanceKey (the widget key).
//   • It calls Get.delete() automatically when the widget leaves the tree.
//   • The controller is never re-created on parent rebuilds — only on a
//     genuine unmount/remount, which is the desired behaviour here.
//
// The widget receives a UniqueKey from QuantityInputWidget (final field,
// created once per parent instance), so the key — and therefore the
// GetX tag — is stable for the entire lifetime of the parent widget.
// ---------------------------------------------------------------------------
class _QtyActionButton extends GetWidget<_QtyRepeatController> {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final BorderRadius? borderRadius;

  const _QtyActionButton({
    required super.key,  // UniqueKey from parent — drives GetWidget.instanceKey
    required this.icon,
    required this.onPressed,
    required this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius ?? BorderRadius.zero,
        onTapDown: (_) {
          HapticFeedback.lightImpact();
          controller.startRepeat(onPressed);
        },
        onTapUp: (_) => controller.stopRepeat(),
        onTapCancel: () => controller.stopRepeat(),
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
