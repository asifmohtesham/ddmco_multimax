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
/// ## GetX — StatelessWidget rationale
///
/// [SharedQtyField] is a [StatelessWidget].  The earlier [StatefulWidget]
/// form existed solely to cache the [QtyPlusMinusDelegate] cast in
/// `State.initState`, avoiding a repeated runtime type-check on every
/// [Obx] rebuild.
///
/// That optimisation is unnecessary in a GetX app: [c] is a
/// [GetxController] resolved by `Get.find` and passed as a constructor
/// param.  Flutter's rebuild cycle never replaces the controller instance,
/// so the cast result is identical across every rebuild.  Computing it
/// once as a `final` local at the top of [build] is functionally
/// equivalent, produces zero allocations beyond the single `is` check,
/// and removes all [State] lifecycle overhead.
///
/// [_clampOnBlur] is a `static` helper with explicit parameters
/// (no closure over [State]).  [_formatQty] was already `static`.
///
/// See [QtyFieldDelegate] class-level doc for the mandatory GetX
/// convention that applies to all `*FieldDelegate` implementors in this
/// package.
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
/// Commit 9 — StatelessWidget migration + GetX convention Dartdoc:
///   - Removed [StatefulWidget] / [State] subclass.  The sole purpose of
///     [State] was to cache the [QtyPlusMinusDelegate] cast in
///     `initState`.  In a GetX app [c] is never replaced by the rebuild
///     cycle; computing the cast once as a local `final` in [build] is
///     functionally equivalent with zero overhead.
///   - [_clampOnBlur] promoted to a `static` helper with explicit
///     `(stepper, c, context)` params.  Call site guards with
///     `if (stepper != null)` before invoking.
///   - Added GetX rationale section in class-level Dartdoc.
///   - No interface, controller, or call-site changes.
class SharedQtyField extends StatelessWidget {
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

  // ── Blur clamping ─────────────────────────────────────────────────────────

  /// Clamps a manually typed value to [QtyPlusMinusDelegate.effectiveMaxQty]
  /// so the ceiling is enforced for keyboard input as well as ± taps.
  ///
  /// Declared `static` because there is no [State] to close over —
  /// all required context is passed explicitly.  No-ops when the ceiling
  /// is `double.infinity` (uncapped DocTypes such as MR, PO, Job Card).
  static void _clampOnBlur(
    QtyPlusMinusDelegate stepper,
    QtyFieldDelegate c,
    BuildContext context,
  ) {
    final entered = double.tryParse(c.qtyController.text) ?? 0.0;
    final ceiling = stepper.effectiveMaxQty;
    if (ceiling.isFinite && entered > ceiling) {
      c.qtyController.text = _formatQty(ceiling);
      c.validateSheet();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Cast evaluated once per build() call as a local final.
    //
    // In a GetX app [c] is a [GetxController] resolved via Get.find and
    // passed as a constructor param.  Flutter's rebuild cycle never
    // replaces the controller instance, so this cast result is identical
    // across every Obx rebuild — computing it here is functionally
    // equivalent to the former State.initState cache with zero overhead.
    final stepper = c is QtyPlusMinusDelegate
        ? c as QtyPlusMinusDelegate
        : null;

    // Outer Obx governs isQtyReadOnly and qtyError — both are RxBool /
    // RxString and change at interaction time.
    //
    // The suffixIcon has its own inner Obx (see InputDecoration below)
    // because qtyInfoText is a plain String? getter (non-Rx): it cannot
    // trigger this outer Obx.  The inner Obx uses qtyInfoTooltip (RxnString)
    // as its reactive anchor — that field is updated whenever the underlying
    // balance changes, which is exactly when qtyInfoText also changes.
    return Obx(() {
      final isReadOnly = stepper?.isQtyReadOnly.value ?? false;
      final hasError   = c.qtyError.value.isNotEmpty;
      final label      = labelText ?? 'Qty';

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Text field ────────────────────────────────────────────────
          Expanded(
            child: TextFormField(
              controller:   c.qtyController,
              readOnly:     isReadOnly,
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
                      : accentColor,
                ),
                errorText:     hasError ? c.qtyError.value : null,
                errorMaxLines: 2,
                suffixText: unitOfMeasure,
                isDense:    true,

                // ── Max-Qty chip as suffixIcon ─────────────────────────
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
                  c.qtyInfoTooltip.value; // reactive anchor
                  final capLabel = c.qtyInfoText;
                  if (capLabel == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Center(
                      widthFactor: 1.0,
                      child: QtyCapBadge(controller: c),
                    ),
                  );
                }),

                // ── Five explicit border states ────────────────────────
                // Declared individually so every state carries a visually
                // intentional colour — same convention as SharedRackField
                // which avoids relying on the default theme border cascade.
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: accentColor.withOpacity(0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: accentColor,
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
              onChanged: (_) => c.validateSheet(),
              onEditingComplete: () {
                if (stepper != null) _clampOnBlur(stepper, c, context);
                FocusScope.of(context).unfocus();
              },
            ),
          ),

          // ── Stepper buttons: [−] [+] right-adjacent ───────────────────
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
              accentColor: accentColor,
              onTap:       () => stepper.adjustQty(-1),
            ),
            const SizedBox(width: 4),
            _StepperButton(
              icon:        Icons.add,
              accentColor: accentColor,
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
