import 'package:flutter/material.dart';

/// Represents the outcome of the most recent save attempt.
///
/// The controller sets this after [saveStockEntry] (or any equivalent)
completes and resets it back to [idle] after a 2-second delay so the
button returns to its normal appearance automatically.
enum SaveResult {
  /// No save has been attempted, or the result has already been cleared.
  idle,

  /// The last save completed successfully.
  success,

  /// The last save failed.
  error,
}

/// App-bar save button that cycles through four visual states:
///
/// | Condition | Appearance |
/// |---|---|
/// | `saveResult == success` | ✓ green |
/// | `saveResult == error` | ✕ red |
/// | `isSaving == true` | spinner |
/// | `isDirty == true` | save icon (enabled) |
/// | otherwise | save icon (dimmed, disabled) |
class SaveIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isSaving;
  final bool isDirty;
  final String tooltip;
  final SaveResult saveResult;

  const SaveIconButton({
    super.key,
    required this.onPressed,
    this.isSaving = false,
    this.isDirty = true,
    this.tooltip = 'Save',
    this.saveResult = SaveResult.idle,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    // ── Result feedback (highest priority) ──────────────────────────────
    if (saveResult == SaveResult.success) {
      return Padding(
        padding: const EdgeInsets.all(10.0),
        child: Icon(Icons.check_circle_outline,
            color: Colors.greenAccent.shade400, size: 26),
      );
    }

    if (saveResult == SaveResult.error) {
      return Padding(
        padding: const EdgeInsets.all(10.0),
        child: Icon(Icons.cancel_outlined,
            color: Colors.redAccent.shade200, size: 26),
      );
    }

    // ── In-flight spinner ────────────────────────────────────────────────
    if (isSaving) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: onPrimary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    // ── Idle save icon ───────────────────────────────────────────────────
    return IconButton(
      icon: const Icon(Icons.save),
      tooltip: tooltip,
      onPressed: isDirty ? onPressed : null,
      color: isDirty ? onPrimary : onPrimary.withOpacity(0.5),
    );
  }
}
