import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

/// A unified sliver header for every DocType list screen.
///
/// Owns three sequential concerns that were previously duplicated across
/// every list screen:
///
///   1. [SliverAppBar.large] — collapsing title + optional extra actions +
///      optional GlobalSearchDelegate icon.
///   2. [SearchBar] — local (in-memory / debounced-API) text search with a
///      badged filter-icon suffix that opens the DocType's filter sheet.
///   3. Active-filter chip row — a [Wrap] of dismissible chips supplied by
///      the caller via [filterChipsBuilder].
///
/// All reactive state (search query, filter count) is read from the caller's
/// GetX controller through plain [RxString] / [RxMap] getters wrapped in
/// [Obx].  No [StatefulWidget], no local [ValueNotifier], no [setState].
///
/// ### Minimal usage
/// ```dart
/// DocTypeListHeader(
///   title: 'Stock Entries',
///   searchHint: 'Search ID, Purpose…',
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

  /// Extra action widgets prepended before the (optional) global-search icon.
  final List<Widget>? extraActions;

  // ── Global API search (optional) ─────────────────────────────────────────

  /// ERPNext DocType name passed to [GlobalSearchDelegate].
  /// Both [searchDoctype] and [searchRoute] must be non-null to show the icon.
  final String? searchDoctype;

  /// Named route for [GlobalSearchDelegate] result navigation.
  final String? searchRoute;

  // ── Local SearchBar ───────────────────────────────────────────────────────

  /// The controller's [RxString] that holds the current query.  The
  /// [SearchBar] reads this to decide whether to show the clear button.
  /// Pass `null` to hide the entire SearchBar row.
  final RxString? searchQuery;

  /// Placeholder text inside the [SearchBar].
  final String searchHint;

  /// Called on every keystroke (debounce is handled by the controller).
  final ValueChanged<String>? onSearchChanged;

  /// Called when the user taps the × clear button.
  final VoidCallback? onSearchClear;

  // ── Filter button ─────────────────────────────────────────────────────────

  /// Number of currently active filters — drives the red badge on the icon.
  /// Must be a plain [int] returned from an [Obx] wrapper in the parent, OR
  /// pass an [RxMap].length directly; the parent [Obx] handles reactivity.
  ///
  /// This widget wraps the badge area in its own [Obx] via [activeFilterCountObs].
  final RxMap<String, dynamic>? activeFilters;

  /// Callback that opens the DocType-specific filter bottom sheet.
  /// Pass `null` to hide the filter icon entirely.
  final VoidCallback? onFilterTap;

  // ── Active filter chips ───────────────────────────────────────────────────

  /// Returns the list of [Chip] widgets for currently active filters.
  /// The entire row is hidden when the list is empty.
  /// Wrapped in [Obx] by the caller's own state; this builder is called
  /// inside an [Obx] here so it re-renders whenever any Rx dependency
  /// read inside it changes.
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
    this.searchHint = 'Search…',
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
        if (searchQuery != null) _buildSearchBar(context),
        if (filterChipsBuilder != null) _buildFilterChips(context),
      ],
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    final List<Widget> actions = [
      ...(extraActions ?? []),
      if (searchDoctype != null && searchRoute != null)
        Builder(
          builder: (context) => IconButton(
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
        ),
    ];

    return SliverAppBar.large(
      title: Text(title),
      actions: actions.isEmpty ? null : actions,
      scrolledUnderElevation: 0,
    );
  }

  // ── SearchBar + filter icon ───────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Obx(() {
          final query = searchQuery?.value ?? '';
          final filterCount = activeFilters?.length ?? 0;
          final colorScheme = Theme.of(context).colorScheme;

          return SearchBar(
            hintText: searchHint,
            leading: const Icon(Icons.search),
            onChanged: onSearchChanged,
            trailing: [
              // Clear button — only when there is text
              if (query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear search',
                  onPressed: onSearchClear,
                ),

              // Filter button — only when a sheet callback is provided
              if (onFilterTap != null)
                Tooltip(
                  message: filterCount > 0
                      ? '$filterCount filter${filterCount > 1 ? 's' : ''} active'
                      : 'Filter',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onFilterTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            filterCount > 0
                                ? Icons.filter_alt
                                : Icons.filter_list,
                            color: filterCount > 0
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          if (filterCount > 0)
                            Positioned(
                              top: -4,
                              right: -6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                    minWidth: 16, minHeight: 16),
                                child: Text(
                                  '$filterCount',
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
                    ),
                  ),
                ),
            ],
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.surfaceContainerHighest),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
            ),
          );
        }),
      ),
    );
  }

  // ── Active filter chip row ────────────────────────────────────────────────

  Widget _buildFilterChips(BuildContext context) {
    return SliverToBoxAdapter(
      child: Obx(() {
        // Reading any Rx inside here makes this reactive.
        final hasSearch = (searchQuery?.value ?? '').isNotEmpty;
        final hasFilters = (activeFilters?.isNotEmpty ?? false);
        if (!hasSearch && !hasFilters) return const SizedBox.shrink();

        final chips = filterChipsBuilder!(context);
        if (chips.isEmpty) return const SizedBox.shrink();

        final colorScheme = Theme.of(context).colorScheme;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
