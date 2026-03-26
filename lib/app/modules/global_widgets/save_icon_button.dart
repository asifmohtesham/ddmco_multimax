import 'dart:async';
import 'package:flutter/material.dart';
import 'package:multimax/app/data/enums/save_result.dart';

export 'package:multimax/app/data/enums/save_result.dart';

/// An AppBar action button that handles three visual states:
///
/// 1. **Saving**  — `isSaving: true`  → spinner (existing behaviour).
/// 2. **Success** — `saveResult: SaveResult.success` → green check for 1.5 s,
///                  then fades back to the save icon.
/// 3. **Error**   — `saveResult: SaveResult.error`   → red error icon for 1.5 s,
///                  then fades back to the save icon.
/// 4. **Idle**    — normal save icon, disabled (greyed) when `isDirty` is false.
class SaveIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isSaving;
  final bool isDirty;
  final SaveResult saveResult;
  final String tooltip;

  const SaveIconButton({
    super.key,
    required this.onPressed,
    this.isSaving    = false,
    this.isDirty     = true,
    this.saveResult  = SaveResult.idle,
    this.tooltip     = 'Save',
  });

  @override
  State<SaveIconButton> createState() => _SaveIconButtonState();
}

class _SaveIconButtonState extends State<SaveIconButton> {
  Timer? _resetTimer;
  SaveResult _displayed = SaveResult.idle;

  @override
  void didUpdateWidget(SaveIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.saveResult != oldWidget.saveResult &&
        widget.saveResult != SaveResult.idle) {
      _displayed = widget.saveResult;
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _displayed = SaveResult.idle);
      });
    }
    if (widget.saveResult == SaveResult.idle &&
        oldWidget.saveResult != SaveResult.idle) {
      _resetTimer?.cancel();
      setState(() => _displayed = SaveResult.idle);
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ── Saving spinner ────────────────────────────────────────────────────
    if (widget.isSaving) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width:  20,
          height: 20,
          child: CircularProgressIndicator(
            color:       cs.onPrimary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    // ── Post-save feedback ────────────────────────────────────────────────
    if (_displayed == SaveResult.success) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(Icons.check_circle, color: Colors.greenAccent.shade400),
      );
    }
    if (_displayed == SaveResult.error) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(Icons.error_outline, color: cs.error),
      );
    }

    // ── Default save icon ─────────────────────────────────────────────────
    // IconButton renders at reduced opacity automatically when onPressed == null.
    return IconButton(
      icon:      const Icon(Icons.save),
      tooltip:   widget.tooltip,
      onPressed: widget.isDirty ? widget.onPressed : null,
      color:     cs.onPrimary,
    );
  }
}
