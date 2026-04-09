// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/batch_no_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/widgets/browse_batch_button.dart';
import 'package:multimax/app/shared/item_sheet/widgets/validated_batch_field.dart';

/// A reusable Batch No input field driven by any
/// [BatchNoFieldWithBrowseDelegate].
///
/// ## Modes
///
/// The widget renders one of two internal sub-trees depending on [editMode]:
///
/// | Mode                      | Widget tree         | Border style          | Use case               |
/// |---------------------------|---------------------|-----------------------|------------------------|
/// | `editMode: false` (default) | `_SimpleField`    | Borderless card       | Stock Entry            |
/// | `editMode: true`            | `_EditModeField`  | [OutlineInputBorder]  | Delivery Note, PO, PR  |
///
/// ### `editMode: false` — Simple (SE) style
///
/// Renders a plain [TextField] inside a borderless
/// [GlobalItemFormSheet.buildInputGroup] container.  A [BalanceChip] is
/// shown below the field.  The suffix row contains a spinner while
/// validating, a ✓ / ⚠ icon after validation, an optional picker button
/// ([onPickerTap]), and a clear button when the field is non-empty.
///
/// ### `editMode: true` — Outline (DN / PR) style
///
/// Delegates to [ValidatedBatchField], which owns the
/// [OutlineInputBorder] decoration, the read-only-when-valid lock, and
/// the **Edit** button that reactivates the field.  The suffix row logic
/// (spinner, status icon, tooltip, picker button, clear / edit button) is
/// encapsulated inside [ValidatedBatchField] — this class does not
/// duplicate it.
///
/// ## Parameters
///
/// | Parameter          | Required | Default | Description                                                            |
/// |--------------------|----------|---------|------------------------------------------------------------------------|
/// | `c`                | ✅        | —       | Controller; any [BatchNoFieldWithBrowseDelegate] implementation.       |
/// | `accentColor`      | ✅        | —       | Tint applied to borders, icons, and the [BalanceChip].                 |
/// | `editMode`         | —        | `false` | Selects between Simple and Outline rendering modes (see table above).  |
/// | `readOnly`         | —        | `false` | Hard read-only override; disables typing in both modes.               |
/// | `fieldKey`         | —        | `null`  | Passed to [ValidatedBatchField] as its form-field key (edit mode only).|
/// | `balanceOverride`  | —        | `null`  | Alternative balance source; see **Balance source** section below.      |
/// | `onPickerTap`      | —        | `null`  | Injects a picker icon button into the suffix row when non-null.        |
/// | `showBrowseBatches`| —        | `false` | Shows the **Browse Batches →** text button below the field.            |
/// | `browseWarehouse`  | —        | `null`  | Warehouse passed to the batch picker; falls back to the delegate value.|
///
/// ## Controller contract
///
/// `c` is typed as [BatchNoFieldWithBrowseDelegate] — the narrow interface
/// defined in Commit 3 of the batch-field refactor.  Any controller that
/// implements this interface (including all [ItemSheetControllerBase]
/// subclasses, which adopt it in Commit 7) can be passed without change.
///
/// The interface is split into two layers:
///
/// | Interface               | Responsibility                                    |
/// |-------------------------|---------------------------------------------------|
/// | [BatchNoFieldDelegate]  | Reactive state, text controller, validation       |
/// | [BatchNoBrowseDelegate] | Browse Batches picker flow                        |
///
/// [BatchNoFieldWithBrowseDelegate] is the union of both.  For controllers
/// that do not need Browse Batches support, [BatchNoFieldDelegate] alone
/// suffices — simply omit [onPickerTap] at the call site to suppress the
/// picker button.
///
/// ## validateSheet
///
/// In `editMode: true`, [ValidatedBatchField] fires
/// [BatchNoFieldDelegate.validateSheet] on every `onChanged` event.  This
/// recomputes the sheet-level save gate (`isSheetValid`) after each
/// keystroke.  Controllers that do not gate a Save button can supply an
/// empty-body implementation:
///
/// ```dart
/// @override void validateSheet() {}
/// ```
///
/// In `editMode: false` (_SimpleField), the field uses `onSubmitted` only —
/// no `onChanged` — so `validateSheet` is **not** called while typing.
///
/// ## Balance source
///
/// By default the [BalanceChip] calls `c.batchBalanceFor('')`.  Pass
/// [balanceOverride] to supply an alternative balance getter — for example
/// Stock Entry, which maintains a separate per-warehouse `batchBalance`
/// distinct from the delegate accessor:
///
/// ```dart
/// SharedBatchField(
///   c:               child,
///   accentColor:     Colors.blueGrey,
///   editMode:        true,
///   fieldKey:        'se_batch_edit',
///   balanceOverride: () => child.batchBalance.value,
///   onPickerTap:     child.openBatchPicker,
/// )
/// ```
///
/// ## Changelog
///
/// | Commit / fix                | Change summary                                                    |
/// |-----------------------------|-------------------------------------------------------------------|
/// | P2-1                        | Added [balanceOverride] optional callback.                        |
/// | P3-A                        | readOnly requires isValid AND batchError == ''.                  |
/// | P3-A                        | helperText / border colour is 3-tier (red / orange / grey).      |
/// | P3-B                        | errorText only for hard-invalid; warning as orange helperText.    |
/// | P4-1                        | _SimpleField respects c.isBatchReadOnly (parity with SE local).  |
/// | C                           | Added [showBrowseBatches] — opens [BatchPickerSheet] on tap.     |
/// | P3-2                        | Added [onPickerTap] — injects picker icon in both idle+valid.    |
/// | fix(BATCH-ICON)             | Wrap multi-icon suffixIcon Row in IntrinsicWidth.                |
/// | fix(BATCH-ICON-VALID)       | Render picker btn in valid state; width computed dynamically.    |
/// | fix(SE-BATCH-ICON)          | _SimpleField also renders picker btn in valid state.             |
/// | DN-8                        | Pass `forceShow: validating` to all BalanceChip calls.           |
/// | DN-9                        | `forceShow: validating \|\| isValid`.                            |
/// | fix(batch-field)            | `isDense: true` in both InputDecorations.                        |
/// | fix(batch-delegate)         | `validateSheet` added to [BatchNoFieldDelegate]; called by       |
/// |                             | [ValidatedBatchField].onChanged in _EditModeField only.          |
/// | Commit 6                    | Extract [ValidatedBatchField] + [BrowseBatchButton] widgets.     |
/// | Commit 7                    | `c` re-typed to [BatchNoFieldWithBrowseDelegate];                |
/// |                             | [ItemSheetControllerBase] adopts interface with 4 overrides.     |
/// | Commit 3 (Dartdoc)          | Expand class-level Dartdoc: mode table, parameter table,         |
/// |                             | validateSheet cross-ref, balance source example, changelog table.|
/// | Commit 4                    | _SimpleField wires c.batchFocusNode into TextField so            |
/// |                             | BarcodeAwareMixin routes scans to ScanScope.batchNo when         |
/// |                             | the batch field has keyboard focus.                              |
class SharedBatchField extends StatelessWidget {
  final BatchNoFieldWithBrowseDelegate c;
  final Color  accentColor;
  final bool   editMode;
  final bool   readOnly;
  final String? fieldKey;

  /// Whether to show the "Browse Batches" shortcut button below the field.
  final bool showBrowseBatches;

  /// Optional warehouse override for the batch picker.  When null the field
  /// reads [BatchNoBrowseDelegate.resolvedWarehouseForBatch].
  final String? browseWarehouse;

  /// Optional balance override.  When non-null, the [BalanceChip] calls this
  /// getter on every rebuild instead of `c.batchBalanceFor('')`.
  ///
  /// Use when the controller maintains a per-warehouse balance separately
  /// from the delegate accessor — see class-level **Balance source** section.
  final double? Function()? balanceOverride;

  /// Optional callback fired when the list-picker icon button is tapped.
  ///
  /// When non-null, a [Icons.shelves] icon button is injected into the
  /// suffix row in both idle and valid states.  When null, the button is
  /// omitted entirely — no dead UI element is rendered.
  final VoidCallback? onPickerTap;

  const SharedBatchField({
    super.key,
    required this.c,
    required this.accentColor,
    this.editMode          = false,
    this.readOnly          = false,
    this.fieldKey,
    this.balanceOverride,
    this.showBrowseBatches = false,
    this.browseWarehouse,
    this.onPickerTap,
  });

  Color get _validFill {
    if (accentColor is MaterialColor) {
      return (accentColor as MaterialColor).shade50;
    }
    return accentColor.withOpacity(0.08);
  }

  Color get _validBorder {
    if (accentColor is MaterialColor) {
      return (accentColor as MaterialColor).shade200;
    }
    return accentColor.withOpacity(0.5);
  }

  @override
  Widget build(BuildContext context) {
    return editMode ? _EditModeField(this) : _SimpleField(this);
  }
}

// ── Picker suffix icon button (shared helper, _SimpleField only) ─────────────
Widget _pickerSuffixBtn(Color color, VoidCallback onTap) => IconButton(
      icon:      Icon(Icons.shelves, color: color, size: 20),
      onPressed: onTap,
      tooltip:   'Browse batches',
      padding:   EdgeInsets.zero,
    );

// ── Simple (borderless) mode ───────────────────────────────────────────────────
class _SimpleField extends StatelessWidget {
  final SharedBatchField w;
  const _SimpleField(this.w);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c     = w.c;

    return Obx(() {
      final isValid    = c.isBatchValid.value;
      final validating = c.isValidatingBatch.value;
      final errorMsg   = c.batchError.value;

      final isReadOnly  = w.readOnly || c.isBatchReadOnly.value;
      final isHardError = !isValid && errorMsg.isNotEmpty;
      final isWarning   =  isValid && errorMsg.isNotEmpty;

      final borderColor = isHardError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : w.accentColor;

      final chipColor   = isWarning ? Colors.orange : w.accentColor;
      final chipBalance = w.balanceOverride?.call() ?? c.batchBalanceFor('');

      Widget buildSuffixRow() => IntrinsicWidth(
        child: Row(
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
                child: Icon(
                  isWarning
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  color: isWarning ? Colors.orange : Colors.green,
                  size: 20,
                ),
              ),
            if (c.batchInfoTooltip.value != null)
              Tooltip(
                message: c.batchInfoTooltip.value!,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.info_outline,
                      color: w.accentColor, size: 20),
                ),
              ),
            if (!validating && !isValid && w.onPickerTap != null)
              _pickerSuffixBtn(w.accentColor, w.onPickerTap!),
            if (!validating && isValid && w.onPickerTap != null)
              _pickerSuffixBtn(
                isWarning ? Colors.orange : w.accentColor,
                w.onPickerTap!,
              ),
            if (c.batchController.text.isNotEmpty && !isReadOnly)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  c.batchController.clear();
                  c.resetBatch();
                },
              ),
          ],
        ),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlobalItemFormSheet.buildInputGroup(
            label: 'Batch No',
            color: borderColor,
            child: TextField(
              controller: c.batchController,
              // Commit 4: wire batchFocusNode so BarcodeAwareMixin._focusedScope
              // detects focus → ScanScope.batchNo and routes scans directly
              // into the batch field when it has keyboard focus.
              focusNode:  c.batchFocusNode,
              readOnly:   isReadOnly,
              style:      theme.textTheme.bodyMedium,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) {
                if (v.isNotEmpty) c.validateBatch(v);
              },
              decoration: InputDecoration(
                hintText:    'Enter or scan batch number',
                border:      InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                isDense:       true,
                errorText:     isHardError ? errorMsg : null,
                errorMaxLines: 2,
                helperText:    isWarning ? errorMsg : null,
                helperMaxLines: 2,
                helperStyle: isWarning
                    ? const TextStyle(
                        color:      Colors.orange,
                        fontWeight: FontWeight.w600,
                        fontSize:   11,
                      )
                    : null,
                suffixIcon: buildSuffixRow(),
              ),
            ),
          ),
          // BrowseBatchButton guards showBrowseBatches internally;
          // no Obx needed at this level for that flag.
          Obx(() => BrowseBatchButton(
            showBrowseBatches: w.showBrowseBatches,
            isValid:           c.isBatchValid.value,
            isReadOnly:        w.readOnly || c.isBatchReadOnly.value,
            isValidating:      c.isValidatingBatch.value,
            itemCode:          c.itemCode.value,
            warehouse:         w.browseWarehouse ?? c.resolvedWarehouseForBatch,
            accentColor:       w.accentColor,
            batchController:   c.batchController,
            onBatchSelected:   c.validateBatch,
          )),
          BalanceChip(
            balance:   chipBalance,
            isLoading: validating,
            color:     chipColor,
            prefix:    'Batch Balance:',
            forceShow: validating || isValid,
          ),
        ],
      );
    });
  }
}

// ── Edit-mode (OutlineInputBorder, delegates to ValidatedBatchField) ────────
//
// onChanged → c.validateSheet
//   Every keystroke fires [BatchNoFieldDelegate.validateSheet], which
//   recomputes the sheet-level save gate (isSheetValid) so the Save button
//   reflects the current form state in real time.  This is the edit-mode
//   counterpart to _SimpleField's onSubmitted-only approach.
//   Controllers that do not gate a Save button supply an empty-body override.
class _EditModeField extends StatelessWidget {
  final SharedBatchField w;
  const _EditModeField(this.w);

  @override
  Widget build(BuildContext context) {
    final c = w.c;

    return Obx(() {
      final isValid    = c.isBatchValid.value;
      final validating = c.isValidatingBatch.value;
      final errorMsg   = c.batchError.value;

      final isHardError = !isValid && errorMsg.isNotEmpty;
      final isWarning   =  isValid && errorMsg.isNotEmpty;
      final chipColor   = isWarning ? Colors.orange : w.accentColor;
      final chipBalance = w.balanceOverride?.call() ?? c.batchBalanceFor('');
      final warehouse   = w.browseWarehouse ?? c.resolvedWarehouseForBatch;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlobalItemFormSheet.buildInputGroup(
            label:   'Batch No',
            color:   w.accentColor,
            bgColor: isValid ? w._validFill : null,
            child: ValidatedBatchField(
              textController: c.batchController,
              isValid:        isValid,
              isValidating:   validating,
              isHardError:    isHardError,
              isWarning:      isWarning,
              errorMsg:       errorMsg.isNotEmpty ? errorMsg : null,
              label:          'Enter or scan batch',
              accentColor:    w.accentColor,
              validFill:      w._validFill,
              validBorder:    w._validBorder,
              onReset:        c.resetBatch,
              onValidate:     () => c.validateBatch(c.batchController.text),
              onSubmitted:    c.validateBatch,
              onChanged:      c.validateSheet,
              onPickerTap:    w.onPickerTap,
              tooltipMessage: c.batchInfoTooltip.value,
              fieldKey:       w.fieldKey ?? 'shared_batch_edit',
            ),
          ),
          BrowseBatchButton(
            showBrowseBatches: w.showBrowseBatches,
            isValid:           isValid,
            isReadOnly:        w.readOnly,
            isValidating:      validating,
            itemCode:          c.itemCode.value,
            warehouse:         warehouse,
            accentColor:       w.accentColor,
            batchController:   c.batchController,
            onBatchSelected:   c.validateBatch,
          ),
          BalanceChip(
            balance:   chipBalance,
            isLoading: validating,
            color:     chipColor,
            prefix:    'Batch Balance:',
            forceShow: validating || isValid,
          ),
        ],
      );
    });
  }
}
