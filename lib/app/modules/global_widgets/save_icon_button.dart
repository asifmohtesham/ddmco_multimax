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

    return IconButton(
      icon: const Icon(Icons.save),
      tooltip: tooltip,
      // The button is disabled if the form is not dirty (no changes to save)
      // or if onPressed is manually set to null.
      onPressed: isDirty ? onPressed : null,
      // Optional: Visual cue for disabled state if needed, though IconButton handles opacity automatically
      color: isDirty ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onPrimary.withOpacity(0.5),
    );
  }
}