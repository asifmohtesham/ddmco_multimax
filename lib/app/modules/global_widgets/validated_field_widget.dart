import 'package:flutter/material.dart';

/// A text field that follows the enter-or-scan → validate → lock lifecycle.
///
/// The widget is intentionally free of Rx / GetX so that callers can wrap
/// it in `Obx` with precisely-scoped reactivity.  Pass the current
/// controller state as plain constructor parameters and rebuild as needed.
///
/// Lifecycle visual states
/// ───────────────────────
/// 1. **Idle** (`!isValid && !isValidating`)  
///    Field is editable.  Suffix shows a ✓ icon-button to trigger
///    validation.
/// 2. **Validating** (`isValidating`)  
///    Field is read-only.  Suffix shows a spinner.
/// 3. **Valid** (`isValid && !isValidating`)  
///    Field is read-only.  Suffix shows optional [extraSuffixActions]
///    followed by an ✏ edit icon-button to reset.
///
/// Below the field an optional [chip] widget is rendered (e.g. BalanceChip).
/// An optional [errorText] is shown below the chip in red (e.g. rack-stock
/// over-allocation message).
class ValidatedFieldWidget extends StatelessWidget {
  /// Text editing controller — must be provided by the caller.
  final TextEditingController controller;

  /// Optional focus node (e.g. to auto-focus after batch validation).
  final FocusNode? focusNode;

  /// Accent colour used for borders, spinner, icons, and fill.
  final Color color;

  /// Placeholder text shown when the field is empty.
  final String hintText;

  /// When true the field is not editable (validated state).
  final bool isReadOnly;

  /// Whether the field value has been successfully validated.
  final bool isValid;

  /// Whether a validation request is in flight.
  final bool isValidating;

  /// Inline helper text shown below the field (e.g. batch error message).
  /// Rendered in red + bold when [hasError] is true.
  final String? helperText;

  /// When true [helperText] is styled as an error (red, bold).
  final bool hasError;

  /// Called when the user taps the validate (✓) button or submits the
  /// field via the keyboard.
  final VoidCallback onValidate;

  /// Called when the user taps the edit (✏) button to reset the field.
  final VoidCallback onReset;

  /// Additional icon widgets inserted before the edit button when the
  /// field is in the valid state.  Typical use: an info-tooltip icon.
  final List<Widget> extraSuffixActions;

  /// Optional widget rendered directly below the field.  Intended for
  /// a [BalanceChip] but accepts any widget.
  final Widget? chip;

  /// Optional error message shown below [chip] in red.  Distinct from
  /// [helperText]: this is for post-validation constraint errors (e.g.
  /// "Only 5 available in RACK-01").
  final String? errorText;

  /// Called on every keystroke (forwarded to [TextFormField.onChanged]).
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the field via the keyboard action.
  /// Defaults to calling [onValidate] when the field is not yet valid.
  final ValueChanged<String>? onFieldSubmitted;

  /// Optional [ValueKey] for the inner [TextFormField].
  final ValueKey<String>? fieldKey;

  /// Font family for the text input (defaults to monospace).
  final String fontFamily;

  const ValidatedFieldWidget({
    super.key,
    required this.controller,
    this.focusNode,
    required this.color,
    required this.hintText,
    required this.isReadOnly,
    required this.isValid,
    required this.isValidating,
    required this.onValidate,
    required this.onReset,
    this.helperText,
    this.hasError = false,
    this.extraSuffixActions = const [],
    this.chip,
    this.errorText,
    this.onChanged,
    this.onFieldSubmitted,
    this.fieldKey,
    this.fontFamily = 'ShureTechMono',
  });

  Widget _buildSuffixIcon() {
    if (isValidating) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      );
    }

    if (isValid) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...extraSuffixActions,
          IconButton(
            icon: Icon(Icons.edit, color: color),
            onPressed: onReset,
            tooltip: 'Edit',
          ),
        ],
      );
    }

    return IconButton(
      icon: Icon(Icons.check, color: color),
      onPressed: onValidate,
      tooltip: 'Validate',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          readOnly: isReadOnly,
          autofocus: false,
          style: TextStyle(fontFamily: fontFamily),
          decoration: InputDecoration(
            hintText: hintText,
            helperText: helperText,
            helperStyle: TextStyle(
              color: hasError ? Colors.red : Colors.grey,
              fontWeight: hasError ? FontWeight.bold : FontWeight.normal,
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : color.withOpacity(0.4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : color,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: isValid ? color.withOpacity(0.05) : Colors.white,
            suffixIcon: _buildSuffixIcon(),
          ),
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted ??
              (_) { if (!isValid) onValidate(); },
        ),
        if (chip != null) chip!,
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, left: 4.0),
            child: Text(
              errorText!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
