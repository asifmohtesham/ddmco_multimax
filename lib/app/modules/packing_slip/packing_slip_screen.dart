import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/result_count_pill.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Packing Slip list screen.
///
/// ## Interaction model
/// Each slip card uses the same expand-panel pattern as [StockEntryScreen]
/// and [DeliveryNoteScreen]:
/// - **Tap** → [PackingSlipController.toggleExpand] expands/collapses the
///   card in place via [GenericDocumentCard.expandedContent].
/// - Inside the panel: a **View** (or **Edit** for Draft slips) CTA
///   navigates to [AppRoutes.PACKING_SLIP_FORM].
///
/// This replaces the previous direct-navigation-on-tap behaviour that caused
/// the [Icons.expand_more] chevron to be a false affordance.
///
/// ## UI/UX contract
/// Do **not** revert the card tap to direct navigation. The [AnimatedRotation]
/// chevron in [GenericDocumentCard] is truthful only when [onTap] toggles
/// the expand panel. Any change to the interaction model must be applied
/// identically to [StockEntryScreen] and [DeliveryNoteScreen] for consistency.
class PackingSlipScreen extends StatefulWidget {
  const PackingSlipScreen({super.key});

  @override
  State<PackingSlipScreen> createState() => _PackingSlipScreenState();
}

class _PackingSlipScreenState extends State<PackingSlipScreen> {
  final PackingSlipController controller = Get.find();
  final _scrollController = ScrollController();
  final _isFarFromTop = false.obs;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _fetchSnackBar;
  Worker? _fetchSnackBarWorker;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _fetchSnackBarWorker?.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (controller.searchQuery.value.isEmpty &&
        _isBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchPackingSlips(isLoadMore: true);
    }
    final far = _scrollController.hasClients && _scrollController.offset > 80;
    if (_isFarFromTop.value != far) _isFarFromTop.value = far;
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterSheet() {
    Get.bottomSheet(
      const PackingSlipFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  /// Builds dismissible filter chips for every active filter + search query.
  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final filters = controller.activeFilters;

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(_chip(
        context,
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchPackingSlips(clear: true);
        },
      ));
    }

    if (filters.containsKey('docstatus')) {
      const labels = {0: 'Draft', 1: 'Submitted', 2: 'Cancelled'};
      final label = labels[filters['docstatus']] ?? '${filters['docstatus']}';
      chips.add(_chip(
        context,
        icon: Icons.flag_outlined,
        label: 'Status: $label',
        onDeleted: () => controller.removeFilter('docstatus'),
      ));
    }

    if (filters.containsKey('delivery_note')) {
      chips.add(_chip(
        context,
        icon: Icons.local_shipping_outlined,
        label: 'DN: ${filters['delivery_note']}',
        onDeleted: () => controller.removeFilter('delivery_note'),
      ));
    }

    if (filters.containsKey('custom_po_no')) {
      chips.add(_chip(
        context,
        icon: Icons.tag,
        label: 'PO: ${filters['custom_po_no']}',
        onDeleted: () => controller.removeFilter('custom_po_no'),
      ));
    }

    if (filters.containsKey('posting_date')) {
      final f = filters['posting_date'];
      if (f is List &&
          f.length >= 2 &&
          f[0] == 'between' &&
          f[1] is List &&
          (f[1] as List).length >= 2) {
        final dates = f[1] as List;
        chips.add(_chip(
          context,
          icon: Icons.date_range,
          label: '${dates[0]}  →  ${dates[1]}',
          onDeleted: () => controller.removeFilter('posting_date'),
        ));
      }
    }

    if (filters.containsKey('_sort')) {
      chips.add(_chip(
        context,
        icon: Icons.sort,
        label: 'Sort: ${filters['_sort']}',
        onDeleted: () {
          controller.removeFilter('_sort');
          controller.setSort('creation', 'desc');
        },
      ));
    }

    return chips;
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onDeleted,
  }) {
    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list screen.
    return FilterChipWidget(icon: icon, label: label, onDeleted: onDeleted);
  }

  /// Small pill showing the slip count inside a group header.
  Widget _countPill(int count, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return AppShellScaffold(
      floatingActionButton: Obx(() => DocTypeGuard(
            doctype: 'Packing Slip',
            permType: 'create',
            child: _isFarFromTop.value
                ? FloatingActionButton(
                    onPressed: controller.openCreateDialog,
                    tooltip: 'New Packing Slip',
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 4,
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                    onPressed: controller.openCreateDialog,
                    tooltip: 'New Packing Slip',
                    icon: const Icon(Icons.add),
                    label: const Text('New Packing Slip'),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 4,
                  ),
          )),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchPackingSlips(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Unified header: AppBar + search + filter chips ─────────────
            DocTypeListHeader(
              title: 'Packing Slip',
              automaticallyImplyLeading: false,
              searchQuery: controller.searchQuery,
              onSearchChanged: controller.onSearchChanged,
              onSearchClear: () {
                controller.searchQuery.value = '';
                controller.fetchPackingSlips(clear: true);
              },
              activeFilters: controller.activeFilters,
              onFilterTap: _showFilterSheet,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters: controller.clearFilters,
            ),

            // ── Result count pill ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.packingSlips.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ResultCountPill(
                  count: controller.packingSlips.length,
                  hasMore: controller.hasMore.value,
                  hasActiveFilters: controller.activeFilters.isNotEmpty ||
                      controller.searchQuery.value.isNotEmpty,
                  noun: 'slip',
                  icon: Icons.assignment_return_outlined,
                );
              }),
            ),

            // ── List content ───────────────────────────────────────────────
            Obx(() {
              if (controller.isLoading.value &&
                  controller.packingSlips.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.packingSlips.isEmpty) {
                final bool hasFilters =
                    controller.activeFilters.isNotEmpty ||
                        controller.searchQuery.value.isNotEmpty;
                String emptySubtitle;
                if (hasFilters) {
                  final parts = <String>[];
                  final af = controller.activeFilters;
                  if (af.containsKey('docstatus')) {
                    const labels = {
                      0: 'Draft',
                      1: 'Submitted',
                      2: 'Cancelled'
                    };
                    parts.add(
                        'Status: ${labels[af['docstatus']] ?? af['docstatus']}');
                  }
                  if (af.containsKey('delivery_note')) {
                    parts.add('DN: ${af['delivery_note']}');
                  }
                  if (af.containsKey('custom_po_no')) {
                    parts.add('PO: ${af['custom_po_no']}');
                  }
                  if (controller.searchQuery.value.isNotEmpty) {
                    parts.add('Search: "${controller.searchQuery.value}"');
                  }
                  emptySubtitle = parts.isNotEmpty
                      ? 'No slips found for ${parts.join(' + ')}.'
                      : 'Try adjusting your filters or search query.';
                } else {
                  emptySubtitle = 'Pull to refresh or create a new one.';
                }

                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ListEmptyState(
                    hasActiveFilters: hasFilters,
                    emptyIcon: Icons.assignment_return_outlined,
                    emptyTitle: 'No Packing Slips Found',
                    emptyMessage: emptySubtitle,
                    filteredTitle: 'No Matching Slips',
                    filteredMessage: emptySubtitle,
                    onClearFilters: controller.clearFilters,
                    onReload: () =>
                        controller.fetchPackingSlips(clear: true),
                  ),
                );
              }

              // Touch map length so Obx listens to customer map updates.
              // ignore: unused_local_variable
              final dummyListener = controller.posCustomerMap.length;

              final grouped = controller.groupedPackingSlips;
              final groupKeys = grouped.keys.toList();

              if (groupKeys.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                      child: Text('No results match your search.')),
                );
              }

              final bool showLoader =
                  controller.searchQuery.value.isEmpty &&
                      controller.hasMore.value;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= groupKeys.length) {
                      return ListEndFooter(
                        hasMore: showLoader,
                        bottomPadding: navBarHeight,
                      );
                    }

                    final groupKey = groupKeys[index];
                    final slips = grouped[groupKey]!;

                    String? customerName =
                        slips.isNotEmpty ? slips.first.customer : null;
                    if ((customerName == null || customerName.isEmpty) &&
                        slips.isNotEmpty) {
                      customerName =
                          controller.getCustomerName(slips.first.customPoNo);
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      elevation: 0,
                      color: colorScheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Group Header (tappable) ──────────────────────
                          InkWell(
                            onTap: () => controller.toggleGroup(groupKey),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 12.0),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                border: Border(
                                    bottom: BorderSide(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.5))),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                        Icons.inventory_2_outlined,
                                        size: 16,
                                        color:
                                            colorScheme.onPrimaryContainer),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          groupKey,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (customerName != null &&
                                            customerName.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 2.0),
                                            child: Text(
                                              customerName,
                                              style: theme
                                                  .textTheme.bodySmall
                                                  ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Count pill + animated chevron
                                  Obx(() {
                                    final isCollapsed =
                                        controller.expandedGroup.value ==
                                            groupKey;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _countPill(slips.length, colorScheme),
                                        const SizedBox(width: 6),
                                        AnimatedRotation(
                                          turns: isCollapsed ? 0.5 : 0.0,
                                          duration: const Duration(
                                              milliseconds: 220),
                                          curve: Curves.easeInOut,
                                          child: Icon(
                                            Icons.expand_more,
                                            size: 20,
                                            color: colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),

                          // ── Slip list (animated show/hide) ────────────────
                          Obx(() {
                            final isCollapsed =
                                controller.expandedGroup.value == groupKey;
                            return AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: isCollapsed
                                  ? const SizedBox.shrink()
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: slips.length,
                                      padding: EdgeInsets.zero,
                                      separatorBuilder: (context, index) =>
                                          Divider(
                                        height: 1,
                                        indent: 16,
                                        endIndent: 16,
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                      itemBuilder: (context, slipIndex) {
                                        final slip = slips[slipIndex];
                                        return _buildSlipCard(
                                            context, slip);
                                      },
                                    ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                  childCount: groupKeys.length + 1,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Builds a [GenericDocumentCard] for a single [PackingSlip] row.
  ///
  /// ## Interaction model
  /// [onTap] calls [PackingSlipController.toggleExpand] to expand/collapse
  /// the card in place. Navigation to [AppRoutes.PACKING_SLIP_FORM] is
  /// deferred to the CTA button inside [_buildExpandedContent], matching
  /// the behaviour of [StockEntryScreen] and [DeliveryNoteScreen].
  ///
  /// ## Field mapping
  /// | Slot          | Source field             |
  /// |---------------|--------------------------|
  /// | title         | slip.name                |
  /// | subtitle      | slip.deliveryNote        |
  /// | status        | slip.status              |
  /// | stats[0]      | case range  'Pkg X–Y'   |
  /// | stats[1]      | item count (if > 0)      |
  /// | auditStats[0] | relative creation time   |
  /// | auditStats[1] | owner (if non-empty)     |
  /// | expandedContent | [_buildExpandedContent]|
  Widget _buildSlipCard(BuildContext context, dynamic slip) {
    final cardKey = GlobalKey();

    void showContextMenu() {
      final box = cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final offset = box.localToGlobal(Offset.zero);
      final size = box.size;
      final rect = RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 8,
      );
      final messenger = ScaffoldMessenger.of(context);
      showMenu<String>(
        context: context,
        position: rect,
        items: [
          PopupMenuItem<String>(
            value: 'fetch_all',
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 18),
                const SizedBox(width: 10),
                Text('Fetch all for ${slip.deliveryNote as String}'),
              ],
            ),
          ),
        ],
      ).then((val) {
        if (val == 'fetch_all') {
          final dn = slip.deliveryNote as String;

          _fetchSnackBarWorker?.dispose();
          _fetchSnackBar?.close();

          _fetchSnackBar = messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 30),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fetching all slips for $dn'),
                  const SizedBox(height: 6),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          );

          _fetchSnackBarWorker = ever(controller.isLoading, (bool loading) {
            if (!loading) {
              _fetchSnackBar?.close();
              _fetchSnackBar = null;
              _fetchSnackBarWorker?.dispose();
              _fetchSnackBarWorker = null;
            }
          });

          controller.fetchAllForDeliveryNote(dn);
        }
      });
    }

    final caseRange =
        'Pkg ${slip.fromCaseNo ?? "?"}\u2013${slip.toCaseNo ?? "?"}';

    final stats = <Widget>[
      GenericDocumentCard.buildIconStat(
          context, Icons.filter_none, caseRange),
      if (slip.items != null && (slip.items as List).isNotEmpty)
        GenericDocumentCard.buildIconStat(
          context,
          Icons.inventory_2_outlined,
          '${(slip.items as List).length} '
          'item${(slip.items as List).length == 1 ? '' : 's'}',
        ),
    ];

    final auditStats = <Widget>[
      GenericDocumentCard.buildIconStat(
        context,
        Icons.schedule_outlined,
        FormattingHelper.getRelativeTime(slip.creation),
      ),
      if (slip.owner != null && (slip.owner as String).isNotEmpty)
        GenericDocumentCard.buildIconStat(
          context,
          Icons.person_outline,
          slip.owner as String,
        ),
    ];

    return Obx(() {
      final isExpanded =
          controller.expandedSlipName.value == (slip.name as String);
      final isLoadingDetails = controller.isLoadingDetails.value &&
          controller.detailedSlip.value?.name != slip.name;

      return GenericDocumentCard(
        key: cardKey,
        title: slip.name as String,
        subtitle: slip.deliveryNote as String,
        status: slip.status as String,
        stats: stats,
        auditStats: auditStats,
        isExpanded: isExpanded,
        isLoadingDetails: isLoadingDetails && isExpanded,
        onTap: () => controller.toggleExpand(slip.name as String),
        onLongPress: (slip.deliveryNote as String).isNotEmpty
            ? showContextMenu
            : null,
        expandedContent: isExpanded
            ? _buildExpandedContent(context, slip.name as String)
            : null,
      );
    });
  }

  /// Builds the expand-panel content for a single [PackingSlip].
  ///
  /// Rendered inside [GenericDocumentCard.expandedContent] after
  /// [PackingSlipController.fetchSlipDetails] completes. Shows case range,
  /// Delivery Note reference, item count summary, and a View / Edit CTA.
  ///
  /// ⚠️ UI/UX contract: mirrors [StockEntryScreen._buildDetailedContent].
  /// The layout (divider, info cells, right-aligned CTA row) must remain
  /// consistent across all three list screens.
  Widget _buildExpandedContent(BuildContext context, String slipName) {
    return Obx(() {
      final detailed = controller.detailedSlip.value;
      if (detailed == null || detailed.name != slipName) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      final caseRange =
          'Pkg ${detailed.fromCaseNo ?? "?"}\u2013${detailed.toCaseNo ?? "?"}';
      final itemCount = detailed.items.length;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Case range + DN ref row ────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _infoCell(
                  context,
                  label: 'CASE RANGE',
                  value: caseRange,
                  icon: Icons.filter_none,
                ),
              ),
              if (detailed.deliveryNote.isNotEmpty)
                Expanded(
                  child: _infoCell(
                    context,
                    label: 'DELIVERY NOTE',
                    value: detailed.deliveryNote,
                    icon: Icons.local_shipping_outlined,
                    alignRight: true,
                  ),
                ),
            ],
          ),

          // ── Item count row (only when items are present) ────────────
          if (itemCount > 0) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            _infoCell(
              context,
              label: 'ITEMS',
              value: '$itemCount item${itemCount == 1 ? '' : 's'}',
              icon: Icons.inventory_2_outlined,
            ),
          ],

          // ── CTA row ───────────────────────────────────────────────
          const SizedBox(height: 12),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.status == 'Draft')
                DocTypeGuard(
                  doctype: 'Packing Slip',
                  permType: 'write',
                  fallback: const SizedBox.shrink(),
                  child: FilledButton.tonalIcon(
                    onPressed: () => Get.toNamed(
                      AppRoutes.PACKING_SLIP_FORM,
                      arguments: {
                        'name': detailed.name,
                        'mode': 'edit',
                      },
                    ),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                  ),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(
                    AppRoutes.PACKING_SLIP_FORM,
                    arguments: {
                      'name': detailed.name,
                      'mode': 'view',
                    },
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View Details'),
                ),
            ],
          ),
        ],
      );
    });
  }

  /// Labelled info cell used inside [_buildExpandedContent].
  ///
  /// Copied verbatim from [StockEntryScreen._infoCell] to guarantee visual
  /// consistency across all list screens. Do not modify independently.
  Widget _infoCell(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
    bool alignRight = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!alignRight) ...[
              Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
            if (alignRight) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: valueColor ?? colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignRight ? TextAlign.end : TextAlign.start,
        ),
      ],
    );
  }
}
