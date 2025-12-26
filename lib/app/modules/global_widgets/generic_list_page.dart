import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

class GenericListPage extends StatelessWidget {
  final String title;
  final RxBool isLoading;
  final List<dynamic> data;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final List<Widget>? actions;
  final Widget? fab;
  final ScrollController? scrollController;

  // Search & Filter configuration
  final Function(String)? onSearch;
  final String searchHint;
  final Widget? filterHeader;

  // Global API Search Configuration
  final String? searchDoctype;
  final String? searchRoute;

  // Empty State configuration
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final VoidCallback? onClearFilters;

  // Tab configuration (for Tabbed Screens)
  final List<Tab>? tabs;
  final TabController? tabController;
  final Widget? tabBarView;

  // Layout overrides
  final Widget? sliverBody; // Pass custom sliver (e.g. for GridView)

  const GenericListPage({
    super.key,
    required this.title,
    required this.isLoading,
    required this.data,
    required this.onRefresh,
    required this.itemBuilder,
    this.actions,
    this.fab,
    this.scrollController,
    this.onSearch,
    this.searchHint = 'Search...',
    this.filterHeader,
    this.searchDoctype,
    this.searchRoute,
    this.emptyTitle = 'No records found',
    this.emptyMessage = 'Pull to refresh to load data.',
    this.emptyIcon = Icons.description_outlined,
    this.onClearFilters,
    this.tabs,
    this.tabController,
    this.tabBarView,
    this.sliverBody,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Construct Actions: Append Global Search Icon if configuration is present
    final List<Widget> pageActions = [
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

    // --- Tabbed Layout (NestedScrollView) ---
    if (tabs != null && tabBarView != null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        drawer: const AppNavDrawer(),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar.large(
                title: Text(title),
                actions: pageActions,
                scrolledUnderElevation: 0,
                bottom: TabBar(
                  controller: tabController,
                  tabs: tabs!,
                  labelColor: colorScheme.primary,
                  indicatorColor: colorScheme.primary,
                ),
              ),
            ];
          },
          body: tabBarView!,
        ),
        floatingActionButton: fab,
      );
    }

    // --- Standard List Layout (CustomScrollView) ---
    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: Text(title),
              actions: pageActions,
              scrolledUnderElevation: 0,
            ),

            // Pinned Search Bar (optional - local list filtering)
            if (onSearch != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: TextField(
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: searchHint,
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
              ),

            // Filter Header (optional)
            if (filterHeader != null)
              SliverToBoxAdapter(child: filterHeader),

            // Content Area
            Obx(() {
              if (isLoading.value && data.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (data.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(emptyIcon, size: 64, color: colorScheme.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            emptyTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            emptyMessage,
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

              // Use custom sliver body (e.g. Grid) or default List
              if (sliverBody != null) return sliverBody!;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  itemBuilder,
                  childCount: data.length,
                ),
              );
            }),

            // Bottom Padding for FAB
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: fab,
    );
  }
}