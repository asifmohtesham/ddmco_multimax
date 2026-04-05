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
/// expose ± stepper buttons and enforce the
/// [QtyPlusMinusDelegate.effectiveMaxQty] ceiling on both stepper taps and
/// manual keyboard entry (blur-clamp).
///
/// ## Behaviour matrix
///
/// | Runtime type of [c]       | ± buttons | Max-Qty chip   | Blur-clamp |
/// |---------------------------|-----------|----------------|------------|
/// | [QtyFieldDelegate] only   | ✖         | if info ≠ null | ✖          |
/// | + [QtyPlusMinusDelegate]  | ✔         | if info ≠ null | ✔          |
///
/// ## Max-Qty chip
///
/// [QtyCapBadge] is rendered automatically as [InputDecoration.suffixIcon]
/// whenever [QtyFieldDelegate.qtyInfoText] returns a non-null value.
/// No opt-in flag is required — presence is driven entirely by the delegate
/// returning a non-null label, consistent with the zero-config convention
/// used by [SharedRackField] (tooltip icon auto-appears when
/// `rackStockTooltip != null`).
///
/// ### Reactivity note
///
/// [QtyFieldDelegate.qtyInfoText] is a plain `String?` getter (non-Rx)
/// because its value is computed synchronously from other Rx sources
/// (e.g. `effectiveMaxQty`, `batchBalance`).  To ensure the chip
/// appears / disappears reactively when those sources change, the
/// suffixIcon builder is wrapped in its own [Obx] keyed off
/// [QtyFieldDelegate.qtyInfoTooltip] — an [RxnString] that is updated
/// whenever the underlying balance changes.  The outer [Obx] only
/// governs [QtyPlusMinusDelegate.isQtyReadOnly] and
/// [QtyFieldDelegate.qtyError].
///
/// ## Read-only guard
///
/// When [QtyPlusMinusDelegate.isQtyReadOnly] is `true` the text field is
/// disabled and both stepper buttons are **hidden** (not merely disabled).
/// This is driven by `docstatus == 1` in the implementing controller and
/// gives a cleaner view-only appearance consistent with how
/// [SharedBatchField] collapses its edit controls.
///
/// ## Constraints
///
/// - [c] owns the [TextEditingController] lifecycle (create / dispose).
///   [SharedQtyField] never calls `dispose()` on [QtyFieldDelegate.qtyController].
/// - [QtyFieldDelegate.validateSheet] is called on every keystroke
///   (`onChanged`) and on blur (`onEditingComplete`).
/// - The widget never calls [QtyPlusMinusDelegate.adjustQty] with values
///   other than `+1` or `−1`; bulk-step overrides are a controller concern.
///
/// ## Changelog
///
/// Commit 5 : Initial implementation.
///   - [StatefulWidget] with `_stepper` cast cached in [State.initState]
///     to avoid a runtime type-check on every [Obx] rebuild.
///   - [_clampOnBlur] enforces [QtyPlusMinusDelegate.effectiveMaxQty]
///     ceiling on manual keyboard entry (fires on `onEditingComplete`).
///   - [_formatQty] strips redundant trailing zeros (`12.0` → `'12'`).
///   - Five explicit [OutlineInputBorder] states (enabled, focused,
///     disabled, error, focusedError) — same convention as
///     [SharedRackField].
///   - [_StepperButton] top-padding offset absorbs Material's
///     label-above-border gap so icons align with input text.
/// fix(cap-badge-reactivity) : Wrap cap-badge row in its own [Obx] keyed
///   off [QtyFieldDelegate.qtyInfoTooltip] ([RxnString]) so the chip
///   appears/disappears reactively when balance changes at runtime.
///   Outer [Obx] read of plain `String? qtyInfoText` was non-reactive.
/// fix(shared-qty-field): UX refinements — chip as suffixIcon, bordered
///   adjacent steppers (Commit 8).
///   - Q1: [QtyCapBadge] moved from standalone top-left Column row into
///     [InputDecoration.suffixIcon] via [Center(widthFactor:1.0)] so the
///     pill is vertically centred in the 48×48 icon slot. Reactive anchor
///     (qtyInfoTooltip Obx) preserved inside the suffixIcon builder.
///   - Q2: [_StepperButton] upgraded from bare [InkWell] to
///     [OutlinedButton] with border matching the field's enabledBorder
///     opacity, making all three elements read as a unified compound
///     control.
///   - Q3: Both buttons moved to the right of the field, adjacent
///     (4 px gap), eliminating full-screen thumb travel.
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
  /// `null` means the stepper and blur-clamping are unavailable.
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
  /// the ceiling is `double.infinity` (uncapped DocTypes such as MR, PO,
  /// Job Card).
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
    // Outer Obx governs isQtyReadOnly and qtyError — both are RxBool /
    // RxString and change at interaction time.
    //
    // The suffixIcon has its own inner Obx (see InputDecoration below)
    // because qtyInfoText is a plain String? getter (non-Rx): it cannot
    // trigger this outer Obx.  The inner Obx uses qtyInfoTooltip (RxnString)
    // as its reactive anchor — that field is updated whenever the underlying
    // balance changes, which is exactly when qtyInfoText also changes.
    return Obx(() {
      final stepper    = _stepper;
      final isReadOnly = stepper?.isQtyReadOnly.value ?? false;
      final hasError   = widget.c.qtyError.value.isNotEmpty;
      final label      = widget.labelText ?? 'Qty';
      final uom        = widget.unitOfMeasure;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Text field ──────────────────────────────────────────────────
          Expanded(
            child: TextFormField(
              controller:  widget.c.qtyController,
              readOnly:    isReadOnly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                // Permit only non-negative decimals while typing.
                // Empty string is allowed so backspace-to-empty works;
                // qtyError surfaces the validation state instead.
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d*$'),
                ),
              ],
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText:  label,
                labelStyle: TextStyle(
                  color: hasError
                      ? Theme.of(context).colorScheme.error
                      : widget.accentColor,
                ),
                errorText:     hasError ? widget.c.qtyError.value : null,
                errorMaxLines: 2,
                suffixText: uom,
                isDense:    true,

                // ── Max-Qty chip as suffixIcon ───────────────────────────
                //
                // Inner Obx keyed off qtyInfoTooltip (RxnString) so the
                // chip reacts to balance changes even though qtyInfoText
                // is non-Rx.  Center(widthFactor:1.0) vertically centres
                // the pill inside the 48×48 icon slot without horizontal
                // stretching.
                suffixIcon: Obx(() {
                  // Touch qtyInfoTooltip.value to subscribe this Obx to
                  // balance updates.  QtyCapBadge reads qtyInfoText via
                  // its own internal Obx — we only need this outer gate
                  // to conditionally wrap the Padding+Center.
                  widget.c.qtyInfoTooltip.value; // reactive anchor
                  final capLabel = widget.c.qtyInfoText;
                  if (capLabel == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Center(
                      widthFactor: 1.0,
                      child: QtyCapBadge(controller: widget.c),
                    ),
                  );
                }),

                // ── Five explicit border states ──────────────────────────
                // Declared individually so every state carries a visually
                // intentional colour — same convention as SharedRackField
                // which avoids relying on the default theme border cascade.
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

          // ── Stepper buttons: [−] [+] right-adjacent ─────────────────────
          //
          // Both buttons are placed to the right of the field, separated
          // by 4 px, so the user's thumb never has to travel across the
          // full screen width.  An 8 px gap separates the field from the
          // button group.  Hidden entirely (not merely disabled) when
          // read-only — consistent with SharedBatchField's collapse pattern.
          if (stepper != null && !isReadOnly) ...[            
            const SizedBox(width: 8),
            _StepperButton(
              icon:        Icons.remove,
              accentColor: widget.accentColor,
              onTap:       () => stepper.adjustQty(-1),
            ),
            const SizedBox(width: 4),
            _StepperButton(
              icon:        Icons.add,
              accentColor: widget.accentColor,
              onTap:       () => stepper.adjustQty(1),
            ),
          ],
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
/// Rendered as a 44 × 44 [OutlinedButton] with a top-padding offset that
/// absorbs the label-above-border gap in Material's [OutlineInputBorder]
/// layout, keeping the icon visually centre-aligned with the input text
/// rather than with the full field height (which includes the floating label).
/// The border colour matches the field's `enabledBorder` opacity
/// (`accentColor.withOpacity(0.5)`) so all three elements (−, field, +)
/// read as a unified compound control.
///
/// The button is only inserted into the [Row] when the stepper capability
/// is present AND [QtyPlusMinusDelegate.isQtyReadOnly] is `false`.
/// **Hiding** (not merely disabling) the buttons when read-only gives a
/// cleaner view-only appearance consistent with how [SharedBatchField]
/// collapses its edit controls when a batch is already validated.
class _StepperButton extends StatelessWidget {
  final IconData      icon;
  final Color         accentColor;
  final VoidCallback  onTap;

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
      // not with the full field height including the floating label.
      padding: const EdgeInsets.only(top: 0),
      child: SizedBox(
        width:  44,
        height: 44,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize:     const Size(44, 44),
            padding:         EdgeInsets.zero,
            side: BorderSide(
              // Match the field's enabledBorder opacity so all three
              // elements (−, field, +) share a single visual border weight.
              color: accentColor.withOpacity(0.5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            foregroundColor: accentColor,
          ),
          onPressed: onTap,
          child: Icon(icon, color: accentColor, size: 22),
        ),
      ),
    );
  }
}
