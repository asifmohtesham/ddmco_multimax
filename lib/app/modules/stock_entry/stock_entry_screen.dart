import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/stock_entry/widgets/stock_entry_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

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

  void _showFilterBottomSheet(BuildContext context) {
    Get.bottomSheet(
      const StockEntryFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface, // M3 Background
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchStockEntries(clear: true),
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // M3 Large App Bar
            SliverAppBar.large(
              title: const Text('Stock Entries'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => _showFilterBottomSheet(context),
                ),
              ],
            ),

            // Search Bar Pinned to top of list
            SliverToBoxAdapter(
              child: Padding(
                // Increased top padding from 0 to 16 for better spacing
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: TextField(
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search ID, Purpose...',
                    prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest, // M3 Search Bar Color
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30), // Pill Shape
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ),
            ),

            // List Content
            Obx(() {
              if (controller.isLoading.value && controller.stockEntries.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (controller.stockEntries.isEmpty) {
                final bool hasFilters = controller.activeFilters.isNotEmpty || controller.searchQuery.value.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            hasFilters ? Icons.filter_alt_off_outlined : Icons.inventory_2_outlined,
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
                            hasFilters
                                ? 'Try adjusting your filters or search query.'
                                : 'Pull to refresh or create a new one.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
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
                              onPressed: () => controller.fetchStockEntries(clear: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    if (index >= controller.stockEntries.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final entry = controller.stockEntries[index];
                    return StockEntryCard(entry: entry);
                  },
                  childCount: controller.stockEntries.length + (controller.hasMore.value ? 1 : 0),
                ),
              );
            }),
          ],
        ),
      ),
      // Create button with Dynamic Permission Guard
      floatingActionButton: Obx(() => RoleGuard(
        roles: controller.writeRoles.toList(), // Access list content to trigger Obx
        child: FloatingActionButton.extended(
          onPressed: controller.openCreateDialog,
          icon: const Icon(Icons.add),
          label: const Text('Create'),
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          elevation: 4,
        ),
      )),
    );
  }
}

class StockEntryCard extends StatelessWidget {
  final dynamic entry;
  final StockEntryController controller = Get.find();

  StockEntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 0, // M3 Filled Card style (flat with color)
      color: colorScheme.surfaceContainer, // Distinct from background
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => controller.toggleExpand(entry.name),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Purpose (Title) + Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.purpose,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.name,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: entry.status),
                ],
              ),

              const SizedBox(height: 16),

              // Row 2: Stats (Total Qty, Time)
              Row(
                children: [
                  _buildIconStat(
                    context,
                    Icons.inventory_2_outlined,
                    '${entry.customTotalQty?.toStringAsFixed(2) ?? "0"} Items',
                  ),
                  const SizedBox(width: 16),
                  _buildIconStat(
                    context,
                    Icons.access_time,
                    FormattingHelper.getRelativeTime(entry.creation),
                  ),
                  const Spacer(),
                  // Animated Arrow
                  Obx(() {
                    final isCurrentlyExpanded = controller.expandedEntryName.value == entry.name;
                    return AnimatedRotation(
                      turns: isCurrentlyExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(Icons.expand_more, color: colorScheme.onSurfaceVariant),
                    );
                  }),
                ],
              ),

              // Expansion Content
              Obx(() {
                final isCurrentlyExpanded = controller.expandedEntryName.value == entry.name;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: !isCurrentlyExpanded
                      ? const SizedBox.shrink()
                      : Column(
                    children: [
                      // Divider with padding
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: colorScheme.outlineVariant, height: 1),
                      ),
                      _buildExpandedDetails(context),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetails(BuildContext context) {
    return Obx(() {
      final detailed = controller.detailedEntry;
      if (controller.isLoadingDetails.value && detailed?.name != entry.name) {
        return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()));
      }

      if (detailed != null && detailed.name == entry.name) {
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
                  child: _buildDetailField(context, 'Type', detailed.stockEntryType ?? '-'),
                ),
                Expanded(
                  child: _buildDetailField(context, 'Posting Date',
                      '${detailed.postingDate} ${detailed.postingTime ?? ''}'),
                ),
                if (detailed.totalAmount > 0)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Total Value',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(
                          '\$${detailed.totalAmount.toStringAsFixed(2)}',
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
                          arguments: {'name': entry.name, 'mode': 'edit'}),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: () => Get.toNamed(AppRoutes.STOCK_ENTRY_FORM,
                        arguments: {'name': entry.name, 'mode': 'view'}),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View Details'),
                  ),
                ]
              ],
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    });
  }

  Widget _buildIconStat(BuildContext context, IconData icon, String text) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}