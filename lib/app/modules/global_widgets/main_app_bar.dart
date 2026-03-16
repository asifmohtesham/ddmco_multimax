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
  final VoidCallback? onSave;
  final VoidCallback? onReload;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  // Search Configuration
  final String? searchDoctype;
  final String? searchRoute;

  const MainAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.status,
    this.isSaving = false,
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
  });

  @override
  Widget build(BuildContext context) {
    final String? displayStatus = isDirty ? 'Not Saved' : status;

    final List<Widget> appActions = [
      if (searchDoctype != null && searchRoute != null)
        IconButton(
          tooltip: 'Search $searchDoctype',
          icon: const Icon(Icons.search),
          onPressed: () {
            showSearch(
              context: context,
              delegate: GlobalSearchDelegate(
                doctype: searchDoctype!,
                targetRoute: searchRoute!,
              ),
            );
          },
        ),
      if (onReload != null)
        IconButton(
          tooltip: 'Reload document',
          icon: const Icon(Icons.refresh),
          onPressed: isSaving ? null : onReload,
        ),
      ...(actions ?? []),
      if (onSave != null)
        SaveIconButton(
          onPressed: onSave,
          isSaving: isSaving,
          isDirty: isDirty,
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
          // Use titleWidget when provided, otherwise fall back to Text(title).
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
