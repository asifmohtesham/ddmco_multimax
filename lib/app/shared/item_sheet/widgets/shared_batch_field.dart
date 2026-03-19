import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// A reusable Batch No input field backed by any [ItemSheetControllerBase].
///
/// ## Modes
///
/// ### `editMode: false` (default — SE style)
/// A plain [TextField] with a borderless card container, checkmark when valid,
/// and a clear/submit icon row.
///
/// ### `editMode: true` (DN / PR style)
/// A [TextFormField] with [OutlineInputBorder], readOnly-when-valid-and-clean,
/// and an explicit **Edit** button to unlock the field.
///
/// P3-A: readOnly now requires isValid AND batchError==null so a P2-A
///       zero-stock warning keeps the field editable.
/// P3-A: helperText / border colour uses three tiers:
///         isBatchValid=false           → red   (hard block)
///         isBatchValid=true, error≠null → orange (warning)
///         no error                      → grey
/// P3-B: _SimpleField uses errorText only for hard-invalid state;
///       P2-A warning rendered as orange helperText instead.
class SharedBatchField extends StatelessWidget {
  final ItemSheetControllerBase c;
  final Color  accentColor;
  final bool   editMode;
  final bool   readOnly;
  final String? fieldKey;

  const SharedBatchField({
    super.key,
    required this.c,
    required this.accentColor,
    this.editMode  = false,
    this.readOnly  = false,
    this.fieldKey,
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

// ── Simple (borderless) mode ─────────────────────────────────────────────────
// P3-B: errorText used only for hard-invalid (isBatchValid=false + error).
//       P2-A warning (isBatchValid=true + error) shown as orange helperText.
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

      // Hard block: invalid batch with an error string.
      final isHardError = !isValid && errorMsg != null;
      // Soft warning: valid batch but zero-stock message.
      final isWarning   =  isValid && errorMsg != null;

      final borderColor = isHardError
          ? theme.colorScheme.error
          : isValid
              ? Colors.green
              : w.accentColor;

      return GlobalItemFormSheet.buildInputGroup(
        label: 'Batch No',
        color: borderColor,
        child: TextField(
          controller: c.batchController,
          readOnly:   w.readOnly,
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
            // P3-B: hard error only
            errorText:     isHardError ? errorMsg : null,
            errorMaxLines: 2,
            // P3-B: warning shown as helper (orange) so no red underline
            helperText: isWarning ? errorMsg : null,
            helperMaxLines: 2,
            helperStyle: isWarning
                ? const TextStyle(
                    color:      Colors.orange,
                    fontWeight: FontWeight.w600,
                    fontSize:   11,
                  )
                : null,
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
                if (c.batchController.text.isNotEmpty && !w.readOnly)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      c.batchController.clear();
                      c.resetBatch();
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ── Edit-mode (OutlineInputBorder, readOnly-when-valid-and-clean) ─────────────
// P3-A: readOnly = readOnly || (isValid && batchError == null)
//       so a zero-stock warning does not lock the field.
// P3-A: helperText colour uses three tiers (red / orange / grey).
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

      // P3-A: field is locked only when valid AND no warning is active.
      final effectiveReadOnly = w.readOnly || (isValid && !isWarning);

      // P3-A: three-tier border / helper colour.
      final helperColor = isHardError
          ? Colors.red
          : isWarning
              ? Colors.orange
              : Colors.grey;

      final enabledBorderColor = isHardError
          ? Colors.red
          : isWarning
              ? Colors.orange
              : w._validBorder;

      return GlobalItemFormSheet.buildInputGroup(
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
            hintText: 'Enter or scan batch',
            helperText: errorMsg,
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
              borderSide: BorderSide(color: enabledBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isHardError
                    ? Colors.red
                    : isWarning
                        ? Colors.orange
                        : w.accentColor,
                width: 2,
              ),
            ),
            filled:    true,
            fillColor: isValid ? w._validFill : Colors.white,
            suffixIcon: _suffixIcon(c, isValid, validating, isWarning),
          ),
          onChanged: (_) => c.validateSheet(),
          onFieldSubmitted: (val) {
            if (!c.isBatchValid.value) c.validateBatch(val);
          },
        ),
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
    if (isValid) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.batchInfoTooltip.value != null)
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
          IconButton(
            icon:  Icon(Icons.edit,
                color: isWarning ? Colors.orange : w.accentColor,
                size: 20),
            onPressed: c.resetBatch,
            tooltip: 'Edit Batch',
          ),
        ],
      );
    }
    return IconButton(
      icon:      const Icon(Icons.arrow_forward),
      onPressed: () => c.validateBatch(c.batchController.text),
      tooltip:   'Validate',
      color:     Colors.grey,
    );
  }
}
