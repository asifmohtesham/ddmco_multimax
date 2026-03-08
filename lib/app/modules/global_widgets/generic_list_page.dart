import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_app_bar.dart';

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
      backgroundColor: Get.theme.colorScheme.surface,
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
      backgroundColor: Get.theme.colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
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
              GenericLocalSearchBar(onSearch: onSearch!, hintText: searchHint),
            if (filterHeader != null)
              SliverToBoxAdapter(child: filterHeader),
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
        return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
      }

      if (data.isEmpty) {
        return GenericListEmptyState(
          title: emptyTitle,
          message: emptyMessage,
          icon: emptyIcon,
          onRefresh: onRefresh,
          onClearFilters: onClearFilters,
        );
      }

      if (sliverBody != null) return sliverBody!;

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: data.length,
        ),
      );
    });
  }
}