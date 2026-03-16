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
///   2. Active-filter chip row — a [Wrap] of dismissible chips supplied by
///      the caller via [filterChipsBuilder].
///
/// ### Search icon
/// When [searchQuery] is non-null the icon is wrapped in [Obx] so the
/// active-dot indicator reacts to query changes.  When [searchQuery] is
/// null no [Obx] is created — GetX requires at least one observable inside
/// every [Obx] closure and would throw otherwise.
///
/// ### Filter icon states
/// • **Idle**   : plain [Icons.filter_list] icon button, default colour.
/// • **Active** : [IconButton.filled] ([Icons.filter_alt]) — solid primary
///               background guarantees visibility against any AppBar surface.
///               A [Badge] overlays the count in the top-right corner using
///               onError-on-error colours.
class DocTypeListHeader extends StatelessWidget {
  // ── AppBar ──────────────────────────────────────────────────────────────
  final String title;
  final List<Widget>? extraActions;

  // ── Search ──────────────────────────────────────────────────────────────
  final String? searchDoctype;
  final String? searchRoute;

  /// When non-null the search icon shows an active-dot indicator and the
  /// [Obx] wrapper is applied.  When null no [Obx] is created.
  final RxString? searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;

  // ── Filter ──────────────────────────────────────────────────────────────
  final RxMap<String, dynamic>? activeFilters;
  final VoidCallback? onFilterTap;

  // ── Chip row ──────────────────────────────────────────────────────────────
  final List<Widget> Function(BuildContext context)? filterChipsBuilder;
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
      if (onFilterTap != null)
        Builder(
          builder: (ctx) {
            return Obx(() {
              final count = activeFilters?.length ?? 0;
              final isActive = count > 0;
              final tooltip = isActive
                  ? '$count filter${count > 1 ? 's' : ''} active — tap to edit'
                  : 'Filter';

              final button = isActive
                  ? IconButton.filled(
                      icon: const Icon(Icons.filter_alt),
                      onPressed: onFilterTap,
                      tooltip: tooltip,
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                    )
                  : IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: onFilterTap,
                      tooltip: tooltip,
                    );

              return isActive
                  ? Badge(label: Text('$count'), child: button)
                  : button;
            });
          },
        ),

      // ── Search icon ─────────────────────────────────────────────────────
      //
      // Two distinct code paths to satisfy GetX’s requirement that every
      // Obx closure subscribes to at least one observable:
      //
      //   searchQuery != null → Obx that reads searchQuery!.value for the
      //                         active-dot indicator.  Observable guaranteed.
      //   searchQuery == null → No dot needed, no Obx created at all.
      if (searchQuery != null ||
          (searchDoctype != null && searchRoute != null))
        Builder(
          builder: (ctx) {
            // ─ path A: searchQuery is non-null — wrap in Obx ──────────────
            if (searchQuery != null) {
              final colorScheme = Theme.of(ctx).colorScheme;
              return Obx(() {
                // searchQuery!.value is the observable that drives Obx.
                final hasActive = searchQuery!.value.isNotEmpty;
                return SizedBox(
                  width: 48,
                  height: 48,
                  child: Tooltip(
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
                        if (hasActive)
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
                  ),
                );
              });
            }

            // ─ path B: searchQuery is null — no Obx ────────────────────
            // No dot indicator needed; no observable to subscribe to.
            return SizedBox(
              width: 48,
              height: 48,
              child: Tooltip(
                message: searchDoctype != null
                    ? 'Search $searchDoctype'
                    : 'Search',
                child: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => showSearch(
                    context: ctx,
                    delegate: DocTypeSearchDelegate(
                      doctype: searchDoctype ?? '',
                      targetRoute: searchRoute ?? '',
                      searchQuery: null,
                      onSearchChanged: onSearchChanged,
                      onSearchClear: onSearchClear,
                      activeFilters: null,
                      onFilterTap: null,
                    ),
                  ),
                ),
              ),
            );
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
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
