// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../qty_field_delegate.dart';
import '../qty_plus_minus_delegate.dart';
import 'qty_cap_badge.dart';

/// Reusable qty text field with optional ± stepper and Max-Qty chip.
///
/// Driven by [QtyFieldDelegate].  When the delegate also implements
/// [QtyPlusMinusDelegate] (i.e. the controller adopts
/// [QtyFieldWithPlusMinusDelegate]), the widget automatically upgrades to
/// expose ± stepper buttons and enforce the [QtyPlusMinusDelegate.effectiveMaxQty]
/// ceiling on both stepper taps and manual keyboard entry (blur-clamp).
///
/// ## Behaviour matrix
///
/// | Runtime type of [c]       | ± buttons | Max-Qty chip    | Blur-clamp |
/// |---------------------------|-----------|-----------------|------------|
/// | [QtyFieldDelegate] only   | ✖         | if info ≠ null  | ✖          |
/// | + [QtyPlusMinusDelegate]  | ✔         | if info ≠ null  | ✔          |
///
/// ## Max-Qty chip
///
/// [QtyCapBadge] is rendered automatically whenever
/// [QtyFieldDelegate.qtyInfoText] returns a non-null value.  No opt-in flag
/// is required — this follows the same zero-config convention as
/// [SharedRackField]'s tooltip icon, which auto-appears when
/// `rackStockTooltip != null`.
///
/// ## Read-only guard
///
/// When [QtyPlusMinusDelegate.isQtyReadOnly] is `true` the text field is
/// disabled and both stepper buttons are hidden.  This is driven by
/// `docstatus == 1` in the implementing controller.
///
/// ## Constraints
///
/// - [c] owns the [TextEditingController] lifecycle (create / dispose).
/// - [c.validateSheet] is called on every keystroke (`onChanged`) and on
///   blur (`onEditingComplete`).
/// - The widget never calls [QtyPlusMinusDelegate.adjustQty] with values
///   other than `+1` or `−1`; bulk-step overrides are a controller concern.
class SharedQtyField extends StatefulWidget {
  final QtyFieldDelegate c;

  /// Accent colour applied to label text, enabled border, and stepper icons.
  final Color accentColor;

  /// Field label text.  Defaults to `'Qty'` when null.
  final String? labelText;

  /// Optional Unit-of-Measure suffix displayed inside the field
  /// (e.g. `'Nos'`, `'Kg'`).
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
  // ── Cached cast ───────────────────────────────────────────────────────────
  //
  // Evaluated once per widget instance.  Avoids a runtime type-check on every
  // Obx rebuild — same pattern used in SharedRackField for the
  // RackBrowseDelegate optional capability.

  /// Non-null when [widget.c] also implements [QtyPlusMinusDelegate].
  /// `null` means the stepper is unavailable for this controller.
  late final QtyPlusMinusDelegate? _stepper;

  @override
  void initState() {
    super.initState();
    _stepper = widget.c is QtyPlusMinusDelegate
        ? widget.c as QtyPlusMinusDelegate
        : null;
  }

  // ── Blur clamping ──────────────────────────────────────────────────────────

  /// Called from [TextFormField.onEditingComplete].
  ///
  /// Clamps manually typed values to [QtyPlusMinusDelegate.effectiveMaxQty]
  /// so the ceiling is enforced for keyboard input as well as ± taps.
  /// No-ops when [_stepper] is null (plain [QtyFieldDelegate] path) or when
  /// the ceiling is infinite (uncapped DocTypes).
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Formats a [double] for display in the qty field.
  ///
  /// Strips redundant trailing zeros so the field feels clean:
  ///   `12.0`   → `'12'`
  ///   `6.5`    → `'6.5'`
  ///   `6.500`  → `'6.5'`
  ///   `0.125`  → `'0.125'`
  static String _formatQty(double v) {
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    // Up to 3 decimal places, trailing zeros stripped.
    return v
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Single Obx wrapping the entire widget so that any Rx change on the
    // delegate (isQtyReadOnly, qtyError, qtyInfoText) triggers one atomic
    // rebuild — identical to how SharedBatchField wraps its Column.
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
          // ── Max-Qty chip ─────────────────────────────────────────────────
          //
          // Auto-rendered whenever qtyInfoText != null.  No opt-in flag:
          // presence is driven entirely by the delegate returning a non-null
          // label, consistent with the zero-config convention used by
          // SharedRackField (tooltip icon auto-appears when
          // rackStockTooltip != null).
          if (capLabel != null) ...[
            QtyCapBadge(controller: widget.c),
            const SizedBox(height: 6),
          ],

          // ── Qty field row ────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Decrement button (−) ──────────────────────────────────
              if (stepper != null && !isReadOnly)
                _StepperButton(
                  icon: Icons.remove,
                  accentColor: widget.accentColor,
                  onTap: () => stepper.adjustQty(-1),
                ),

              // ── Text field ─────────────────────────────────────────────
              Expanded(
                child: TextFormField(
                  controller: widget.c.qtyController,
                  readOnly: isReadOnly,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    // Permit only non-negative decimals while typing.
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d*$'),
                    ),
                  ],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: TextStyle(
                      color: hasError
                          ? Theme.of(context).colorScheme.error
                          : widget.accentColor,
                    ),
                    errorText: hasError
                        ? widget.c.qtyError.value
                        : null,
                    errorMaxLines: 2,
                    suffixText: uom,
                    isDense: true,
                    // ── Five explicit border states ───────────────────
                    // Declared individually so every state has a visually
                    // intentional border colour — same convention as
                    // SharedRackField.
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: widget.accentColor.withOpacity(0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: widget.accentColor,
                        width: 2,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
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
              if (stepper != null && !isReadOnly)
                _StepperButton(
                  icon: Icons.add,
                  accentColor: widget.accentColor,
                  onTap: () => stepper.adjustQty(1),
                ),
            ],
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StepperButton
// ─────────────────────────────────────────────────────────────────────────────

/// Internal ± step button used by [SharedQtyField].
///
/// Rendered as a 44 × 44 tappable [InkWell] with a top-padding offset that
/// absorbs the label-above-border gap in Material's [OutlineInputBorder]
/// layout, keeping the icon visually centre-aligned with the input text.
///
/// The button is only inserted into the [Row] when the stepper is available
/// AND [QtyPlusMinusDelegate.isQtyReadOnly] is `false`.  Hiding (not merely
/// disabling) the buttons when read-only gives a cleaner view-only appearance
/// consistent with how [SharedBatchField] collapses its edit controls.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 20 px top offset absorbs Material's default label-above-border gap
      // (~18–20 px) so the icon sits centre-aligned with the input text,
      // not with the full field height including the label.
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Icon(icon, color: accentColor, size: 22),
          ),
        ),
      ),
    );
  }
}
