import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? status;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool isDirty;

  // Search Configuration
  final String? searchDoctype;
  final String? searchRoute;

  const MainAppBar({
    super.key,
    required this.title,
    this.status,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = false,
    this.isDirty = false,
    this.searchDoctype,
    this.searchRoute,
  });

  @override
  Widget build(BuildContext context) {
    // Centralised Logic: If dirty, override status to 'Not Saved'
    final String? displayStatus = isDirty ? 'Not Saved' : status;

    // Construct Actions: Append Search Icon if search configuration is present
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
      ...(actions ?? []),
    ];

    return AppBar(
      title: displayStatus != null
          ? Column(
        crossAxisAlignment: centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 2),
          StatusPill(status: displayStatus),
        ],
      )
          : Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      centerTitle: centerTitle,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).primaryColor,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      actions: appActions,
      leading: leading,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));
}