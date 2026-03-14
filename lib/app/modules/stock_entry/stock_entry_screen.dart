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
    // Infinite-scroll trigger at 90% of list
    if (_isBottom && controller.hasMore.value && !controller.isFetchingMore.value) {
      controller.fetchStockEntries(isLoadMore: true);
    }
    // FAB collapse/expand based on scroll position
    final far = _scrollController.hasClients && _scrollController.offset > 80;
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
  // Build individual dismissible chips for every active filter.
  // Each chip shows the human-readable label & value and can be removed
  // independently — no need to reopen the filter sheet.
  // ---------------------------------------------------------------------------
  List<Widget> _buildActiveFilterChips(BuildContext context) {
    final chips = <Widget>[];
    final filters = controller.activeFilters;

    // Search chip
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

    // Status (docstatus)
    if (filters.containsKey('docstatus')) {
      const labels = {0: 'Draft', 1: 'Submitted', 2: 'Cancelled'};
      final label = labels[filters['docstatus']] ?? '${filters['docstatus']}';
      chips.add(_filterChip(
        context,
        icon: Icons.flag_outlined,
        label: 'Status: $label',
        onDeleted: () => controller.removeFilter('docstatus'),
      ));
    }

    // Stock Entry Type
    if (filters.containsKey('stock_entry_type')) {
      chips.add(_filterChip(
        context,
        icon: Icons.category_outlined,
        label: 'Type: ${filters['stock_entry_type']}',
        onDeleted: () => controller.removeFilter('stock_entry_type'),
      ));
    }

    // Purpose
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

    // Reference No
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

    // Owner
    if (filters.containsKey('owner') &&
        filters['owner'].toString().isNotEmpty) {
      chips.add(_filterChip(
        context,
        icon: Icons.person_outline,
        label: 'Owner: ${filters['owner']}',
        onDeleted: () => controller.removeFilter('owner'),
      ));
    }

    // Date Range
    if (filters.containsKey('creation')) {
      final creationFilter = filters['creation'];
      if (creationFilter is List &&
          creationFilter.length >= 2 &&
          creationFilter[0] == 'between' &&
          creationFilter[1] is List &&
          (creationFilter[1] as List).length >= 2) {
        final dates = creationFilter[1] as List;
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
            // M3 Large App Bar
            // • Filter icon is badged with active filter count (GetX Obx)
            // • Tooltip added for accessibility
            // • Result count shown as subtitle via flexibleSpace bottom
            // ----------------------------------------------------------------
            SliverAppBar.large(
              title: const Text('Stock Entries'),
              actions: [
                Obx(() {
                  final filterCount = controller.activeFilters.length;
                  return Badge(
                    label: Text('$filterCount'),
                    isLabelVisible: filterCount > 0,
                    child: IconButton(
                      tooltip: filterCount > 0
                          ? '$filterCount filter${filterCount > 1 ? 's' : ''} active'
                          : 'Filter entries',
                      icon: Icon(
                        filterCount > 0
                            ? Icons.filter_alt
                            : Icons.filter_list,
                      ),
                      onPressed: () => _showFilterBottomSheet(context),
                    ),
                  );
                }),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Obx(() {
                  final count = controller.stockEntries.length;
                  final hasMore = controller.hasMore.value;
                  if (controller.isLoading.value) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hasMore ? '$count+ entries' : '$count entries',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ----------------------------------------------------------------
            // Search Bar — uses M3 SearchBar widget
            // Debounce is already handled in controller.onSearchChanged (500ms)
            // ----------------------------------------------------------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

            // ----------------------------------------------------------------
            // Active filter chips — individual per-filter, each self-dismissible
            // A "Clear all" button is appended when multiple filters are active
            // ----------------------------------------------------------------
            SliverToBoxAdapter(
              child: Obx(() {
                final hasFilters = controller.activeFilters.isNotEmpty;
                final hasSearch = controller.searchQuery.value.isNotEmpty;
                if (!hasFilters && !hasSearch) return const SizedBox.shrink();

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
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            controller.clearFilters();
                          },
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
              if (controller.isLoading.value && controller.stockEntries.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.stockEntries.isEmpty) {
                final bool hasFilters = controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;

                // Build descriptive contextual message listing active filters
                String emptySubtitle;
                if (hasFilters) {
                  final parts = <String>[];
                  final af = controller.activeFilters;
                  if (af.containsKey('docstatus')) {
                    const labels = {0: 'Draft', 1: 'Submitted', 2: 'Cancelled'};
                    parts.add('Status: ${labels[af['docstatus']] ?? af['docstatus']}');
                  }
                  if (af.containsKey('stock_entry_type')) {
                    parts.add('Type: ${af['stock_entry_type']}');
                  }
                  if (controller.searchQuery.value.isNotEmpty) {
                    parts.add('Search: "${controller.searchQuery.value}"');
                  }
                  emptySubtitle = parts.isNotEmpty
                      ? 'No entries found for ${parts.join(' + ')}.'
                      : 'Try adjusting your filters or search query.';
                } else {
                  emptySubtitle = 'Pull to refresh or create a new one.';
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
                            hasFilters ? 'No Matching Entries' : 'No Stock Entries',
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
                              onPressed: () => controller.clearFilters(),
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear Filters'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  controller.fetchStockEntries(clear: true),
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
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
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
                          controller.expandedEntryName.value == entry.name;
                      final isLoadingDetails = controller.isLoadingDetails.value &&
                          controller.detailedEntry?.name != entry.name;

                      return GenericDocumentCard(
                        title: entry.purpose,
                        subtitle: entry.name,
                        status: entry.status,
                        // postingDate is more meaningful to warehouse staff
                        // than the system creation timestamp
                        stats: [
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.inventory_2_outlined,
                            '${entry.customTotalQty?.toStringAsFixed(2) ?? "0"} Items',
                          ),
                          GenericDocumentCard.buildIconStat(
                            context,
                            Icons.calendar_today_outlined,
                            entry.postingDate?.isNotEmpty == true
                                ? entry.postingDate!
                                : FormattingHelper.getRelativeTime(entry.creation),
                          ),
                        ],
                        isExpanded: isExpanded,
                        isLoadingDetails: isLoadingDetails && isExpanded,
                        onTap: () => controller.toggleExpand(entry.name),
                        expandedContent: isExpanded
                            ? _buildDetailedContent(context, entry.name)
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
      // -----------------------------------------------------------------------
      // FAB: collapses to a compact icon-only button when user scrolls down,
      // recovering list real-estate on long result sets.
      // Role guard is unchanged — only writers see the FAB.
      // -----------------------------------------------------------------------
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

  Widget _buildDetailedContent(BuildContext context, String entryName) {
    return Obx(() {
      final detailed = controller.detailedEntry;
      if (detailed == null || detailed.name != entryName) {
        return const SizedBox.shrink();
      }

      final colorScheme = Theme.of(context).colorScheme;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warehouse Flow (Source -> Target)
          if (detailed.fromWarehouse != null || detailed.toWarehouse != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (detailed.fromWarehouse != null)
                    Expanded(
                        child: _buildWarehouseInfo(
                            context, 'From', detailed.fromWarehouse!)),
                  if (detailed.fromWarehouse != null &&
                      detailed.toWarehouse != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Icon(Icons.arrow_forward,
                          size: 18, color: colorScheme.outline),
                    ),
                  if (detailed.toWarehouse != null)
                    Expanded(
                        child: _buildWarehouseInfo(
                            context, 'To', detailed.toWarehouse!)),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Additional Details Grid
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDetailField(
                    context,
                    'Posted',
                    FormattingHelper.getRelativeTime(
                        '${detailed.postingDate} ${detailed.postingTime ?? ''}')),
              ),
              if (detailed.totalAmount > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total Value',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        '${FormattingHelper.getCurrencySymbol(detailed.currency)} ${NumberFormat.decimalPatternDigits(decimalDigits: 2).format(detailed.totalAmount)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Audit Info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildAuditRow(
                    context, 'Created', detailed.owner, detailed.creation),
                if (detailed.modifiedBy != null &&
                    detailed.modified.isNotEmpty) ...[
                  if (detailed.creation != detailed.modified)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: _buildAuditRow(context, 'Modified',
                          detailed.modifiedBy, detailed.modified),
                    ),
                ]
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (detailed.status == 'Draft') ...[
                RoleGuard(
                  roles: controller.writeRoles.toList(),
                  fallback: const SizedBox.shrink(),
                  child: FilledButton.tonalIcon(
                    onPressed: () => Get.toNamed(AppRoutes.STOCK_ENTRY_FORM,
                        arguments: {
                          'name': detailed.name,
                          'mode': 'edit'
                        }),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.STOCK_ENTRY_FORM,
                      arguments: {
                        'name': detailed.name,
                        'mode': 'view'
                      }),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View Details'),
                ),
              ]
            ],
          ),
        ],
      );
    });
  }

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
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 12),
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
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          FormattingHelper.getRelativeTime(date),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: colorScheme.outline),
        ),
      ],
    );
  }

  Widget _buildWarehouseInfo(
      BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                )),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildDetailField(
      BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
