import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/item_form_sheet/validated_rack_field.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable Rack input field backed by any [ItemSheetControllerBase].
///
/// ## Modes
///
/// ### `editMode: false` (default — SE style)
/// Borderless [TextField], green check-circle when valid, clear + validate
/// icons, per-rack stock tooltip.  [BalanceChip] shown below the field
/// displaying the selected rack's balance from [rackStockMap].
///
/// ### `editMode: true` (PR / DN style)
/// Delegates to [ValidatedRackField] → [ValidatedFieldWidget], giving
/// consistent OutlineInputBorder, spinner → edit-button lifecycle, and
/// picker button support through [onPickerTap].  [BalanceChip] shown below.
///
/// ## Picker integration
/// Pass [onPickerTap] to show the shelves icon button in the suffix area
/// when `editMode: true`.  The full picker lifecycle (controller creation,
/// data load, sheet presentation) is owned by the caller
/// (UniversalItemFormSheet); this widget only renders the button.
///
/// P3-C: onChanged simplified — c.resetRack() replaces inline Rx read.
/// P3-D: Per-rack stock tooltip in _EditModeRack suffix row.
/// Balance chip: sources rackStockMap[rackController.text] for the balance.
/// Commit-E: _EditModeRack now delegates to ValidatedRackField instead of
///   its own hand-rolled TextFormField, eliminating the duplicate
///   OutlineInputBorder / suffix / readOnly implementation.
class SharedRackField extends StatelessWidget {
  final ItemSheetControllerBase c;
  final Color  accentColor;
  final String label;
  final String hint;
  final bool   editMode;

  /// Optional callback fired when the picker icon button is tapped.
  /// Only active when [editMode] is true.  When null, no picker button
  /// is shown.
  final VoidCallback? onPickerTap;

  const SharedRackField({
    super.key,
    required this.c,
    required this.accentColor,
    this.label       = 'Rack',
    this.hint        = 'Enter or scan rack ID',
    this.editMode    = false,
    this.onPickerTap,
  });

  /// Returns the balance for the currently-typed rack from rackStockMap,
  /// or 0.0 if the rack is not in the map.
  double _rackBalance(ItemSheetControllerBase c) {
    final rack = c.rackController.text.trim();
    if (rack.isEmpty) return 0.0;
    return c.rackStockMap[rack] ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return editMode ? _EditModeRack(this) : _SimpleRack(this);
  }
}

// ── Simple (borderless) mode — SE style, unchanged ───────────────────────────
class _SimpleRack extends StatelessWidget {
  final SharedRackField w;
  const _SimpleRack(this.w);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c     = w.c;

    return Obx(() {
      final hasError   = c.rackError.value != null;
      final isValid    = c.isRackValid.value;
      final validating = c.isValidatingRack.value;
      final rackBal    = w._rackBalance(c);

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
                errorText:   c.rackError.value,
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
          BalanceChip(
            balance:   rackBal,
            isLoading: validating,
            color:     w.accentColor,
            prefix:    'Rack Balance:',
          ),
        ],
      );
    });
  }
}

// ── Edit-mode — delegates to ValidatedRackField ───────────────────────────────
//
// Previously owned its own TextFormField + OutlineInputBorder + suffix
// logic (Commits A-D history). Now delegates entirely to ValidatedRackField
// → ValidatedFieldWidget so both DN and SE share a single rack field
// implementation. The BalanceChip is rendered below as before.
class _EditModeRack extends StatelessWidget {
  final SharedRackField w;
  const _EditModeRack(this.w);

  @override
  Widget build(BuildContext context) {
    final c = w.c;

    return Obx(() {
      final isValid    = c.isRackValid.value;
      final validating = c.isValidatingRack.value;
      final rackBal    = w._rackBalance(c);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValidatedRackField(
            key:            const ValueKey('shared_rack_edit'),
            textController: c.rackController,
            isValid:        isValid,
            isValidating:   validating,
            label:          w.hint,   // hint text used as field label/hintText
            color:          w.accentColor,
            onReset:        c.resetRack,
            onValidate:     () => c.validateRack(c.rackController.text),
            onSubmitted:    (val) => c.validateRack(val),
            onPickerTap:    w.onPickerTap,
          ),
          // Rack balance chip — sources the typed rack's balance from rackStockMap.
          BalanceChip(
            balance:   rackBal,
            isLoading: validating,
            color:     w.accentColor,
            prefix:    'Rack Balance:',
          ),
        ],
      );
    });
  }
}
