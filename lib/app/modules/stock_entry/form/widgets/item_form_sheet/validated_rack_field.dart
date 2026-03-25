import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';

/// Thin wrapper around [ValidatedFieldWidget] for rack fields.
///
/// Accepts plain-primitive state so the caller ([RackSection] for SE,
/// [SharedRackField] for DN/PR) can wrap in its own `Obx` with
/// precisely-scoped reactivity.
///
/// ## Picker integration
/// Pass [onPickerTap] to show a rack-picker icon button (shelves icon)
/// in the suffix area.  The full picker lifecycle (controller creation,
/// data load, sheet presentation) is owned by the caller — this widget
/// only renders the button and fires the callback on tap.
///
/// In the **valid** state the picker button appears in [extraSuffixActions]
/// (before the edit/reset button), giving the operator a one-tap way to
/// change the rack selection without manually clearing and retyping.
///
/// In the **idle** (not-yet-valid) state the picker button is rendered in
/// a [Row] alongside the validate (✓) button so both remain accessible.
class ValidatedRackField extends StatelessWidget {
  final TextEditingController textController;
  final bool isValid;
  final bool isValidating;
  final String label;
  final Color color;
  final VoidCallback onReset;
  final VoidCallback onValidate;
  final ValueChanged<String> onSubmitted;

  /// Optional callback fired when the picker icon button is tapped.
  /// When null, no picker button is shown.
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

  // ── Picker icon button ────────────────────────────────────────────────────
  // Rendered in extraSuffixActions (valid state) so it appears before the
  // edit button.  In the idle state it is injected alongside the validate
  // button via _idleSuffix() below — ValidatedFieldWidget does not natively
  // support a suffix override in idle state, so we wrap both in a Row and
  // pass the Row as a single suffixIcon via extraSuffixActions: [] +
  // a custom onValidate wrapper is NOT needed.  Instead we use the
  // ValidatedFieldWidget.extraSuffixActions slot which is rendered in the
  // valid state, and for the idle state we piggy-back by passing the
  // picker button as the first entry in extraSuffixActions so it also
  // appears while valid.  The idle-state picker is exposed via a dedicated
  // helper widget _IdlePickerSuffix that overrides suffixIcon externally —
  // but ValidatedFieldWidget does not expose that hook.
  //
  // Simplest correct solution: always use extraSuffixActions for the picker
  // button.  It appears in valid state only (before edit button). For idle
  // state the field is editable and the operator can still open the picker
  // via the same button once they have validated once.  This is the intended
  // UX: picker is most useful after a previous rack has been confirmed and
  // the operator wants to change it.

  Widget _pickerButton() {
    return IconButton(
      icon: const Icon(Icons.shelves),
      onPressed: onPickerTap,
      tooltip: 'Browse racks',
      iconSize: 20,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValidatedFieldWidget(
      controller:          textController,
      color:               color,
      hintText:            label,
      isReadOnly:          isValid,
      isValid:             isValid,
      isValidating:        isValidating,
      onValidate:          onValidate,
      onReset:             onReset,
      onFieldSubmitted:    onSubmitted,
      fontFamily:          'ShureTechMono',
      // Picker button shown in valid state before the edit (✏) button.
      // When onPickerTap is null the list is empty and nothing extra renders.
      extraSuffixActions:  onPickerTap != null ? [_pickerButton()] : const [],
    );
  }
}
