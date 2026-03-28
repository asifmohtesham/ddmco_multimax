import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

/// A unified sliver header for every DocType **form** screen.
///
/// Enforces the form-screen app-bar convention defined in
/// `docs/app_bar_conventions.md`:
///
/// | Slot | Widget |
/// |------|--------|
/// | Leading (left) | ← Back arrow (auto-inserted by Flutter) |
/// | Actions (right) | Reload · Save · Share |
///
/// ## Usage
///
/// ```dart
/// DocTypeFormHeader(
///   title:    controller.docName,
///   onReload: controller.reload,
///   onSave:   controller.save,
///   onShare:  controller.share,
///   isDirty:  controller.isDirty,       // optional — disables Save when false
///   isSaving: controller.isSaving,      // optional — shows spinner while true
///   saveResult: controller.saveResult,  // optional — shows success/error flash
/// )
/// ```
///
/// ## Relationship to [DocTypeListHeader]
///
/// This widget is a thin, purpose-built wrapper around [DocTypeListHeader].
/// It always passes `automaticallyImplyLeading: true` (the default) so
/// Flutter auto-inserts the back arrow when a predecessor route exists on
/// the stack — which is always the case for form screens pushed from a list.
///
/// For **list screens** use [DocTypeListHeader] directly with
/// `automaticallyImplyLeading: false`; see `docs/app_bar_conventions.md`.
class DocTypeFormHeader extends StatelessWidget {
  // ── Required ───────────────────────────────────────────────────────────

  /// The document name shown as the collapsing app-bar title
  /// (e.g. `"WO-00123"`, `"BOM-3000015-001"`).
  final String title;

  // ── Action callbacks ─────────────────────────────────────────────────

  /// Called when the Reload icon is tapped.
  /// Pass `null` to hide the Reload button entirely.
  final VoidCallback? onReload;

  /// Called when the Save icon is tapped.
  /// Pass `null` to hide the Save button entirely.
  final VoidCallback? onSave;

  /// Called when the Share icon is tapped.
  /// Pass `null` to hide the Share button entirely.
  final VoidCallback? onShare;

  // ── Save-button state ───────────────────────────────────────────────

  /// When `true` the Save button is rendered as active (enabled);
  /// when `false` it is greyed-out and non-interactive.
  /// Defaults to `true` so the button is always enabled unless explicitly
  /// signalled otherwise.
  final bool isDirty;

  /// When `true` the Save icon is replaced with a [CircularProgressIndicator]
  /// and the button is non-interactive.
  final bool isSaving;

  /// Drives the post-save success / error flash on [SaveIconButton].
  /// Defaults to [SaveResult.idle] (no feedback shown).
  final SaveResult saveResult;

  // ── Escape hatch ─────────────────────────────────────────────────────

  /// Additional action widgets inserted **before** Reload · Save · Share.
  /// Use sparingly — the three standard actions should cover most cases.
  final List<Widget>? extraActions;

  const DocTypeFormHeader({
    super.key,
    required this.title,
    this.onReload,
    this.onSave,
    this.onShare,
    this.isDirty    = true,
    this.isSaving   = false,
    this.saveResult = SaveResult.idle,
    this.extraActions,
  });

  @override
  Widget build(BuildContext context) {
    return DocTypeListHeader(
      title: title,
      // automaticallyImplyLeading is intentionally omitted → defaults to true
      // → Flutter auto-inserts the back arrow for pushed form routes.
      extraActions: [
        // ── Caller-supplied extras (before standard actions) ────────────
        ...(extraActions ?? []),

        // ── 1. Reload ───────────────────────────────────────────────
        if (onReload != null)
          IconButton(
            icon:      const Icon(Icons.refresh),
            tooltip:   'Reload',
            onPressed: onReload,
          ),

        // ── 2. Save (delegates to SaveIconButton for all visual states) ───
        if (onSave != null)
          SaveIconButton(
            onPressed:  onSave,
            isSaving:   isSaving,
            isDirty:    isDirty,
            saveResult: saveResult,
            tooltip:    'Save',
          ),

        // ── 3. Share ───────────────────────────────────────────────
        if (onShare != null)
          IconButton(
            icon:      const Icon(Icons.share_outlined),
            tooltip:   'Share',
            onPressed: onShare,
          ),
      ],
    );
  }
}
