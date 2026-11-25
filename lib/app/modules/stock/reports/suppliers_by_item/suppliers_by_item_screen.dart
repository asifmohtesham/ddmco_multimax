import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields_sheet.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_layout.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_rows.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_view_sheet.dart';

class SuppliersByItemScreen extends StatefulWidget {
  const SuppliersByItemScreen({super.key});

  @override
  State<SuppliersByItemScreen> createState() => _SuppliersByItemScreenState();
}

class _SuppliersByItemScreenState extends State<SuppliersByItemScreen> {
  static const _includeDraftsKey = 'include_drafts';
  static const _expandBomKey = 'expand_bom';
  static const _filterFields = [
    ReportFilterField(
      key: 'items',
      label: 'Items',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item',
      selectedChipOverflow: TextOverflow.ellipsis,
      prefixIcon: Icons.category_outlined,
    ),
    ReportFilterField(
      key: 'variant_of',
      label: 'Variant Of',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Item',
      linkFilters: {'has_variants': 1},
      selectedChipOverflow: TextOverflow.ellipsis,
      prefixIcon: Icons.account_tree_outlined,
    ),
    ReportFilterField(
      key: 'suppliers',
      label: 'Suppliers',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Supplier',
      prefixIcon: Icons.local_shipping_outlined,
      helperText:
          'Matches suppliers linked to the item and, when BOM expansion is '
          'enabled, its components. All suppliers are shown.',
    ),
    ReportFilterField(
      key: 'warehouses',
      label: 'Warehouses',
      type: ReportFilterType.doctypeMultiLink,
      linkDoctype: 'Warehouse',
      prefixIcon: Icons.warehouse_outlined,
      helperText:
          'Filters Balance Qty, Projected Qty, Reorder Level and Reorder Qty. '
          'Groups include child warehouses. '
          'All warehouses are used when empty.',
    ),
    ReportFilterField(
      key: _includeDraftsKey,
      label: 'Include Draft Purchase Orders',
      type: ReportFilterType.switchToggle,
      prefixIcon: Icons.edit_note_outlined,
      helperText:
          'Suppliers that appear only on draft purchase orders are hidden when off.',
    ),
    ReportFilterField(
      key: _expandBomKey,
      label: 'Expand BOM components',
      type: ReportFilterType.switchToggle,
      prefixIcon: Icons.account_tree_outlined,
      helperText:
          'Shows what each item is made from and who supplies those components.',
    ),
  ];

  late final _controller = Get.find<SuppliersByItemController>(
    tag: SuppliersByItemBinding.tagForRoute(ModalRoute.of(context)),
  );
  final _scrollController = ScrollController();
  final _searchInput = TextEditingController();
  final _searchFocus = FocusNode();
  final _toolbarKey = GlobalKey(debugLabel: 'Suppliers by Item toolbar');
  final _searchHeaderKey = GlobalKey(
    debugLabel: 'Suppliers by Item search header',
  );
  final _supplierHeaderKey = GlobalKey();
  final _pinnedSupplier = ValueNotifier<_PinnedSupplier?>(null);
  final _paintedSupplier = ValueNotifier<SuppliersByItemRowKey?>(null);
  final _treeKey = GlobalKey<_SuppliersTreeState>();
  var _wasCurrent = true;
  final _draft = {
    for (final field in _filterFields) field.key: TextEditingController(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_wasCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_controller.refreshFieldsScope());
      });
    }
    _wasCurrent = current;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchInput.dispose();
    _searchFocus.dispose();
    _pinnedSupplier.dispose();
    _paintedSupplier.dispose();
    for (final input in _draft.values) {
      input.dispose();
    }
    super.dispose();
  }

  void _loadDraft() {
    final filters = _controller.filters.value;
    final links = filters.linkFilters;
    for (final entry in _draft.entries) {
      entry.value.text = switch (entry.key) {
        _includeDraftsKey => filters.includeDrafts ? '1' : '',
        _expandBomKey => filters.expandBom ? '1' : '',
        _ => joinMultiValue(links[entry.key] ?? const []),
      };
    }
  }

  SuppliersByItemFilters get _draftFilters => SuppliersByItemFilters(
    items: splitMultiValue(_draft['items']!.text),
    variantOf: splitMultiValue(_draft['variant_of']!.text),
    suppliers: splitMultiValue(_draft['suppliers']!.text),
    warehouses: splitMultiValue(_draft['warehouses']!.text),
    includeDrafts: _draft[_includeDraftsKey]!.text == '1',
    expandBom: _draft[_expandBomKey]!.text == '1',
  );

  void _openFilters(BuildContext context, {String? focusKey}) {
    if (_controller.isLoading.value) return;
    _loadDraft();
    showReportFilterSheet(
      context: context,
      title: 'Suppliers by Item Filters',
      fields: _filterFields,
      controllers: _draft,
      focusKey: focusKey,
      onRun: () => _controller.run(filters: _draftFilters),
      runBusy: _controller.isLoading,
      onClear: _clearFilters,
    );
  }

  void _clearFilters() {
    _controller.run(filters: const SuppliersByItemFilters());
  }

  void _clearFilter(String key) {
    if (_controller.isLoading.value) return;
    _loadDraft();
    _draft[key]!.text = key == _includeDraftsKey ? '1' : '';
    _controller.run(filters: _draftFilters);
  }

  List<Widget> _filterChips(BuildContext context) {
    if (_controller.isLoading.value) return [];
    return [
      for (final field in _filterFields)
        if (_controller.activeFilters[field.key] case final value?)
          FilterChipWidget(
            icon: Icons.filter_alt_outlined,
            label: '${field.label}: $value',
            onDeleted: () => _clearFilter(field.key),
            onTap: () => _openFilters(context, focusKey: field.key),
          ),
    ];
  }

  void _changeSearch(String text) {
    _treeKey.currentState?.changeSearch(
      wasSearching: _controller.query.value.trim().isNotEmpty,
      willSearch: text.trim().isNotEmpty,
    );
    _controller.setQuery(text);
  }

  void _clearSearch() {
    _searchInput.clear();
    _changeSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final fromItem =
        ModalRoute.of(context)?.settings.arguments is SuppliersByItemFilters;
    final padding = MediaQuery.paddingOf(context);

    return AppShellScaffold(
      bottomNavigationBar: Obx(() {
        final settingsError = _controller.settingsScopeLoadError.value;
        if (settingsError == null &&
            _controller.fieldsSaveError.value == null &&
            _controller.fieldsLoadError.value == null &&
            _controller.viewSaveError.value == null &&
            _controller.viewLoadError.value == null) {
          return const SizedBox.shrink();
        }
        return Material(
          color: context.scheme.fg,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settingsError != null)
                  _SettingsScopeFeedback(
                    message: settingsError,
                    busy: _controller.fieldsScopeLoading.value,
                    onRetry: _controller.refreshFieldsScope,
                  ),
                SuppliersByItemFieldsFeedback(controller: _controller),
                SuppliersByItemViewFeedback(controller: _controller),
              ],
            ),
          ),
        );
      }),
      body: Obx(() {
        final loading = _controller.isLoading.value;
        final error = _controller.error.value;
        final fields = _controller.fieldVisibility;
        final filterRevision = _controller.filterRevision.value;
        final query = _controller.query.value;
        final search = _controller.search;
        final summary = _controller.summary;
        final view = _controller.view.value;
        final showResults = _controller.hasLoaded && !loading && error == null;
        final canPinSearch =
            showResults ||
            query.isNotEmpty ||
            (loading && _controller.loadedRevision.value > 0);

        return RefreshIndicator(
          onRefresh: _controller.run,
          child: Scrollbar(
            controller: _scrollController,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    (notification is ScrollStartNotification &&
                            notification.dragDetails != null ||
                        notification is UserScrollNotification &&
                            notification.direction != ScrollDirection.idle)) {
                  _treeKey.currentState?.cancelAnchor();
                }
                return false;
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  DocTypeListHeader(
                    key: _toolbarKey,
                    title: 'Suppliers by Item',
                    automaticallyImplyLeading: fromItem,
                    activeFilters: _controller.activeFilters,
                    onFilterTap: loading ? null : () => _openFilters(context),
                    filterChipsBuilder: _filterChips,
                    onClearAllFilters: _clearFilters,
                    quickChips: [_ViewChip(controller: _controller)],
                    quickChipsKey: loading,
                    extraActions: [
                      IconButton(
                        tooltip: 'Fields',
                        icon: const Icon(Icons.view_agenda_outlined),
                        onPressed: () =>
                            showSuppliersByItemFields(context, _controller),
                      ),
                      AsyncIconButton(
                        busy: _controller.isLoading,
                        onPressed: _controller.run,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh report',
                        spinnerColor: Theme.of(context).colorScheme.onSurface,
                      ),
                    ],
                  ),
                  if (canPinSearch)
                    _ResultsHeaderSliver(
                      key: _searchHeaderKey,
                      child: Material(
                        color: context.scheme.fg,
                        child: _ResultsHeader(
                          summary: showResults ? summary : null,
                          fields: fields,
                          searchInput: _searchInput,
                          searchFocus: _searchFocus,
                          query: query,
                          matchCount: showResults
                              ? search?.matchingItemIds.length
                              : null,
                          otherCount: search?.matchingOtherIds.length ?? 0,
                          onChanged: _changeSearch,
                          onClear: _clearSearch,
                        ),
                      ),
                    ),
                  // Keep the viewport state across loading and retry.
                  ValueListenableBuilder(
                    valueListenable: _pinnedSupplier,
                    builder: (context, pinned, _) => _SupplierHeaderSliver(
                      key: _supplierHeaderKey,
                      supplierKey: pinned?.entry.key,
                      groupEnd: pinned?.groupEnd,
                      paintedSupplier: _paintedSupplier,
                      child:
                          !showResults ||
                              pinned == null ||
                              view.group != SuppliersByItemGroup.supplier
                          ? const SizedBox.shrink()
                          : ColoredBox(
                              color: context.scheme.fg,
                              child: _treeKey.currentState!._groupTile(
                                pinned.entry,
                                fields,
                              ),
                            ),
                    ),
                  ),
                  _SuppliersTree(
                    key: _treeKey,
                    controller: _controller,
                    visible: showResults ? _controller.visibleRows : null,
                    fields: fields,
                    filterRevision: filterRevision,
                    view: view,
                    query: query,
                    scrollController: _scrollController,
                    toolbarKey: _toolbarKey,
                    searchHeaderKey: _searchHeaderKey,
                    supplierHeaderKey: _supplierHeaderKey,
                    pinnedSupplier: _pinnedSupplier,
                    paintedSupplier: _paintedSupplier,
                    bottomPadding: padding.bottom,
                    onResetSearchInput: _searchInput.clear,
                  ),
                  if (loading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          label: 'Loading report',
                          child: const CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else if (error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ReportState(
                        message: error,
                        icon: Icons.error_outline,
                        retry: _controller,
                      ),
                    )
                  else if (showResults) ...[
                    if (_controller.nodes.isEmpty)
                      const SliverToBoxAdapter(
                        child: _ReportState(
                          message: 'No items found for these filters',
                          icon: Icons.inventory_2_outlined,
                        ),
                      )
                    else if (search != null &&
                        search.matchingItemIds.isEmpty &&
                        search.matchingOtherIds.isEmpty)
                      SliverToBoxAdapter(
                        child: _ReportState(
                          message: 'No matches for “${query.trim()}”',
                          icon: Icons.search_off,
                          action: TextButton(
                            onPressed: _clearSearch,
                            child: const Text('Clear search'),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SuppliersByItemFooter(
                        totals: summary.totalsByUom,
                        hasResults: _controller.nodes.isNotEmpty,
                        excludesUnknownUom: summary.hasUnknownStockUom,
                        bottomPadding: padding.bottom,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SettingsScopeFeedback extends StatelessWidget {
  const _SettingsScopeFeedback({
    required this.message,
    required this.busy,
    required this.onRetry,
  });

  final String message;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
    child: Row(
      children: [
        if (busy) ...[
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.scheme.textMuted),
            ),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: busy ? null : onRetry,
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _ViewChip extends StatefulWidget {
  const _ViewChip({required this.controller});

  final SuppliersByItemController controller;

  @override
  State<_ViewChip> createState() => _ViewChipState();
}

class _ViewChipState extends State<_ViewChip> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await showSuppliersByItemView(context, widget.controller);
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final view = widget.controller.view.value;
    final group = suppliersByItemGroupLabel(view.group);
    final sort = suppliersByItemSortLabel(view.sortField);
    final direction = suppliersByItemDirectionLabel(
      view.sortField,
      view.sortDirection,
    );
    final arrow = view.sortDirection == SuppliersByItemSortDirection.asc
        ? '↑'
        : '↓';
    final caption = view.group == SuppliersByItemGroup.template
        ? '$sort $arrow'
        : '$group · $sort $arrow';
    final saving = widget.controller.viewSaving.value;
    return Tooltip(
      message: 'View',
      excludeFromSemantics: true,
      child: ActionChip(
        key: const ValueKey('suppliers-by-item-view'),
        focusNode: _focus,
        visualDensity: VisualDensity.compact,
        padding: MediaQuery.textScalerOf(context).scale(12) > 12
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
            : null,
        onPressed: _open,
        label: Semantics(
          label: 'View',
          value: '$group, $sort, $direction',
          excludeSemantics: true,
          child: Text(caption),
        ),
        avatar: saving
            ? Semantics(
                label: 'Saving View',
                liveRegion: true,
                child: const Center(
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : null,
      ),
    );
  });
}

class _ReportState extends StatelessWidget {
  const _ReportState({
    required this.message,
    required this.icon,
    this.retry,
    this.action,
  });

  final String message;
  final IconData icon;
  final SuppliersByItemController? retry;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: context.scheme.textSubtle),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (retry case final controller?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AsyncFilledButton(
                  busy: controller.isLoading,
                  onPressed: controller.run,
                  icon: const Icon(Icons.refresh),
                  label: 'Retry',
                ),
              ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

/// A naturally sized header that contributes pinned extent only when there
/// is room for it and at least 144 dp of results. The search field stays in
/// the same element when the keyboard changes the viewport height.
class _ResultsHeaderSliver extends SingleChildRenderObjectWidget {
  const _ResultsHeaderSliver({super.key, required super.child});

  @override
  _RenderResultsHeader createRenderObject(BuildContext context) =>
      _RenderResultsHeader();
}

class _RenderResultsHeader extends RenderSliverToBoxAdapter {
  bool pinned = false;

  @override
  void performLayout() {
    super.performLayout();
    final box = child;
    if (box == null) {
      pinned = false;
      return;
    }
    final extent = box.size.height;
    // The large title can collapse, so measure the viewport space left
    // after the app bar paints instead of using its full scroll extent.
    final available = math.max(
      0.0,
      constraints.remainingPaintExtent - constraints.overlap,
    );
    final shouldPin = available - extent >= 144;
    if (pinned != shouldPin) {
      pinned = shouldPin;
      markNeedsSemanticsUpdate();
    }
    if (!pinned) return;

    geometry = SliverGeometry(
      scrollExtent: extent,
      paintOrigin: constraints.overlap,
      paintExtent: extent,
      layoutExtent: (extent - constraints.scrollOffset).clamp(0.0, extent),
      maxPaintExtent: extent,
      maxScrollObstructionExtent: extent,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
      hasVisualOverflow: true,
    );
    final data = box.parentData! as SliverPhysicalParentData;
    data.paintOffset = Offset.zero;
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      pinned ? 0 : super.childMainAxisPosition(child);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (pinned) config.addTagForChildren(RenderViewport.excludeFromScrolling);
  }
}

typedef _PinnedSupplier = ({SuppliersByItemLayoutRow entry, double groupEnd});

/// Paints one overlay heading above the lazy rows, inside the scrollable so
/// the heading's taps and drags use the same viewport as the in-flow heading.
class _SupplierHeaderSliver extends SingleChildRenderObjectWidget {
  const _SupplierHeaderSliver({
    super.key,
    required this.supplierKey,
    required this.groupEnd,
    required this.paintedSupplier,
    required super.child,
  });

  final SuppliersByItemRowKey? supplierKey;
  final double? groupEnd;
  final ValueNotifier<SuppliersByItemRowKey?> paintedSupplier;

  @override
  _RenderSupplierHeader createRenderObject(BuildContext context) =>
      _RenderSupplierHeader(paintedSupplier)
        ..supplierKey = supplierKey
        ..groupEnd = groupEnd;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSupplierHeader renderObject,
  ) {
    renderObject
      ..supplierKey = supplierKey
      ..groupEnd = groupEnd;
  }
}

class _RenderSupplierHeader extends RenderSliverToBoxAdapter {
  _RenderSupplierHeader(this._paintedSupplier);

  final ValueNotifier<SuppliersByItemRowKey?> _paintedSupplier;
  SuppliersByItemRowKey? _supplierKey;
  double? _groupEnd;
  SuppliersByItemRowKey? _laidOutSupplierKey;
  bool _paintedSupplierUpdateScheduled = false;

  set supplierKey(SuppliersByItemRowKey? value) {
    if (_supplierKey == value) return;
    _supplierKey = value;
    markNeedsLayout();
  }

  set groupEnd(double? value) {
    if (_groupEnd == value) return;
    _groupEnd = value;
    markNeedsLayout();
  }

  double get _childTop => geometry!.paintExtent - child!.size.height;

  @override
  void performLayout() {
    final box = child!;
    box.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final remaining = _groupEnd == null
        ? 0.0
        : math.max(0.0, _groupEnd! - constraints.scrollOffset);
    final available = math.max(
      0.0,
      constraints.remainingPaintExtent - constraints.overlap,
    );
    final extent = available - box.size.height >= 48
        ? math.min(box.size.height, remaining)
        : 0.0;
    geometry = SliverGeometry(
      paintOrigin: constraints.overlap,
      paintExtent: extent,
      layoutExtent: 0,
      maxPaintExtent: box.size.height,
      maxScrollObstructionExtent: extent,
      hasVisualOverflow: true,
    );
    (box.parentData! as SliverPhysicalParentData).paintOffset = Offset(
      0,
      _childTop,
    );
    _laidOutSupplierKey = extent > 0 ? _supplierKey : null;
    if (_paintedSupplier.value != _laidOutSupplierKey &&
        !_paintedSupplierUpdateScheduled) {
      _paintedSupplierUpdateScheduled = true;
      // Update in-flow heading semantics after layout has finished.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paintedSupplierUpdateScheduled = false;
        if (attached) _paintedSupplier.value = _laidOutSupplierKey;
      });
    }
  }

  @override
  double childMainAxisPosition(RenderBox child) => _childTop;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (geometry!.paintExtent == 0) return;
    context.pushClipRect(needsCompositing, offset, _paintClip, super.paint);
  }

  Rect get _paintClip =>
      Rect.fromLTWH(0, 0, constraints.crossAxisExtent, geometry!.paintExtent);

  @override
  Rect describeApproximatePaintClip(RenderObject child) => _paintClip;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.addTagForChildren(RenderViewport.excludeFromScrolling);
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.summary,
    required this.fields,
    required this.searchInput,
    required this.searchFocus,
    required this.query,
    required this.matchCount,
    required this.otherCount,
    required this.onChanged,
    required this.onClear,
  });

  final SuppliersByItemSummary? summary;
  final SuppliersByItemFieldVisibility fields;
  final TextEditingController searchInput;
  final FocusNode searchFocus;
  final String query;
  final int? matchCount;
  final int otherCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final result = summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result != null) _SummaryStrip(summary: result, fields: fields),
          TextField(
            controller: searchInput,
            focusNode: searchFocus,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search within results',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              constraints: const BoxConstraints(minHeight: 48),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search query',
                      onPressed: onClear,
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          if (matchCount != null &&
              fields.shows(SuppliersByItemField.searchMatchCount))
            _MatchCount(
              text: [
                '${SuppliersByItemField.summaryItemCount.label} $matchCount',
                if (otherCount != 0) 'Other matching rows $otherCount',
              ].join(' · '),
            ),
        ],
      ),
    );
  }
}

class _MatchCount extends StatefulWidget {
  const _MatchCount({required this.text});

  final String text;

  @override
  State<_MatchCount> createState() => _MatchCountState();
}

class _MatchCountState extends State<_MatchCount> {
  Timer? _timer;
  String? _announcement;

  @override
  void initState() {
    super.initState();
    _scheduleAnnouncement();
  }

  @override
  void didUpdateWidget(covariant _MatchCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _scheduleAnnouncement();
  }

  void _scheduleAnnouncement() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      setState(() => _announcement = widget.text);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Semantics(
      liveRegion: true,
      label: _announcement,
      excludeSemantics: true,
      child: Text(
        widget.text,
        style: TextStyle(color: context.scheme.textMuted),
      ),
    ),
  );
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.fields});

  final SuppliersByItemSummary summary;
  final SuppliersByItemFieldVisibility fields;

  @override
  Widget build(BuildContext context) {
    final stock = {
      for (final entry in summary.totalsByUom.entries)
        if (entry.value.balanceQty case final value?) entry.key: value,
    };
    final cells = <Widget>[
      if (fields.shows(SuppliersByItemField.summaryItemCount))
        _SummaryCell(
          caption: SuppliersByItemField.summaryItemCount.label,
          value: '${summary.itemCount}',
        ),
      if (fields.shows(SuppliersByItemField.summarySupplierCount))
        _SummaryCell(
          caption: SuppliersByItemField.summarySupplierCount.label,
          value: '${summary.supplierCount}',
        ),
      if (fields.shows(SuppliersByItemField.summaryNoDirectCount))
        _SummaryCell(
          caption: SuppliersByItemField.summaryNoDirectCount.label,
          value: '${summary.noDirectCount}',
        ),
      if (fields.shows(SuppliersByItemField.summaryStockByUom))
        _SummaryCell(
          caption: SuppliersByItemField.summaryStockByUom.label,
          value: switch (stock.length) {
            0 => '-',
            1 => suppliersByItemQuantity(
              stock.values.single,
              stock.keys.single,
            ),
            _ => 'Balance Qty by Stock UOM',
          },
          onPressed: stock.length > 1 ? () => _showStock(context, stock) : null,
        ),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.scheme.subtle,
          border: Border.all(color: context.scheme.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                for (final cell in cells)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: cell,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showStock(BuildContext context, Map<String, num> stock) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: context.scheme.fg,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Balance Qty by Stock UOM',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              for (final entry in stock.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(suppliersByItemQuantity(entry.value, entry.key)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.caption,
    required this.value,
    this.onPressed,
  });

  final String caption;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final captionStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: context.scheme.textMuted);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: valueStyle, textAlign: TextAlign.center),
          Text(caption, style: captionStyle, textAlign: TextAlign.center),
        ],
      ),
    );
    if (onPressed == null) {
      return Semantics(
        label: '$caption ${value == '-' ? 'unavailable' : value}',
        excludeSemantics: true,
        child: child,
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
      ),
      child: child,
    );
  }
}

class _ReadingAnchor {
  _ReadingAnchor({
    required this.key,
    required this.owner,
    required this.pair,
    required this.source,
    required this.ancestors,
    required this.neighbors,
    required this.offset,
    required this.position,
    required RenderBox box,
  }) : originalBox = WeakReference(box);

  final SuppliersByItemRowKey key;
  final SuppliersByItemSourceKey? owner;
  final SuppliersByItemSourceKey? pair;
  final SuppliersByItemSourceKey? source;
  final List<SuppliersByItemRowKey> ancestors;
  final List<SuppliersByItemRowKey> neighbors;
  final double offset;
  final ScrollPosition position;
  final WeakReference<RenderBox> originalBox;

  bool evicted = false;
  bool hasAligned = false;
  bool returningFromSearch = false;
  bool resolveOccurrence = false;
  int estimatedSeeksLeft = 0;
  ({int index, double offset})? seekBefore;
  ({int index, double offset})? seekAfter;
  SuppliersByItemRowKey? resolvedKey;
  final seekFrames = <({int first, int last, int pixels})>{};
}

typedef _BrowsePosition = ({_ReadingAnchor? anchor, double? offset});

class _SuppliersTree extends StatefulWidget {
  const _SuppliersTree({
    super.key,
    required this.controller,
    required this.visible,
    required this.fields,
    required this.filterRevision,
    required this.view,
    required this.query,
    required this.scrollController,
    required this.toolbarKey,
    required this.searchHeaderKey,
    required this.supplierHeaderKey,
    required this.pinnedSupplier,
    required this.paintedSupplier,
    required this.bottomPadding,
    required this.onResetSearchInput,
  });

  final SuppliersByItemController controller;
  final SuppliersByItemVisibleRows? visible;
  final SuppliersByItemFieldVisibility fields;
  final int filterRevision;
  final SuppliersByItemView view;
  final String query;
  final ScrollController scrollController;
  final GlobalKey toolbarKey;
  final GlobalKey searchHeaderKey;
  final GlobalKey supplierHeaderKey;
  final ValueNotifier<_PinnedSupplier?> pinnedSupplier;
  final ValueListenable<SuppliersByItemRowKey?> paintedSupplier;
  final double bottomPadding;
  final VoidCallback onResetSearchInput;

  @override
  State<_SuppliersTree> createState() => _SuppliersTreeState();
}

class _SuppliersTreeState extends State<_SuppliersTree> {
  static const _rowGap = 4.0;
  static const _precision = 0.5;
  final _listKey = GlobalKey();
  SuppliersByItemVisibleRows? _laidOut;
  _ReadingAnchor? _anchor;
  final _browsePositions = <SuppliersByItemGroup, _BrowsePosition>{};
  final _beforeSearch = <SuppliersByItemGroup, _BrowsePosition>{};
  double? _restoreBrowseOffset;
  ({SuppliersByItemRowKey item, SuppliersByItemRowKey lastSupplier})?
  _supplierReveal;
  bool _goToTop = false;
  bool _correctionScheduled = false;
  bool _supplierHeaderScheduled = false;
  bool _supplierHeaderChanged = false;
  bool _routeVisible = true;

  @override
  void didUpdateWidget(covariant _SuppliersTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRevision != widget.filterRevision) {
      _browsePositions.clear();
      _beforeSearch.clear();
      _startAtTop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.query.isEmpty) widget.onResetSearchInput();
      });
    } else if (oldWidget.query == widget.query) {
      final viewChanged = oldWidget.view != widget.view;
      if (viewChanged &&
          oldWidget.view.group != widget.view.group &&
          widget.query.trim().isEmpty &&
          oldWidget.visible != null) {
        _browsePositions[oldWidget.view.group] = _captureBrowsePosition();
      }
      if (viewChanged ||
          oldWidget.visible != null && widget.visible == null ||
          SuppliersByItemField.values.any(
            (field) =>
                oldWidget.fields.shows(field) != widget.fields.shows(field),
          )) {
        _anchor ??= _captureAnchor();
        _supplierReveal = null;
      }
      if (_anchor case final anchor? when viewChanged) {
        anchor.resolveOccurrence = true;
        anchor.resolvedKey = null;
        anchor.hasAligned = false;
        anchor.estimatedSeeksLeft = 4;
        anchor.seekBefore = null;
        anchor.seekAfter = null;
        anchor.seekFrames.clear();
      }
    }
  }

  void cancelAnchor() {
    _anchor = null;
    _restoreBrowseOffset = null;
    _supplierReveal = null;
    _goToTop = false;
  }

  void _startAtTop() {
    cancelAnchor();
    _goToTop = true;
  }

  void changeSearch({required bool wasSearching, required bool willSearch}) {
    if (!wasSearching && !willSearch) return;
    final group = widget.view.group;
    if (!wasSearching) {
      _beforeSearch.addAll(_browsePositions);
      _beforeSearch[group] = _captureBrowsePosition(anchor: _anchor);
    }
    if (willSearch) {
      _startAtTop();
    } else {
      final saved = _beforeSearch[group];
      _anchor = saved?.anchor;
      _anchor?.returningFromSearch = true;
      _anchor?.hasAligned = false;
      _anchor?.estimatedSeeksLeft = 0;
      _anchor?.seekFrames.clear();
      _restoreBrowseOffset = saved?.offset;
      _goToTop = _anchor == null && _restoreBrowseOffset == null;
      _beforeSearch.clear();
    }
  }

  _BrowsePosition _captureBrowsePosition({_ReadingAnchor? anchor}) {
    final scroll = widget.scrollController;
    if (anchor == null &&
        scroll.hasClients &&
        scroll.position.hasContentDimensions &&
        scroll.offset >= scroll.position.maxScrollExtent - _precision) {
      return (anchor: null, offset: scroll.offset);
    }
    final captured = anchor ?? _captureAnchor();
    return (anchor: captured, offset: scroll.hasClients ? scroll.offset : null);
  }

  RenderSliverList? get _renderList =>
      _listKey.currentContext?.findRenderObject() as RenderSliverList?;

  double _headerBottom(
    RenderAbstractViewport viewport, {
    bool includeSupplier = true,
  }) {
    double bottomOf(RenderObject? box) {
      if (box is! RenderBox || !box.attached || !box.hasSize) return 0;
      return box
          .localToGlobal(Offset(0, box.size.height), ancestor: viewport)
          .dy;
    }

    final toolbarSliver = widget.toolbarKey.currentContext?.findRenderObject();
    final toolbarBottom = toolbarSliver is RenderSliverPersistentHeader
        ? bottomOf(toolbarSliver.child)
        : 0.0;
    final searchSliver = widget.searchHeaderKey.currentContext
        ?.findRenderObject();
    final base = searchSliver is _RenderResultsHeader && searchSliver.pinned
        ? math.max(toolbarBottom, bottomOf(searchSliver.child))
        : toolbarBottom;
    if (!includeSupplier) return base;
    final supplierSliver = widget.supplierHeaderKey.currentContext
        ?.findRenderObject();
    // A grouping change can swap the overlay's child before the next
    // layout. Its geometry still describes the heading that covered the rows.
    return base +
        (supplierSliver is _RenderSupplierHeader
            ? supplierSliver.geometry?.paintExtent ?? 0
            : 0);
  }

  void _scheduleSupplierHeader() {
    if (_supplierHeaderScheduled ||
        (widget.view.group != SuppliersByItemGroup.supplier &&
            widget.pinnedSupplier.value == null)) {
      return;
    }
    _supplierHeaderScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _supplierHeaderScheduled = false;
      if (!mounted) return;
      final supplier = _supplierAtTop();
      if (widget.pinnedSupplier.value == supplier) return;
      _supplierHeaderChanged = true;
      widget.pinnedSupplier.value = supplier;
    });
  }

  _PinnedSupplier? _supplierAtTop() {
    final list = _renderList;
    final viewport = RenderAbstractViewport.maybeOf(list);
    final visible = _laidOut;
    if (widget.view.group != SuppliersByItemGroup.supplier ||
        list == null ||
        viewport == null ||
        visible == null) {
      return null;
    }
    final base = _headerBottom(viewport, includeSupplier: false);
    double topOf(RenderBox box) =>
        box.localToGlobal(Offset.zero, ancestor: viewport).dy;

    for (var box = list.firstChild; box != null; box = list.childAfter(box)) {
      final top = topOf(box);
      if (top > base) return null;
      if (top + box.size.height <= base) continue;

      final index = list.indexOf(box);
      final row = visible.rows[index];
      if (top == base && row.group != null) return null;
      final groupIndex = row.group != null
          ? index
          : visible.indexByKey[row.ancestorKeys.firstOrNull];
      if (groupIndex == null) return null;
      // Look only at the laid-out cache for the next heading. If the next
      // heading is farther away, the current one has room at its full height.
      var remainingGroup = double.infinity;
      for (
        var next = list.childAfter(box);
        next != null;
        next = list.childAfter(next)
      ) {
        if (visible.rows[list.indexOf(next)].group != null) {
          remainingGroup = topOf(next) - base;
          break;
        }
      }
      final last = list.lastChild!;
      if (list.indexOf(last) == visible.rows.length - 1) {
        remainingGroup = math.min(
          remainingGroup,
          topOf(last) + last.size.height - base,
        );
      }
      return (
        entry: visible.rows[groupIndex],
        groupEnd: list.constraints.scrollOffset + remainingGroup,
      );
    }
    return null;
  }

  _ReadingAnchor? _captureAnchor() {
    final scroll = widget.scrollController;
    final list = _renderList;
    final viewport = RenderAbstractViewport.maybeOf(list);
    final visible = _laidOut;
    if (!scroll.hasClients ||
        list == null ||
        viewport == null ||
        visible == null) {
      return null;
    }
    final position = scroll.position;
    if (!position.hasContentDimensions ||
        position.pixels <= position.minScrollExtent + _precision) {
      return null;
    }

    final headerBottom = _headerBottom(viewport);
    for (var box = list.firstChild; box != null; box = list.childAfter(box)) {
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top >= position.viewportDimension) break;
      if (top + box.size.height - _rowGap <= headerBottom) continue;
      final index = list.indexOf(box);
      final row = visible.rows[index];
      return _ReadingAnchor(
        key: row.key,
        owner: row.ownerKey,
        pair: row.pairKey,
        source: row.group == null ? row.sourceKey : null,
        ancestors: row.ancestorKeys,
        neighbors: [
          if (index + 1 < visible.rows.length) visible.rows[index + 1].key,
          if (index > 0) visible.rows[index - 1].key,
        ],
        offset: top - headerBottom,
        position: position,
        box: box,
      );
    }
    return null;
  }

  void _scheduleCorrection() {
    if (_correctionScheduled ||
        !_routeVisible ||
        (_anchor == null &&
            _restoreBrowseOffset == null &&
            _supplierReveal == null &&
            !_goToTop)) {
      return;
    }
    _correctionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_restoreAnchor);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  int? _anchorIndex(_ReadingAnchor anchor, SuppliersByItemVisibleRows rows) {
    final exact = rows.indexByKey[anchor.resolvedKey ?? anchor.key];
    if (exact != null) return exact;
    for (final key in [
      ...anchor.ancestors.reversed,
      if (anchor.owner case final owner?) owner,
      ...anchor.neighbors,
    ]) {
      final index = rows.indexByKey[key];
      if (index != null) return index;
    }
    return rows.rows.isEmpty ? null : 0;
  }

  void _restoreAnchor(Duration _) {
    _correctionScheduled = false;
    if (!mounted || !_routeVisible) return;
    final scroll = widget.scrollController;
    if (!scroll.hasClients || !scroll.position.hasContentDimensions) return;
    final position = scroll.position;
    if (_goToTop) {
      _goToTop = false;
      scroll.jumpTo(position.minScrollExtent);
      return;
    }
    if (_restoreBrowseOffset case final offset?) {
      if (_laidOut == null) return;
      final target = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() > _precision) {
        scroll.jumpTo(target);
        // A lazy list can extend its estimated scroll limit on this layout.
        _scheduleCorrection();
      } else {
        _restoreBrowseOffset = null;
        _scheduleCorrection();
      }
      return;
    }
    if (_supplierReveal case final reveal?) {
      _revealDirectSuppliers(reveal.item, reveal.lastSupplier, position);
      return;
    }

    final anchor = _anchor;
    if (anchor == null) return;
    if (_supplierHeaderChanged) {
      _supplierHeaderChanged = false;
      _scheduleCorrection();
      return;
    }
    if (!identical(position, anchor.position)) {
      cancelAnchor();
      return;
    }
    final visible = _laidOut;
    if (visible == null) return;
    if (anchor.resolveOccurrence) {
      anchor.resolveOccurrence = false;
      anchor.resolvedKey = widget.controller.revealAnchorOccurrence(
        key: anchor.key,
        ownerKey: anchor.owner,
        pairKey: anchor.pair,
        sourceKey: anchor.source,
      );
      if (anchor.resolvedKey != null &&
          !visible.indexByKey.containsKey(anchor.resolvedKey)) {
        _scheduleCorrection();
        return;
      }
    }
    final index = _anchorIndex(anchor, visible);
    final list = _renderList;
    final viewport = RenderAbstractViewport.maybeOf(list);
    if (index == null || list == null || viewport == null) {
      cancelAnchor();
      return;
    }
    final first = list.firstChild;
    final last = list.lastChild;
    if (first == null || last == null) return;

    double topOf(RenderBox box) =>
        box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final headerBottom = _headerBottom(viewport);
    final pixels = position.pixels;
    final firstIndex = list.indexOf(first);
    final lastIndex = list.indexOf(last);
    final window = math.max(48.0, position.viewportDimension - headerBottom);
    if (index < firstIndex || index > lastIndex) {
      anchor.evicted = true;
      anchor.hasAligned = false;
      if (!anchor.seekFrames.add((
        first: firstIndex,
        last: lastIndex,
        pixels: (pixels / _precision).round(),
      ))) {
        cancelAnchor();
        return;
      }
      final distance = index < firstIndex
          ? firstIndex - index
          : index - lastIndex;
      final measuredExtent =
          (topOf(last) + last.size.height - topOf(first)) /
          (lastIndex - firstIndex + 1);
      final double delta;
      if (anchor.estimatedSeeksLeft > 0 &&
          distance * measuredExtent > 2 * window) {
        anchor.estimatedSeeksLeft--;
        final sample = index < firstIndex
            ? (index: firstIndex, offset: pixels + topOf(first) - headerBottom)
            : (index: lastIndex, offset: pixels + topOf(last) - headerBottom);
        if (sample.index < index) {
          anchor.seekBefore = sample;
        } else {
          anchor.seekAfter = sample;
        }
        // Sample a second area when rows farther away are taller or shorter.
        // If a jump crossed the target, interpolate from both sides.
        final before = anchor.seekBefore;
        final after = anchor.seekAfter;
        final extent = before != null && after != null
            ? (after.offset - before.offset) / (after.index - before.index)
            : measuredExtent;
        delta = sample.offset - pixels + (index - sample.index) * extent;
      } else {
        delta = index < firstIndex
            ? (topOf(first) - headerBottom - 48).clamp(-window, -48.0)
            : (topOf(last) + last.size.height - headerBottom + 48).clamp(
                48.0,
                window,
              );
      }
      final target = (pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - pixels).abs() > _precision) {
        scroll.jumpTo(target);
        _scheduleCorrection();
      } else {
        cancelAnchor();
      }
      return;
    }

    var child = first;
    while (list.indexOf(child) < index) {
      child = list.childAfter(child)!;
    }
    final rowTop = topOf(child);
    final rowHeight = child.size.height - _rowGap;
    if (!identical(anchor.originalBox.target, child)) anchor.evicted = true;
    final keepSearchOffset =
        anchor.returningFromSearch &&
        visible.rows[index].key == anchor.key &&
        anchor.offset + rowHeight > 0 &&
        headerBottom + anchor.offset < position.viewportDimension;
    final offset = anchor.evicted
        ? math.max(0.0, anchor.offset)
        : anchor.offset;
    final desiredTop =
        headerBottom +
        (keepSearchOffset
            ? anchor.offset
            : offset + rowHeight < 20 ||
                  headerBottom + offset + 20 > position.viewportDimension
            ? 0.0
            : offset);
    final target = (pixels + rowTop - desiredTop).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final needsCorrection = (target - pixels).abs() > _precision;
    if (needsCorrection) scroll.jumpTo(target);

    if (anchor.hasAligned && !needsCorrection) {
      // At this point any discrepancy is constrained by a real scroll limit.
      assert(
        keepSearchOffset ||
            !anchor.evicted ||
            rowTop >= headerBottom - _precision ||
            ((pixels - position.maxScrollExtent).abs() <= _precision ||
                (pixels - position.minScrollExtent).abs() <= _precision),
      );
      _anchor = null;
    } else {
      anchor.hasAligned = true;
      _scheduleCorrection();
    }
  }

  Widget _groupTile(
    SuppliersByItemLayoutRow row,
    SuppliersByItemFieldVisibility fields,
  ) {
    final view = widget.controller;
    return SuppliersByItemDisplayTile(
      entry: row,
      shows: fields.shows,
      includeDrafts: view.filters.value.includeDrafts,
      supplierFilterActive: view.filters.value.suppliers.isNotEmpty,
      expanded: view.isBranchExpanded(row.key),
      evidenceExpanded: false,
      onToggleBranch: view.canToggleBranchKey(row.key)
          ? () => _toggleBranch(row)
          : null,
      onToggleEvidence: () {},
    );
  }

  void _toggleBranch(SuppliersByItemLayoutRow row) {
    cancelAnchor();
    final view = widget.controller;
    view.toggleBranchKey(row.key);
    if (!view.isBranchExpanded(row.key)) return;
    final visible = view.visibleRows.indexByKey;
    for (final child in row.children.reversed) {
      if (child.group == null &&
          child.node.row.kind == SuppliersByItemRowKind.supplier &&
          visible.containsKey(child.key)) {
        _supplierReveal = (item: row.key, lastSupplier: child.key);
        return;
      }
    }
  }

  void _revealDirectSuppliers(
    SuppliersByItemRowKey item,
    SuppliersByItemRowKey lastSupplier,
    ScrollPosition position,
  ) {
    final list = _renderList;
    final viewport = RenderAbstractViewport.maybeOf(list);
    final itemIndex = _laidOut?.indexByKey[item];
    final supplierIndex = _laidOut?.indexByKey[lastSupplier];
    _supplierReveal = null;
    if (list == null ||
        viewport == null ||
        itemIndex == null ||
        supplierIndex == null) {
      return;
    }

    RenderBox? itemBox;
    RenderBox? lastBox;
    for (var box = list.firstChild; box != null; box = list.childAfter(box)) {
      final index = list.indexOf(box);
      if (index == itemIndex) itemBox = box;
      if (index > supplierIndex) break;
      lastBox = box;
    }
    if (itemBox == null || lastBox == null) return;

    final itemTop = itemBox.localToGlobal(Offset.zero, ancestor: viewport).dy;
    // If the last supplier is outside the lazy list's cache, move only as far
    // as the measured rows require and recheck after the next layout.
    final supplierBottom = lastBox
        .localToGlobal(
          Offset(0, lastBox.size.height - _rowGap),
          ancestor: viewport,
        )
        .dy;
    final delta = math.min(
      supplierBottom - (position.viewportDimension - widget.bottomPadding),
      itemTop - _headerBottom(viewport),
    );
    final target = math.min(position.pixels + delta, position.maxScrollExtent);
    if (target - position.pixels <= _precision) return;
    position.jumpTo(target);
    _supplierReveal = (item: item, lastSupplier: lastSupplier);
    _scheduleCorrection();
  }

  @override
  Widget build(BuildContext context) {
    _routeVisible = TickerMode.valuesOf(context).enabled;
    final visible = widget.visible;
    final rows = visible?.rows ?? const <SuppliersByItemLayoutRow>[];
    final view = widget.controller;
    final filters = view.filters.value;
    final indexByKey = visible?.indexByKey ?? const {};
    final columnRuns = suppliersByItemColumnRuns(rows, widget.fields.shows);
    final list = SliverList.builder(
      key: _listKey,
      itemCount: rows.length,
      findChildIndexCallback: (key) =>
          key is ValueKey<SuppliersByItemRowKey> ? indexByKey[key.value] : null,
      itemBuilder: (context, index) {
        final row = rows[index];
        final key = row.key;
        final pair = row.pairKey;
        final parentIndex = indexByKey[row.parentKey];
        final parent = parentIndex == null ? null : rows[parentIndex];
        final ownerIndex = indexByKey[parent?.parentKey];
        return Padding(
          key: key is ({String nodeId})
              ? ValueKey(key)
              : ValueKey<SuppliersByItemRowKey>(key),
          padding: const EdgeInsets.only(bottom: _rowGap),
          child: row.group == null
              ? SuppliersByItemDisplayTile(
                  entry: row,
                  shows: widget.fields.shows,
                  includeDrafts: filters.includeDrafts,
                  supplierFilterActive: filters.suppliers.isNotEmpty,
                  expanded: view.isBranchExpanded(key),
                  evidenceExpanded: pair != null && view.isPairExpanded(pair),
                  onToggleBranch: view.canToggleBranchKey(key)
                      ? () => _toggleBranch(row)
                      : null,
                  onToggleEvidence: () {
                    cancelAnchor();
                    if (pair != null) view.togglePair(pair);
                  },
                  columnRun: columnRuns[row.key],
                  parentOutputUom: ownerIndex == null
                      ? null
                      : rows[ownerIndex].node.row.stockUom,
                )
              : ValueListenableBuilder(
                  valueListenable: widget.paintedSupplier,
                  child: _groupTile(row, widget.fields),
                  builder: (context, painted, child) => ExcludeSemantics(
                    excluding: painted == row.key,
                    child: child,
                  ),
                ),
        );
      },
    );
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        _laidOut = visible;
        _scheduleSupplierHeader();
        _scheduleCorrection();
        return list;
      },
    );
  }
}
