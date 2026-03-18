import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';

/// Thin wrapper around [ValidatedFieldWidget] for rack fields in Stock Entry.
///
/// Accepts plain-primitive state so the caller (RackSection) can wrap in
/// its own Obx with precisely-scoped reactivity.
class ValidatedRackField extends StatelessWidget {
  final TextEditingController textController;
  final bool isValid;
  final bool isValidating;
  final String label;
  final Color color;
  final VoidCallback onReset;
  final VoidCallback onValidate;
  final ValueChanged<String> onSubmitted;

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
  });

  @override
  Widget build(BuildContext context) {
    return ValidatedFieldWidget(
      controller: textController,
      color: color,
      hintText: label,
      isReadOnly: isValid,
      isValid: isValid,
      isValidating: isValidating,
      onValidate: onValidate,
      onReset: onReset,
      onFieldSubmitted: onSubmitted,
      fontFamily: 'ShureTechMono',
    );
  }
}
