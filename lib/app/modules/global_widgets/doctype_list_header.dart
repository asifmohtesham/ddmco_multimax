import 'dart:math' as math;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// owns the full layout (status-bar shield + collapsed toolbar +
/// expanding large title + optional filter chip row) inside a single
/// coordinated layout pass.
///
/// ---
///
/// ## Status-bar / notification-panel overlap
///
/// [SliverPersistentHeader] positions its delegate widget at `y = 0` of
/// the scroll viewport, which is itself at `y = 0` of the [Scaffold] body.
/// When the [Scaffold] does **not** pad the body for the system status bar
/// (e.g. `extendBodyBehindAppBar: true`, transparent system UI, or
/// Android 15+ edge-to-edge mode) the header would paint directly behind
/// the notification pull-down panel.
///
/// The delegate reads `MediaQuery.paddingOf(context).top` every build and
/// adds that value — `_kStatusBar` — to both the height extents and the
/// Column layout:
///
/// ```
/// minExtent = _kStatusBar + _kToolbar
/// maxExtent = _kStatusBar + _kToolbar + _kExpandedExtra
///             + (_chipsActive ? _kChipRow : 0)
/// ```
///
/// A `SizedBox(_kStatusBar)` filled with the surface colour sits at the
/// very top of the Column, acting as an opaque shield that matches the
/// AppBar background so the transition looks seamless.  When
/// `_kStatusBar == 0` (tablet / desktop / Scaffold that already pads the
/// body) the SizedBox collapses to zero height and the layout is
/// identical to before.
///
/// ---
///
/// ## Status-bar icon contrast (notification panel readability)
///
/// The [Material] root uses `colorScheme.surface` as its background.  When
/// that colour is light (e.g. white, as set in this app's theme) the Android
/// system status-bar icons render in **dark** mode so they remain visible
/// against the light surface.  The style is determined at build time from the
/// resolved surface colour's relative luminance:
///
/// - `luminance > 0.5` → `statusBarIconBrightness: Brightness.dark`
///   (dark/black icons — readable on white / light surfaces)
/// - `luminance ≤ 0.5` → `statusBarIconBrightness: Brightness.light`
///   (light/white icons — readable on dark surfaces)
///
/// The style is applied via an [AnnotatedRegion]<[SystemUiOverlayStyle]>,
/// which is the Flutter-idiomatic way to set system-UI colours from widget
/// code without calling `SystemChrome.setSystemUIOverlayStyle()` globally.
/// [AnnotatedRegion] applies the style only while this widget is in the tree
/// and automatically restores the previous style when it leaves.
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
/// maxExtent = _kStatusBar          (MediaQuery top padding — 0 when not needed)
///           + _kToolbar            (56 dp — always)
///           + _kExpandedExtra      (96 dp — large-title extra)
///           + _kChipRow            (56 dp — only when _chipsActive is true)
/// minExtent = _kStatusBar + _kToolbar
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
  // GetX's reactive graph regardless of whether filterChipsBuilder is set.
  // The reads use null-safe fallbacks so no NPE is possible.
  @override
  Widget build(BuildContext context) {
    if (activeFilters != null || searchQuery != null) {
      return Obx(() {
        final _ = activeFilters?.length;    // ignore: unused_local_variable
        final __ = searchQuery?.value;      // ignore: unused_local_variable
        return _buildSliver(context);
      });
    }
    return _buildSliver(context);
  }

  Widget _buildSliver(BuildContext context) {
    // Read the status-bar height once per build and pass it into the
    // delegate.  SliverPersistentHeader calls the delegate's build() with
    // the same BuildContext, so the delegate can re-read it there too —
    // but passing it explicitly keeps minExtent / maxExtent consistent
    // with the same snapshot used for layout.
    final statusBarHeight = MediaQuery.paddingOf(context).top;

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
        statusBarHeight: statusBarHeight,
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

  /// Height of the system status bar on this device / orientation.
  /// Comes from [MediaQuery.paddingOf(context).top] captured in
  /// [DocTypeListHeader._buildSliver].
  /// Zero on tablets, desktops, and Scaffolds that already pad the body.
  final double statusBarHeight;

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
    required this.statusBarHeight,
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
  //
  // statusBarHeight is included in BOTH min and max so the sliver layout
  // protocol allocates the correct amount of space at all collapse states.
  @override
  double get minExtent => statusBarHeight + _kToolbar;

  @override
  double get maxExtent =>
      statusBarHeight +
      _kToolbar +
      _kExpandedExtra +
      (_chipsActive ? _kChipRow : 0.0);

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // collapseProgress is computed against the *content* shrink range only
    // (i.e. _kExpandedExtra), not the status-bar height, so the large-title
    // fade is unaffected by the inset.
    final collapseProgress =
        math.min(1.0, shrinkOffset / _kExpandedExtra);
    final expandProgress = 1.0 - collapseProgress;

    final chipsNowActive = _chipsActive;

    // ── Status-bar icon brightness ─────────────────────────────────────────
    //
    // Determine whether the system status-bar icons (clock, battery, signal)
    // should be rendered dark or light based on the resolved surface colour.
    //
    // colorScheme.surface in this app is Colors.white (luminance ≈ 1.0), so
    // the icons must be DARK (black) to stay visible.  The luminance check
    // makes this theme-safe: if the surface ever changes to a dark colour the
    // icons automatically switch to light.
    //
    // AnnotatedRegion<SystemUiOverlayStyle> is the Flutter-idiomatic approach:
    // it applies the style only while this widget subtree is active and
    // restores the previous style when it leaves — unlike
    // SystemChrome.setSystemUIOverlayStyle() which mutates global state.
    final surfaceLuminance = colorScheme.surface.computeLuminance();
    final iconBrightness = surfaceLuminance > 0.5
        ? Brightness.dark   // dark icons readable on light (white) surface
        : Brightness.light; // light icons readable on dark surface

    final overlayStyle = SystemUiOverlayStyle(
      // Transparent so the shield SizedBox background (from Material) shows
      // through — we never hard-code a status-bar background colour here.
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,        // Android
      statusBarBrightness: iconBrightness == Brightness.dark  // iOS
          ? Brightness.light
          : Brightness.dark,
      // Keep bottom-nav bar icons consistent while this header is on screen.
      systemNavigationBarIconBrightness: iconBrightness,
    );

    // ─ Status-bar shield ───────────────────────────────────────────────────
    // An opaque block that fills the inset with the surface colour.
    // Collapses to zero on devices/configs where statusBarHeight == 0.
    final statusBarShield = SizedBox(
      height: statusBarHeight,
      // No child needed — the parent Material provides the background colour.
    );

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

    // ─ Chip row ──────────────────────────────────────────────────────────
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

    // ─ Full layout ─────────────────────────────────────────────────────────
    //
    // Stack order (top → bottom on screen):
    //   1. statusBarShield  — covers the system status bar area
    //   2. large-title fade — collapses as shrinkOffset grows
    //   3. toolbar          — always present
    //   4. chip row         — only when chipsNowActive
    //
    // Column is anchored to the bottom so that as the header shrinks the
    // toolbar and chip row stay pinned at the bottom of the allocated space.
    //
    // AnnotatedRegion wraps the entire widget tree so the SystemUiOverlayStyle
    // is active for the full lifetime of this header frame.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Material(
        color: colorScheme.surface,
        elevation: overlapsContent ? 1.0 : 0.0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status-bar shield: always at the very top, always full height.
            // Because the Column is end-aligned we pin it to the top with a
            // Spacer trick: prepend the shield before the expanding region so
            // it stays fixed regardless of collapse state.
            //
            // To achieve top-pinning inside an end-aligned Column we flip the
            // anchor: place the shield first (it will be pushed up), then
            // the content below it fills the remaining space.
            //
            // Actually we need the shield at the top regardless of shrink —
            // use a Stack instead of relying on Column ordering:
            //   The outer SizedBox constrains to maxExtent height.
            //   The shield is Positioned at top:0.
            //   The content Column is below it.
            //
            // Simpler: add the shield as the first child of the Column and
            // use mainAxisAlignment.end only on the *content* children.
            // We achieve this by wrapping content in an Expanded + Column.
            statusBarShield,
            Expanded(
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
            ),
          ],
        ),
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

    // ── Leading widget ──────────────────────────────────────────────────────────
  //
  // Hard-fail guards:
  //
  // 1. Scaffold.of(ctx).openDrawer() throws StateError when the Scaffold has no
  //    drawer. We catch that and fall back to a plain back-arrow so the screen
  //    is still navigable.
  //
  // 2. Navigator.of(context).maybePop() throws FlutterError when there is no
  //    Navigator ancestor (bare tests, certain nested-Navigator configurations).
  //    We guard with a null-check on Navigator.maybeOf() before calling pop.
  Widget? _buildLeading(BuildContext context) {
    if (!automaticallyImplyLeading) {
      // Top-level list screen: attempt to open the Scaffold drawer.
      // Falls back to a plain ← arrow if no drawer is registered, so the
      // screen is always navigable rather than throwing StateError.
      return Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: MaterialLocalizations.of(ctx).openAppDrawerTooltip,
          onPressed: () {
            final scaffold = Scaffold.maybeOf(ctx);
            if (scaffold != null && scaffold.hasDrawer) {
              scaffold.openDrawer();
            } else {
              // Drawer unavailable — degrade gracefully to back navigation.
              Navigator.maybeOf(ctx)?.maybePop();
            }
          },
        ),
      );
    }

    // Form / pushed screen: show ← back arrow only when there is a route
    // to pop back to AND a Navigator is available.
    final ModalRoute<Object?>? parentRoute = ModalRoute.of(context);
    final bool canPop = parentRoute?.canPop ?? false;
    if (canPop) {
      return IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        // Navigator.maybeOf avoids the FlutterError thrown by Navigator.of
        // when no Navigator ancestor exists (e.g. bare widget tests).
        onPressed: () => Navigator.maybeOf(context)?.maybePop(),
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
  // statusBarHeight is also compared so an orientation change (portrait ↔
  // landscape, which changes the status-bar height on some devices) forces
  // a full recalculation of minExtent / maxExtent.
  @override
  bool shouldRebuild(covariant _DocTypeListHeaderDelegate old) {
    final filtersChanged =
        (activeFilters?.length ?? 0) != (old.activeFilters?.length ?? 0);
    final searchChanged =
        (searchQuery?.value ?? '') != (old.searchQuery?.value ?? '');

    return filtersChanged ||
        searchChanged ||
        statusBarHeight != old.statusBarHeight ||
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
