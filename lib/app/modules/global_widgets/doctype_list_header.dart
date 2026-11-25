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
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';
import 'package:multimax/app/modules/global_widgets/recent_search_suggestions.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

const double _target = 48;
const double _expandedBand = 96;
const double _middleSpacing = 8;

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
  /// Active chips scroll horizontally. A bulk action is offered when more
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
    this.extraActionsKey,
  });

  @override
  State<DocTypeListHeader> createState() => _DocTypeListHeaderState();
}

enum _LeadingAction { menu, back }

class _DocTypeListHeaderState extends State<DocTypeListHeader> {
  final _funnelFocus = FocusNode(debugLabel: 'Filters');
  final _titleFocus = FocusNode(debugLabel: 'Show full title');

  @override
  void dispose() {
    _funnelFocus.dispose();
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
        final geometry = _HeaderGeometryCalculator.measure(
          context,
          viewport: viewport,
          title: header.title,
          hasLeading: leading != null,
          extraCount: extras.length,
          hasFunnel: hasAdd,
          hasSearch: hasSearch,
          badgeCount: filters.length,
          bottomHeight: _bottomHeight(context, header.bottom, bottomScaler),
          applied: applied,
          quick: quick,
          hasBulk: hasBulk,
          bulkLabel: header.clearAllLabel,
        );
        return sliver = SliverPersistentHeader(
          key: header.sliverKey,
          pinned: header.pinnedAppBar && geometry.canPin,
          floating: header.floatingAppBar,
          delegate: _ListHeaderDelegate(
            header: header,
            theme: theme,
            textScaler: textScaler,
            bottomScaler: bottomScaler,
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
  double bulkPaint,
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
  double minimumLimit,
  TextStyle largeStyle,
  TextStyle compactStyle,
});

extension on _HeaderGeometry {
  double get fixedExtent => status + toolbar + bottom + row;
  bool get canPin => fixedExtent <= minimumLimit;
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
    required List<Widget> applied,
    required List<Widget> quick,
    required bool hasBulk,
    required String bulkLabel,
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
    final labelStyle =
        theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14);
    final bulkPaint = hasBulk
        ? math.max(
            34.0,
            measureHeaderText(
                  context,
                  bulkLabel,
                  labelStyle,
                ).size.height.ceilToDouble() +
                2,
          )
        : 0.0;
    double row = 0;
    if (hasFunnel || hasBulk || applied.isNotEmpty || quick.isNotEmpty) {
      row = math.max(_target, bulkPaint);
      if (hasFunnel) {
        row = math.max(row, AddFilterChip.requiredHeight(context));
      }
      for (final chip in applied.whereType<FilterChipWidget>()) {
        row = math.max(row, chip.requiredHeight(context));
      }
      if (quick.isNotEmpty) {
        final line = measureHeaderText(context, 'Ag', labelStyle).size.height;
        row = math.max(row, line.ceilToDouble() + 16);
      }
    }

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
    final minimumLimit =
        viewport.height - math.min(_target, viewport.height / 2);
    final disclose =
        compact > 0 &&
        status + toolbar + bottomHeight + row + compact > minimumLimit;
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
    return (
      width: viewport.width,
      status: status,
      toolbar: toolbar,
      bottom: bottomHeight,
      row: row,
      bulkPaint: bulkPaint,
      largeTitle: largeTitle,
      expanded: math.max(_expandedBand, math.max(largeTitle, compact)),
      compact: compact,
      badge: size,
      funnel: funnel,
      separateBadge: separateBadge,
      overflow: overflow,
      overflowSearch: overflowSearch,
      overflowFunnel: overflowFunnel,
      middleSpacing: middleSpacing,
      disclose: disclose,
      minimumLimit: minimumLimit,
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
    required this.titleFocus,
  }) : _filterRow = _FilterRow(
         key: const ValueKey('list-header-filter-row'),
         applied: applied,
         quick: quick,
         query: query,
         height: geometry.row,
         bulkPaint: geometry.bulkPaint,
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
  final FocusNode titleFocus;
  final _FilterRow _filterRow;

  @override
  double get minExtent =>
      math.min(geometry.fixedExtent + geometry.compact, geometry.minimumLimit);

  @override
  double get maxExtent => geometry.fixedExtent + geometry.expanded;

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
          policy: WidgetOrderTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: g.status),
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
              _toolbar(context, showTitle: !large && g.compact == 0),
              if (header.bottom case final bottom?)
                SizedBox(
                  height: g.bottom,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: bottomScaler),
                    child: ListHeaderBottomScope(child: bottom),
                  ),
                ),
              _filterRow,
            ],
          ),
        ),
      ),
    );
    if (g.canPin) return contents;
    // If even the controls cannot fit while pinned, let them scroll away.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.bottomCenter,
        minHeight: g.fixedExtent + band,
        maxHeight: g.fixedExtent + band,
        child: contents,
      ),
    );
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
        header.bottom != old.header.bottom;
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
    required this.height,
    required this.bulkPaint,
    required this.enabled,
    required this.add,
    required this.bulk,
    required this.bulkLabel,
    required this.funnelFocus,
  });

  final List<Widget> applied;
  final List<Widget> quick;
  final String query;
  final double height;
  final double bulkPaint;
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
    final pending = _pending;
    if (pending != null &&
        FocusManager.instance.primaryFocus != pending.focus) {
      _pending = null;
    }
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
      final focusContext = candidate.context;
      if (focusContext == null) return;
      final scroll = Scrollable.maybeOf(focusContext, axis: Axis.horizontal);
      final render = focusContext.findRenderObject();
      if (scroll != null && render != null && render.attached) {
        scroll.position.ensureVisible(
          render,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        scroll.position.ensureVisible(
          render,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  List<Widget> _appliedSlots() {
    final ids = _chips.keys.iterator;
    return [
      for (final chip in widget.applied)
        if (chip is FilterChipWidget && ids.moveNext())
          _focusSlot(ids.current, chip)
        else
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: chip,
          ),
    ];
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

  @override
  Widget build(BuildContext context) {
    if (widget.height == 0) return const SizedBox.shrink();
    return ListHeaderFilterScope(
      enabled: widget.enabled,
      child: SizedBox(
        height: widget.height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._appliedSlots(),
              if (widget.add case final add?)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: AddFilterChip(onTap: add, focusNode: _addFocus),
                ),
              if (widget.bulk case final bulk?)
                HeaderChipButton(
                  label: widget.bulkLabel,
                  focusNode: _bulkFocus,
                  onPressed: widget.enabled
                      ? () {
                          _beforeReset(null, _bulkFocus);
                          bulk();
                        }
                      : null,
                  paintedHeight: widget.bulkPaint,
                  paint: HeaderChipPaint.bulk,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.clear_all, size: 16),
                      const SizedBox(width: 8),
                      Text(widget.bulkLabel),
                    ],
                  ),
                ),
              if (widget.quick.isNotEmpty &&
                  (widget.add != null || widget.applied.isNotEmpty))
                ExcludeSemantics(
                  child: Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsetsDirectional.only(start: 2, end: 8),
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              for (final chip in widget.quick)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ListHeaderQuickChipTheme(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: _target,
                        minHeight: widget.height,
                        maxHeight: widget.height,
                      ),
                      child: chip,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
