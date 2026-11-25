import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/header_chip_band.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_owner_overlay.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_logic.dart';

typedef _OccurrenceId = (VariantGroup, String, int);
typedef _TrackOccurrence = Widget Function(VariantGroup, String, int, Widget);

class _VariantHeaderKey extends GlobalObjectKey {
  const _VariantHeaderKey(super.value);
}

class ItemVariantDetailsScreen extends GetView<ItemVariantDetailsController> {
  const ItemVariantDetailsScreen({super.key});

  static const _headingExtent = 52.0;
  static bool _wrapHeading(BuildContext context, String stockLabel) =>
      MediaQuery.textScalerOf(context).scale(12) > 12 ||
      stockLabel.runes.length > 22;

  static double _groupHeadingExtent(BuildContext context, String stockLabel) {
    if (!_wrapHeading(context, stockLabel)) return _headingExtent;
    final scale = MediaQuery.textScalerOf(context);
    final text = Theme.of(context).textTheme;
    double lineHeight(TextStyle? style, double fallback) =>
        scale.scale(style?.fontSize ?? fallback) * (style?.height ?? 1.3);
    final title = lineHeight(text.titleMedium, 16);
    final summary = lineHeight(text.bodySmall, 12);
    return (2 * title + 2 * summary + 12).ceilToDouble();
  }

  // Native groups measure one child per delegate, even when offscreen.
  static const _maxNativeGroups = 24;

  static const filterFields = [
    ReportFilterField(
      key: 'item',
      label: 'Items',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item',
      prefixIcon: Icons.category_outlined,
      linkFilters: {'has_variants': 1},
    ),
    ReportFilterField(
      key: 'item_group',
      label: 'Item Groups',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item Group',
      prefixIcon: Icons.account_tree_outlined,
    ),
    ReportFilterField(
      key: 'warehouse',
      label: 'Warehouses',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Warehouse',
      prefixIcon: Icons.warehouse_outlined,
    ),
  ];

  List<Widget> _buildFilterChips(BuildContext context) {
    if (controller.isLoading.value) return [];
    return [
      for (final entry in controller.activeFilters.entries)
        FilterChipWidget(
          key: ValueKey(entry.key),
          icon: Icons.filter_alt_outlined,
          label: entry.value,
          onDeleted: () => controller.clearFilter(entry.key),
          onTap: () => _openFilters(context, focusKey: entry.key),
        ),
    ];
  }

  void _openFilters(BuildContext context, {String? focusKey}) {
    if (controller.isLoading.value) return;
    showReportFilterSheet(
      context: context,
      focusKey: focusKey,
      title: 'Item Variant Details Filters',
      fields: filterFields,
      controllers: controller.filterControllers,
      onRun: controller.runReport,
      onClear: controller.clearFilters,
      validate: controller.validateFilters,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return AppShellScaffold(
      body: Obx(() {
        final busy = controller.isLoading.value;
        final data = controller.results.value;
        final query = controller.query.value;
        final stock = controller.inStock.value;
        final stockCaption = switch (controller.warehouseCount) {
          0 => 'In stock',
          1 => 'In stock in 1 warehouse',
          final count => 'In stock in $count warehouses',
        };
        final groups = controller.visibleGroups(data, query, stock);
        final shown = groups.expand((match) => match.variants).toList();
        final grouped = (data?.templateCount ?? 0) > 0;
        final collapsed =
            grouped &&
            groups.every(
              (match) =>
                  match.group.heading != null &&
                  (!data!.isExpanded(match.group) || match.variants.isEmpty),
            );
        final rowCount = controller.reportData.length;
        final draggable = canDragVariantScrollbar(
          rowCount,
          collapsed: collapsed,
        );
        final filtered = query.isNotEmpty || stock;
        final footerStyle = Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
        if (query.isNotEmpty) controller.queueMatchedDetails(shown);
        final lazyGroups =
            grouped && !collapsed && groups.length > _maxNativeGroups;
        final headingExtent = _groupHeadingExtent(context, _currentStockLabel);
        final occurrenceIds = <_OccurrenceId>[
          for (final match in groups) ...[
            if (match.group.heading != null) (match.group, 'title', 0),
            if (data!.isExpanded(match.group) && match.variants.isNotEmpty) ...[
              if (match.group.heading != null) (match.group, 'subtotal', 0),
              for (var index = 0; index < match.variants.length; index++)
                (match.group, 'variant', index),
            ],
          ],
        ];
        final occurrenceIndices = {
          for (final (index, id) in occurrenceIds.indexed) id: index,
        };
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: ReportFieldsResults(
            controller: controller.fields,
            scrollController: controller.scrollController,
            result: (
              data,
              query,
              stock,
              controller.viewRevision.value,
              query.isEmpty ? 0 : controller.searchRevision.value,
            ),
            occurrenceIds: occurrenceIds,
            fallbacks: (id) => id is _OccurrenceId && id.$2 != 'title'
                ? [(id.$1, 'title', 0)]
                : const [],
            interactive: draggable,
            thumbVisibility: !busy && rowCount > 0,
            builder: (context, anchors) {
              Widget track(
                VariantGroup group,
                String type,
                int index,
                Widget child,
              ) {
                final id = (group, type, index);
                return anchors.row(id, occurrenceIndices[id]!, child);
              }

              final results = CustomScrollView(
                controller: controller.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  anchors.header(
                    DocTypeListHeader(
                      sliverKey: _VariantHeaderKey(controller),
                      title: 'Item Variant Details',
                      automaticallyImplyLeading: false,
                      activeFilters: controller.activeFilters,
                      onFilterTap: busy ? null : () => _openFilters(context),
                      filterChipsBuilder: _buildFilterChips,
                      onClearAllFilters: controller.clearFilters,
                      extraActions: [
                        ReportFieldsAction(controller: controller.fields),
                      ],
                      quickChips: [
                        if (data != null)
                          HeaderQuickChip(
                            key: const ValueKey('variant-in-stock'),
                            role: HeaderQuickRole.toggle,
                            active: stock,
                            onPressed: () => controller.setInStock(!stock),
                            caption: stockCaption,
                            label: stockCaption,
                          ),
                      ],
                    ),
                  ),
                  if (!busy)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data != null) ...[
                              Text(
                                [
                                  if (grouped)
                                    '${data.templateCount} templates',
                                  if (query.isNotEmpty || stock)
                                    '${shown.length} of ${data.variants.length} variants'
                                  else
                                    '${data.variants.length} variants',
                                ].join(' · '),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: controller.searchController,
                                onChanged: controller.search,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  labelText: 'Search loaded results',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: query.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'Clear search',
                                          onPressed: () {
                                            controller.searchController.clear();
                                            controller.search('');
                                          },
                                          icon: const Icon(Icons.clear),
                                        )
                                      : null,
                                ),
                              ),
                              Obx(() {
                                final progress = controller.nameProgress.value;
                                if (query.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                if (progress != null) {
                                  return Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      'Searching names… ${progress.done} / ${progress.total}',
                                    ),
                                  );
                                }
                                if (controller.nameSearchIncomplete.value) {
                                  return Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Some item names could not be loaded.',
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: controller.retrySearchNames,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  );
                                }
                                return const SizedBox.shrink();
                              }),
                              if (grouped)
                                Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          controller.setAllExpanded(false),
                                      child: const Text('Collapse All'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          controller.setAllExpanded(true),
                                      child: const Text('Expand All'),
                                    ),
                                  ],
                                ),
                              if (!draggable)
                                Text(
                                  grouped
                                      ? 'Collapse groups to drag the scrollbar'
                                      : 'Swipe the list to scroll long results',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  if (busy)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (controller.reportData.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.style_outlined,
                                size: 64,
                                color: cs.outlineVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                controller.reportError.value ??
                                    (controller.hasRun.value
                                        ? 'No variants match these filters.'
                                        : 'Select Items or Item Groups, then run the report.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.tonalIcon(
                                onPressed: () => _openFilters(context),
                                icon: const Icon(Icons.filter_alt_outlined),
                                label: const Text('Set Filters'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (data != null) ...[
                    if (lazyGroups)
                      _lazyGroupSliver(
                        data,
                        groups,
                        filtered,
                        track,
                        headingExtent,
                      )
                    else
                      ..._resultSlivers(
                        data,
                        groups,
                        filtered,
                        cs,
                        track,
                        anchors.topObstruction,
                        headingExtent,
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          16,
                          12,
                          80 + bottomPadding,
                        ),
                        child: shown.isEmpty
                            ? Obx(() {
                                if (controller.nameProgress.value != null ||
                                    (query.isNotEmpty &&
                                        controller
                                            .nameSearchIncomplete
                                            .value)) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  'No variants match.',
                                  textAlign: TextAlign.center,
                                  style: footerStyle,
                                );
                              })
                            : Text(
                                [
                                  'End of list',
                                  'Quantity totals for shown results',
                                  ...variantQuantitySummary(
                                    shown,
                                    controller.reportColumns,
                                  ),
                                ].join('\n'),
                                textAlign: TextAlign.center,
                                style: footerStyle,
                              ),
                      ),
                    ),
                  ],
                ],
              );
              return Stack(
                children: [
                  results,
                  if (lazyGroups)
                    ValueListenableBuilder(
                      valueListenable: controller.stickyHeading,
                      builder: (context, sticky, _) {
                        if (sticky == null || !data!.isExpanded(sticky.group)) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: sticky.headerBottom,
                          left: 12,
                          right: 12,
                          height: headingExtent,
                          child: ClipRect(
                            child: Transform.translate(
                              offset: Offset(0, sticky.offset),
                              child: anchors.topObstruction(
                                _groupTitle(sticky.group),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        );
      }),
    );
  }

  static final _pendingAnchors = Expando<bool>();

  static void _preserveVariantAnchor(
    BuildContext context,
    ItemVariantDetailsController controller,
  ) {
    final scroll = controller.scrollController;
    if (!scroll.hasClients) return;
    final position = scroll.position;
    if (_pendingAnchors[position] == true) return;
    final pixels = position.pixels;
    _RenderVisibleVariant? anchor;
    double originalOffset = 0;
    final headerKey = _VariantHeaderKey(controller);

    void findAnchor(Element element) {
      if (anchor != null) return;
      if (element.widget is _VisibleVariant) {
        final box = element.renderObject! as _RenderVisibleVariant;
        final viewport = RenderAbstractViewport.maybeOf(box);
        if (box.hasSize && viewport != null) {
          final toolbarExtent = DocTypeListHeader.extentInViewport(
            headerKey,
            viewport,
          );
          if (toolbarExtent == null) return;
          final offset = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
          if (offset + box.size.height >
                  toolbarExtent.clamp(0.0, double.infinity) &&
              offset < position.viewportDimension) {
            anchor = box;
            originalOffset = offset;
          }
        }
        return;
      }
      element.visitChildren(findAnchor);
    }

    // Async tile updates read the previous layout during the build phase.
    (context as Element).visitChildren(findAnchor);
    final box = anchor;
    if (box == null) return;
    _pendingAnchors[position] = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingAnchors[position] = null;
      if (!context.mounted ||
          !box.attached ||
          !scroll.hasClients ||
          scroll.position != position ||
          position.pixels != pixels) {
        return;
      }
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final offset = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final target = (pixels + offset - originalOffset).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != pixels) scroll.jumpTo(target);
    });
  }

  Widget _groupTitle(VariantGroup group) => _GroupTitle(
    group: group,
    expanded: true,
    summary: group.variantCountLabel,
    currentStockLabel: _currentStockLabel,
    onTap: () => controller.toggleGroup(group),
  );

  Widget _collapsedTitle(
    VariantGroup group,
    int shown,
    bool filtered,
    double minHeight,
  ) {
    final summary = group.collapsedSummary(
      shown,
      filtered: filtered,
      currentStockLabel: _currentStockLabel,
    );
    return Obx(() {
      final cached = controller.detailsFor(group.code).value;
      final name = (group.heading?['item_name'] ?? cached?['item_name'])
          ?.toString()
          .trim();
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: _GroupTitle(
          group: group,
          expanded: false,
          name: name,
          summary: summary,
          currentStockLabel: _currentStockLabel,
          onTap: () => controller.toggleGroup(group),
        ),
      );
    });
  }

  String get _currentStockLabel =>
      variantColumnLabel(controller.reportColumns, 'current_stock')!;

  Widget _lazyGroupSliver(
    VariantResults data,
    List<({VariantGroup group, List<VariantRow> variants})> groups,
    bool filtered,
    _TrackOccurrence track,
    double headingExtent,
  ) {
    final entries =
        <({VariantGroup group, VariantRow? row, bool title, int index})>[];
    final counts = {
      for (final match in groups) match.group: match.variants.length,
    };
    for (final match in groups) {
      final group = match.group;
      final heading = group.heading;
      if (heading != null) {
        entries.add((group: group, row: null, title: true, index: 0));
      }
      if (!data.isExpanded(group) || match.variants.isEmpty) continue;
      if (heading != null) {
        entries.add((group: group, row: null, title: false, index: 0));
      }
      entries.addAll(
        match.variants.indexed.map(
          ((int, VariantRow) entry) =>
              (group: group, row: entry.$2, title: false, index: entry.$1),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: _StickyGroupList(
        sticky: controller.stickyHeading,
        headingExtent: headingExtent,
        headerKey: _VariantHeaderKey(controller),
        groupAt: (index) {
          final entry = entries[index];
          return (
            group: entry.group,
            title: entry.title,
            expanded:
                entry.group.heading != null && data.isExpanded(entry.group),
          );
        },
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = entries[index];
          if (entry.title) {
            final expanded =
                data.isExpanded(entry.group) && counts[entry.group]! > 0;
            return track(
              entry.group,
              'title',
              0,
              expanded
                  ? SizedBox(
                      height: headingExtent,
                      child: _groupTitle(entry.group),
                    )
                  : _collapsedTitle(
                      entry.group,
                      counts[entry.group]!,
                      filtered,
                      headingExtent,
                    ),
            );
          }
          final row = entry.row;
          if (row == null) {
            return track(
              entry.group,
              'subtotal',
              0,
              _GroupBody(
                child: _TemplateHeader(
                  row: entry.group.heading!,
                  columns: controller.reportColumns,
                ),
              ),
            );
          }
          final templateCode = entry.group.heading == null
              ? null
              : entry.group.code;
          final tile = track(
            entry.group,
            'variant',
            entry.index,
            _variantTile(row, templateCode),
          );
          if (templateCode == null) return tile;
          return _GroupBody(
            last:
                index + 1 == entries.length ||
                entries[index + 1].group != entry.group,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: tile,
            ),
          );
        }, childCount: entries.length),
      ),
    );
  }

  List<Widget> _resultSlivers(
    VariantResults data,
    List<({VariantGroup group, List<VariantRow> variants})> groups,
    bool filtered,
    ColorScheme scheme,
    _TrackOccurrence track,
    Widget Function(Widget) topObstruction,
    double headingExtent,
  ) {
    final slivers = <Widget>[];
    final columns = controller.reportColumns;
    Widget variants(
      VariantGroup group,
      List<VariantRow> rows,
      String? templateCode,
    ) => SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => track(
        group,
        'variant',
        index,
        _variantTile(rows[index], templateCode),
      ),
    );
    Widget inset(Widget sliver, VariantGroup group) => SliverPadding(
      key: ObjectKey(group),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: sliver,
    );
    var collapsed = <({VariantGroup group, List<VariantRow> variants})>[];
    void flushCollapsed() {
      if (collapsed.isEmpty) return;
      final run = collapsed;
      collapsed = [];
      slivers.add(
        inset(
          SliverList.builder(
            itemCount: run.length,
            itemBuilder: (context, index) => track(
              run[index].group,
              'title',
              0,
              _collapsedTitle(
                run[index].group,
                run[index].variants.length,
                filtered,
                headingExtent,
              ),
            ),
          ),
          run.first.group,
        ),
      );
    }

    for (final match in groups) {
      final group = match.group;
      final heading = group.heading;
      if (heading != null &&
          (!data.isExpanded(group) || match.variants.isEmpty)) {
        collapsed.add(match);
        continue;
      }
      flushCollapsed();
      if (heading == null) {
        slivers.add(inset(variants(group, match.variants, null), group));
      } else {
        final title = topObstruction(
          track(
            group,
            'title',
            0,
            SizedBox(height: headingExtent, child: _groupTitle(group)),
          ),
        );
        slivers.add(
          inset(
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 8),
              sliver: DecoratedSliver(
                decoration: _groupDecoration(scheme, top: true, bottom: true),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final available =
                            constraints.remainingPaintExtent -
                            constraints.overlap;
                        return available >= headingExtent + kMinInteractiveDimension
                            ? PinnedHeaderSliver(child: title)
                            : SliverToBoxAdapter(child: title);
                      },
                    ),
                    SliverToBoxAdapter(
                      child: track(
                        group,
                        'subtotal',
                        0,
                        _TemplateHeader(row: heading, columns: columns),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      sliver: variants(group, match.variants, group.code),
                    ),
                  ],
                ),
              ),
            ),
            group,
          ),
        );
      }
    }
    flushCollapsed();
    return slivers;
  }

  Widget _variantTile(VariantRow row, String? templateCode) => Padding(
    padding: templateCode == null
        ? const EdgeInsets.fromLTRB(4, 0, 4, 14)
        : const EdgeInsets.only(bottom: 8),
    child: _VariantTile(
      key: ValueKey(variantCode(row)),
      row: row,
      columns: controller.reportColumns,
      controller: controller,
      templateCode: templateCode,
    ),
  );
}

// ── Image gallery viewer ──────────────────────────────────────────────────────

void _openImageViewer(
  BuildContext context, {
  required List<_GalleryItem> items,
  required int initialIndex,
  required ReportFieldsController fields,
  required int generation,
}) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => ReportFieldsOwnerOverlay(
      fields: fields,
      generation: generation,
      builder: (_) => _ImageGallery(items: items, initialIndex: initialIndex),
    ),
  );
}

// ── Template heading ──────────────────────────────────────────────────────────

/// The subtotal row ERPNext v16.55 puts above each template's variants:
/// the template's code and Item Group, and the totals the report gives it,
/// under the report's own column labels.
// Multi-delegate viewports lay out a child in every delegate to estimate
// scroll extents. A single lazy delegate avoids that cost for large reports.
typedef _GroupAt =
    ({VariantGroup group, bool title, bool expanded}) Function(int index);

class _StickyGroupList extends SliverList {
  final ValueNotifier<StickyVariantHeading?> sticky;
  final GlobalKey headerKey;
  final _GroupAt groupAt;
  final double headingExtent;

  const _StickyGroupList({
    required this.sticky,
    required this.headerKey,
    required this.groupAt,
    required this.headingExtent,
    required super.delegate,
  });

  @override
  RenderSliverList createRenderObject(BuildContext context) =>
      _RenderStickyGroupList(
        childManager: context as SliverMultiBoxAdaptorElement,
        sticky: sticky,
        headerKey: headerKey,
        groupAt: groupAt,
        headingExtent: headingExtent,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStickyGroupList renderObject,
  ) {
    renderObject
      ..groupAt = groupAt
      ..headingExtent = headingExtent
      ..markNeedsLayout();
  }
}

class _RenderStickyGroupList extends RenderSliverList {
  final ValueNotifier<StickyVariantHeading?> sticky;
  final GlobalKey headerKey;
  _GroupAt groupAt;
  double headingExtent;
  ({VariantGroup group, double offset})? _next;
  bool _scheduled = false;

  _RenderStickyGroupList({
    required super.childManager,
    required this.sticky,
    required this.headerKey,
    required this.groupAt,
    required this.headingExtent,
  });

  @override
  void performLayout() {
    super.performLayout();
    if (geometry?.scrollOffsetCorrection != null) return;
    final boundary =
        constraints.scrollOffset +
        constraints.overlap.clamp(0.0, double.infinity);
    VariantGroup? active;
    var offset = 0.0;
    if (constraints.remainingPaintExtent > 0) {
      for (var child = firstChild; child != null; child = childAfter(child)) {
        final top = childScrollOffset(child)!;
        if (top + paintExtentOf(child) <= boundary) continue;
        final entry = groupAt(indexOf(child));
        if (active == null) {
          if (!entry.expanded ||
              top > boundary ||
              (entry.title && top == boundary)) {
            break;
          }
          active = entry.group;
        } else if (entry.group != active) {
          offset = (top - boundary - headingExtent).clamp(-headingExtent, 0.0);
          break;
        }
      }
    }
    _next = active == null ? null : (group: active, offset: offset);
    if (_scheduled || (_next == null && sticky.value == null)) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached) return;
      final next = _next;
      final viewport = RenderAbstractViewport.maybeOf(this);
      // The preceding header can only be measured after the viewport's layout.
      final headerBottom = viewport != null && next != null
          ? DocTypeListHeader.extentInViewport(
              headerKey,
              viewport,
            )?.clamp(0.0, double.infinity)
          : null;
      sticky.value =
          next != null &&
              headerBottom != null &&
              constraints.viewportMainAxisExtent - headerBottom >=
                  headingExtent + kMinInteractiveDimension
          ? (group: next.group, offset: next.offset, headerBottom: headerBottom)
          : null;
    });
  }
}

// SliverList may build cached children and estimate extents with offscreen
// delegates. Schedule enrichment from paint so those children stay cheap.
class _VisibleVariant extends SingleChildRenderObjectWidget {
  final VoidCallback onPaint;
  const _VisibleVariant({required this.onPaint, required super.child});

  @override
  _RenderVisibleVariant createRenderObject(BuildContext context) =>
      _RenderVisibleVariant(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderVisibleVariant renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderVisibleVariant extends RenderProxyBox {
  VoidCallback onPaint;
  _RenderVisibleVariant(this.onPaint);

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

// Strengthen the Material outline token with theme ink for both surfaces.
Color _resultOutline(ColorScheme scheme) =>
    Color.lerp(scheme.outlineVariant, scheme.onSurface, 0.60)!;

BoxDecoration _groupDecoration(
  ColorScheme scheme, {
  bool top = false,
  bool bottom = false,
}) {
  const corner = Radius.circular(12);
  final side = BorderSide(color: _resultOutline(scheme));
  return BoxDecoration(
    color: scheme.surfaceContainer,
    borderRadius: BorderRadius.vertical(
      top: top ? corner : Radius.zero,
      bottom: bottom ? corner : Radius.zero,
    ),
    border: Border(
      top: top ? side : BorderSide.none,
      bottom: bottom ? side : BorderSide.none,
      left: side,
      right: side,
    ),
  );
}

// The large-report delegate paints adjoining pieces of the same outline.
// It can still build and lay out only the visible and cached rows.
class _GroupBody extends StatelessWidget {
  final Widget child;
  final bool last;

  const _GroupBody({required this.child, this.last = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 8 : 0),
    child: DecoratedBox(
      decoration: _groupDecoration(Theme.of(context).colorScheme, bottom: last),
      child: child,
    ),
  );
}

class _GroupTitle extends StatelessWidget {
  final VariantGroup group;
  final bool expanded;
  final String? name;
  final String summary;
  final String currentStockLabel;
  final VoidCallback onTap;

  const _GroupTitle({
    required this.group,
    required this.expanded,
    this.name,
    required this.summary,
    required this.currentStockLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines =
        ItemVariantDetailsScreen._wrapHeading(context, currentStockLabel)
        ? 2
        : 1;
    final codeLabel = name == null || name!.isEmpty || name == group.code
        ? group.code
        : '${group.code}, $name';
    final stockSummary = expanded
        ? group.collapsedSummary(
            group.variants.length,
            filtered: false,
            currentStockLabel: currentStockLabel,
          )
        : summary;
    return Semantics(
      header: true,
      button: true,
      expanded: expanded,
      label: 'Template $codeLabel, ${stockSummary.replaceFirst(' · ', ', ')}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(bottom: expanded ? 0 : 4),
            child: Ink(
              decoration: _groupDecoration(
                theme.colorScheme,
                top: true,
                bottom: !expanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _code(theme, lines),
                          Text(
                            summary,
                            maxLines: expanded ? lines : null,
                            overflow: expanded ? TextOverflow.ellipsis : null,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _code(ThemeData theme, int lines) => Text(
    name == null || name!.isEmpty || name == group.code
        ? group.code
        : '${group.code} · $name',
    maxLines: lines,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _TemplateHeader extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> columns;

  const _TemplateHeader({required this.row, required this.columns});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final itemGroup = row['item_group']?.toString() ?? '';
    final totals = templateTotals(row, columns);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (itemGroup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                itemGroup,
                style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          if (totals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  for (final t in totals)
                    Text.rich(
                      TextSpan(
                        text: '${t.label}  ',
                        style: text.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        children: [
                          TextSpan(
                            text: t.value,
                            style: text.labelMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Variant tile ──────────────────────────────────────────────────────────────

class _VariantTile extends StatefulWidget {
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> columns;
  final ItemVariantDetailsController controller;

  final String? templateCode;

  const _VariantTile({
    super.key,
    required this.row,
    required this.columns,
    required this.controller,
    required this.templateCode,
  });

  @override
  State<_VariantTile> createState() => _VariantTileState();
}

class _VariantTileState extends State<_VariantTile> {
  String? _lastDisplayedImage;

  String? _imageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return '${Get.find<ApiProvider>().baseUrl}$path';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final _VariantTile(:row, :columns, :controller, :templateCode) = widget;
    final itemCode = variantCode(row);
    final detail = controller.detailsFor(itemCode);

    final stockUom = row['stock_uom'];
    final zeroStock = num.tryParse('${row['current_stock']}') == 0;

    return _VisibleVariant(
      onPaint: () => controller.queueNearbyDetails(itemCode),
      child: Obx(() {
        final details = detail.value;
        final fields = controller.fields.state.value;
        final generation = controller.fields.ownerGeneration;
        final reportName = row['item_name']?.toString().trim() ?? '';
        final itemName = reportName.isEmpty
            ? (details?['item_name']?.toString() ?? '')
            : reportName;
        final itemGroup = fields.shows('item_group')
            ? (row['item_group'] ?? details?['item_group'])?.toString() ?? ''
            : '';
        final chips = selectedVariantValues(
          row,
          columns,
          fields.shows,
        ).toList();
        final currentStock = fields.shows('current_stock')
            ? formatStockQuantity(
                row['current_stock'],
                fields.shows('stock_uom') ? stockUom : null,
              )
            : '';
        final imageUrl = _imageUrl(details?['image'] as String?);
        final height = templateCode == null ? 200.0 : 84.0;
        final stockRows = controller.stockBalances[itemCode];
        final stockError = controller.stockErrors[itemCode];
        final stockBalanceLabel =
            controller.stockBalanceLabels[itemCode] ?? 'Balance Qty';
        final isStockLoading = controller.loadingStock[itemCode] == true;
        final isExpanded = stockRows != null;

        void openGallery() {
          if (generation != controller.fields.ownerGeneration) return;
          // Collect all variant images in report order so the gallery
          // can slide between items; open at the tapped item's index.
          final items = <_GalleryItem>[];
          var startIndex = 0;
          for (final r in variantRowsOf(controller.reportData)) {
            final code = variantCode(r);
            final url = _imageUrl(
              controller.itemDetails[code]?['image'] as String?,
            );
            if (url == null) continue;
            if (code == itemCode) startIndex = items.length;
            items.add(
              _GalleryItem(
                url: url,
                itemCode: code,
                itemName:
                    controller.itemDetails[code]?['item_name'] as String? ?? '',
              ),
            );
          }
          if (items.isEmpty) return;
          _openImageViewer(
            context,
            items: items,
            initialIndex: startIndex,
            fields: controller.fields,
            generation: generation,
          );
        }

        Widget card({Widget? banner, bool broken = false}) => Card.outlined(
          margin: EdgeInsets.zero,
          color: cs.surface,
          elevation: 0,
          clipBehavior: Clip.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _resultOutline(cs)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (banner != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: banner,
                ),

              Padding(
                padding: EdgeInsets.all(templateCode == null ? 14 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row (tappable → item form) ──────────
                    Semantics(
                      label: templateCode == null
                          ? 'Open item $itemCode'
                          : 'Open variant $itemCode of $templateCode',
                      button: true,
                      child: InkWell(
                        onTap: () => Get.toNamed(
                          AppRoutes.ITEM_FORM,
                          arguments: {'itemCode': itemCode},
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (banner == null) ...[
                                _ItemThumb(
                                  width: 54,
                                  height: 54,
                                  broken: broken,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemCode,
                                      style: text.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (itemName.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          itemName,
                                          style: text.bodySmall?.copyWith(
                                            color: cs.onSurface,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if (itemGroup.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1),
                                        child: Text(
                                          itemGroup,
                                          semanticsLabel:
                                              '${fields.label('item_group')} $itemGroup',
                                          style: text.labelSmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: cs.onSurfaceVariant,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (currentStock.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${fields.label('current_stock')} $currentStock',
                          style: text.labelMedium?.copyWith(
                            color: zeroStock
                                ? cs.onSurfaceVariant
                                : cs.onSurface,
                            fontWeight: zeroStock
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),

                    // ── Attribute chips ──────────────────────────────
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final chip in chips)
                            _AttrChip(label: chip.label, value: chip.value),
                        ],
                      ),
                    ],

                    // ── Check Stock button ───────────────────────────
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isStockLoading
                            ? null
                            : () => controller.fetchStockBalance(itemCode),
                        icon: isStockLoading
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              )
                            : Icon(
                                isExpanded
                                    ? Icons.expand_less
                                    : Icons.inventory_2_outlined,
                                size: 16,
                              ),
                        label: Text(
                          isExpanded
                              ? 'Hide Stock'
                              : controller.activeFilters.containsKey(
                                  'warehouse',
                                )
                              ? 'Check Stock Across Warehouses'
                              : 'Check Stock',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.primary,
                          side: BorderSide(
                            color: cs.primary.withValues(alpha: 0.4),
                          ),
                          minimumSize: const Size(0, 48),
                          visualDensity: VisualDensity.standard,
                          textStyle: text.labelSmall,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),

                    // ── Stock section ────────────────────────────────
                    if (isExpanded)
                      _StockSection(
                        rows: stockRows,
                        stockUom: stockUom,
                        balanceLabel: stockBalanceLabel,
                      ),
                    if (stockError != null)
                      Semantics(
                        liveRegion: true,
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text(stockError)),
                            TextButton(
                              onPressed: isStockLoading
                                  ? null
                                  : () =>
                                        controller.fetchStockBalance(itemCode),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
        final ratio = MediaQuery.devicePixelRatioOf(context);
        return LayoutBuilder(
          builder: (context, constraints) => imageUrl == null
              ? card()
              : Image.network(
                  imageUrl,
                  key: ValueKey(imageUrl),
                  width: double.infinity,
                  height: height,
                  cacheWidth: ((constraints.maxWidth - 8) * ratio).ceil(),
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, error, stack) => card(broken: true),
                  frameBuilder: (context, image, frame, synchronouslyLoaded) {
                    if (frame == null) return card();
                    if (_lastDisplayedImage != imageUrl) {
                      _lastDisplayedImage = imageUrl;
                      ItemVariantDetailsScreen._preserveVariantAnchor(
                        Scrollable.of(context).context,
                        controller,
                      );
                    }
                    return card(
                      banner: Semantics(
                        label: 'View image for $itemCode',
                        button: true,
                        child: InkWell(onTap: openGallery, child: image),
                      ),
                    );
                  },
                ),
        );
      }),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  const _ItemThumb({
    required this.width,
    required this.height,
    this.broken = false,
  });

  final double width;
  final double height;
  final bool broken;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: broken ? cs.surfaceContainerHighest : cs.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          broken ? Icons.broken_image_outlined : Icons.image_outlined,
          size: (height * 24 / 54).clamp(20, 48).toDouble(),
          color: broken ? cs.onSurfaceVariant : cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

// ── Attribute chip ─────────────────────────────────────────────────────────────

class _AttrChip extends StatelessWidget {
  final String label;
  final String value;
  const _AttrChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.isEmpty ? value : '$label: $value',
        style: text.labelSmall?.copyWith(
          color: cs.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Stock section (container + summary + rows) ────────────────────────────────

class _StockSection extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Object? stockUom;
  final String balanceLabel;
  const _StockSection({
    required this.rows,
    required this.stockUom,
    required this.balanceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, left: 4),
        child: Text(
          'No stock in any rack.',
          style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final totalQty = rows.fold<double>(
      0,
      (sum, r) => sum + ((r['qty'] as num?)?.toDouble() ?? 0),
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.shelves, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${rows.length} rack${rows.length != 1 ? 's' : ''}',
                  style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Total · $balanceLabel ${formatStockQuantity(totalQty, stockUom)}',
                    textAlign: TextAlign.end,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: totalQty > 0 ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
          // Per-rack rows
          ...rows.asMap().entries.map((entry) {
            final isLast = entry.key == rows.length - 1;
            final r = entry.value;
            return Column(
              children: [
                _StockRow(
                  rack: r['rack']?.toString() ?? '—',
                  qty: (r['qty'] as num?) ?? 0,
                  stockUom: stockUom,
                  balanceLabel: balanceLabel,
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Stock row ──────────────────────────────────────────────────────────────────

class _StockRow extends StatelessWidget {
  final String rack;
  final num qty;
  final Object? stockUom;
  final String balanceLabel;
  const _StockRow({
    required this.rack,
    required this.qty,
    required this.stockUom,
    required this.balanceLabel,
  });

  Color _qtyColor(ColorScheme cs, Brightness brightness) {
    if (qty < 0) return cs.error;
    if (qty == 0) return cs.onSurfaceVariant;
    // Status ramp: x700 on light surfaces, x300 on dark — a fixed dark
    // green is unreadable on the dark-mode tint.
    return brightness == Brightness.dark
        ? AppColors.green300
        : AppColors.green700;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = _qtyColor(cs, Theme.of(context).brightness);
    final quantity = formatStockQuantity(qty, stockUom);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rack,
              style: text.bodyMedium?.copyWith(color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              quantity,
              semanticsLabel: '$balanceLabel $quantity',
              style: text.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gallery data ───────────────────────────────────────────────────────────────

class _GalleryItem {
  final String url;
  final String itemCode;
  final String itemName;
  const _GalleryItem({
    required this.url,
    required this.itemCode,
    required this.itemName,
  });
}

// ── Full-screen image gallery ─────────────────────────────────────────────────

class _ImageGallery extends StatefulWidget {
  final List<_GalleryItem> items;
  final int initialIndex;
  const _ImageGallery({required this.items, required this.initialIndex});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  late int _current = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final item = widget.items[_current];

    return ItemImagePreview(
      key: ValueKey(_current),
      url: item.url,
      title: [
        item.itemCode,
        item.itemName,
      ].where((text) => text.isNotEmpty).join(' · '),
      navigationActions: [
        if (total > 1) ...[
          IconButton(
            tooltip: 'Previous image',
            onPressed: _current == 0 ? null : () => setState(() => _current--),
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${_current + 1} / $total'),
          IconButton(
            tooltip: 'Next image',
            onPressed: _current == total - 1
                ? null
                : () => setState(() => _current++),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ],
    );
  }
}
