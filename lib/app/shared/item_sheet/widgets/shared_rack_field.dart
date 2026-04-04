// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/validated_rack_field.dart';
import 'package:multimax/app/shared/item_sheet/rack_field_with_browse_delegate.dart';

/// A reusable Rack input field backed by any [RackFieldWithBrowseDelegate].
///
/// ## Modes
///
/// ### `editMode: false` (default — SE style)
/// Borderless [TextField], green check-circle when valid, clear + validate
/// icons, per-rack stock tooltip.  [BalanceChip] shown below the field
/// displaying the selected rack's balance via [RackFieldDelegate.rackBalanceFor].
///
/// ### `editMode: true` (PR / DN style)
/// Wraps [ValidatedRackField] inside [GlobalItemFormSheet.buildInputGroup]
/// so the coloured left-border section header (sourced from [label]) is
/// rendered, matching the layout of every other field in the sheet.
/// [BalanceChip] shown below.
///
/// ## Label vs Hint
/// [label]  — section header shown above / beside the field border
///            (passed to buildInputGroup).  Defaults to 'Rack'.
/// [hint]   — placeholder text inside the text field
///            (passed as ValidatedRackField.label / hintText).
///            Defaults to 'Enter or scan rack ID'.
///
/// ## Balance source
/// By default the [BalanceChip] sources [_rackBalance] which calls
/// [RackFieldDelegate.rackBalanceFor] on the controller.  Controllers
/// that pre-load a `Map<String, double>` return a map lookup; controllers
/// that maintain a live [RxDouble] override [rackBalanceFor] to return
/// `rackBalance.value` instead.
///
/// Pass [balanceOverride] to bypass [rackBalanceFor] entirely and supply
/// an alternative balance getter at the call site:
///
/// ```dart
/// SharedRackField(
///   c:               child,
///   accentColor:     Colors.blueGrey,
///   balanceOverride: () => child.rackBalance.value,
/// )
/// ```
///
/// ## Picker integration
/// Pass [onPickerTap] to show the shelves icon button in the suffix area
/// when `editMode: true`.  The full picker lifecycle (controller creation,
/// data load, sheet presentation) is owned by the caller
/// (UniversalItemFormSheet); this widget only renders the button.
///
/// ## Architecture note
/// This widget previously depended on [ItemSheetControllerBase] directly.
/// As of Commit 4 it depends only on [RackFieldWithBrowseDelegate], the
/// narrow interface introduced in Commit 2.  Any DocType controller that
/// implements this interface can now host this widget with zero additional
/// ceremony — no inheritance of the full item-sheet base class required.
///
/// Existing call sites (SE, DN, PR) are unaffected: their controllers
/// extend [ItemSheetControllerBase] which adopts the interface in Commit 3.
///
/// P3-C: onChanged simplified — c.resetRack() replaces inline Rx read.
/// P3-D: Per-rack stock tooltip in _EditModeRack suffix row.
/// Balance chip: sources rackBalanceFor(rack) for the balance (Commit 4).
/// Commit-E: _EditModeRack now delegates to ValidatedRackField instead of
///   its own hand-rolled TextFormField, eliminating the duplicate
///   OutlineInputBorder / suffix / readOnly implementation.
/// Commit 2: _EditModeRack wraps ValidatedRackField in buildInputGroup so
///   the section label is rendered in editMode (Bug 2 fix).
/// DN-8: pass forceShow: validating to all BalanceChip calls so the chip
///   stays visible (showing spinner) during the async fetch instead of
///   disappearing and reappearing when balance is temporarily 0.
/// DN-9: forceShow: validating || isValid — chip persists after validation
///   completes even when rackBalance is momentarily 0.0 (rackStockMapRx
///   populated asynchronously by preloadRackStockMap; chip must not
///   collapse between validation-complete and map-populated rebuilds).
/// DN-10: add balanceOverride callback — parity with SharedBatchField P2-1.
///   Callers that need a live RxDouble balance (e.g. DeliveryNote rackBalance)
///   pass balanceOverride; all existing callers fall back to _rackBalance().
class SharedRackField extends StatelessWidget {
  final RackFieldWithBrowseDelegate c;
  final Color  accentColor;
  final String label;
  final String hint;
  final bool   editMode;

  /// Optional balance override.  When non-null, the [BalanceChip] calls this
  /// getter on every rebuild instead of calling
  /// [RackFieldDelegate.rackBalanceFor] via [_rackBalance].
  ///
  /// Use this when the call site needs a balance value that is not
  /// sourced through [rackBalanceFor] — for example a separate live
  /// RxDouble field maintained by the orchestrator controller.
  final double? Function()? balanceOverride;

  /// Optional callback fired when the picker icon button is tapped.
  /// Only active when [editMode] is true.  When null, no picker button
  /// is shown.
  final VoidCallback? onPickerTap;

  const SharedRackField({
    super.key,
    required this.c,
    required this.accentColor,
    this.label          = 'Rack',
    this.hint           = 'Enter or scan rack ID',
    this.editMode       = false,
    this.balanceOverride,
    this.onPickerTap,
  });

  /// Returns the balance for the currently-typed rack via
  /// [RackFieldDelegate.rackBalanceFor].  Returns 0.0 when the field
  /// is empty (guard before the delegate call).
  ///
  /// Used as fallback when [balanceOverride] is not supplied.
  double _rackBalance(RackFieldWithBrowseDelegate c) {
    final rack = c.rackController.text.trim();
    if (rack.isEmpty) return 0.0;
    return c.rackBalanceFor(rack);
  }

  @override
  Widget build(BuildContext context) {
    return editMode ? _EditModeRack(this) : _SimpleRack(this);
  }
}

// ── Simple (borderless) mode — SE style, unchanged ────────────────────────
class _SimpleRack extends StatelessWidget {
  final SharedRackField w;
  const _SimpleRack(this.w);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c     = w.c;

    return Obx(() {
      // Commit 4: rackError is RxString (non-nullable, '' = no error).
      // Use isNotEmpty instead of != null to align with the standardised
      // RackFieldDelegate contract (both modes now consistent).
      final hasError   = c.rackError.value.isNotEmpty;
      final isValid    = c.isRackValid.value;
      final validating = c.isValidatingRack.value;
      // DN-10: respect balanceOverride when supplied; fall back to rackBalanceFor.
      final rackBal    = w.balanceOverride?.call() ?? w._rackBalance(c);

      final borderColor = hasError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : w.accentColor;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlobalItemFormSheet.buildInputGroup(
            label: w.label,
            color: borderColor,
            child: TextField(
              controller: c.rackController,
              focusNode:  c.rackFocusNode,
              style:      theme.textTheme.bodyMedium,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) {
                if (v.isNotEmpty) c.validateRack(v);
              },
              decoration: InputDecoration(
                hintText:    w.hint,
                border:      InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                errorText:   hasError ? c.rackError.value : null,
                errorMaxLines: 2,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (validating)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (isValid)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.check_circle,
                            color: Colors.green, size: 20),
                      ),
                    if (c.rackStockTooltip.value != null)
                      Tooltip(
                        message: c.rackStockTooltip.value!,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.inventory_2_outlined,
                              color: w.accentColor, size: 20),
                        ),
                      ),
                    if (c.rackController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          c.rackController.clear();
                          c.resetRack();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          // DN-9: forceShow: validating || isValid — chip stays visible after
          // validation completes even when rackBalance is momentarily 0.0.
          BalanceChip(
            balance:   rackBal,
            isLoading: validating,
            color:     w.accentColor,
            prefix:    'Rack Balance:',
            forceShow: validating || isValid,
          ),
        ],
      );
    });
  }
}

// ── Edit-mode — delegates to ValidatedRackField ─────────────────────────────
//
// Previously owned its own TextFormField + OutlineInputBorder + suffix
// logic (Commits A-D history). Now delegates entirely to ValidatedRackField
// → ValidatedFieldWidget so both DN and SE share a single rack field
// implementation.
//
// Commit 2: wrapped in buildInputGroup(label: w.label) so the coloured
// section header is rendered in editMode, matching _SimpleRack.  The
// ValidatedRackField receives w.hint as its own inner label/hintText
// (unchanged from Commit-E).
//
// DN-10: rackBal now respects balanceOverride, matching _SimpleRack.
class _EditModeRack extends StatelessWidget {
  final SharedRackField w;
  const _EditModeRack(this.w);

  @override
  Widget build(BuildContext context) {
    final c = w.c;

    return Obx(() {
      final isValid    = c.isRackValid.value;
      final validating = c.isValidatingRack.value;
      // DN-10: respect balanceOverride when supplied; fall back to rackBalanceFor.
      final rackBal    = w.balanceOverride?.call() ?? w._rackBalance(c);

      // Derive the border accent colour to match _SimpleRack behaviour:
      // green when valid, error colour on error, accent otherwise.
      final theme = Theme.of(context);
      final hasError    = c.rackError.value.isNotEmpty;
      final borderColor = hasError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : w.accentColor;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bug 2 fix: wrap ValidatedRackField in buildInputGroup so the
          // section label (w.label, e.g. 'Rack' / 'Source Rack') is
          // rendered above the field, consistent with every other
          // SharedXxxField in the sheet.
          GlobalItemFormSheet.buildInputGroup(
            label: w.label,
            color: borderColor,
            child: ValidatedRackField(
              key:            const ValueKey('shared_rack_edit'),
              textController: c.rackController,
              isValid:        isValid,
              isValidating:   validating,
              label:          w.hint,   // inner field hint/label
              color:          w.accentColor,
              onReset:        c.resetRack,
              onValidate:     () => c.validateRack(c.rackController.text),
              onSubmitted:    (val) => c.validateRack(val),
              onPickerTap:    w.onPickerTap,
            ),
          ),
          // DN-9: forceShow: validating || isValid — chip stays visible after
          // validation completes even when rackBalance is momentarily 0.0.
          BalanceChip(
            balance:   rackBal,
            isLoading: validating,
            color:     w.accentColor,
            prefix:    'Rack Balance:',
            forceShow: validating || isValid,
          ),
        ],
      );
    });
  }
}
