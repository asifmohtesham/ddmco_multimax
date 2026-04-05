// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../qty_field_delegate.dart';
import '../qty_plus_minus_delegate.dart';
import 'qty_cap_badge.dart';

/// Reusable qty text field with optional ± stepper and Max-Qty chip.
///
/// ## Usage
///
/// ```dart
/// // Any DocType controller that implements QtyFieldDelegate:
/// SharedQtyField(c: controller, accentColor: accentColor)
/// ```
///
/// The widget automatically upgrades its behaviour based on [c]'s runtime
/// type:
///
/// | Runtime type of [c]              | ± buttons | Max-Qty chip    | Blur-clamp |
/// |----------------------------------|-----------|-----------------|------------|
/// | `QtyFieldDelegate` only          | ✖         | if info ≠ null  | ✖           |
/// | + `QtyPlusMinusDelegate`         | ✔         | if info ≠ null  | ✔           |
///
/// ## Constraints
///
/// - [c] owns the [TextEditingController] lifecycle (create / dispose).
/// - [c.validateSheet] is called on every keystroke and on blur.
/// - When [c] is also [QtyPlusMinusDelegate]:
///   - [QtyPlusMinusDelegate.isQtyReadOnly] disables both the field and buttons.
///   - [QtyPlusMinusDelegate.effectiveMaxQty] caps both ± steps and blur input.
class SharedQtyField extends StatefulWidget {
  final QtyFieldDelegate c;
  final Color accentColor;
  final String? labelText;
  final String? unitOfMeasure;

  const SharedQtyField({
    super.key,
    required this.c,
    required this.accentColor,
    this.labelText,
    this.unitOfMeasure,
  });

  @override
  State<SharedQtyField> createState() => _SharedQtyFieldState();
}

class _SharedQtyFieldState extends State<SharedQtyField> {
  // Cached cast — evaluated once on first build; null = stepper unavailable.
  QtyPlusMinusDelegate? get _stepper =>
      widget.c is QtyPlusMinusDelegate
          ? widget.c as QtyPlusMinusDelegate
          : null;

  // ── Blur clamping ────────────────────────────────────────────────────────────

  void _clampOnBlur() {
    final stepper = _stepper;
    if (stepper == null) return;
    final entered = double.tryParse(widget.c.qtyController.text) ?? 0.0;
    final ceiling = stepper.effectiveMaxQty;
    if (ceiling.isFinite && entered > ceiling) {
      widget.c.qtyController.text = _formatQty(ceiling);
      widget.c.validateSheet();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Formats a [double] for display in the qty field.
  ///
  /// Strips unnecessary trailing zeros:
  /// - `12.0`  → `'12'`
  /// - `6.5`   → `'6.5'`
  /// - `6.500` → `'6.5'`
  static String _formatQty(double v) {
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    // Up to 3 decimal places, trailing zeros stripped.
    return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  // ── Build ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final stepper    = _stepper;
      final isReadOnly = stepper?.isQtyReadOnly.value ?? false;
      final hasError   = widget.c.qtyError.value.isNotEmpty;
      final label      = widget.labelText ?? 'Qty';
      final uom        = widget.unitOfMeasure;
      final capLabel   = widget.c.qtyInfoText;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Max-Qty chip (auto-shown whenever qtyInfoText != null) ────────
          if (capLabel != null) ...[
            QtyCapBadge(controller: widget.c),
            const SizedBox(height: 6),
          ],

          // ── Qty field row ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Decrement button (−) ───────────────────────────────────
              if (stepper != null)
                _StepperButton(
                  icon: Icons.remove,
                  accentColor: widget.accentColor,
                  enabled: !isReadOnly,
                  onTap: () => stepper.adjustQty(-1),
                ),

              // ── Text field ──────────────────────────────────────────────
              Expanded(
                child: TextFormField(
                  controller:    widget.c.qtyController,
                  readOnly:      isReadOnly,
                  keyboardType:  const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    // Allow only non-negative decimals.
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: TextStyle(
                      color: hasError
                          ? Theme.of(context).colorScheme.error
                          : widget.accentColor,
                    ),
                    errorText: hasError ? widget.c.qtyError.value : null,
                    suffixText: uom,
                    border:            const OutlineInputBorder(),
                    enabledBorder:     OutlineInputBorder(
                      borderSide: BorderSide(
                        color: widget.accentColor.withOpacity(0.5),
                      ),
                    ),
                    focusedBorder:     OutlineInputBorder(
                      borderSide: BorderSide(
                        color: widget.accentColor,
                        width: 2,
                      ),
                    ),
                    disabledBorder:    OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                    errorBorder:       OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (_) => widget.c.validateSheet(),
                  onEditingComplete: () {
                    _clampOnBlur();
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),

              // ── Increment button (+) ───────────────────────────────────
              if (stepper != null)
                _StepperButton(
                  icon: Icons.add,
                  accentColor: widget.accentColor,
                  enabled: !isReadOnly,
                  onTap: () => stepper.adjustQty(1),
                ),
            ],
          ),
        ],
      );
    });
  }
}

// ──────────────────────────────────────────────────────────────────────────────────
// _StepperButton ──────────────────────────────────────────────────────────────────────────────────

/// Internal ± step button used by [SharedQtyField].
///
/// Renders as a square [Material] button with an icon, matching the height
/// of the adjacent [TextFormField].  Disabled when [enabled] is false.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.accentColor,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effective = enabled ? accentColor : Theme.of(context).disabledColor;
    return Padding(
      // Align the button vertically with the TextFormField (which has a label
      // that adds top space).  A 20px top pad matches Material's default
      // label-above-border gap so the button sits centre-aligned with the
      // input text.
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Icon(icon, color: effective, size: 22),
          ),
        ),
      ),
    );
  }
}
