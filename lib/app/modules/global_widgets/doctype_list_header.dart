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
/// All reactive state (search query, filter count) is read from the caller’s
/// GetX controller through plain [RxString] / [RxMap] getters wrapped in
/// [Obx].  No [StatefulWidget], no local [ValueNotifier], no [setState].
///
/// ### Action icon layout (left → right in AppBar)
/// ```
/// [ extraActions... ]  [ filter ]  [ search ]
/// ```
/// • **filter** — idle: outlined [Icons.filter_list] icon button.
///               active: filled [Icons.filter_alt] button (primary bg,
///               onPrimary icon) with the active count in the tooltip.
///               Hidden when [onFilterTap] is null.
/// • **search** — standard icon button with an 8 px error dot when a
///               query is active. Hidden when search is not wired up.
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

  /// Map of currently active filters — drives the filled state and tooltip
  /// count on the filter icon.
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

      // ── Filter icon ─────────────────────────────────────────────────────
      //
      // Idle  : plain IconButton, Icons.filter_list, default icon colour.
      // Active: IconButton.filled, Icons.filter_alt.
      //         Filled renders onPrimary icon on a solid primary background
      //         — always legible against colorScheme.surface in any M3 theme.
      //         The count is surfaced in the tooltip; no badge overlay needed
      //         because the filled pill itself communicates “active” clearly.
      if (onFilterTap != null)
        Builder(
          builder: (ctx) {
            return Obx(() {
              final count = activeFilters?.length ?? 0;
              final isActive = count > 0;

              final tooltip = isActive
                  ? '$count filter${count > 1 ? 's' : ''} active — tap to edit'
                  : 'Filter';

              if (isActive) {
                // Filled button: solid primary circle, onPrimary icon.
                // Always visible regardless of AppBar background colour.
                return Tooltip(
                  message: tooltip,
                  child: IconButton.filled(
                    icon: const Icon(Icons.filter_alt),
                    onPressed: onFilterTap,
                    // Constrain size to match a regular IconButton so the
                    // AppBar action row doesn’t reflow when toggling.
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                );
              }

              // Idle: plain icon button
              return Tooltip(
                message: tooltip,
                child: IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: onFilterTap,
                ),
              );
            });
          },
        ),

      // ── Search icon ─────────────────────────────────────────────────────
      if (searchQuery != null ||
          (searchDoctype != null && searchRoute != null))
        Builder(
          builder: (ctx) {
            final colorScheme = Theme.of(ctx).colorScheme;
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
                        context: ctx,
                        delegate: DocTypeSearchDelegate(
                          doctype: searchDoctype ?? '',
                          targetRoute: searchRoute ?? '',
                          searchQuery: searchQuery,
                          onSearchChanged: onSearchChanged,
                          onSearchClear: onSearchClear,
                          activeFilters: null,
                          onFilterTap: null,
                        ),
                      ),
                    ),
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
