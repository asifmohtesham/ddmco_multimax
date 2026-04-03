import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/batch_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable Batch No input field backed by any [ItemSheetControllerBase].
///
/// ## Modes
///
/// ### `editMode: false` (default -- SE style)
/// Plain [TextField] with borderless card container. A [BalanceChip] is
/// rendered below the field showing the batch balance.
///
/// ### `editMode: true` (DN / PR style)
/// [TextFormField] with [OutlineInputBorder], readOnly-when-valid-and-clean,
/// explicit **Edit** button. [BalanceChip] shown below the field.
///
/// ## Balance source
/// By default the [BalanceChip] sources `c.maxQty` (computed getter on base;
/// see Commit 4). Pass [balanceOverride] to supply an alternative balance
/// getter -- for example Stock Entry, which maintains a separate per-warehouse
/// `batchBalance` distinct from the base `maxQty` field:
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
/// P3-A : readOnly requires isValid AND batchError==null.
/// P3-A : helperText / border colour is 3-tier (red / orange / grey).
/// P3-B : errorText only for hard-invalid; warning rendered as orange helperText.
/// P4-1 : _SimpleField now also respects c.isBatchReadOnly (parity with SE local BatchField).
/// C    : Added [showBrowseBatches] flag -- renders a 'Browse Batches ->' text
///        button that opens [BatchPickerSheet] when the batch is not yet
///        validated.  Passing warehouse + accentColor is optional; the field
///        falls back to controller values automatically.
/// P3-2 : Added [onPickerTap] -- when provided, a list-picker icon button is
///        injected into the suffixIcon Row in both idle and valid states.
/// fix  : Removed stale `.value` calls on `c.maxQty` -- maxQty is a plain
///        `double` computed getter since Commit 4, not an RxDouble.
/// fix(BATCH-ICON): wrap every multi-icon suffixIcon Row in a SizedBox with
///        explicit width so Flutter's tight suffixIcon constraints do not
///        collapse the Row to zero width (hiding the picker icon).
/// fix(BATCH-ICON-VALID): render picker btn in valid state; compute SizedBox
///        width dynamically based on which slots (tooltip, picker, edit) are
///        visible, so the icon is never clipped.
class SharedBatchField extends StatelessWidget {
  final ItemSheetControllerBase c;
  final Color  accentColor;
  final bool   editMode;
  final bool   readOnly;
  final String? fieldKey;

  /// Whether to show the "Browse Batches ->" shortcut button below the field.
  /// Defaults to false to preserve backward compatibility.
  final bool showBrowseBatches;

  /// Optional warehouse override for the batch picker.  When null the field
  /// reads [ItemSheetControllerBase.resolvedWarehouse].
  final String? browseWarehouse;

  /// Optional balance override.  When non-null, the [BalanceChip] calls this
  /// getter on every rebuild instead of reading [ItemSheetControllerBase.maxQty].
  final double? Function()? balanceOverride;

  /// Optional callback fired when the list-picker icon button inside the
  /// suffixIcon is tapped.  When provided, the button is shown in both the
  /// idle (not-yet-valid) and valid states.  The full picker lifecycle is owned
  /// by the caller -- this widget only renders the button and fires the callback.
  ///
  /// When null (default) no picker button is added to the suffix row.
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

// ── Picker suffix icon button (shared helper) ────────────────────────────────────
Widget _pickerSuffixBtn(Color color, VoidCallback onTap) => IconButton(
      icon:      Icon(Icons.format_list_bulleted_rounded, color: color, size: 20),
      onPressed: onTap,
      tooltip:   'Browse batches',
      padding:   EdgeInsets.zero,
    );

// ── Browse-batch button (shared by both modes, below the field) ────────────
class _BrowseBatchButton extends StatelessWidget {
  final SharedBatchField w;
  const _BrowseBatchButton(this.w);

  @override
  Widget build(BuildContext context) {
    if (!w.showBrowseBatches) return const SizedBox.shrink();

    return Obx(() {
      final c          = w.c;
      final isValid    = c.isBatchValid.value;
      final isRO       = w.readOnly || c.isBatchReadOnly.value;
      final validating = c.isValidatingBatch.value;

      if (isValid || isRO || validating) return const SizedBox.shrink();

      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () async {
            final warehouse = w.browseWarehouse ?? c.resolvedWarehouse;
            final selected  = await showBatchPickerSheet(
              context,
              itemCode:    c.itemCode.value,
              warehouse:   warehouse,
              accentColor: w.accentColor,
            );
            if (selected != null && selected.isNotEmpty) {
              c.batchController.text = selected;
              await c.validateBatch(selected);
            }
          },
          icon : Icon(Icons.list_alt, size: 16, color: w.accentColor),
          label: Text(
            'Browse Batches',
            style: TextStyle(
              color:      w.accentColor,
              fontSize:   12,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: TextButton.styleFrom(
            padding:         const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize:   MaterialTapTargetSize.shrinkWrap,
            minimumSize:     Size.zero,
          ),
        ),
      );
    });
  }
}

// ── Simple (borderless) mode ─────────────────────────────────────────────────
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
      final isHardError = !isValid && errorMsg != null;
      final isWarning   =  isValid && errorMsg != null;

      final borderColor = isHardError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : w.accentColor;

      final chipColor   = isWarning ? Colors.orange : w.accentColor;
      final chipBalance = w.balanceOverride?.call() ?? c.maxQty;

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
          _BrowseBatchButton(w),
          BalanceChip(
            balance:   chipBalance,
            isLoading: validating,
            color:     chipColor,
            prefix:    'Batch Balance:',
          ),
        ],
      );
    });
  }
}

// ── Edit-mode (OutlineInputBorder, readOnly-when-valid-and-clean) ─────────────
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

      final isHardError = !isValid && errorMsg != null;
      final isWarning   =  isValid && errorMsg != null;

      final effectiveReadOnly  = w.readOnly || (isValid && !isWarning);
      final helperColor        = isHardError
          ? Colors.red
          : isWarning ? Colors.orange : Colors.grey;
      final enabledBorderColor = isHardError
          ? Colors.red
          : isWarning ? Colors.orange : w._validBorder;
      final chipColor   = isWarning ? Colors.orange : w.accentColor;
      final chipBalance = w.balanceOverride?.call() ?? c.maxQty;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlobalItemFormSheet.buildInputGroup(
            label:   'Batch No',
            color:   w.accentColor,
            bgColor: isValid ? w._validFill : null,
            child: TextFormField(
              key:        ValueKey(w.fieldKey ?? 'shared_batch_edit'),
              controller: c.batchController,
              readOnly:   effectiveReadOnly,
              autofocus:  false,
              style: const TextStyle(fontFamily: 'ShureTechMono'),
              decoration: InputDecoration(
                hintText:       'Enter or scan batch',
                helperText:     errorMsg,
                helperMaxLines: 2,
                helperStyle: TextStyle(
                  color:      helperColor,
                  fontWeight: (isHardError || isWarning)
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:   BorderSide(color: enabledBorderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isHardError
                        ? Colors.red
                        : isWarning ? Colors.orange : w.accentColor,
                    width: 2,
                  ),
                ),
                filled:    true,
                fillColor: isValid ? w._validFill : Colors.white,
                suffixIcon: _suffixIcon(c, isValid, validating, isWarning),
              ),
              onChanged:        (_) => c.validateSheet(),
              onFieldSubmitted: (val) {
                if (!c.isBatchValid.value) c.validateBatch(val);
              },
            ),
          ),
          _BrowseBatchButton(w),
          BalanceChip(
            balance:   chipBalance,
            isLoading: validating,
            color:     chipColor,
            prefix:    'Batch Balance:',
          ),
        ],
      );
    });
  }

  Widget _suffixIcon(
    ItemSheetControllerBase c,
    bool isValid,
    bool validating,
    bool isWarning,
  ) {
    if (validating) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: w.accentColor),
        ),
      );
    }

    // fix(BATCH-ICON): SizedBox with explicit width prevents tight-constraints
    // collapse of the inner Row (Flutter's suffixIcon slot forces tight
    // BoxConstraints, making a bare mainAxisSize.min Row collapse to 0 width).
    // Width is computed dynamically: 48px per visible action slot.

    if (isValid) {
      // Slots: [tooltip?] [picker?] [edit]
      final hasPicker  = w.onPickerTap != null;
      final hasTooltip = c.batchInfoTooltip.value != null;
      final width = 48.0
          + (hasPicker  ? 48.0 : 0.0)
          + (hasTooltip ? 48.0 : 0.0);
      return SizedBox(
        width: width,
        child: Row(
          mainAxisSize:      MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (hasTooltip)
              Tooltip(
                message:     c.batchInfoTooltip.value!,
                triggerMode: TooltipTriggerMode.tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    isWarning
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    color: isWarning ? Colors.orange : w.accentColor,
                    size: 20,
                  ),
                ),
              ),
            // fix(BATCH-ICON-VALID): picker also shown in valid state.
            if (hasPicker)
              _pickerSuffixBtn(
                isWarning ? Colors.orange : w.accentColor,
                w.onPickerTap!,
              ),
            IconButton(
              icon:     Icon(Icons.edit,
                  color: isWarning ? Colors.orange : w.accentColor,
                  size: 20),
              onPressed: c.resetBatch,
              tooltip:   'Edit Batch',
            ),
          ],
        ),
      );
    }

    // Idle state: [picker?] [validate arrow]
    final hasPicker = w.onPickerTap != null;
    return SizedBox(
      width: hasPicker ? 96.0 : 48.0,
      child: Row(
        mainAxisSize:      MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (hasPicker)
            _pickerSuffixBtn(w.accentColor, w.onPickerTap!),
          IconButton(
            icon:      const Icon(Icons.arrow_forward),
            onPressed: () => c.validateBatch(c.batchController.text),
            tooltip:   'Validate',
            color:     Colors.grey,
          ),
        ],
      ),
    );
  }
}
