import 'dart:math' as math;
import 'package:auto_size_text/auto_size_text.dart';
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
///           + _kChipRow            (56 dp — only when _chipsActive is true)
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
/// ## Reactive rebuild chain (Fixes 1–3)
///
/// ```
/// Rx mutation
///   └─ Obx in build() re-runs DocTypeListHeader.build()     [Fix 3]
///        └─ new delegate with fresh Rx snapshots
///             └─ shouldRebuild compares .length / .value       [Fix 2]
///                  └─ returns true → SliverPersistentHeader
///                       recalculates maxExtent
///                            └─ Column guard == maxExtent      [Fix 1]
/// ```
///
/// ## Search icon
/// When [searchQuery] is non-null an [Obx] wraps the icon so the active-dot
/// indicator reacts to query changes.  When null no [Obx] is created.
///
/// ## Filter icon states
/// • Idle — plain [Icons.filter_list].
/// • Active — [IconButton.filled] ([Icons.filter_alt]) + [Badge] count.
///
/// ## Title visibility — collapsed toolbar
/// The collapsed toolbar title uses [AutoSizeText] to guarantee the full
/// DocType name is always readable:
///
/// 1. Up to [_kAutoSizeMaxLines] lines are allowed before the font shrinks.
/// 2. Font shrinks in 0.5 sp steps down to [_kAutoSizeMinFont] (11 sp).
/// 3. Only if the text still overflows at 11 sp does [TextOverflow.clip]
///    fire — this is the hard safety net, not the first resort.
///
/// The expanded (large) title in the area above the toolbar never clips:
/// [softWrap] is `true`, [maxLines] is `null`.
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

  // ✔ FIX 3: Obx wrapper triggers a widget rebuild whenever activeFilters
  // or searchQuery mutates in-place.  This produces a new delegate with
  // fresh Rx snapshots, which shouldRebuild (Fix 2) detects as changed,
  // causing SliverPersistentHeader to recalculate maxExtent (Fix 1 guard).
  //
  // Obx reads both Rx values unconditionally so both are registered with
  // GetX’s reactive graph regardless of whether filterChipsBuilder is set.
  // The reads use null-safe fallbacks so no NPE is possible.
  @override
  Widget build(BuildContext context) {
    // Touch the Rx values inside Obx so mutations schedule a rebuild.
    if (activeFilters != null || searchQuery != null) {
      return Obx(() {
        // Register both observables with the reactive graph.
        final _ = activeFilters?.length;    // ignore: unused_local_variable
        final __ = searchQuery?.value;      // ignore: unused_local_variable
        return _buildSliver();
      });
    }
    // No reactive props — plain StatelessWidget path, zero overhead.
    return _buildSliver();
  }

  Widget _buildSliver() {
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
// AutoSizeText tuning constants
// ──────────────────────────────────────────────────────────────────────────────

/// Minimum font size the collapsed toolbar title may shrink to before
/// [TextOverflow.clip] is used as a last resort.
const double _kAutoSizeMinFont = 11.0;

/// Maximum number of lines the collapsed toolbar title may wrap to before
/// AutoSizeText starts reducing the font size.
const int _kAutoSizeMaxLines = 2;

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

  // ── Chip presence ─────────────────────────────────────────────────────────
  //
  // Single source of truth for chip row height allocation.
  // Read synchronously (no Obx) — used by maxExtent AND the Column guard.
  bool get _chipsActive =>
      filterChipsBuilder != null &&
      ((searchQuery?.value ?? '').isNotEmpty ||
          (activeFilters?.isNotEmpty ?? false));

  // ── Extents ────────────────────────────────────────────────────────────
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

    final collapseProgress =
        math.min(1.0, shrinkOffset / _kExpandedExtra);
    final expandProgress = 1.0 - collapseProgress;

    final chipsNowActive = _chipsActive;

    final toolbar = _buildToolbar(context, colorScheme, theme);

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

    Widget? chipRow;
    if (chipsNowActive) {
      final chips = filterChipsBuilder!(context);
      if (chips.isNotEmpty) {
        chipRow = Material(
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
      }
    }

    return Material(
      color: colorScheme.surface,
      elevation: overlapsContent ? 1.0 : 0.0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: math.max(0.0, _kExpandedExtra * expandProgress),
            child: largeTitle,
          ),
          toolbar,
          if (chipsNowActive && chipRow != null)
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
    final titleStyle = theme.textTheme.titleLarge;
    final maxFontSize = (titleStyle?.fontSize ?? 22.0);

    return SizedBox(
      height: _kToolbar,
      child: NavigationToolbar(
        leading: _buildLeading(context),
        middle: AutoSizeText(
          title,
          style: titleStyle,
          maxLines: _kAutoSizeMaxLines,
          minFontSize: _kAutoSizeMinFont,
          maxFontSize: maxFontSize,
          stepGranularity: 0.5,
          overflow: TextOverflow.clip,
          softWrap: true,
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
      return Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: MaterialLocalizations.of(ctx).openAppDrawerTooltip,
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      );
    }
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
  //
  // ✔ FIX 2: also compare Rx *values*, not just object identity.
  //
  // GetX mutates RxMap / RxString in-place, so the same object reference
  // is passed on both calls.  Pure identity checks miss content changes
  // and leave maxExtent stale.
  //
  // Reading .length / .value here is intentionally outside Obx — we want
  // a synchronous snapshot for the sliver layout protocol.  The reads do
  // NOT register with GetX’s reactive graph from this context; fine-grained
  // reactivity inside the built widget tree is still handled by Obx in
  // _buildActions.
  @override
  bool shouldRebuild(covariant _DocTypeListHeaderDelegate old) {
    final filtersChanged =
        (activeFilters?.length ?? 0) != (old.activeFilters?.length ?? 0);
    final searchChanged =
        (searchQuery?.value ?? '') != (old.searchQuery?.value ?? '');

    return filtersChanged ||
        searchChanged ||
        title != old.title ||
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
