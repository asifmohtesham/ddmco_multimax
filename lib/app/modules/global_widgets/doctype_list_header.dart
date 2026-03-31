import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Heights — keep all magic numbers in one place.
// ──────────────────────────────────────────────────────────────────────────────

/// Height of the permanently-pinned collapsed toolbar row.
const double _kToolbar = kToolbarHeight; // 56 dp

/// Extra vertical space the large title occupies above the toolbar when
/// fully expanded.  Matches Material 3 SliverAppBar.large default.
const double _kExpandedExtra = 96.0; // total expanded = 152 dp

/// Height reserved for the active-filter chip row.
const double _kChipRow = kToolbarHeight; // 56 dp — fits a single Wrap row

// ──────────────────────────────────────────────────────────────────────────────
// Public widget
// ──────────────────────────────────────────────────────────────────────────────

/// A unified sliver header for every DocType **list** screen.
///
/// Emits **exactly one sliver** — a [SliverPersistentHeader] whose delegate
/// owns the full layout (collapsed toolbar + expanding large title +
/// optional filter chip row) inside a single coordinated layout pass.
/// This guarantees the entire header moves as one indivisible unit and
/// never allows the chip row to scroll away independently of the toolbar.
///
/// ---
///
/// ## Sticky behaviour
///
/// Both the toolbar and the chip row honour the same [pinnedAppBar] flag.
///
/// | [pinnedAppBar] | [floatingAppBar] | Behaviour |
/// |----------------|------------------|-----------|
/// | `true` (default) | `false` (default) | Toolbar + chips **permanently pinned**. Large title fades out on scroll. |
/// | `true` | `true` | Same pinning + header snaps back on any upward swipe. |
/// | `false` | `false` | Entire header scrolls off-screen. |
/// | `false` | `true` | Floats: scrolls away, snaps back on upward fling. |
///
/// ## Height budget
///
/// ```
/// maxExtent = _kToolbar            (56 dp — always)
///           + _kExpandedExtra      (96 dp — large-title extra)
///           + _kChipRow            (56 dp — only when chips are active)
/// minExtent = _kToolbar            (56 dp — collapsed, always pinned)
/// ```
///
/// ---
///
/// ## Leading button convention
///
/// | Screen type | [automaticallyImplyLeading] | Result |
/// |-------------|----------------------------|--------|
/// | **List screen** (top-level destination) | `false` | ☰ Drawer hamburger |
/// | **Form screen** (pushed onto stack) | `true` (default) | ← Back arrow |
///
/// ## Search icon
/// When [searchQuery] is non-null an [Obx] wraps the icon so the active-dot
/// indicator reacts to query changes.  When null no [Obx] is created.
///
/// ## Filter icon states
/// • Idle — plain [Icons.filter_list].
/// • Active — [IconButton.filled] ([Icons.filter_alt]) + [Badge] count.
///
/// ## Title visibility
/// Always rendered in full — no ellipsis, no clamping.
class DocTypeListHeader extends StatelessWidget {
  // ── AppBar ────────────────────────────────────────────────────────────
  final String title;
  final List<Widget>? extraActions;

  /// Whether [SliverAppBar] auto-inserts a leading widget.
  /// Pass `false` for top-level list screens (shows hamburger).
  /// Omit (defaults `true`) for form screens (shows back arrow).
  final bool automaticallyImplyLeading;

  /// Keeps the collapsed toolbar + chip row pinned at the top.
  /// Defaults to `true`.  Pass `false` to let the whole header scroll away.
  final bool pinnedAppBar;

  /// Snaps the header back into view on any upward swipe.
  /// Defaults to `false`.  Only meaningful when [pinnedAppBar] is `true`.
  final bool floatingAppBar;

  // ── Search ────────────────────────────────────────────────────────────
  final String? searchDoctype;
  final String? searchRoute;
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
    this.pinnedAppBar = true,
    this.floatingAppBar = false,
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
    // Single sliver — the delegate owns all layout.
    return SliverPersistentHeader(
      pinned: pinnedAppBar,
      floating: floatingAppBar,
      delegate: _DocTypeListHeaderDelegate(
        title: title,
        extraActions: extraActions,
        automaticallyImplyLeading: automaticallyImplyLeading,
        searchDoctype: searchDoctype,
        searchRoute: searchRoute,
        searchQuery: searchQuery,
        onSearchChanged: onSearchChanged,
        onSearchClear: onSearchClear,
        activeFilters: activeFilters,
        onFilterTap: onFilterTap,
        filterChipsBuilder: filterChipsBuilder,
        onClearAllFilters: onClearAllFilters,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Master delegate — owns the full header layout
// ──────────────────────────────────────────────────────────────────────────────

class _DocTypeListHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final List<Widget>? extraActions;
  final bool automaticallyImplyLeading;
  final String? searchDoctype;
  final String? searchRoute;
  final RxString? searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;
  final RxMap? activeFilters;
  final VoidCallback? onFilterTap;
  final List<Widget> Function(BuildContext context)? filterChipsBuilder;
  final VoidCallback? onClearAllFilters;

  const _DocTypeListHeaderDelegate({
    required this.title,
    required this.extraActions,
    required this.automaticallyImplyLeading,
    required this.searchDoctype,
    required this.searchRoute,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.activeFilters,
    required this.onFilterTap,
    required this.filterChipsBuilder,
    required this.onClearAllFilters,
  });

  // ── Chip presence (synchronous, no Obx) ────────────────────────────────
  bool get _chipsActive =>
      filterChipsBuilder != null &&
      ((searchQuery?.value ?? '').isNotEmpty ||
          (activeFilters?.isNotEmpty ?? false));

  // ── Extents ────────────────────────────────────────────────────────────
  //
  // minExtent: collapsed toolbar only — always pinned, never shrinks further.
  // maxExtent: toolbar + large-title extra + chip row (when active).
  @override
  double get minExtent => _kToolbar;

  @override
  double get maxExtent =>
      _kToolbar + _kExpandedExtra + (_chipsActive ? _kChipRow : 0.0);

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // How far through the collapse animation are we? (0.0 → 1.0)
    // Clamp to [0,1] so rounding errors never produce negative opacity.
    final collapseProgress =
        math.min(1.0, shrinkOffset / _kExpandedExtra);
    final expandProgress = 1.0 - collapseProgress;

    // ─ Toolbar row ─────────────────────────────────────────────────────────
    final toolbar = _buildToolbar(context, colorScheme, theme);

    // ─ Large title (fades out as user scrolls) ───────────────────────────
    final largeTitle = Opacity(
      opacity: expandProgress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 72, 8),
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            softWrap: true,
            overflow: TextOverflow.clip,
            maxLines: null,
          ),
        ),
      ),
    );

    // ─ Chip row (Obx for reactivity) ───────────────────────────────────
    Widget? chipRow;
    if (filterChipsBuilder != null) {
      chipRow = Obx(() {
        final hasSearch = (searchQuery?.value ?? '').isNotEmpty;
        final hasFilters = (activeFilters?.isNotEmpty ?? false);
        if (!hasSearch && !hasFilters) return const SizedBox.shrink();

        final chips = filterChipsBuilder!(context);
        if (chips.isEmpty) return const SizedBox.shrink();

        return Material(
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

    // ─ Full layout ───────────────────────────────────────────────────────────
    //
    // The SliverPersistentHeader gives us a fixed-height box that shrinks
    // from maxExtent down to minExtent.  We lay the content out in a Column
    // anchored to the BOTTOM of that box so the toolbar row is always at the
    // bottom (i.e. always visible) and the large title scrolls off the top.
    return Material(
      color: colorScheme.surface,
      elevation: overlapsContent ? 1.0 : 0.0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Large title occupies the space above the toolbar.
          // SizedBox clamps to zero when fully collapsed.
          SizedBox(
            height: math.max(0.0, _kExpandedExtra * expandProgress),
            child: largeTitle,
          ),
          // Pinned toolbar — always visible, always 56 dp.
          toolbar,
          // Chip row — always below the toolbar; shown/hidden via Obx.
          if (chipRow != null)
            SizedBox(height: _kChipRow, child: chipRow),
        ],
      ),
    );
  }

  // ── Toolbar row ──────────────────────────────────────────────────────────
  Widget _buildToolbar(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return SizedBox(
      height: _kToolbar,
      child: NavigationToolbar(
        leading: _buildLeading(context),
        middle: Text(
          title,
          style: theme.textTheme.titleLarge,
          softWrap: true,
          overflow: TextOverflow.clip,
          maxLines: null,
        ),
        trailing: _buildActions(context, colorScheme),
        centerMiddle: false,
        middleSpacing: 8,
      ),
    );
  }

  // ── Leading widget ────────────────────────────────────────────────────────
  Widget? _buildLeading(BuildContext context) {
    if (!automaticallyImplyLeading) {
      // Top-level screen: show the drawer hamburger.
      return Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: MaterialLocalizations.of(ctx).openAppDrawerTooltip,
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      );
    }
    // Form screen: let Navigator provide the back button.
    final ModalRoute<Object?>? parentRoute = ModalRoute.of(context);
    final bool canPop = parentRoute?.canPop ?? false;
    if (canPop) {
      return IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.of(context).maybePop(),
      );
    }
    return null;
  }

  // ── Actions row ──────────────────────────────────────────────────────────
  Widget? _buildActions(BuildContext context, ColorScheme colorScheme) {
    final items = <Widget>[
      ...(extraActions ?? []),

      // ─ Filter icon ─────────────────────────────────────────────────────
      if (onFilterTap != null)
        Obx(() {
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
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                )
              : IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: onFilterTap,
                  tooltip: tooltip,
                );
          return isActive ? Badge(label: Text('$count'), child: button) : button;
        }),

      // ─ Search icon ────────────────────────────────────────────────────
      if (searchQuery != null || (searchDoctype != null && searchRoute != null))
        Builder(
          builder: (ctx) {
            if (searchQuery != null) {
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

    if (items.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: items);
  }

  // ── shouldRebuild ────────────────────────────────────────────────────────
  @override
  bool shouldRebuild(covariant _DocTypeListHeaderDelegate old) {
    return title != old.title ||
        automaticallyImplyLeading != old.automaticallyImplyLeading ||
        extraActions != old.extraActions ||
        searchDoctype != old.searchDoctype ||
        searchRoute != old.searchRoute ||
        searchQuery != old.searchQuery ||
        onSearchChanged != old.onSearchChanged ||
        onSearchClear != old.onSearchClear ||
        activeFilters != old.activeFilters ||
        onFilterTap != old.onFilterTap ||
        filterChipsBuilder != old.filterChipsBuilder ||
        onClearAllFilters != old.onClearAllFilters;
  }
}
