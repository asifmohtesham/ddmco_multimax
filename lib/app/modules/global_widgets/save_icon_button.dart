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
  final bool showFilledWhenDirty;

  /// Accent/foreground color for bars where the default theme colors are
  /// illegible (e.g. the solid-maroon form header). When set, the saving
  /// spinner and the filled-when-dirty state use this color instead of the
  /// theme defaults.
  final Color? onColor;

  const SaveIconButton({
    super.key,
    required this.onPressed,
    this.isSaving             = false,
    this.isDirty              = true,
    this.saveResult           = SaveResult.idle,
    this.tooltip              = 'Save',
    this.showFilledWhenDirty  = false,
    this.onColor,
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
      return SizedBox.square(       // ← enforces equal width & height
        dimension: 20,
        child: Center(              // ← centres within the IconButton tap zone
          child: CircularProgressIndicator(
            color:       widget.onColor ?? cs.primary,
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
    // Filled variant: navy background when dirty and caller opts in.
    // No explicit icon color: argument is ever set — that is the fix from
    // commit 48e1596b and must not regress.
    if (widget.showFilledWhenDirty && widget.isDirty) {
      final bool hasOnColor = widget.onColor != null;
      return IconButton(
        style: IconButton.styleFrom(
          backgroundColor: hasOnColor
              ? widget.onColor!.withValues(alpha: 0.18)
              : const Color(0xFF25286F),
          foregroundColor: hasOnColor ? widget.onColor : Colors.white,
        ),
        icon:      const Icon(Icons.save),
        tooltip:   widget.tooltip,
        onPressed: widget.onPressed,
      );
    }

    // Plain / disabled.
    // When [onColor] is set (e.g. the solid-maroon form header) the default
    // disabledColor renders dark-on-maroon = near-invisible. Honour onColor so
    // the idle "nothing to save" icon stays a legible — but muted — onColor
    // glyph instead of vanishing into the bar. Without onColor we keep the
    // theme defaults (no explicit color — the fix from 48e1596b stands).
    final bool hasOnColor = widget.onColor != null;
    return IconButton(
      style: hasOnColor
          ? IconButton.styleFrom(
              foregroundColor:         widget.onColor,
              disabledForegroundColor: widget.onColor!.withValues(alpha: 0.55),
            )
          : null,
      icon:      const Icon(Icons.save),
      tooltip:   widget.tooltip,
      onPressed: widget.isDirty ? widget.onPressed : null,
    );
  }
}
