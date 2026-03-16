import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

/// A unified sliver header for every DocType list screen.
///
/// Owns two sequential concerns:
///
///   1. [SliverAppBar.large] — collapsing title + optional extra actions +
///      two action icons: a **filter** [IconButton] (badged) and a **search**
///      [IconButton], both always reachable with a single tap.
///
///      Previously the filter icon lived inside the [DocTypeSearchDelegate]
///      overlay, requiring two taps to reach (search icon → filter icon).
///      It is now promoted to the AppBar row itself for immediate access.
///
///   2. Active-filter chip row — a [Wrap] of dismissible chips supplied by
///      the caller via [filterChipsBuilder].  This stays in the list body
///      so active filters remain visible while scrolling.
///
/// All reactive state (search query, filter count) is read from the caller's
/// GetX controller through plain [RxString] / [RxMap] getters wrapped in
/// [Obx].  No [StatefulWidget], no local [ValueNotifier], no [setState].
///
/// ### Action icon layout (right → left in AppBar)
/// ```
/// [ extraActions... ]  [ filter️ ]  [ 🔍 ]
/// ```
/// The filter icon is hidden when [onFilterTap] is null.
/// The search icon is hidden when both [searchQuery] and
/// [searchDoctype]/[searchRoute] are null.
///
/// ### Minimal usage
/// ```dart
/// DocTypeListHeader(
///   title: 'Batch',
///   searchQuery: controller.searchQuery,
///   onSearchChanged: controller.onSearchChanged,
///   onSearchClear: () {
///     controller.searchQuery.value = '';
///     controller.fetchBatches(clear: true);
///   },
///   activeFilters: controller.activeFilters,
///   onFilterTap: () => _openFilterSheet(),
///   filterChipsBuilder: (ctx) => _buildFilterChips(ctx),
/// )
/// ```
class DocTypeListHeader extends StatelessWidget {
  // ── AppBar ──────────────────────────────────────────────────────────────

  /// Page title shown in the large / collapsed app bar.
  final String title;

  /// Extra action widgets prepended before the filter and search icons.
  final List<Widget>? extraActions;

  // ── Search ──────────────────────────────────────────────────────────────

  /// ERPNext DocType name passed to [DocTypeSearchDelegate] for API search.
  /// When empty or null only local-search mode is used.
  final String? searchDoctype;

  /// Named route for [DocTypeSearchDelegate] result navigation (API mode).
  final String? searchRoute;

  /// The controller’s [RxString] that holds the current query.
  /// Pass `null` to hide the search icon entirely.
  final RxString? searchQuery;

  /// Called on every keystroke (debounce is handled by the controller).
  final ValueChanged<String>? onSearchChanged;

  /// Called when the user taps the × clear button inside the search delegate.
  final VoidCallback? onSearchClear;

  // ── Filter button (AppBar action — one tap) ──────────────────────────────

  /// Map of currently active filters — drives the red badge count on the icon.
  final RxMap<String, dynamic>? activeFilters;

  /// Callback that opens the DocType-specific filter bottom sheet.
  /// When null the filter icon is hidden entirely.
  final VoidCallback? onFilterTap;

  // ── Active filter chips ──────────────────────────────────────────────────

  /// Returns the list of [Chip] widgets for currently active filters.
  /// The entire row is hidden when the list is empty.
  final List<Widget> Function(BuildContext context)? filterChipsBuilder;

  /// Callback for the “Clear all” button shown when chips.length > 1.
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
        _buildAppBar(context),
        if (filterChipsBuilder != null) _buildFilterChips(context),
      ],
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    final List<Widget> actions = [
      ...(extraActions ?? []),

      // ── Filter icon (one tap → bottom sheet) ──────────────────────────────
      // Shown only when onFilterTap is provided.
      // Sits to the LEFT of the search icon so the user sees:
      //   [ filter ]  [ search ]
      if (onFilterTap != null)
        Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            return Obx(() {
              final count = activeFilters?.length ?? 0;
              return Tooltip(
                message: count > 0
                    ? '$count filter${count > 1 ? 's' : ''} active'
                    : 'Filter',
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        count > 0
                            ? Icons.filter_alt
                            : Icons.filter_list,
                        color: count > 0
                            ? colorScheme.primary
                            : null,
                      ),
                      onPressed: onFilterTap,
                    ),
                    if (count > 0)
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
                            '$count',
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

      // ── Search icon (one tap → search overlay) ───────────────────────────
      // Shown when either local-search (searchQuery) or API-search
      // (searchDoctype + searchRoute) is wired up.
      // The search delegate no longer hosts the filter icon; it only
      // owns the text field and the API result list.
      if (searchQuery != null ||
          (searchDoctype != null && searchRoute != null))
        Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            return Obx(() {
              final hasActiveSearch =
                  searchQuery?.value.isNotEmpty ?? false;

              return Tooltip(
                message: searchDoctype != null
                    ? 'Search $searchDoctype'
                    : 'Search',
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
                          // Filter is now in the AppBar, not the delegate.
                          activeFilters: null,
                          onFilterTap: null,
                        ),
                      ),
                    ),
                    // Search-active dot
                    if (hasActiveSearch)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
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

class MultiSliver extends StatelessWidget {
  final List<Widget> children;
  const MultiSliver({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(slivers: children);
  }
}
