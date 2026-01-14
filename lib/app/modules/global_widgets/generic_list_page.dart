import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_app_bar.dart';
import 'package:multimax/theme/frappe_theme.dart';

class GenericListPage extends StatelessWidget {
  // Core Data
  final String title;
  final RxBool isLoading;
  final List<dynamic> data;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext context, int index) itemBuilder;

  // Configuration
  final List<Widget>? actions;
  final Widget? fab;
  final ScrollController? scrollController;
  final Widget? sliverBody;

  // Search & Filter
  final Function(String)? onSearch;
  final String searchHint;
  final Widget? filterHeader;
  final String? searchDoctype;
  final String? searchRoute;

  // Empty State
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final VoidCallback? onClearFilters;

  // Tabs
  final List<Tab>? tabs;
  final TabController? tabController;
  final Widget? tabBarView;

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
    this.sliverBody,
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
  });

  @override
  Widget build(BuildContext context) {
    if (tabs != null && tabBarView != null) {
      return _buildTabbedLayout();
    }
    return _buildStandardLayout();
  }

  Widget _buildTabbedLayout() {
    return Scaffold(
      backgroundColor: FrappeTheme.surface,
      drawer: const AppNavDrawer(),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          GenericListAppBar(
            title: title,
            actions: actions,
            searchDoctype: searchDoctype,
            searchRoute: searchRoute,
            tabs: tabs,
            tabController: tabController,
          ),
        ],
        body: tabBarView!,
      ),
      floatingActionButton: fab,
    );
  }

  Widget _buildStandardLayout() {
    return Scaffold(
      backgroundColor: FrappeTheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        color: FrappeTheme.primary,
        onRefresh: onRefresh,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            GenericListAppBar(
              title: title,
              actions: actions,
              searchDoctype: searchDoctype,
              searchRoute: searchRoute,
            ),
            if (onSearch != null)
              SliverToBoxAdapter(
                child: GenericLocalSearchBar(
                  onSearch: onSearch!,
                  hintText: searchHint,
                ),
              ),
            if (filterHeader != null) SliverToBoxAdapter(child: filterHeader),
            _buildContent(),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: fab,
    );
  }

  Widget _buildContent() {
    return Obx(() {
      if (isLoading.value && data.isEmpty) {
        return const SliverFillRemaining(
          child: Center(
            child: CircularProgressIndicator(color: FrappeTheme.primary),
          ),
        );
      }

      if (data.isEmpty) {
        return SliverFillRemaining(
          child: GenericListEmptyState(
            title: emptyTitle,
            message: emptyMessage,
            icon: emptyIcon,
            onRefresh: onRefresh,
            onClearFilters: onClearFilters,
          ),
        );
      }

      // If sliverBody is provided (e.g. for Grid View), use it
      if (sliverBody != null) return sliverBody!;

      // Otherwise default list
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: data.length,
        ),
      );
    });
  }
}

// --- Internal Helper Widgets ---

class GenericLocalSearchBar extends StatelessWidget {
  final Function(String) onSearch;
  final String hintText;

  const GenericLocalSearchBar({
    super.key,
    required this.onSearch,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: onSearch,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
    );
  }
}

class GenericListEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback onRefresh;
  final VoidCallback? onClearFilters;

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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (onClearFilters != null)
            TextButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_list_off),
              label: const Text("Clear Filters"),
            )
          else
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text("Refresh"),
              style: ElevatedButton.styleFrom(
                backgroundColor: FrappeTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
