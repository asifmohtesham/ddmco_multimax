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
/// | Bottom (optional) | [TabBar] or other fixed-height widget |
///
/// ## Usage
///
/// ```dart
/// DocTypeFormHeader(
///   title:      controller.docName,
///   onReload:   controller.reload,
///   onSave:     controller.save,
///   onShare:    controller.share,
///   canSave:    controller.isDirty.value,
///   docStatus:  controller.docStatus,   // 0 draft · 1 submitted · 2 cancelled
///   isSaving:   controller.isSaving.value,
///   saveResult: controller.saveResult.value,
///   bottom:     TabBar(controller: _tabCtrl, tabs: [...]),
/// )
/// ```
///
/// ## Save-button safety
///
/// The Save button is active only when **both** conditions hold:
/// - `canSave == true` (the controller signals un-saved changes)
/// - `docStatus == 0` (the document is still in draft state)
///
/// `canSave` defaults to `false` — a screen that forgets to wire the parameter
/// gets a permanently-disabled Save button, not a permanently-active one.
/// `docStatus` defaults to `0` so existing call sites that only wire `canSave`
/// continue to work without change.
///
/// ## Bottom slot
///
/// Pass a [PreferredSizeWidget] (typically a [TabBar]) as [bottom] to pin it
/// below the collapsed toolbar. Its height is added to both `minExtent` and
/// `maxExtent` so the sliver always reserves the correct amount of space and
/// the widget is never scrolled away with the large title.
///
/// ## Relationship to [DocTypeListHeader]
///
/// This widget is a thin wrapper around [DocTypeListHeader].
/// It always omits `automaticallyImplyLeading` (defaults to `true`) so Flutter
/// auto-inserts the back arrow for pushed form routes.
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

  /// Whether the form has unsaved changes.
  ///
  /// Defaults to `false` — a screen that forgets to wire this parameter gets a
  /// disabled Save button rather than a permanently-active one.
  ///
  /// The Save button is also force-disabled when [docStatus] ≠ 0, regardless
  /// of this flag.
  final bool canSave;

  /// ERPNext document lifecycle status.
  ///
  /// | Value | Meaning | Save button |
  /// |-------|---------|-------------|
  /// | 0 | Draft | Active when [canSave] is `true` |
  /// | 1 | Submitted | Always disabled |
  /// | 2 | Cancelled | Always disabled |
  ///
  /// Defaults to `0` (draft).
  final int docStatus;

  /// When `true` the Save icon is replaced with a [CircularProgressIndicator]
  /// and the button is non-interactive.
  final bool isSaving;

  /// Drives the post-save success / error flash on [SaveIconButton].
  /// Defaults to [SaveResult.idle] (no feedback shown).
  final SaveResult saveResult;

  // ── Bottom slot ──────────────────────────────────────────────────────

  /// Optional widget pinned below the collapsed toolbar — typically a [TabBar].
  ///
  /// Its [PreferredSizeWidget.preferredSize.height] is added to both
  /// `minExtent` and `maxExtent` so the sliver always reserves the right amount
  /// of space and the widget remains visible regardless of scroll position.
  final PreferredSizeWidget? bottom;

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
    this.canSave    = false,
    this.docStatus  = 0,
    this.isSaving   = false,
    this.saveResult = SaveResult.idle,
    this.bottom,
    this.extraActions,
  });

  bool get _canSave => canSave && docStatus == 0;

  @override
  Widget build(BuildContext context) {
    return DocTypeListHeader(
      title:  title,
      bottom: bottom,
      // automaticallyImplyLeading is intentionally omitted → defaults to true
      // → Flutter auto-inserts the back arrow for pushed form routes.
      extraActions: [
        // ── Caller-supplied extras (before standard actions) ────────────
        ...(extraActions ?? []),

        // ── 1. Reload ───────────────────────────────────────────────────
        if (onReload != null)
          IconButton(
            icon:      const Icon(Icons.refresh),
            tooltip:   'Reload',
            onPressed: onReload,
          ),

        // ── 2. Save (delegates to SaveIconButton for all visual states) ──
        if (onSave != null)
          SaveIconButton(
            onPressed:  onSave,
            isSaving:   isSaving,
            isDirty:    _canSave,
            saveResult: saveResult,
            tooltip:    'Save',
          ),

        // ── 3. Share ─────────────────────────────────────────────────────
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
