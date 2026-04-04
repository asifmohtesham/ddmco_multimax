// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/batch_no_field_with_browse_delegate.dart';
import 'package:multimax/app/shared/item_sheet/widgets/browse_batch_button.dart';
import 'package:multimax/app/shared/item_sheet/widgets/validated_batch_field.dart';

/// A reusable Batch No input field backed by any
/// [BatchNoFieldWithBrowseDelegate].
///
/// ## Modes
///
/// ### `editMode: false` (default -- SE style)
/// Plain [TextField] with borderless card container. A [BalanceChip] is
/// rendered below the field showing the batch balance.
///
/// ### `editMode: true` (DN / PR style)
/// [ValidatedBatchField] with [OutlineInputBorder], readOnly-when-valid,
/// explicit **Edit** button. [BalanceChip] shown below the field.
///
/// ## Controller contract
///
/// `c` is typed as [BatchNoFieldWithBrowseDelegate] — the narrow interface
/// defined in Commit 3 of the batch-field refactor.  Any controller that
/// implements this interface (including all [ItemSheetControllerBase]
/// subclasses, which adopt it in Commit 7) can be passed without change.
///
/// ## Balance source
/// By default the [BalanceChip] sources `c.batchBalanceFor('')` (the
/// delegate's balance accessor).  Pass [balanceOverride] to supply an
/// alternative balance getter — for example Stock Entry, which maintains a
/// separate per-warehouse `batchBalance` distinct from the delegate value:
///
/// ```dart
/// SharedBatchField(
///   c:               child,
///   accentColor:     Colors.purple,
///   balanceOverride: () => child.batchBalance.value,
/// )
/// ```
///
/// P2-1 : added [balanceOverride] optional callback.
/// P3-A : readOnly requires isValid AND batchError==''.
/// P3-A : helperText / border colour is 3-tier (red / orange / grey).
/// P3-B : errorText only for hard-invalid; warning rendered as orange helperText.
/// P4-1 : _SimpleField now also respects c.isBatchReadOnly (parity with SE local BatchField).
/// C    : Added [showBrowseBatches] flag -- renders a 'Browse Batches ->'
///        text button that opens [BatchPickerSheet] when the batch is not yet
///        validated.  Passing warehouse + accentColor is optional.
/// P3-2 : Added [onPickerTap] -- when provided, a list-picker icon button is
///        injected into the suffixIcon Row in both idle and valid states.
/// fix  : Removed stale `.value` calls on `c.maxQty`.
/// fix(BATCH-ICON): wrap every multi-icon suffixIcon Row in SizedBox with
///        explicit width so Flutter tight constraints do not collapse the Row.
/// fix(BATCH-ICON-VALID): render picker btn in valid state; compute SizedBox
///        width dynamically based on visible slots.
/// fix(SE-BATCH-ICON): _SimpleField now also renders picker btn in valid state.
/// DN-8 : pass forceShow: validating to all BalanceChip calls.
/// DN-9 : forceShow: validating || isValid.
/// fix(batch-field): isDense: true in both InputDecorations.
/// Commit 7: c re-typed to BatchNoFieldWithBrowseDelegate; _EditModeField
///        delegates to ValidatedBatchField; _BrowseBatchButton replaced with
///        BrowseBatchButton (extracted in Commit 6).
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
  /// getter on every rebuild instead of the delegate accessor.
  final double? Function()? balanceOverride;

  /// Optional callback fired when the list-picker icon button is tapped.
  /// When provided, the button is shown in both idle and valid states.
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
