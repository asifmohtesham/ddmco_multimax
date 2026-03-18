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
/// and a clear/submit icon row. Used by Stock Entry.
///
/// ### `editMode: true` (DN / PR style)
/// A [TextFormField] with [OutlineInputBorder], readOnly-when-valid, and an
/// explicit **Edit** button to unlock the field. The [accentColor] drives the
/// border and valid-state tint. Error text rendered as `helperText`.
/// Replaces the private `_BatchFieldDN` widget and the inline PR batch field.
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

  // Returns accentColor.shade50 when available, else a 10% opacity tint.
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
class _SimpleField extends StatelessWidget {
  final SharedBatchField w;
  const _SimpleField(this.w);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c     = w.c;

    return Obx(() {
      final hasError   = c.batchError.value != null;
      final isValid    = c.isBatchValid.value;
      final validating = c.isValidatingBatch.value;

      final borderColor = hasError
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
            errorText:   c.batchError.value,
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

// ── Edit-mode (OutlineInputBorder, readOnly-when-valid) ──────────────────────
// Replaces: _BatchFieldDN (DN) and the inline Obx batch field (PR).
class _EditModeField extends StatelessWidget {
  final SharedBatchField w;
  const _EditModeField(this.w);

  @override
  Widget build(BuildContext context) {
    final c = w.c;

    return Obx(() {
      final isValid    = c.isBatchValid.value;
      final validating = c.isValidatingBatch.value;
      final hasError   = c.batchError.value != null;

      final activeBorderColor = hasError ? Colors.red : w.accentColor;

      return GlobalItemFormSheet.buildInputGroup(
        label:   'Batch No',
        color:   w.accentColor,
        bgColor: isValid ? w._validFill : null,
        child: TextFormField(
          key:        ValueKey(w.fieldKey ?? 'shared_batch_edit'),
          controller: c.batchController,
          readOnly:   w.readOnly || isValid,
          autofocus:  false,
          style: const TextStyle(fontFamily: 'ShureTechMono'),
          decoration: InputDecoration(
            hintText: 'Enter or scan batch',
            // Error rendered as helperText to preserve layout height
            helperText: c.batchError.value,
            helperStyle: TextStyle(
              color:      hasError ? Colors.red : Colors.grey,
              fontWeight: hasError ? FontWeight.bold : FontWeight.normal,
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: hasError ? Colors.red : w._validBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: activeBorderColor, width: 2),
            ),
            filled:    true,
            fillColor: isValid ? w._validFill : Colors.white,
            suffixIcon: _suffixIcon(c, isValid, validating),
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
                child: Icon(Icons.info_outline,
                    color: w.accentColor, size: 20),
              ),
            ),
          IconButton(
            icon:    Icon(Icons.edit, color: w.accentColor, size: 20),
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
