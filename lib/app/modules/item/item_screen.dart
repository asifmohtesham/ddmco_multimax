import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/item/widgets/item_list_app_bar.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';

class ItemScreen extends StatefulWidget {
  const ItemScreen({super.key});

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  final ItemController controller = Get.find();
  final _scrollController = ScrollController();
  final String _baseUrl = Get.find<ApiProvider>().baseUrl;

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
      controller.fetchItems(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchItems(clear: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── DocTypeListAppBar (collapsing title + search + filter chips) ──
            const ItemListAppBar(),

            // ── Content ──────────────────────────────────────────────────────
            Obx(() {
              // Loading state (initial fetch)
              if (controller.isLoading.value &&
                  controller.displayedItems.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              // Empty state
              if (controller.displayedItems.isEmpty) {
                return _buildEmptyState(context, colorScheme);
              }

              // Grid view
              if (controller.isGridView.value) {
                return SliverPadding(
                  padding: const EdgeInsets.all(8.0),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= controller.displayedItems.length) {
                          return const SizedBox.shrink();
                        }
                        return _buildGridCard(
                            controller.displayedItems[index]);
                      },
                      childCount: controller.displayedItems.length,
                    ),
                  ),
                );
              }

              // List view (with infinite-scroll load-more footer)
              final itemCount = controller.displayedItems.length +
                  (controller.hasMore.value ? 1 : 0);

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= controller.displayedItems.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return _buildListCard(
                        controller.displayedItems[index]);
                  },
                  childCount: itemCount,
                ),
              );
            }),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  // ── empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(
      BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final hasFilters = controller.filterCount > 0;

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
                hasFilters ? 'No Matching Items' : 'No Items Found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasFilters
                    ? 'Try adjusting your filters or search query.'
                    : 'Pull to refresh to load items.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (hasFilters)
                FilledButton.tonalIcon(
                  onPressed: controller.clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear Filters'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: () => controller.fetchItems(clear: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── list card ──────────────────────────────────────────────────────────────

  Widget _buildListCard(Item item) {
    return Obx(() {
      final isExpanded =
          controller.expandedItemName.value == item.name;
      final stockList = controller.getStockFor(item.itemCode);
      final isLoadingStock =
          controller.isLoadingStock.value && isExpanded;

      return GenericDocumentCard(
        title: item.itemName,
        subtitle: item.itemCode,
        status: item.itemGroup,
        leading: _buildImage(item, size: 56),
        isExpanded: isExpanded,
        isLoadingDetails: isLoadingStock,
        onTap: () => controller.toggleExpand(item.name, item.itemCode),
        stats: [
          GenericDocumentCard.buildIconStat(
              context, Icons.emoji_flags, item.countryOfOrigin ?? '-'),
          if (item.variantOf != null)
            GenericDocumentCard.buildIconStat(
                context, Icons.copy, item.variantOf ?? ''),
        ],
        expandedContent: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  item.description!,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black87),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Customer References
            if (item.customerItems.isNotEmpty) ...[
              const Text('Customer References',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ...item.customerItems.map(
                (ci) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(ci.customerName,
                          style: const TextStyle(fontSize: 12)),
                      Text(ci.refCode,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
            ],

            const Text('Stock Balance',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),

            if (stockList == null || stockList.isEmpty)
              const Text(
                'No stock data available.',
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              )
            else
              ...stockList.map(
                (stock) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${stock.warehouse}'
                        '${stock.rack != null ? " (${stock.rack})" : ""}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '${stock.quantity.toStringAsFixed(2)} '
                        '${item.stockUom ?? ''}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: stock.quantity > 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => Get.toNamed(
                  AppRoutes.ITEM_FORM,
                  arguments: {'itemCode': item.itemCode},
                ),
                child: const Text('View Full Details'),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ── grid card ──────────────────────────────────────────────────────────────

  Widget _buildGridCard(Item item) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () => Get.toNamed(
          AppRoutes.ITEM_FORM,
          arguments: {'itemCode': item.itemCode},
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: _buildImage(item, fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.itemCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.grey,
                      fontFeatures: [FontFeature.slashedZero()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── image helper ───────────────────────────────────────────────────────────

  Widget _buildImage(Item item,
      {double? size, BoxFit fit = BoxFit.contain}) {
    if (item.image != null && item.image!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          '$_baseUrl${item.image}',
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (c, o, s) => Container(
            width: size,
            height: size,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined,
                color: Colors.grey),
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade400,
        size: size != null ? size * 0.5 : 30,
      ),
    );
  }
}
