import 'package:flutter/material.dart';

class SaveIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isSaving;
  final bool isDirty;
  final String tooltip;

  const SaveIconButton({
    super.key,
    required this.onPressed,
    this.isSaving = false,
    this.isDirty = true,
    this.tooltip = 'Save',
  });

  @override
  Widget build(BuildContext context) {
    if (isSaving) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.onPrimary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    // IconButton automatically renders at reduced opacity when onPressed is null.
    // No manual colour dimming needed — passing null disables the button visually.
    return IconButton(
      icon: const Icon(Icons.save),
      tooltip: tooltip,
      onPressed: isDirty ? onPressed : null,
      color: Theme.of(context).colorScheme.onPrimary,
    );
  }
}
