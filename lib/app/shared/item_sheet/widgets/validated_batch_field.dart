// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';

/// Thin primitive-state wrapper that renders the batch-no input in its
/// validated / validating / idle states using an [OutlineInputBorder].
///
/// ## Why this file lives in `shared/item_sheet/widgets/`
///
/// Mirrors [ValidatedRackField] — created here (rather than inside a specific
/// DocType module) so that **any** DocType can reference it without a
/// cross-module dependency.  [SharedBatchField] delegates its
/// `_EditModeField` rendering to this widget starting from Commit 7.
///
/// ## Responsibility
///
/// Accepts **plain-primitive state** so the caller can wrap it in its own
/// `Obx` with precisely-scoped reactivity.  This widget owns only:
/// - Rendering the three suffix states (idle, validating, valid)
/// - Surfacing a picker button when [onPickerTap] is provided
/// - Rendering the [OutlineInputBorder] form field with all border variants
///
/// It never reads from a controller, never modifies state, and never owns
/// a [TextEditingController] lifecycle.
///
/// ## Suffix-icon states
///
/// | State      | Suffix row                                           |
/// |------------|------------------------------------------------------|
/// | Idle       | `[picker btn]?` + `[✓ validate btn]`                |
/// | Validating | spinner only (picker suppressed during in-flight req) |
/// | Valid      | `[tooltip icon]?` + `[picker btn]?` + `[✏ edit btn]` |
///
/// ## Picker integration
///
/// Pass [onPickerTap] to show the shelves icon button in idle and valid
/// states.  The full picker lifecycle — controller creation, data load,
/// sheet presentation — is owned by the **caller**.  This widget only
/// renders the button and fires [onPickerTap] on tap.
///
/// ## Usage
///
/// ```dart
/// Obx(() => ValidatedBatchField(
///   textController: c.batchController,
///   isValid:        c.isBatchValid.value,
///   isValidating:   c.isValidatingBatch.value,
///   isHardError:    !c.isBatchValid.value && c.batchError.value.isNotEmpty,
///   isWarning:       c.isBatchValid.value && c.batchError.value.isNotEmpty,
///   errorMsg:       c.batchError.value.isNotEmpty ? c.batchError.value : null,
///   label:          'Enter or scan batch',
///   accentColor:    Colors.purple,
///   validFill:      Colors.purple.shade50,
///   validBorder:    Colors.purple.shade200,
///   onReset:        c.resetBatch,
///   onValidate:     () => c.validateBatch(c.batchController.text),
///   onSubmitted:    c.validateBatch,
///   onPickerTap:    () => _openBatchPicker(),  // optional
///   tooltipMessage: c.batchInfoTooltip.value,  // optional
///   fieldKey:       'shared_batch_edit',
/// ))
/// ```
class ValidatedBatchField extends StatelessWidget {
  /// The controller whose text reflects the currently entered batch number.
  /// This widget never modifies the controller.
  final TextEditingController textController;

  /// Whether the current batch value has been confirmed valid by the server.
  /// When `true`, the field becomes read-only and the edit (✏) suffix is shown.
  final bool isValid;

  /// Whether a validation round-trip is currently in flight.
  /// When `true`, a spinner replaces all suffix actions.
  final bool isValidating;

  /// Whether the field is in a hard-error state (invalid batch).
  /// Drives [Colors.red] border and error-colour helper text.
  final bool isHardError;

  /// Whether the field is in a warning state (valid but with a caution message).
  /// Drives [Colors.orange] border and warning-colour helper text.
  final bool isWarning;

  /// The validation message shown as [InputDecoration.helperText].
  /// Null when no message should be displayed.
  final String? errorMsg;

  /// Inner hint text shown inside the field boundary.
  /// Typically `'Enter or scan batch'` or a DocType-specific variant.
  final String label;

  /// Accent colour for icons, validate button, and focused border.
  /// Should match the parent DocType's theme colour.
  final Color accentColor;

  /// Fill colour applied to the field when [isValid] is `true`.
  /// Typically a very light shade of [accentColor] (e.g. `shade50`).
  final Color validFill;

  /// Enabled-border colour applied when [isValid] is `true`.
  /// Typically a medium shade of [accentColor] (e.g. `shade200`).
  final Color validBorder;

  /// Callback invoked when the user taps the edit (✏) button or the field
  /// should be cleared.  The caller resets all batch-related reactive state.
  final VoidCallback onReset;

  /// Callback invoked when the user taps the validate (✓) button.
  final VoidCallback onValidate;

  /// Callback invoked when the user submits the text field via keyboard.
  final ValueChanged<String> onSubmitted;

  /// Called when [onChanged] fires — lets the parent sheet re-run its own
  /// validation (e.g. [ItemSheetControllerBase.validateSheet]).  Optional.
  final VoidCallback? onChanged;

  /// Optional callback fired when the picker (shelves) icon button is tapped.
  /// When non-null, the shelves icon is shown in idle and valid states.
  final VoidCallback? onPickerTap;

  /// Optional tooltip message shown as an info/warning icon in the valid
  /// suffix row.  Typically sourced from [batchInfoTooltip].
  final String? tooltipMessage;

  /// Optional [ValueKey] string applied to the [TextFormField].
  final String? fieldKey;

  const ValidatedBatchField({
    super.key,
    required this.textController,
    required this.isValid,
    required this.isValidating,
    required this.isHardError,
    required this.isWarning,
    required this.label,
    required this.accentColor,
    required this.validFill,
    required this.validBorder,
    required this.onReset,
    required this.onValidate,
    required this.onSubmitted,
    this.errorMsg,
    this.onChanged,
    this.onPickerTap,
    this.tooltipMessage,
    this.fieldKey,
  });

  // ── Private helpers ──────────────────────────────────────────────────────

  Color get _enabledBorderColor =>
      isHardError ? Colors.red : isWarning ? Colors.orange : validBorder;

  Color get _focusedBorderColor =>
      isHardError ? Colors.red : isWarning ? Colors.orange : accentColor;

  Color get _helperColor =>
      isHardError ? Colors.red : isWarning ? Colors.orange : Colors.grey;

  Widget _pickerBtn() => IconButton(
        icon: Icon(Icons.shelves, color: accentColor, size: 20),
        onPressed: onPickerTap,
        tooltip: 'Browse batches',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      );

  // ── Suffix states ────────────────────────────────────────────────────────

  Widget _buildSuffix() {
    // ── Validating ──────────────────────────────────────────────────────
    if (isValidating) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
        ),
      );
    }

    // ── Valid ───────────────────────────────────────────────────────────
    if (isValid) {
      final hasPicker  = onPickerTap != null;
      final hasTooltip = tooltipMessage != null;
      // 48px per slot: tooltip icon | picker btn | edit btn (always present)
      final width = 48.0 + (hasPicker ? 48.0 : 0.0) + (hasTooltip ? 48.0 : 0.0);
      return SizedBox(
        width: width,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (hasTooltip)
              Tooltip(
                message: tooltipMessage!,
                triggerMode: TooltipTriggerMode.tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    isWarning
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    color: isWarning ? Colors.orange : accentColor,
                    size: 20,
                  ),
                ),
              ),
            if (hasPicker)
              IconButton(
                icon: Icon(
                  Icons.shelves,
                  color: isWarning ? Colors.orange : accentColor,
                  size: 20,
                ),
                onPressed: onPickerTap,
                tooltip: 'Browse batches',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            IconButton(
              icon: Icon(
                Icons.edit,
                color: isWarning ? Colors.orange : accentColor,
                size: 20,
              ),
              onPressed: onReset,
              tooltip: 'Edit Batch',
            ),
          ],
        ),
      );
    }

    // ── Idle ────────────────────────────────────────────────────────────
    final hasPicker = onPickerTap != null;
    return SizedBox(
      width: hasPicker ? 96.0 : 48.0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (hasPicker) _pickerBtn(),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: onValidate,
            tooltip: 'Validate',
            color: Colors.grey,
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key:        fieldKey != null ? ValueKey(fieldKey) : null,
      controller: textController,
      readOnly:   isValid && !isWarning,
      autofocus:  false,
      style: const TextStyle(fontFamily: 'ShureTechMono'),
      decoration: InputDecoration(
        hintText:       label,
        helperText:     errorMsg,
        helperMaxLines: 2,
        helperStyle: errorMsg != null
            ? TextStyle(
                color:      _helperColor,
                fontWeight: (isHardError || isWarning)
                    ? FontWeight.bold
                    : FontWeight.normal,
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   BorderSide(color: _enabledBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   BorderSide(color: _focusedBorderColor, width: 2),
        ),
        filled:    true,
        fillColor: isValid ? validFill : Colors.white,
        // isDense collapses the ~20px invisible helper/error reserved slot
        // so the buildInputGroup tinted Container ends flush with the
        // visible field boundary.  helperText still renders when non-null.
        isDense:    true,
        suffixIcon: _buildSuffix(),
      ),
      onChanged:        (_) => onChanged?.call(),
      onFieldSubmitted: (val) {
        if (!isValid) onSubmitted(val);
      },
    );
  }
}
