import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock_entry/widgets/stock_entry_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';

class StockEntryScreen extends StatefulWidget {
  const StockEntryScreen({super.key});

  @override
  State<StockEntryScreen> createState() => _StockEntryScreenState();
}

class _StockEntryScreenState extends State<StockEntryScreen> {
  final StockEntryController controller = Get.find();
  final _scrollController = ScrollController();

  /// Drives FAB collapse: true when scrolled more than 80px down.
  final _isFarFromTop = false.obs;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchStockEntries(isLoadMore: true);
    }
    final far =
        _scrollController.hasClients && _scrollController.offset > 80;
    if (_isFarFromTop.value != far) _isFarFromTop.value = far;
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterBottomSheet(BuildContext context) {
    Get.bottomSheet(
      const StockEntryFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  // ---------------------------------------------------------------------------
  // Individual dismissible chips — one per active filter key.
  // ---------------------------------------------------------------------------
  List<Widget> _buildActiveFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final filters = controller.activeFilters;

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(_filterChip(
        context,
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchStockEntries(clear: true);
        },
      ));
    }

    if (filters.containsKey('docstatus')) {
      const labels = {0: 'Draft', 1: 'Submitted', 2: 'Cancelled'};
      final label =
          labels[filters['docstatus']] ?? '${filters['docstatus']}';
      chips.add(_filterChip(
        context,
        icon: Icons.flag_outlined,
        label: 'Status: $label',
        onDeleted: () => controller.removeFilter('docstatus'),
      ));
    }

    if (filters.containsKey('stock_entry_type')) {
      chips.add(_filterChip(
        context,
        icon: Icons.category_outlined,
        label: 'Type: ${filters['stock_entry_type']}',
        onDeleted: () => controller.removeFilter('stock_entry_type'),
      ));
    }

    if (filters.containsKey('purpose')) {
      final val = filters['purpose'];
      final display = val is List && val.length > 1
          ? val[1].toString().replaceAll('%', '')
          : val.toString();
      chips.add(_filterChip(
        context,
        icon: Icons.label_outline,
        label: 'Purpose: $display',
        onDeleted: () => controller.removeFilter('purpose'),
      ));
    }

    if (filters.containsKey('custom_reference_no')) {
      final val = filters['custom_reference_no'];
      final display = val is List && val.length > 1
          ? val[1].toString().replaceAll('%', '')
          : val.toString();
      chips.add(_filterChip(
        context,
        icon: Icons.tag,
        label: 'Ref: $display',
        onDeleted: () => controller.removeFilter('custom_reference_no'),
      ));
    }

    if (filters.containsKey('owner') &&
        filters['owner'].toString().isNotEmpty) {
      chips.add(_filterChip(
        context,
        icon: Icons.person_outline,
        label: 'Owner: ${filters['owner']}',
        onDeleted: () => controller.removeFilter('owner'),
      ));
    }

    if (filters.containsKey('creation')) {
      final f = filters['creation'];
      if (f is List &&
          f.length >= 2 &&
          f[0] == 'between' &&
          f[1] is List &&
          (f[1] as List).length >= 2) {
        final dates = f[1] as List;
        chips.add(_filterChip(
          context,
          icon: Icons.date_range,
          label: '${dates[0]}  →  ${dates[1]}',
          onDeleted: () => controller.removeFilter('creation'),
        ));
      }
    }

    return chips;
  }

  Widget _filterChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onDeleted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
      backgroundColor: colorScheme.secondaryContainer,
      deleteIconColor: colorScheme.onSecondaryContainer,
      onDeleted: onDeleted,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchStockEntries(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ----------------------------------------------------------------
            // AppBar — badge is placed INSIDE the icon via Stack so it never
            // overflows the action bar safe area.
            // ----------------------------------------------------------------
            SliverAppBar.large(
              title: const Text('Stock Entries'),
              actions: [
                Obx(() {
                  final filterCount = controller.activeFilters.length;
                  return IconButton(
                    tooltip: filterCount > 0
                        ? '$filterCount filter${filterCount > 1 ? 's' : ''} active'
                        : 'Filter entries',
                    onPressed: () => _showFilterBottomSheet(context),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          filterCount > 0
                              ? Icons.filter_alt
                              : Icons.filter_list,
                        ),
                        if (filterCount > 0)
                          Positioned(
                            top: -4,
                            right: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                '$filterCount',
                                style: TextStyle(
                                  color: colorScheme.onError,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),

            // ----------------------------------------------------------------
            // Result count row — sits BELOW the AppBar as its own sliver so it
            // has a distinct surface colour and is clearly readable.
            // Shown only when not in initial loading state.
            // ----------------------------------------------------------------
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value &&
                    controller.stockEntries.isEmpty) {
                  return const SizedBox.shrink();
                }
                final count = controller.stockEntries.length;
                final hasMore = controller.hasMore.value;
                final hasFilters = controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
                return Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          // Distinct tonal surface so the label floats above
                          // the page background rather than blending into it.
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 14,
                              color: colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasMore
                                  ? '$count+ entries'
                                  : '$count entr${count == 1 ? 'y' : 'ies'}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (hasFilters) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.filter_alt,
                                size: 12,
                                color: colorScheme.onSecondaryContainer
                                    .withOpacity(0.7),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),

            // Search Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Obx(() => SearchBar(
                      hintText: 'Search ID, Purpose...',
                      leading: const Icon(Icons.search),
                      onChanged: controller.onSearchChanged,
                      trailing: [
                        if (controller.searchQuery.value.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: () {
                              controller.searchQuery.value = '';
                              controller.fetchStockEntries(clear: true);
                            },
                          ),
                      ],
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor: WidgetStatePropertyAll(
                        colorScheme.surfaceContainerHighest,
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    )),
              ),
            ),

            // Active filter chips
            SliverToBoxAdapter(
              child: Obx(() {
                final hasFilters = controller.activeFilters.isNotEmpty;
                final hasSearch =
                    controller.searchQuery.value.isNotEmpty;
                if (!hasFilters && !hasSearch) {
                  return const SizedBox.shrink();
                }
                final chips = _buildActiveFilterChips(context);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...chips,
                      if (chips.length > 1)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            visualDensity: VisualDensity.compact,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: controller.clearFilters,
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text('Clear all'),
                        ),
                    ],
                  ),
                );
              }),
            ),

            // ----------------------------------------------------------------
            // List Content
            // ----------------------------------------------------------------
            Obx(() {
              if (controller.isLoading.value &&
                  controller.stockEntries.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.stockEntries.isEmpty) {
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
                  if (af.containsKey('stock_entry_type')) {
                    parts.add('Type: ${af['stock_entry_type']}');
                  }
                  if (controller.searchQuery.value.isNotEmpty) {
                    parts.add(
                        'Search: "${controller.searchQuery.value}"');
                  }
                  emptySubtitle = parts.isNotEmpty
                      ? 'No entries found for ${parts.join(' + ')}.'
                      : 'Try adjusting your filters or search query.';
                } else {
                  emptySubtitle =
                      'Pull to refresh or create a new one.';
                }

                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            hasFilters
                                ? Icons.filter_alt_off_outlined
                                : Icons.inventory_2_outlined,
                            size: 64,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasFilters
                                ? 'No Matching Entries'
                                : 'No Stock Entries',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            emptySubtitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          if (hasFilters)
                            FilledButton.tonalIcon(
                              onPressed: controller.clearFilters,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear Filters'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: () => controller
                                  .fetchStockEntries(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final showLoader = controller.hasMore.value;
              final baseCount = controller.stockEntries.length;
              const extraCount = 1;

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= baseCount) {
                      if (showLoader) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(
                          child: Text(
                            'End of results',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    final entry = controller.stockEntries[index];

                    return Obx(() {
                      final isExpanded =
                          controller.expandedEntryName.value ==
                              entry.name;
                      final isLoadingDetails =
                          controller.isLoadingDetails.value &&
                              controller.detailedEntry?.name != entry.name;

                      // Build warehouse stat inline — available from list
                      // API now that from_warehouse is in the fields list.
                      // Shows source warehouse; falls back to destination
                      // for receipts (no from_warehouse).
                      final warehouseLabel =
                          entry.fromWarehouse?.isNotEmpty == true
                              ? entry.fromWarehouse!
                              : entry.toWarehouse?.isNotEmpty == true
                                  ? entry.toWarehouse!
                                  : null;

                      return GenericDocumentCard(
                        title: entry.purpose,
                        subtitle: entry.name,
                        status: entry.status,
                        stats: [
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.inventory_2_outlined,
                            '${entry.customTotalQty?.toStringAsFixed(0) ?? "0"} Items',
                          ),
                          if (warehouseLabel != null)
                            GenericDocumentCard.buildIconStat(
                              context,
                              Icons.warehouse_outlined,
                              warehouseLabel,
                            ),
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.calendar_today_outlined,
                            entry.postingDate.isNotEmpty
                                ? entry.postingDate
                                : FormattingHelper
                                    .getRelativeTime(entry.creation),
                          ),
                        ],
                        isExpanded: isExpanded,
                        isLoadingDetails: isLoadingDetails && isExpanded,
                        onTap: () =>
                            controller.toggleExpand(entry.name),
                        expandedContent: isExpanded
                            ? _buildDetailedContent(
                                context, entry.name)
                            : null,
                      );
                    });
                  },
                  childCount: baseCount + extraCount,
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: Obx(() => RoleGuard(
            roles: controller.writeRoles.toList(),
            child: _isFarFromTop.value
                ? FloatingActionButton(
                    onPressed: controller.openCreateDialog,
                    tooltip: 'Create Stock Entry',
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 4,
                    child: const Icon(Icons.add),
                  )
                : FloatingActionButton.extended(
                    onPressed: controller.openCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 4,
                  ),
          )),
    );
  }

  // ---------------------------------------------------------------------------
  // Expanded section — flattened to a tight info grid directly on the card
  // surface. No nested tonal containers. Sections separated by slim dividers.
  // Layout:
  //   [row] Warehouse flow  (from → to) if both exist
  //   [row] Posted date  |  Total value
  //   [row] Audit trail (created / modified)
  //   [row] Action button (right-aligned)
  // ---------------------------------------------------------------------------
  Widget _buildDetailedContent(BuildContext context, String entryName) {
    return Obx(() {
      final detailed = controller.detailedEntry;
      if (detailed == null || detailed.name != entryName) {
        return const SizedBox.shrink();
      }

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final labelStyle = theme.textTheme.labelSmall
          ?.copyWith(color: colorScheme.onSurfaceVariant);
      final valueStyle = theme.textTheme.bodySmall
          ?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Warehouse flow row (only when BOTH warehouses present) ──────
          if (detailed.fromWarehouse != null &&
              detailed.fromWarehouse!.isNotEmpty &&
              detailed.toWarehouse != null &&
              detailed.toWarehouse!.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: _infoCell(
                    context,
                    label: 'FROM',
                    value: detailed.fromWarehouse!,
                    icon: Icons.output_outlined,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward,
                      size: 14, color: colorScheme.outline),
                ),
                Expanded(
                  child: _infoCell(
                    context,
                    label: 'TO',
                    value: detailed.toWarehouse!,
                    icon: Icons.input_outlined,
                    alignRight: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
          ],

          // ── Posted date + total value ────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _infoCell(
                  context,
                  label: 'POSTED',
                  value: FormattingHelper.getRelativeTime(
                      '${detailed.postingDate} ${detailed.postingTime ?? ''}'),
                  icon: Icons.schedule_outlined,
                ),
              ),
              if (detailed.totalAmount > 0)
                Expanded(
                  child: _infoCell(
                    context,
                    label: 'TOTAL VALUE',
                    value:
                        '${FormattingHelper.getCurrencySymbol(detailed.currency)} '
                        '${NumberFormat.decimalPatternDigits(decimalDigits: 2).format(detailed.totalAmount)}',
                    icon: Icons.payments_outlined,
                    valueColor: colorScheme.primary,
                    alignRight: true,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 10),

          // ── Audit trail ──────────────────────────────────────────────────
          _buildAuditRow(
              context, 'Created', detailed.owner, detailed.creation),
          if (detailed.modifiedBy != null &&
              detailed.modified.isNotEmpty &&
              detailed.creation != detailed.modified) ...[
            const SizedBox(height: 4),
            _buildAuditRow(context, 'Modified', detailed.modifiedBy,
                detailed.modified),
          ],

          const SizedBox(height: 12),

          // ── Action button ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.status == 'Draft')
                RoleGuard(
                  roles: controller.writeRoles.toList(),
                  fallback: const SizedBox.shrink(),
                  child: FilledButton.tonalIcon(
                    onPressed: () => Get.toNamed(
                      AppRoutes.STOCK_ENTRY_FORM,
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
                    AppRoutes.STOCK_ENTRY_FORM,
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

  // ── Flat two-line info cell (label + value), optionally right-aligned ──────
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
          mainAxisAlignment: alignRight
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
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

  // ── Compact single-line audit row ─────────────────────────────────────────
  Widget _buildAuditRow(
      BuildContext context, String action, String? user, String date) {
    if (user == null || user.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(
          action == 'Created'
              ? Icons.add_circle_outline
              : Icons.edit_outlined,
          size: 13,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant, fontSize: 11),
              children: [
                TextSpan(text: '$action by '),
                TextSpan(
                  text: user,
                  style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        Text(
          FormattingHelper.getRelativeTime(date),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: colorScheme.outline, fontSize: 10),
        ),
      ],
    );
  }
}
