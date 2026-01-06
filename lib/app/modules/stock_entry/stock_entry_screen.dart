import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock_entry/widgets/stock_entry_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class StockEntryScreen extends StatefulWidget {
  const StockEntryScreen({super.key});

  @override
  State<StockEntryScreen> createState() => _StockEntryScreenState();
}

class _StockEntryScreenState extends State<StockEntryScreen> {
  final StockEntryController controller = Get.find();
  final _scrollController = ScrollController();

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
    if (_isBottom && controller.hasMore.value && !controller.isFetchingMore.value) {
      controller.fetchStockEntries(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterBottomSheet() {
    Get.bottomSheet(
      const StockEntryFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasFilters = controller.activeFilters.isNotEmpty || controller.searchQuery.value.isNotEmpty;

      return GenericListPage(
        title: 'Stock Entries',
        isLoading: controller.isLoading,
        data: controller.stockEntries,
        onRefresh: () => controller.fetchStockEntries(clear: true),
        scrollController: _scrollController,

        // Search & Filter Configuration
        onSearch: controller.onSearchChanged,
        searchHint: 'Search ID, Purpose...',
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterBottomSheet,
          ),
        ],

        // Floating Action Button
        fab: RoleGuard(
          roles: controller.writeRoles.toList(),
          child: FloatingActionButton.extended(
            onPressed: controller.openCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create'),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            elevation: 4,
          ),
        ),

        // Empty State Configuration
        emptyTitle: hasFilters ? 'No Matching Entries' : 'No Stock Entries',
        emptyMessage: hasFilters
            ? 'Try adjusting your filters or search query.'
            : 'Pull to refresh or create a new one.',
        emptyIcon: hasFilters ? Icons.filter_alt_off_outlined : Icons.inventory_2_outlined,
        onClearFilters: hasFilters ? controller.clearFilters : null,

        // Required dummy builder, as we are using sliverBody for custom list behavior
        itemBuilder: (context, index) => const SizedBox.shrink(),

        // Custom Sliver Body to support "Load More" indicator
        sliverBody: SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              // Load More Indicator
              if (index >= controller.stockEntries.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final entry = controller.stockEntries[index];

              // Reactive Card Expansion
              return Obx(() {
                final isExpanded = controller.expandedEntryName.value == entry.name;
                final isLoadingDetails =
                    controller.isLoadingDetails.value && controller.detailedEntry?.name != entry.name;

                return GenericDocumentCard(
                  title: entry.purpose,
                  subtitle: entry.name,
                  status: entry.status,
                  stats: [
                    GenericDocumentCard.buildIconStat(
                      context,
                      Icons.inventory_2_outlined,
                      '${entry.customTotalQty?.toStringAsFixed(2) ?? "0"} Items',
                    ),
                    GenericDocumentCard.buildIconStat(
                      context,
                      Icons.access_time,
                      FormattingHelper.getRelativeTime(entry.creation),
                    ),
                  ],
                  isExpanded: isExpanded,
                  isLoadingDetails: isLoadingDetails && isExpanded,
                  onTap: () => controller.toggleExpand(entry.name),
                  expandedContent: isExpanded ? _buildDetailedContent(context, entry.name) : null,
                );
              });
            },
            childCount: controller.stockEntries.length + (controller.hasMore.value ? 1 : 0),
          ),
        ),
      );
    });
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
                    Expanded(child: _buildWarehouseInfo(context, 'From', detailed.fromWarehouse!)),

                  if (detailed.fromWarehouse != null && detailed.toWarehouse != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Icon(Icons.arrow_forward, size: 18, color: colorScheme.outline),
                    ),

                  if (detailed.toWarehouse != null)
                    Expanded(child: _buildWarehouseInfo(context, 'To', detailed.toWarehouse!)),
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
                    FormattingHelper.getRelativeTime('${detailed.postingDate} ${detailed.postingTime ?? ''}')),
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
                              ?.copyWith(color: colorScheme.onSurfaceVariant)),
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

          // Contextual Audit Info (Created/Modified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildAuditRow(context, 'Created', detailed.owner, detailed.creation),
                if (detailed.modifiedBy != null && detailed.modified.isNotEmpty) ...[
                  // Only show modified if it's different from creation
                  if (detailed.creation != detailed.modified)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: _buildAuditRow(context, 'Modified', detailed.modifiedBy, detailed.modified),
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
                        arguments: {'name': detailed.name, 'mode': 'edit'}),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: () => Get.toNamed(AppRoutes.STOCK_ENTRY_FORM,
                      arguments: {'name': detailed.name, 'mode': 'view'}),
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

  Widget _buildAuditRow(BuildContext context, String action, String? user, String date) {
    if (user == null || user.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          action == 'Created' ? Icons.add_circle_outline : Icons.edit_outlined,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 12),
              children: [
                TextSpan(text: '$action by '),
                TextSpan(
                  text: user,
                  style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          FormattingHelper.getRelativeTime(date),
          style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
      ],
    );
  }

  Widget _buildWarehouseInfo(BuildContext context, String label, String value) {
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildDetailField(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}