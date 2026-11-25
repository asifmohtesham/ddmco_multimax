import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/header_chip_band.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/global_widgets/recent_search_suggestions.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

const double _target = 48;
const double _expandedBand = 96;
const double _middleSpacing = 8;
// Room for the result count and the start of the first card.
const double _resultsSpace = 88;

/// The shared, scalable persistent header for DocType list screens.
class DocTypeListHeader extends StatefulWidget {
  /// Minimum height of a visible filter and quick-chip row.
  static const chipRowHeight = _target;

  /// The laid-out header's lower edge in an ancestor's coordinates.
  static double? extentInViewport(GlobalKey key, RenderObject viewport) {
    final sliver = key.currentContext?.findRenderObject();
    final child = sliver is RenderSliverPersistentHeader ? sliver.child : null;
    if (child == null || !child.attached || !child.hasSize) return null;
    return child
        .localToGlobal(Offset(0, child.size.height), ancestor: viewport)
        .dy;
  }

  /// Identifies the persistent sliver for consumers that position overlays.
  final GlobalKey? sliverKey;

  // ── AppBar ────────────────────────────────────────────────────────────
  final String title;
  final List<Widget>? extraActions;

  /// Prefer Back over Menu when both actions are available.
  final bool automaticallyImplyLeading;

  /// Keeps the collapsed toolbar + chip row pinned at the top.
  /// Defaults to `true` when the viewport can also show results.
  final bool pinnedAppBar;

  /// Snaps the header back into view on any upward swipe.
  /// Defaults to `false`.  Only meaningful when [pinnedAppBar] is `true`.
  final bool floatingAppBar;

  // ── Search ────────────────────────────────────────────────────────────
  final String? searchDoctype;

  /// Overrides the doctype or route used to scope recent searches.
  final String? recentSearchKey;
  final String? searchRoute;
  final RxString? searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;

  // ── Filter ────────────────────────────────────────────────────────────
  final RxMap? activeFilters;
  final VoidCallback? onFilterTap;
  final bool filtersEnabled;
  final String clearAllLabel;

  // ── Chip row ──────────────────────────────────────────────────────────
  /// Builder that returns the list of chip widgets to display.
  ///
  /// Active chips wrap. A bulk action is offered when more
  /// than one chip is displayed and [onClearAllFilters] is supplied.
  final List<Widget> Function(BuildContext context)? filterChipsBuilder;
  final VoidCallback? onClearAllFilters;

  /// Chips that are always shown in the chip row, after the active-filter
  /// chips and the `+ Filter` add-chip — e.g. a report's sort choices. Unlike
  /// [filterChipsBuilder] they do not depend on a filter being active.
  final List<Widget>? quickChips;

  /// Additional invalidation key for opaque quick controls.
  final Object? quickChipsKey;

  // ── Image scan ────────────────────────────────────────────────────────
  /// When non-null, the search delegate shows a camera icon that opens the
  /// image scan flow. Only [ItemListAppBar] sets this.
  final ValueChanged<ImageScanResult>? onImageScanResult;

  // ── Bottom slot ───────────────────────────────────────────────────────
  /// Optional widget pinned below the collapsed toolbar — typically a [TabBar].
  ///
  /// Its preferred height reserves space in both extents. The slot can grow
  /// when its incoming text scaler needs more room for captions.
  final PreferredSizeWidget? bottom;

  /// Builds a measured bottom under the header's effective text scaler.
  /// The legacy [bottom] keeps its incoming text scaler.
  final PreferredSizeWidget Function(BuildContext)? measuredBottomBuilder;

  /// Additional invalidation key for opaque toolbar actions.
  final Object? extraActionsKey;

  const DocTypeListHeader({
    super.key,
    this.sliverKey,
    required this.title,
    this.extraActions,
    this.automaticallyImplyLeading = true,
    this.pinnedAppBar = true,
    this.floatingAppBar = false,
    this.searchDoctype,
    this.recentSearchKey,
    this.searchRoute,
    this.searchQuery,
    this.onSearchChanged,
    this.onSearchClear,
    this.activeFilters,
    this.onFilterTap,
    this.filtersEnabled = true,
    this.clearAllLabel = 'Reset filters',
    this.filterChipsBuilder,
    this.onClearAllFilters,
    this.quickChips,
    this.quickChipsKey,
    this.onImageScanResult,
    this.bottom,
    this.measuredBottomBuilder,
    this.extraActionsKey,
  });

  @override
  State<DocTypeListHeader> createState() => _DocTypeListHeaderState();
}

enum _LeadingAction { menu, back }

class _DocTypeListHeaderState extends State<DocTypeListHeader> {
  final _funnelFocus = FocusNode(debugLabel: 'Filters');
  final _searchFocus = FocusNode(debugLabel: 'Search');
  final _titleFocus = FocusNode(debugLabel: 'Show full title');
  final _bandKey = GlobalKey(debugLabel: 'list-header-filter-row');
  final _bottomKey = GlobalKey(debugLabel: 'list-header-measured-bottom');
  final _toolbarKey = GlobalKey(debugLabel: 'list-header-toolbar');
  final _rowsKey = GlobalKey(debugLabel: 'list-header-rows');

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  void _fontsChanged() {
    // Recreate the sliver's measurement when the font metrics change.
    setState(() {});
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _funnelFocus.dispose();
    _searchFocus.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomScaler = MediaQuery.textScalerOf(context);
    return ListHeaderTextScope(
      child: Builder(
        builder: (context) {
          if (widget.activeFilters != null || widget.searchQuery != null) {
            return Obx(() => _buildSliver(context, bottomScaler));
          }
          return _buildSliver(context, bottomScaler);
        },
      ),
    );
  }

  Widget _buildSliver(BuildContext context, TextScaler bottomScaler) {
    final filters = Map<Object?, Object?>.of(widget.activeFilters ?? const {});
    final query = widget.searchQuery?.value ?? '';
    final applied = List<Widget>.unmodifiable(
      filters.isNotEmpty || query.isNotEmpty
          ? widget.filterChipsBuilder?.call(context) ?? const []
          : const [],
    );
    final extras = List<Widget>.unmodifiable(widget.extraActions ?? const []);
    final quick = List<Widget>.unmodifiable(widget.quickChips ?? const []);
    final theme = Theme.of(context);
    final leading = _resolveLeading(context);
    final hasSearch =
        widget.searchQuery != null ||
        (widget.searchDoctype != null && widget.searchRoute != null);
    final hasAdd = widget.onFilterTap != null;
    final hasBulk = applied.length > 1 && widget.onClearAllFilters != null;
    final recentKey = listRecentSearchKey(
      context,
      widget.recentSearchKey,
      widget.searchDoctype,
    );
    final header = widget;
    final textScaler = MediaQuery.textScalerOf(context);
    final bottom = header.measuredBottomBuilder?.call(context) ?? header.bottom;
    final measuredBottom =
        header.measuredBottomBuilder != null ||
        bottom is MeasuredListHeaderBottom;
    final slotScaler = measuredBottom ? textScaler : bottomScaler;
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final bold = MediaQuery.boldTextOf(context);
    final filterSnapshot = _freezeFilterValue(filters);
    Size? measuredViewport;
    SliverPersistentHeader? sliver;
    return SliverLayoutBuilder(
      builder: (_, constraints) {
        final viewport = Size(
          constraints.crossAxisExtent,
          constraints.viewportMainAxisExtent,
        );
        // Scroll-offset changes do not affect the measured geometry.
        if (viewport == measuredViewport) return sliver!;
        measuredViewport = viewport;
        final plan = planHeaderBand(context, viewport.width, [
          if (hasAdd) AddFilterChip.measureInBand,
          ...applied.map(_chipMeasure),
          ...quick.map(_chipMeasure),
          if (hasBulk)
            (context, width) => measureBandChip(
              context,
              header.clearAllLabel,
              maxWidth: width,
              insets: 40,
            ),
        ], hasSplit: applied.any((chip) => chip is FilterChipWidget));
        final bottomHeight = bottom is MeasuredListHeaderBottom
            ? bottom.heightFor(context, viewport.width)
            : measuredBottom
            ? bottom?.preferredSize.height ?? 0
            : _bottomHeight(context, bottom, slotScaler);
        final geometry = _HeaderGeometryCalculator.measure(
          context,
          viewport: viewport,
          title: header.title,
          hasLeading: leading != null,
          extraCount: extras.length,
          hasFunnel: hasAdd,
          hasSearch: hasSearch,
          badgeCount: filters.length,
          bottomHeight: bottomHeight,
          row: plan.height,
          capExpanded: measuredBottom,
        );
        return sliver = SliverPersistentHeader(
          key: header.sliverKey,
          pinned: header.pinnedAppBar && geometry.canPin,
          floating: header.floatingAppBar,
          delegate: _ListHeaderDelegate(
            header: header,
            theme: theme,
            textScaler: textScaler,
            bottomScaler: slotScaler,
            bottom: bottom,
            bottomKey: measuredBottom ? _bottomKey : null,
            bandKey: _bandKey,
            toolbarKey: _toolbarKey,
            rowsKey: _rowsKey,
            plan: plan,
            direction: direction,
            locale: locale,
            bold: bold,
            filterSnapshot: filterSnapshot,
            count: filters.length,
            query: query,
            leading: leading,
            recentKey: recentKey,
            extras: extras,
            quick: quick,
            applied: applied,
            hasSearch: hasSearch,
            hasBulk: hasBulk,
            geometry: geometry,
            funnelFocus: _funnelFocus,
            searchFocus: _searchFocus,
            titleFocus: _titleFocus,
          ),
        );
      },
    );
  }

  _LeadingAction? _resolveLeading(BuildContext context) {
    final canPop = ModalRoute.canPopOf(context) ?? false;
    final hasDrawer = Scaffold.hasDrawer(context);
    if (canPop && (widget.automaticallyImplyLeading || !hasDrawer)) {
      return _LeadingAction.back;
    }
    return hasDrawer ? _LeadingAction.menu : null;
  }
}

HeaderChipMeasure _chipMeasure(Widget chip) => switch (chip) {
  FilterChipWidget() => chip.measureInBand,
  HeaderQuickChip() => chip.measure,
  MeasuredHeaderChip() => chip.measure,
  _ => (context, maxWidth) {
    final style = headerBandLabelStyle(context);
    final line = measureHeaderText(context, 'Ag', style).size.height;
    return (
      width: maxWidth,
      height: math.max(_target, line.ceil() + 16.0),
      paintHeight: 34,
      stackedReset: false,
      stackedChoice: false,
      maxLines: null,
      ellipsized: false,
    );
  },
};

Object? _freezeFilterValue(Object? value) => switch (value) {
  Map() => Map.unmodifiable(
    value.map((key, value) => MapEntry(key, _freezeFilterValue(value))),
  ),
  Set() => Set.unmodifiable(value.map(_freezeFilterValue)),
  Iterable() => List.unmodifiable(value.map(_freezeFilterValue)),
  _ => value,
};

TextStyle _largeTitleStyle(BuildContext context) =>
    (Theme.of(context).textTheme.headlineMedium ??
            const TextStyle(fontSize: 28))
        .copyWith(color: context.scheme.text, fontWeight: FontWeight.w600);

double _bottomHeight(
  BuildContext context,
  PreferredSizeWidget? bottom,
  TextScaler scaler,
) {
  if (bottom == null) return 0;
  final preset = Get.isRegistered<ThemeController>()
      ? Get.find<ThemeController>().textSize.value.factor
      : 1.0;
  final baseline = TextScaler.linear(preset);
  if (scaler == baseline) return bottom.preferredSize.height;
  final label =
      Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontSize: 14);
  double extraHeight(TextStyle style) =>
      measureHeaderText(
        context,
        'Ag',
        style,
        textScaler: scaler,
      ).size.height.ceilToDouble() -
      measureHeaderText(
        context,
        'Ag',
        style,
        textScaler: baseline,
      ).size.height.ceilToDouble();
  return bottom.preferredSize.height +
      math.max(
        0,
        math.max(extraHeight(label), extraHeight(label.copyWith(fontSize: 12))),
      );
}

typedef _HeaderGeometry = ({
  double width,
  double status,
  double toolbar,
  double bottom,
  double row,
  double largeTitle,
  double expanded,
  double compact,
  Size badge,
  Size funnel,
  bool separateBadge,
  bool overflow,
  bool overflowSearch,
  bool overflowFunnel,
  double middleSpacing,
  bool disclose,
  double extentLimit,
  bool capExpanded,
  TextStyle largeStyle,
  TextStyle compactStyle,
});

extension on _HeaderGeometry {
  double get fixedExtent => status + toolbar + bottom + row;
  bool get canPin => fixedExtent <= extentLimit;
}

abstract final class _HeaderGeometryCalculator {
  static _HeaderGeometry measure(
    BuildContext context, {
    required Size viewport,
    required String title,
    required bool hasLeading,
    required int extraCount,
    required bool hasFunnel,
    required bool hasSearch,
    required int badgeCount,
    required double bottomHeight,
    required double row,
    required bool capExpanded,
  }) {
    final status = MediaQuery.paddingOf(context).top;
    final size = hasFunnel && badgeCount > 0
        ? CountBadge.measureToolbar(context, badgeCount)
        : Size.zero;
    final badgeWidth = math.max(_target, size.width + 2);
    final badgeHeight = math.max(_target, size.height + 2);
    // A badge that reaches the 24 dp glyph's centre obscures its core.
    final separateBadge =
        size != Size.zero &&
        badgeWidth - 2 - size.width <= badgeWidth / 2 &&
        size.height + 2 >= badgeHeight / 2;
    final funnel = Size(
      separateBadge ? 44 + size.width : badgeWidth,
      badgeHeight,
    );
    final toolbar = hasFunnel
        ? math.max(kToolbarHeight, funnel.height)
        : kToolbarHeight;
    final theme = Theme.of(context);
    final largeStyle = _largeTitleStyle(context);
    final compactStyle =
        (theme.textTheme.titleLarge ?? const TextStyle(fontSize: 22)).copyWith(
          color: context.scheme.text,
        );
    final bandWidth = math.max(1.0, viewport.width - 32);
    final largeTitle =
        measureHeaderText(
          context,
          title,
          largeStyle,
          maxWidth: bandWidth,
        ).size.height.ceilToDouble() +
        8;
    final fixedWidth =
        (hasLeading ? _target : 0) +
        (hasSearch ? _target : 0) +
        (hasFunnel ? funnel.width : 0) +
        2 * _middleSpacing;
    bool fitsInline(int actions) {
      final available = viewport.width - fixedWidth - actions * _target;
      if (available <= 0) return false;
      final metrics = measureHeaderText(
        context,
        title,
        compactStyle,
        maxWidth: available,
        maxLines: 2,
      );
      return !metrics.didExceedMaxLines &&
          metrics.size.height.ceil() <= toolbar;
    }

    final fitsWithExtras = fitsInline(extraCount);
    var overflow = !fitsWithExtras && extraCount >= 3;
    var compact = fitsWithExtras || (overflow && fitsInline(1))
        ? 0.0
        : measureHeaderText(
            context,
            title,
            compactStyle,
            maxWidth: bandWidth,
          ).size.height.ceilToDouble();
    final minimumReserve = math.min(_target, viewport.height / 2);
    final resultReserve = capExpanded
        ? math.max(minimumReserve, math.min(_resultsSpace, viewport.height / 3))
        : minimumReserve;
    final extentLimit = viewport.height - resultReserve;
    final fixed = status + toolbar + bottomHeight + row;
    final disclose = compact > 0 && fixed + compact > extentLimit;
    var overflowSearch = false;
    var overflowFunnel = false;
    var middleSpacing = _middleSpacing;
    if (disclose) {
      compact = 0;
      final leadingWidth = hasLeading ? _target : 0.0;
      final searchWidth = hasSearch ? _target : 0.0;
      final funnelWidth = hasFunnel ? funnel.width : 0.0;
      double requiredWidth() =>
          leadingWidth +
          _target +
          (overflow ? 0 : extraCount * _target) +
          (overflow || overflowSearch || overflowFunnel ? _target : 0) +
          (overflowSearch ? 0 : searchWidth) +
          (overflowFunnel ? 0 : funnelWidth);
      if (extraCount > 1 && requiredWidth() > viewport.width) {
        overflow = true;
      }
      if (hasSearch && requiredWidth() > viewport.width) {
        overflowSearch = true;
      }
      if (hasFunnel && requiredWidth() > viewport.width) {
        overflowFunnel = true;
      }
      middleSpacing = ((viewport.width - requiredWidth()) / 2).clamp(
        0.0,
        _middleSpacing,
      );
    }
    final fullTitleBand = math.max(
      _expandedBand,
      math.max(largeTitle, compact),
    );
    final titleSpace = capExpanded
        ? math.min(fullTitleBand, extentLimit - fixed)
        : fullTitleBand;
    return (
      width: viewport.width,
      status: status,
      toolbar: toolbar,
      bottom: bottomHeight,
      row: row,
      largeTitle: largeTitle,
      expanded: titleSpace >= largeTitle
          ? math.max(titleSpace, compact)
          : compact,
      compact: compact,
      badge: size,
      funnel: funnel,
      separateBadge: separateBadge,
      overflow: overflow,
      overflowSearch: overflowSearch,
      overflowFunnel: overflowFunnel,
      middleSpacing: middleSpacing,
      disclose: disclose,
      extentLimit: extentLimit,
      capExpanded: capExpanded,
      largeStyle: largeStyle,
      compactStyle: compactStyle,
    );
  }
}

class _ListHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ListHeaderDelegate({
    required this.header,
    required this.theme,
    required this.textScaler,
    required this.bottomScaler,
    required this.bottom,
    required this.bottomKey,
    required GlobalKey bandKey,
    required this.toolbarKey,
    required this.rowsKey,
    required this.plan,
    required this.direction,
    required this.locale,
    required this.bold,
    required this.filterSnapshot,
    required this.count,
    required this.query,
    required this.leading,
    required this.recentKey,
    required this.extras,
    required this.quick,
    required this.applied,
    required this.hasSearch,
    required this.hasBulk,
    required this.geometry,
    required this.funnelFocus,
    required this.searchFocus,
    required this.titleFocus,
  }) : _filterRow = _FilterRow(
         key: bandKey,
         applied: applied,
         quick: quick,
         query: query,
         plan: plan,
         enabled: header.filtersEnabled,
         add: header.onFilterTap,
         bulk: hasBulk ? header.onClearAllFilters : null,
         bulkLabel: header.clearAllLabel,
         funnelFocus: funnelFocus,
       );

  final DocTypeListHeader header;
  final ThemeData theme;
  final TextScaler textScaler;
  final TextScaler bottomScaler;
  final PreferredSizeWidget? bottom;
  final GlobalKey? bottomKey;
  final GlobalKey toolbarKey;
  final GlobalKey rowsKey;
  final HeaderBandPlan plan;
  final TextDirection direction;
  final Locale? locale;
  final bool bold;
  final Object? filterSnapshot;
  final int count;
  final String query;
  final _LeadingAction? leading;
  final String? recentKey;
  final List<Widget> extras;
  final List<Widget> quick;
  final List<Widget> applied;
  final bool hasSearch;
  final bool hasBulk;
  final _HeaderGeometry geometry;
  final FocusNode funnelFocus;
  final FocusNode searchFocus;
  final FocusNode titleFocus;
  final _FilterRow _filterRow;

  @override
  double get minExtent =>
      math.min(geometry.fixedExtent + geometry.compact, geometry.extentLimit);

  @override
  double get maxExtent {
    final extent = geometry.fixedExtent + geometry.expanded;
    return geometry.capExpanded
        ? math.min(extent, geometry.extentLimit)
        : extent;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final g = geometry;
    final travel = g.expanded - g.compact;
    final offset = shrinkOffset.clamp(0.0, travel);
    final band = g.expanded - offset;
    final large = travel > 0 && offset < travel / 2 && band >= g.largeTitle;
    final surface = context.scheme.fg;
    final lightSurface = surface.computeLuminance() > 0.5;
    final measuredBottom = bottomKey != null;
    // The stateful bottom can attach after the band when it moves between
    // slivers. Keep traversal in the header's visual order.
    Widget inOrder(double order, Widget child) => measuredBottom
        ? FocusTraversalOrder(order: NumericFocusOrder(order), child: child)
        : child;

    // Keep the toolbar and rows mounted when changing sliver or scroll layout.
    final toolbar = KeyedSubtree(
      key: toolbarKey,
      child: inOrder(1, _toolbar(context, showTitle: !large && g.compact == 0)),
    );
    final rows = Column(
      key: rowsKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bottom case final bottom?)
          inOrder(
            2,
            SizedBox(
              height: g.bottom,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: bottomScaler),
                child: KeyedSubtree(key: bottomKey, child: bottom),
              ),
            ),
          ),
        inOrder(3, _filterRow),
      ],
    );
    final scrollRows = g.capExpanded && !g.canPin;
    final status = scrollRows
        ? math.min(g.status, g.extentLimit / 2)
        : g.status;
    final controlsSpace = g.extentLimit - status;
    final rowsSpace = controlsSpace - g.toolbar;
    final scrollToolbar =
        scrollRows && rowsSpace < math.min(_target, g.bottom + g.row);
    Widget scrollControls(double height, Widget child) => SizedBox(
      height: height,
      child: SingleChildScrollView(primary: false, child: child),
    );

    final contents = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: lightSurface
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: lightSurface ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: lightSurface
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Material(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: overlapsContent ? 1 : 0,
        child: FocusTraversalGroup(
          policy: measuredBottom
              ? OrderedTraversalPolicy(secondary: WidgetOrderTraversalPolicy())
              : WidgetOrderTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: status),
              SizedBox(
                height: band,
                child: large || g.compact > 0
                    ? Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          16,
                          0,
                          16,
                          large ? 8 : 0,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.bottomStart,
                          child: _heading(
                            large ? g.largeStyle : g.compactStyle,
                          ),
                        ),
                      )
                    : null,
              ),
              if (scrollToolbar)
                scrollControls(
                  controlsSpace,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [toolbar, rows],
                  ),
                )
              else ...[
                toolbar,
                if (scrollRows) scrollControls(rowsSpace, rows) else rows,
              ],
            ],
          ),
        ),
      ),
    );
    // Report headers keep their sliver scroll extent for sticky row alignment.
    final body = !g.capExpanded && !g.canPin
        ? ClipRect(
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: g.fixedExtent + band,
              maxHeight: g.fixedExtent + band,
              child: contents,
            ),
          )
        : contents;
    return header.sliverKey == null
        ? body
        : SizeChangedLayoutNotifier(child: body);
  }

  Widget _heading(TextStyle style) => Semantics(
    header: true,
    child: Text(
      header.title,
      style: style,
      softWrap: true,
      overflow: TextOverflow.visible,
    ),
  );

  Widget _toolbar(BuildContext context, {required bool showTitle}) {
    final g = geometry;
    final menuActions = [
      if (g.overflow) ...extras,
      if (g.overflowFunnel) _funnel(context),
      if (g.overflowSearch) _search(context),
    ];
    final actions = [
      if (!g.overflow) ...extras,
      if (menuActions.isNotEmpty) _MoreActions(actions: menuActions),
      if (header.onFilterTap != null && !g.overflowFunnel) _funnel(context),
      if (hasSearch && !g.overflowSearch) _search(context),
    ];
    final leading = _leading(context);
    return SizedBox(
      height: g.toolbar,
      child: HeaderActionTheme(
        child: NavigationToolbar(
          leading: leading == null
              ? null
              : Center(widthFactor: 1, child: leading),
          middle: showTitle
              ? g.disclose
                    ? _titleDisclosure(context)
                    : _heading(g.compactStyle)
              : null,
          trailing: actions.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions),
          centerMiddle: false,
          middleSpacing: showTitle && g.disclose
              ? g.middleSpacing
              : _middleSpacing,
        ),
      ),
    );
  }

  Widget? _leading(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    return switch (leading) {
      _LeadingAction.menu => HeaderIconAction(
        tooltip: l10n.openAppDrawerTooltip,
        onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
        child: const Icon(Icons.menu),
      ),
      _LeadingAction.back => HeaderIconAction(
        tooltip: l10n.backButtonTooltip,
        onPressed: () => Navigator.maybeOf(context)?.maybePop(),
        child: const BackButtonIcon(),
      ),
      null => null,
    };
  }

  Widget _titleDisclosure(BuildContext context) => Tooltip(
    message: 'Show full title',
    excludeFromSemantics: true,
    child: TextButton(
      focusNode: titleFocus,
      style:
          headerActionButtonStyle(
            context,
            foregroundColor: HeaderPalette.of(context).ink,
          ).copyWith(
            fixedSize: const WidgetStatePropertyAll(Size.square(_target)),
            backgroundBuilder: (context, states, child) =>
                HeaderActionContour(states: states, child: child!),
          ),
      onPressed: () async {
        final route = ModalRoute.of(context);
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: ListHeaderTextScope(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Builder(
                      builder: (context) => _heading(_largeTitleStyle(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        if (context.mounted &&
            (route?.isCurrent ?? true) &&
            FocusScope.of(context).traversalDescendants.contains(titleFocus)) {
          titleFocus.requestFocus();
        }
      },
      child: Semantics(
        header: true,
        label: header.title,
        hint: 'Show full title',
        child: const ExcludeSemantics(child: Icon(Icons.title)),
      ),
    ),
  );

  Widget _funnel(BuildContext context) {
    final g = geometry;
    final palette = HeaderPalette.of(context);
    final colors = theme.colorScheme;
    final active = count > 0;
    final enabled = header.filtersEnabled;
    final alignment = g.separateBadge
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.center;

    return HeaderIconAction(
      key: const ValueKey<String>('list-header-filter-slot'),
      tooltip: active ? 'Filters, $count active' : 'Filters',
      onPressed: enabled ? header.onFilterTap : null,
      focusNode: funnelFocus,
      width: g.funnel.width,
      height: g.funnel.height,
      discAlignment: alignment,
      backgroundColor: active && enabled ? colors.primary : null,
      foregroundColor: active && enabled ? colors.onPrimary : palette.ink,
      disabledFilter: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: alignment,
            child: SizedBox(
              width: 40,
              child: Icon(active ? Icons.filter_alt : Icons.filter_list),
            ),
          ),
          if (active)
            PositionedDirectional(
              end: 2,
              top: 2,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CountBadge(
                    count: count,
                    toolbar: true,
                    toolbarBounds: g.badge,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _search(BuildContext context) {
    final doctype = header.searchDoctype;
    final label = doctype == null || doctype.isEmpty
        ? 'Search'
        : 'Search $doctype';
    return HeaderIconAction(
      tooltip: query.isEmpty ? label : '$label, current query: $query',
      focusNode: searchFocus,
      onPressed: () => showListSearch(
        context,
        query: query,
        doctype: doctype ?? '',
        targetRoute: header.searchRoute ?? '',
        recentSearchKey: recentKey,
        onSearchChanged: header.onSearchChanged,
        onSearchClear: header.onSearchClear,
        onImageScanResult: header.onImageScanResult,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(child: Icon(Icons.search)),
          if (query.isNotEmpty)
            PositionedDirectional(
              top: 6,
              end: 6,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    key: const ValueKey<String>('list-header-search-dot'),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ListHeaderDelegate old) {
    const widgetEquality = ListEquality<Widget>();
    return geometry != old.geometry ||
        !const ListEquality<HeaderBandSlot>().equals(
          plan.slots,
          old.plan.slots,
        ) ||
        theme != old.theme ||
        textScaler != old.textScaler ||
        bottomScaler != old.bottomScaler ||
        direction != old.direction ||
        locale != old.locale ||
        bold != old.bold ||
        leading != old.leading ||
        count != old.count ||
        !const DeepCollectionEquality().equals(
          filterSnapshot,
          old.filterSnapshot,
        ) ||
        query != old.query ||
        recentKey != old.recentKey ||
        hasSearch != old.hasSearch ||
        hasBulk != old.hasBulk ||
        !widgetEquality.equals(applied, old.applied) ||
        !widgetEquality.equals(quick, old.quick) ||
        !widgetEquality.equals(extras, old.extras) ||
        header.title != old.header.title ||
        header.extraActionsKey != old.header.extraActionsKey ||
        header.quickChipsKey != old.header.quickChipsKey ||
        header.searchDoctype != old.header.searchDoctype ||
        header.searchRoute != old.header.searchRoute ||
        !identical(header.searchQuery, old.header.searchQuery) ||
        header.onSearchChanged != old.header.onSearchChanged ||
        header.onSearchClear != old.header.onSearchClear ||
        header.onImageScanResult != old.header.onImageScanResult ||
        header.onFilterTap != old.header.onFilterTap ||
        header.onClearAllFilters != old.header.onClearAllFilters ||
        header.filtersEnabled != old.header.filtersEnabled ||
        header.clearAllLabel != old.header.clearAllLabel ||
        bottom != old.bottom;
  }
}

class _MoreActions extends StatefulWidget {
  const _MoreActions({required this.actions});

  final List<Widget> actions;

  @override
  State<_MoreActions> createState() => _MoreActionsState();
}

class _MoreActionsState extends State<_MoreActions> {
  final _menu = MenuController();
  final _trigger = FocusNode(debugLabel: 'More actions');
  final _contents = FocusScopeNode(debugLabel: 'More actions menu');
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (ModalRoute.isCurrentOf(context) == false && _menu.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu.isOpen && _route?.isCurrent == false) {
          _menu.close();
        }
      });
    }
  }

  @override
  void dispose() {
    _trigger.dispose();
    _contents.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menu,
    childFocusNode: _trigger,
    style: MenuStyle(
      alignment: AlignmentDirectional.bottomEnd,
      backgroundColor: WidgetStatePropertyAll(context.scheme.fg),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    onOpen: () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu.isOpen && (_route?.isCurrent ?? true)) {
          _contents.traversalDescendants.firstOrNull?.requestFocus();
        }
      });
    },
    onClose: () {
      if (mounted && (_route?.isCurrent ?? true)) _trigger.requestFocus();
    },
    menuChildren: [
      ListHeaderTextScope(
        child: HeaderActionTheme(
          child: Semantics(
            label: 'More actions',
            container: true,
            explicitChildNodes: true,
            child: FocusScope(
              node: _contents,
              skipTraversal: true,
              includeSemantics: false,
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: Wrap(children: widget.actions),
              ),
            ),
          ),
        ),
      ),
    ],
    builder: (context, controller, child) => HeaderIconAction(
      tooltip: 'More actions',
      focusNode: _trigger,
      onPressed: () {
        if (controller.isOpen) {
          controller.close();
        } else {
          controller.open();
        }
      },
      child: const Icon(Icons.more_horiz),
    ),
  );
}

class _FilterRow extends StatefulWidget {
  const _FilterRow({
    super.key,
    required this.applied,
    required this.quick,
    required this.query,
    required this.plan,
    required this.enabled,
    required this.add,
    required this.bulk,
    required this.bulkLabel,
    required this.funnelFocus,
  });

  final List<Widget> applied;
  final List<Widget> quick;
  final String query;
  final HeaderBandPlan plan;
  final bool enabled;
  final VoidCallback? add;
  final VoidCallback? bulk;
  final String bulkLabel;
  final FocusNode funnelFocus;

  @override
  State<_FilterRow> createState() => _FilterRowState();
}

typedef _ChipIdentity = ({Object signature, int occurrence});

enum _ChipRole { search }

class _ChipFocus {
  FocusNode? _edit;
  FocusNode? _reset;

  FocusNode edit(FilterChipWidget chip) =>
      chip.editFocusNode ??
      (_edit ??= FocusNode(debugLabel: 'Edit ${chip.label}'));

  FocusNode reset(FilterChipWidget chip) =>
      chip.resetFocusNode ??
      (_reset ??= FocusNode(debugLabel: 'Reset ${chip.label}'));

  void dispose() {
    _edit?.dispose();
    _reset?.dispose();
  }
}

class _FilterRowState extends State<_FilterRow> {
  final _addFocus = FocusNode(debugLabel: 'Add filter');
  final _bulkFocus = FocusNode(debugLabel: 'Reset filters');
  final _nodes = <_ChipIdentity, _ChipFocus>{};
  final _retired = <_ChipFocus>{};
  late Map<_ChipIdentity, FilterChipWidget> _chips;
  ({_ChipIdentity? chip, FocusNode focus, ModalRoute<dynamic>? route})?
  _pending;

  @override
  void initState() {
    super.initState();
    _chips = _identify();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _traversal.dispose();
    _addFocus.dispose();
    _bulkFocus.dispose();
    for (final nodes in [..._nodes.values, ..._retired]) {
      nodes.dispose();
    }
    _retired.clear();
    super.dispose();
  }

  Map<_ChipIdentity, FilterChipWidget> _identify({
    List<_ChipIdentity> previous = const [],
  }) {
    final chips = widget.applied.whereType<FilterChipWidget>().toList();
    Object signature(FilterChipWidget chip) =>
        chip.key ??
        (widget.query.isNotEmpty &&
                chip.icon == Icons.search &&
                chip.label == 'Search: ${widget.query}'
            ? _ChipRole.search
            : (chip.label, chip.icon));
    final oldGroups = groupBy(previous, (id) => id.signature);
    final newGroups = groupBy(chips, signature);
    final removed = _pending?.chip;
    final available = <Object, Iterator<_ChipIdentity>>{};
    final nextOccurrence = <Object, int>{};
    for (final entry in oldGroups.entries) {
      final prior = entry.value;
      final fewer = (newGroups[entry.key]?.length ?? 0) < prior.length;
      available[entry.key] = prior
          .where((id) => !(fewer && id == removed))
          .iterator;
      nextOccurrence[entry.key] =
          prior.map((id) => id.occurrence).reduce(math.max) + 1;
    }
    return {
      for (final chip in chips)
        if (available[signature(chip)] case final ids? when ids.moveNext())
          ids.current: chip
        else
          (
            signature: signature(chip),
            occurrence:
                nextOccurrence.update(
                  signature(chip),
                  (next) => next + 1,
                  ifAbsent: () => 1,
                ) -
                1,
          ): chip,
    };
  }

  @override
  void didUpdateWidget(covariant _FilterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _pending;
    if (pending != null &&
        (!widget.enabled ||
            !pending.focus.hasFocus ||
            pending.route?.isCurrent == false)) {
      _pending = null;
    }
    final old = _chips.keys.toList();
    _chips = _identify(previous: old);
    final removed = old.where((id) => !_chips.containsKey(id)).toList();
    final committed = _pending;
    if (committed != null &&
        (committed.chip == null
            ? widget.bulk == null
            : removed.contains(committed.chip))) {
      _scheduleRecovery(old, committed.chip, committed.route);
      _pending = null;
    }
    for (final id in removed) {
      final nodes = _nodes.remove(id);
      if (nodes == null) continue;
      _retired.add(nodes);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_retired.remove(nodes)) nodes.dispose();
      });
    }
  }

  void _focusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    final pending = _pending;
    if (pending != null && focus != pending.focus) {
      _pending = null;
    }
    if (focus == null ||
        focus.context?.findAncestorStateOfType<_FilterRowState>() != this) {
      return;
    }
    revealHeaderBandFocus(context, focus);
  }

  void _beforeReset(_ChipIdentity? id, FocusNode focus) {
    if (FocusManager.instance.primaryFocus == focus) {
      _pending = (chip: id, focus: focus, route: ModalRoute.of(context));
    }
  }

  FocusNode? _focusFor(_ChipIdentity id, {bool preferReset = false}) {
    final chip = _chips[id];
    final nodes = _nodes[id];
    if (chip == null || nodes == null || !chip.enabled) return null;
    if (preferReset || chip.onTap == null) return nodes.reset(chip);
    return nodes.edit(chip);
  }

  void _scheduleRecovery(
    List<_ChipIdentity> old,
    _ChipIdentity? removed,
    ModalRoute<dynamic>? route,
  ) {
    final index = removed == null ? -1 : old.indexOf(removed);
    final current = _chips.keys.toList();
    final added = current.where((id) => !old.contains(id)).toList();
    final replacement =
        index >= 0 &&
            old.length == current.length &&
            added.length == 1 &&
            current[index] == added.single
        ? added.single
        : null;
    final oldFocus = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || route?.isCurrent == false || !widget.enabled) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null &&
          primary is! FocusScopeNode &&
          primary != oldFocus) {
        return;
      }
      final scope = FocusScope.of(context);
      final traversable = scope.traversalDescendants.toSet();
      final candidate =
          [
            if (replacement != null) _focusFor(replacement, preferReset: true),
            if (index >= 0) ...old.skip(index + 1).map(_focusFor),
            if (widget.add != null) _addFocus,
            if (index >= 0)
              ...old.take(index).toList().reversed.map(_focusFor)
            else
              ...current.map(_focusFor),
            widget.funnelFocus,
          ].whereType<FocusNode>().where(traversable.contains).firstOrNull ??
          FocusTraversalGroup.of(
            context,
          ).findFirstFocus(scope, ignoreCurrentFocus: true);
      if (candidate == null || candidate is FocusScopeNode) return;
      candidate.requestFocus();
    });
  }

  Widget _focusSlot(_ChipIdentity id, FilterChipWidget chip) {
    final nodes = _nodes.putIfAbsent(id, _ChipFocus.new);
    final resetFocus = nodes.reset(chip);
    return KeyedSubtree(
      key: ValueKey(id),
      child: chip.withHeaderFocus(
        editFocusNode: nodes.edit(chip),
        resetFocusNode: resetFocus,
        onResetInvoked: () => _beforeReset(id, resetFocus),
      ),
    );
  }

  Widget _legacyChip(Widget chip, HeaderChipSize size) =>
      ListHeaderQuickChipTheme(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: _target,
              minHeight: size.height,
            ),
            child: chip,
          ),
        ),
      );

  Widget _bulkChip(HeaderChipSize size, VoidCallback bulk) {
    final palette = HeaderPalette.of(context);
    return HeaderChipButton(
      label: widget.bulkLabel,
      focusNode: _bulkFocus,
      onPressed: widget.enabled
          ? () {
              _beforeReset(null, _bulkFocus);
              bulk();
            }
          : null,
      width: size.width,
      height: size.height,
      paintedHeight: size.paintHeight,
      paint: HeaderChipPaint.bulk,
      bandBulkOutline: true,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.clear_all, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: HeaderBandCaption(
              widget.bulkLabel,
              size: size,
              color: widget.enabled ? palette.error : palette.muted,
            ),
          ),
        ],
      ),
    );
  }

  late final _traversal = HeaderBandTraversalPolicy(
    (node) => node.context?.findAncestorStateOfType<_FilterRowState>() == this,
  );

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    if (plan.height == 0) return const SizedBox.shrink();
    final ids = _chips.keys.iterator;
    final slots = <Widget>[];

    void addSlot(Object id, Widget Function(HeaderChipSize size) builder) {
      final index = slots.length;
      final slot = plan.slots[index];
      slots.add(
        Positioned(
          key: ValueKey(id),
          left: slot.x,
          top: slot.y,
          width: slot.size.width,
          height: slot.size.height,
          child: Semantics(
            container: true,
            sortKey: OrdinalSortKey(index.toDouble()),
            child: FocusTraversalOrder(
              order: NumericFocusOrder(2.0 * index),
              child: HeaderChipSizeScope(
                size: slot.size,
                child: builder(slot.size),
              ),
            ),
          ),
        ),
      );
    }

    if (widget.add case final add?) {
      addSlot(#add, (_) => AddFilterChip(onTap: add, focusNode: _addFocus));
    }
    for (final (i, chip) in widget.applied.indexed) {
      if (chip is FilterChipWidget) {
        ids.moveNext();
        final id = ids.current;
        addSlot(id, (_) => _focusSlot(id, chip));
      } else {
        addSlot((#applied, chip.key ?? i), (size) => _legacyChip(chip, size));
      }
    }
    for (final (i, chip) in widget.quick.indexed) {
      addSlot(
        (#quick, chip.key ?? i),
        (size) => chip is HeaderQuickChip || chip is MeasuredHeaderChip
            ? chip
            : _legacyChip(chip, size),
      );
    }
    if (widget.bulk case final bulk?) {
      addSlot(#bulk, (size) => _bulkChip(size, bulk));
    }
    return ListHeaderFilterScope(
      enabled: widget.enabled,
      child: FocusTraversalGroup(
        policy: _traversal,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: SizedBox(
            height: plan.height,
            child: Stack(
              key: const ValueKey('list-header-chip-band'),
              children: slots,
            ),
          ),
        ),
      ),
    );
  }
}
