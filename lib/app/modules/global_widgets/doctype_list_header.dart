import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

/// A unified sliver header for every DocType **list** screen.
///
/// Owns two sequential concerns:
///
/// 1. [SliverAppBar.large] — collapsing title + optional extra actions +
///    two action icons: a **filter** [IconButton] (badged) and a **search**
///    [IconButton], both always reachable with a single tap.
///
/// 2. Active-filter chip row — a [Wrap] of dismissible chips supplied by
///    the caller via [filterChipsBuilder].
///
/// ---
///
/// ## Sticky behaviour
///
/// * **AppBar ([SliverAppBar.large], `pinned: true`):**
///   The large-title area scrolls away; the collapsed toolbar (title +
///   action icons) is permanently pinned at the top of the viewport.
///
/// * **Filter chip row ([SliverPersistentHeader], `pinned: true`):**
///   Pinned immediately below the collapsed toolbar whenever
///   [filterChipsBuilder] is non-null.  The row reserves its slot in the
///   sliver layout at all times ([_FilterChipHeaderDelegate.minExtent] is
///   always [kToolbarHeight] when a builder is provided), but hides its
///   visual content reactively when no chips are active — so the user sees
///   a zero-height gap rather than a blank bar.
///
/// ---
///
/// ## Leading button convention
///
/// | Screen type | [automaticallyImplyLeading] | Result |
/// |-------------|----------------------------|--------|
/// | **List screen** (top-level nav destination) | `false` | ☰ Drawer / hamburger icon |
/// | **Form screen** (pushed on top of a list)  | `true` (default) | ← Back arrow |
///
/// > **⚠️** The hamburger only appears when the owning [Scaffold] has a
/// > [Scaffold.drawer] set.  Use `AppShellScaffold` (which injects
/// > `AppNavDrawer` automatically) for all list screens.
/// >
/// > For form screens use [DocTypeFormHeader], which always sets
/// > `automaticallyImplyLeading: true` and provides the standard
/// > Reload · Save · Share action row.
/// >
/// > See `docs/app_bar_conventions.md` for the complete convention.
///
/// ---
///
/// ## Search icon
/// When [searchQuery] is non-null the icon is wrapped in [Obx] so the
/// active-dot indicator reacts to query changes.  When [searchQuery] is
/// null no [Obx] is created — GetX requires at least one observable inside
/// every [Obx] closure and would throw otherwise.
///
/// ## Filter icon states
/// • **Idle** : plain [Icons.filter_list] icon button, default colour.
/// • **Active** : [IconButton.filled] ([Icons.filter_alt]) — solid primary
///   background guarantees visibility against any AppBar surface.
///   A [Badge] overlays the count in the top-right corner.
///
/// ## Title visibility
/// The [title] is always rendered in full — no ellipsis, no clamping.
/// When the name is long the large-title area expands vertically to
/// accommodate it.  The collapsed (pinned) bar also never truncates.
class DocTypeListHeader extends StatelessWidget {
  // ── AppBar ────────────────────────────────────────────────────────────
  final String title;
  final List<Widget>? extraActions;

  /// Controls whether [SliverAppBar] automatically inserts a leading widget.
  ///
  /// **List screens — pass `false`:**
  /// Prevents the auto-inserted back arrow on top-level destination screens.
  /// The [Scaffold.drawer] hamburger icon will appear instead, provided the
  /// owning [Scaffold] has a drawer (use `AppShellScaffold`).
  ///
  /// **Form screens — omit (defaults to `true`):**
  /// Flutter auto-inserts a back arrow when a predecessor route exists on
  /// the stack, which is always the case for form screens pushed from a list.
  /// Use [DocTypeFormHeader] for form screens instead of setting this flag.
  ///
  /// Defaults to `true` to preserve existing behaviour for all callers that
  /// do not yet set this explicitly.
  final bool automaticallyImplyLeading;

  // ── Search ────────────────────────────────────────────────────────────
  final String? searchDoctype;
  final String? searchRoute;

  /// When non-null the search icon shows an active-dot indicator and the
  /// [Obx] wrapper is applied.  When null no [Obx] is created.
  final RxString? searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;

  // ── Filter ────────────────────────────────────────────────────────────
  final RxMap? activeFilters;
  final VoidCallback? onFilterTap;

  // ── Chip row ──────────────────────────────────────────────────────────
  final List<Widget> Function(BuildContext context)? filterChipsBuilder;
  final VoidCallback? onClearAllFilters;

  const DocTypeListHeader({
    super.key,
    required this.title,
    this.extraActions,
    this.automaticallyImplyLeading = true,
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

  // ── AppBar ────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    final List<Widget> actions = [
      ...(extraActions ?? []),

      // ── Filter icon ─────────────────────────────────────────────────
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

      // ── Search icon ───────────────────────────────────────────────────
      //
      // Two distinct code paths to satisfy GetX's requirement that every
      // Obx closure subscribes to at least one observable:
      //
      //   searchQuery != null → Obx reads searchQuery!.value for the
      //                         active-dot indicator.  Observable guaranteed.
      //   searchQuery == null → No dot needed, no Obx created at all.
      if (searchQuery != null || (searchDoctype != null && searchRoute != null))
        Builder(
          builder: (ctx) {
            // ─ path A: searchQuery non-null — wrap in Obx ────────────
            if (searchQuery != null) {
              final colorScheme = Theme.of(ctx).colorScheme;
              return Obx(() {
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

            // ─ path B: searchQuery null — no Obx ─────────────────────
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

    // ── Title widget ────────────────────────────────────────────────────
    //
    // softWrap: true  — allow the text to break across lines.
    // overflow: clip  — never add an ellipsis.
    // maxLines: null  — unlimited lines; large-title area expands to fit.
    final titleWidget = Text(
      title,
      softWrap: true,
      overflow: TextOverflow.clip,
      maxLines: null,
    );

    return SliverAppBar.large(
      title: titleWidget,
      actions: actions.isEmpty ? null : actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
      scrolledUnderElevation: 1.0,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
        title: Text(
          title,
          softWrap: true,
          overflow: TextOverflow.clip,
          maxLines: null,
        ),
        collapseMode: CollapseMode.none,
      ),
    );
  }

  // ── Active filter chip row ────────────────────────────────────────────
  Widget _buildFilterChips(BuildContext context) {
    return SliverPersistentHeader(
      // pinned: true guarantees the chip row is NEVER pushed off-screen by
      // the scroll position.  The visual content is hidden reactively inside
      // build() when no chips are active; the sliver itself always holds its
      // reserved slot in the layout so subsequent slivers do not shift up.
      pinned: true,
      delegate: _FilterChipHeaderDelegate(
        searchQuery: searchQuery,
        activeFilters: activeFilters,
        filterChipsBuilder: filterChipsBuilder!,
        onClearAllFilters: onClearAllFilters,
      ),
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

// ---------------------------------------------------------------------------
// Filter chip persistent header delegate
// ---------------------------------------------------------------------------

class _FilterChipHeaderDelegate extends SliverPersistentHeaderDelegate {
  final RxString? searchQuery;
  final RxMap? activeFilters;
  final List<Widget> Function(BuildContext context) filterChipsBuilder;
  final VoidCallback? onClearAllFilters;

  _FilterChipHeaderDelegate({
    required this.searchQuery,
    required this.activeFilters,
    required this.filterChipsBuilder,
    required this.onClearAllFilters,
  });

  // ── Content presence ───────────────────────────────────────────────────
  //
  // Called synchronously by the sliver layout protocol OUTSIDE the widget
  // tree — [Obx] is unavailable here.  Read Rx values directly (.value) so
  // Flutter gets a stable, immediate answer without scheduling a rebuild.
  //
  // Note: this intentionally does NOT register these reads with GetX's
  // reactive graph because [SliverPersistentHeaderDelegate] is not a widget.
  // Reactive updates are handled inside [build] via [Obx] instead.
  bool get _hasContent =>
      (searchQuery?.value ?? '').isNotEmpty ||
      (activeFilters?.isNotEmpty ?? false);

  // ── Extents ────────────────────────────────────────────────────────────
  //
  // [minExtent] == [maxExtent] — the chip row never partially collapses;
  // it is either fully visible (when _hasContent is true) or hidden via a
  // zero-height [SizedBox] returned from [build].
  //
  // Using [kToolbarHeight] (56 dp) as the reserved height covers a single
  // row of chips plus top/bottom padding.  Screens with many chips whose
  // [Wrap] overflows a single line will clip — a multi-run chip layout
  // should increase this constant or switch to a dynamic-height approach
  // (Commit 4 in the iterative plan).
  @override
  double get minExtent => _hasContent ? kToolbarHeight : 0.0;

  @override
  double get maxExtent => minExtent;

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Obx drives reactive rebuilds when searchQuery or activeFilters change.
    return Obx(() {
      final hasSearch = (searchQuery?.value ?? '').isNotEmpty;
      final hasFilters = (activeFilters?.isNotEmpty ?? false);

      // Hide visually when nothing is active.  The sliver still occupies
      // its reserved slot (minExtent) in the layout — that is what keeps
      // the chip row pinned and prevents list items from shifting up.
      if (!hasSearch && !hasFilters) return const SizedBox.shrink();

      final chips = filterChipsBuilder(context);
      if (chips.isEmpty) return const SizedBox.shrink();

      final colorScheme = Theme.of(context).colorScheme;

      return Material(
        // Solid surface ensures the pinned chip row is opaque and
        // does not show list content bleeding through behind it.
        color: colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
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
        ),
      );
    });
  }

  // ── shouldRebuild ──────────────────────────────────────────────────────
  @override
  bool shouldRebuild(covariant _FilterChipHeaderDelegate oldDelegate) {
    // Identity checks on the Rx objects and callbacks are sufficient.
    // Fine-grained value changes are handled reactively by Obx in build().
    return filterChipsBuilder != oldDelegate.filterChipsBuilder ||
        onClearAllFilters != oldDelegate.onClearAllFilters ||
        searchQuery != oldDelegate.searchQuery ||
        activeFilters != oldDelegate.activeFilters;
  }
}
