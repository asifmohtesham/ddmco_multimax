import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

/// A unified sliver header for every DocType list screen.
///
/// Owns two sequential concerns that were previously three:
///
///   1. [SliverAppBar.large] — collapsing title + optional extra actions +
///      a single search [IconButton] that opens [DocTypeSearchDelegate].
///      The delegate hosts both the **text query field** and the
///      **badged filter icon** (previously the SearchBar trailing suffix),
///      so the user reaches search AND filter from one AppBar entry point.
///
///   2. Active-filter chip row — a [Wrap] of dismissible chips supplied by
///      the caller via [filterChipsBuilder].  This stays in the list body
///      so active filters remain visible while scrolling.
///
/// The local [SearchBar] widget that previously sat between the AppBar and
/// the chip row has been removed.  All its features live inside the
/// [DocTypeSearchDelegate] overlay instead.
///
/// All reactive state (search query, filter count) is read from the caller's
/// GetX controller through plain [RxString] / [RxMap] getters wrapped in
/// [Obx].  No [StatefulWidget], no local [ValueNotifier], no [setState].
///
/// ### Minimal usage
/// ```dart
/// DocTypeListHeader(
///   title: 'Stock Entries',
///   searchQuery: controller.searchQuery,
///   onSearchChanged: controller.onSearchChanged,
///   onSearchClear: () {
///     controller.searchQuery.value = '';
///     controller.fetchStockEntries(clear: true);
///   },
///   activeFilterCount: controller.activeFilters.length,
///   onFilterTap: () => _showFilterSheet(context),
///   filterChipsBuilder: (ctx) => _buildFilterChips(ctx),
/// )
/// ```
class DocTypeListHeader extends StatelessWidget {
  // ── AppBar ────────────────────────────────────────────────────────────────

  /// Page title shown in the large / collapsed app bar.
  final String title;

  /// Extra action widgets prepended before the search icon.
  final List<Widget>? extraActions;

  // ── Search (AppBar delegate) ──────────────────────────────────────────────

  /// ERPNext DocType name passed to [DocTypeSearchDelegate] for API search.
  /// When empty or null only local-search mode is used.
  final String? searchDoctype;

  /// Named route for [DocTypeSearchDelegate] result navigation (API mode).
  final String? searchRoute;

  /// The controller's [RxString] that holds the current query.
  /// Pass `null` to hide the search icon entirely.
  final RxString? searchQuery;

  /// Called on every keystroke (debounce is handled by the controller).
  final ValueChanged<String>? onSearchChanged;

  /// Called when the user taps the × clear button inside the delegate.
  final VoidCallback? onSearchClear;

  // ── Filter button (lives inside the AppBar delegate) ──────────────────────

  /// Map of currently active filters — drives the red badge on the icon.
  final RxMap<String, dynamic>? activeFilters;

  /// Callback that opens the DocType-specific filter bottom sheet.
  /// Pass `null` to hide the filter icon in the delegate.
  final VoidCallback? onFilterTap;

  // ── Active filter chips ───────────────────────────────────────────────────

  /// Returns the list of [Chip] widgets for currently active filters.
  /// The entire row is hidden when the list is empty.
  final List<Widget> Function(BuildContext context)? filterChipsBuilder;

  /// Callback for the "Clear all" button shown when chips.length > 1.
  final VoidCallback? onClearAllFilters;

  const DocTypeListHeader({
    super.key,
    required this.title,
    this.extraActions,
    this.searchDoctype,
    this.searchRoute,
    this.searchQuery,
    this.onSearchChanged,
    this.onSearchClear,
    this.activeFilters,
    this.onFilterTap,
    this.filterChipsBuilder,
    this.onClearAllFilters,
  });

  @override
  Widget build(BuildContext context) {
    return MultiSliver(
      children: [
        _buildAppBar(),
        if (filterChipsBuilder != null) _buildFilterChips(context),
      ],
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    final List<Widget> actions = [
      ...(extraActions ?? []),

      // Search icon — shown when either API-search or local-search is wired up
      if (searchQuery != null || (searchDoctype != null && searchRoute != null))
        Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            return Obx(() {
              final filterCount = activeFilters?.length ?? 0;
              final hasActiveSearch =
                  searchQuery?.value.isNotEmpty ?? false;
              final badgeCount =
                  filterCount + (hasActiveSearch ? 1 : 0);

              return Tooltip(
                message: searchDoctype != null
                    ? 'Search & Filter $searchDoctype'
                    : 'Search & Filter',
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => showSearch(
                        context: context,
                        delegate: DocTypeSearchDelegate(
                          doctype: searchDoctype ?? '',
                          targetRoute: searchRoute ?? '',
                          searchQuery: searchQuery,
                          onSearchChanged: onSearchChanged,
                          onSearchClear: onSearchClear,
                          activeFilters: activeFilters,
                          onFilterTap: onFilterTap,
                        ),
                      ),
                    ),
                    // Compound badge: filter count + search-active dot
                    if (badgeCount > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                              minWidth: 16, minHeight: 16),
                          child: Text(
                            '$badgeCount',
                            style: TextStyle(
                              color: colorScheme.onError,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            });
          },
        ),
    ];

    return SliverAppBar.large(
      title: Text(title),
      actions: actions.isEmpty ? null : actions,
      scrolledUnderElevation: 0,
    );
  }

  // ── Active filter chip row ────────────────────────────────────────────────

  Widget _buildFilterChips(BuildContext context) {
    return SliverToBoxAdapter(
      child: Obx(() {
        final hasSearch = (searchQuery?.value ?? '').isNotEmpty;
        final hasFilters = (activeFilters?.isNotEmpty ?? false);
        if (!hasSearch && !hasFilters) return const SizedBox.shrink();

        final chips = filterChipsBuilder!(context);
        if (chips.isEmpty) return const SizedBox.shrink();

        final colorScheme = Theme.of(context).colorScheme;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...chips,
              if (chips.length > 1 && onClearAllFilters != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: onClearAllFilters,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear all'),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal MultiSliver shim
// ---------------------------------------------------------------------------
// Flutter's slivers API has no built-in "group of slivers" widget.  Rather
// than pulling in the `sliver_tools` package for a single use-case, this thin
// shim wraps multiple slivers so DocTypeListHeader can be used as a single
// widget in a CustomScrollView's slivers list.

class MultiSliver extends StatelessWidget {
  final List<Widget> children;
  const MultiSliver({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    // SliverMainAxisGroup clips and groups multiple slivers — available since
    // Flutter 3.16.  It is sticky-header-aware and scroll-position-aware.
    return SliverMainAxisGroup(slivers: children);
  }
}
