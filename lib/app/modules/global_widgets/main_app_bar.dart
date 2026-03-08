import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? status;
  final bool isDirty;
  final bool isSaving;
  final VoidCallback? onSave;
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
    this.status,
    this.isSaving = false,
    this.onSave,
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
    // 1. Determine Display Status: Override with 'Not Saved' if dirty
    final String? displayStatus = isDirty ? 'Not Saved' : status;

    // 2. Construct Actions List: [Search] -> [Custom Actions] -> [Save]
    final List<Widget> appActions = [
      // Global Search Action
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

      // Custom Actions injected by the screen
      ...(actions ?? []),

      // Global Save Action
      if (onSave != null)
        SaveIconButton(
          onPressed: onSave,
          isSaving: isSaving,
          isDirty: isDirty,
        ),
    ];

    // Check if the current Scaffold has a drawer
    final bool hasDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;

    return AppBar(
      leading: leading ?? (showBack && !hasDrawer && Navigator.canPop(context)
          ? IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Get.back(),
      )
          : null),
      title: Column(
        crossAxisAlignment: centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
          ),
          if (displayStatus != null) ...[
            const SizedBox(height: 4),
            StatusPill(status: displayStatus),
          ]
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
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));
}