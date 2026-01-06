import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

// --- Component: App Bar ---
class GenericListAppBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final String? searchDoctype;
  final String? searchRoute;
  final TabController? tabController;
  final List<Tab>? tabs;

  const GenericListAppBar({
    super.key,
    required this.title,
    this.actions,
    this.searchDoctype,
    this.searchRoute,
    this.tabController,
    this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> pageActions = [
      if (searchDoctype != null && searchRoute != null)
        IconButton(
          tooltip: 'Search $searchDoctype',
          icon: const Icon(Icons.search),
          onPressed: () => showSearch(
            context: context,
            delegate: GlobalSearchDelegate(
              doctype: searchDoctype!,
              targetRoute: searchRoute!,
            ),
          ),
        ),
      ...(actions ?? []),
    ];

    return SliverAppBar.large(
      title: Text(title),
      actions: pageActions,
      scrolledUnderElevation: 0,
      bottom: tabs != null
          ? TabBar(
        controller: tabController,
        tabs: tabs!,
        labelColor: Theme.of(context).colorScheme.primary,
        indicatorColor: Theme.of(context).colorScheme.primary,
      )
          : null,
    );
  }
}

// --- Component: Local Search Bar ---
class GenericLocalSearchBar extends StatelessWidget {
  final Function(String) onSearch;
  final String hintText;

  const GenericLocalSearchBar({
    super.key,
    required this.onSearch,
    this.hintText = 'Search...',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          onChanged: onSearch,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ),
    );
  }
}

// --- Component: Empty State ---
class GenericListEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onClearFilters;
  final VoidCallback onRefresh;

  const GenericListEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.onRefresh,
    this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: colorScheme.outlineVariant),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (onClearFilters != null)
                FilledButton.tonalIcon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear Filters'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}