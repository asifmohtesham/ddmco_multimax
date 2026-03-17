import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

/// Step 2 — replaces the two near-identical Source Rack / Target Rack blocks.
/// Parameterised by [color], callbacks, and reactive state from the controller.
class ValidatedRackField extends StatelessWidget {
  final TextEditingController textController;
  final RxBool isValid;
  final RxBool isValidating;
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

  Widget _suffixIcon() {
    if (isValidating.value) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      );
    }
    if (isValid.value) {
      return IconButton(
        icon: Icon(Icons.edit, color: color),
        onPressed: onReset,
      );
    }
    return IconButton(
      icon: Icon(Icons.check, color: color),
      onPressed: onValidate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalItemFormSheet.buildInputGroup(
          label: label,
          color: color,
          bgColor: isValid.value ? color.withOpacity(0.07) : null,
          child: TextFormField(
            controller: textController,
            readOnly: isValid.value,
            autofocus: false,
            decoration: InputDecoration(
              hintText: 'Rack',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: color.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: color, width: 2),
              ),
              filled: true,
              fillColor:
                  isValid.value ? color.withOpacity(0.07) : Colors.white,
              suffixIcon: _suffixIcon(),
            ),
            onFieldSubmitted: onSubmitted,
          ),
        ));
  }
}
