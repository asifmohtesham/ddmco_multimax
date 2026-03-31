import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';

/// Thin wrapper around [ValidatedFieldWidget] for rack fields.
///
/// Accepts plain-primitive state so the caller ([SharedDualRackSection] for
/// SE) can wrap in its own `Obx` with precisely-scoped reactivity.
///
/// ## Picker integration
/// Pass [onPickerTap] to show a rack-picker icon button (shelves icon) in the
/// suffix area in **both** idle and valid states:
///
/// * **Idle**  : `[shelves] [✓]`  — pick a rack OR type and validate manually.
/// * **Valid** : `[shelves] [✏]`  — change rack without clearing first.
/// * **Validating**: spinner only (no picker while a round-trip is in flight).
///
/// The full picker lifecycle (controller creation, data load, sheet
/// presentation) is owned by the caller — this widget only renders the
/// button and fires the callback on tap.
class ValidatedRackField extends StatelessWidget {
  final TextEditingController textController;
  final bool                  isValid;
  final bool                  isValidating;
  final String                label;
  final Color                 color;
  final VoidCallback          onReset;
  final VoidCallback          onValidate;
  final ValueChanged<String>  onSubmitted;

  /// Optional callback fired when the picker icon button is tapped.
  /// When null, no picker button is shown (falls back to plain ✓ / ✏).
  final VoidCallback? onPickerTap;

  const ValidatedRackField({
    super.key,
    required this.textController,
    required this.isValid,
    required this.isValidating,
    required this.label,
    required this.color,
    required this.onReset,
    required this.onValidate,
    required this.onSubmitted,
    this.onPickerTap,
  });

  // ── Picker icon button (shared between idle + valid suffix rows) ───────────
  Widget _pickerBtn() => IconButton(
        icon:     const Icon(Icons.shelves),
        onPressed: onPickerTap,
        tooltip:  'Browse racks',
        iconSize: 20,
        padding:  EdgeInsets.zero,
        constraints: const BoxConstraints(),
      );

  // ── Idle composite suffix: [shelves] + [✓] ─────────────────────────────────
  Widget _idlePickerSuffix() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pickerBtn(),
          IconButton(
            icon:     Icon(Icons.check, color: color),
            onPressed: onValidate,
            tooltip:  'Validate',
            padding:  EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ValidatedFieldWidget(
      controller:       textController,
      color:            color,
      hintText:         label,
      isReadOnly:       isValid,
      isValid:          isValid,
      isValidating:     isValidating,
      onValidate:       onValidate,
      onReset:          onReset,
      onFieldSubmitted: onSubmitted,
      fontFamily:       'ShureTechMono',
      // Valid state: picker before the edit button.
      extraSuffixActions: onPickerTap != null ? [_pickerBtn()] : const [],
      // Idle state: composite row replaces the plain ✓ button.
      idleSuffixWidget: onPickerTap != null ? _idlePickerSuffix() : null,
    );
  }
}
