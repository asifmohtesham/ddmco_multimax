import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  /// Optional widget to replace the [title] text. When provided, [title] is
  /// still required (used as a fallback / accessibility label) but the
  /// visual title column renders [titleWidget] instead of a [Text].
  final Widget? titleWidget;

  final String? status;
  final bool isDirty;
  final bool isSaving;

  /// Result of the most recent save attempt. Forwarded directly to
  /// [SaveIconButton]. Defaults to [SaveResult.idle] (no-op).
  final SaveResult saveResult;

  final VoidCallback? onSave;
  final VoidCallback? onReload;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  // ── Search configuration ─────────────────────────────────────────────────────────

  /// When provided, shows a 🔍 icon in the app bar that opens
  /// [DocTypeSearchDelegate].
  ///
  /// **API mode** — set both [searchDoctype] and [searchRoute]:
  /// the delegate queries the ERPNext search API and navigates on tap.
  ///
  /// **Local mode** — set only [searchDoctype] (leave [searchRoute] empty)
  /// and provide [onSearchChanged] + [onSearchClear]:
  /// every keystroke is forwarded to the controller; no network call is made.
  final String? searchDoctype;

  /// Target route for API-mode search navigation. Leave empty for local mode.
  final String? searchRoute;

  /// Local-mode: called on every keystroke. Ignored in API mode.
  final ValueChanged<String>? onSearchChanged;

  /// Local-mode: called when the user taps the × clear button.
  final VoidCallback? onSearchClear;

  const MainAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.status,
    this.isSaving = false,
    this.saveResult = SaveResult.idle,
    this.onSave,
    this.onReload,
    this.actions,
    this.leading,
    this.showBack = true,
    this.bottom,
    this.centerTitle = false,
    this.isDirty = false,
    this.searchDoctype,
    this.searchRoute,
    this.onSearchChanged,
    this.onSearchClear,
  });

  /// Whether the search icon should be rendered.
  /// Requires at least [searchDoctype] to be set.
  bool get _hasSearch => (searchDoctype ?? '').isNotEmpty;

  /// API mode: both doctype and route are provided.
  bool get _isApiSearch =>
      _hasSearch && (searchRoute ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final String? displayStatus = isDirty ? 'Not Saved' : status;

    final List<Widget> appActions = [
      // ── Search icon (API or local mode) ─────────────────────────────────
      if (_hasSearch)
        IconButton(
          tooltip: 'Search ${searchDoctype!}',
          icon: const Icon(Icons.search),
          onPressed: () {
            showSearch(
              context: context,
              delegate: DocTypeSearchDelegate(
                doctype:        searchDoctype!,
                targetRoute:    _isApiSearch ? searchRoute! : '',
                onSearchChanged: !_isApiSearch ? onSearchChanged : null,
                onSearchClear:   !_isApiSearch ? onSearchClear  : null,
              ),
            );
          },
        ),
      // ── Reload ──────────────────────────────────────────────────────────────
      if (onReload != null)
        IconButton(
          tooltip: 'Reload document',
          icon: const Icon(Icons.refresh),
          onPressed: isSaving ? null : onReload,
        ),
      // ── Extra caller-supplied actions ────────────────────────────────────
      ...(actions ?? []),
      // ── Save icon (always last) ────────────────────────────────────────
      if (onSave != null)
        SaveIconButton(
          onPressed:  onSave,
          isSaving:   isSaving,
          isDirty:    isDirty,
          saveResult: saveResult,
        ),
    ];

    return AppBar(
      leading: leading ??
          (showBack && Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.maybePop(context),
                )
              : null),
      title: Column(
        crossAxisAlignment:
            centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          titleWidget ??
              Text(
                title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
          if (displayStatus != null) ...[
            const SizedBox(height: 4),
            StatusPill(status: displayStatus),
          ],
        ],
      ),
      actions: appActions,
      centerTitle: centerTitle,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).primaryColor,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));
}
