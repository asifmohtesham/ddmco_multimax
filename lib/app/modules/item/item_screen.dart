import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/item/widgets/item_list_app_bar.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
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
    // Fix #1: scroll listener removed; infinite scroll is handled by
    // NotificationListener<ScrollEndNotification> in build() instead,
    // which only fires once at scroll end, not on every pixel change.
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── build ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Fix #1: wrap in NotificationListener to fire load-more only once at
    // scroll end, preventing double-fire from _stockLevelsCache obs updates.
    return AppShellScaffold(
      body: NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent * 0.9 &&
              controller.hasMore.value &&
              !controller.isFetchingMore.value) {
            controller.fetchItems(isLoadMore: true);
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: () => controller.fetchItems(clear: true),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const ItemListAppBar(),

              Obx(() {
                if (controller.isLoading.value &&
                    controller.displayedItems.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (controller.displayedItems.isEmpty) {
                  return _buildEmptyState(context, cs);
                }

                // Fix #5: grid view now also has load-more footer
                if (controller.isGridView.value) {
                  return _buildGrid(cs);
                }

                return _buildList();
              }),

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
  }

  // ── grid ──────────────────────────────────────────────────────────────────────

  Widget _buildGrid(ColorScheme cs) {
    final items = controller.displayedItems;
    // +1 slot for the load-more footer when more pages exist
    final cellCount = items.length + (controller.hasMore.value ? 1 : 0);

    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Fix #5: last cell is the load-more spinner
            if (index >= items.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return _buildGridCard(items[index]);
          },
          childCount: cellCount,
        ),
      ),
    );
  }

  // ── list ───────────────────────────────────────────────────────────────────────

  Widget _buildList() {
    final itemCount = controller.displayedItems.length +
        (controller.hasMore.value ? 1 : 0);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= controller.displayedItems.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _buildListCard(controller.displayedItems[index]);
        },
        childCount: itemCount,
      ),
    );
  }

  // ── empty state ────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context, ColorScheme cs) {
    final theme = Theme.of(context);
    final hasFilters = controller.filterCount > 0;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasFilters
                    ? Icons.filter_alt_off_outlined
                    : Icons.inventory_2_outlined,
                size: 64,
                color: cs.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                hasFilters ? 'No Matching Items' : 'No Items Found',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                hasFilters
                    ? 'Try adjusting your filters or search query.'
                    : 'Pull to refresh to load items.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              hasFilters
                  ? FilledButton.tonalIcon(
                      onPressed: controller.clearFilters,
                      icon: const Icon(Icons.filter_alt_off),
                      label: const Text('Clear Filters'),
                    )
                  : FilledButton.tonalIcon(
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

  // ── list card ───────────────────────────────────────────────────────────────────

  Widget _buildListCard(Item item) {
    return Obx(() {
      final isExpanded = controller.expandedItemName.value == item.name;
      final stockList = controller.getStockFor(item.itemCode);
      // Fix #8: per-item loading state via _stockLoadingSet
      final isLoadingThisItem = controller.isStockLoading(item.itemCode);
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      return GenericDocumentCard(
        title: item.itemName,
        subtitle: item.itemCode,
        status: item.itemGroup,
        leading: _ItemImage(
          key: ValueKey(item.itemCode),
          imageUrl: item.image != null ? '$_baseUrl${item.image}' : null,
          size: 56,
        ),
        isExpanded: isExpanded,
        isLoadingDetails: isLoadingThisItem,
        // Fix #10: long-press navigates directly without needing expansion
        onLongPress: () => Get.toNamed(
          AppRoutes.ITEM_FORM,
          arguments: {'itemCode': item.itemCode},
        ),
        onTap: () => controller.toggleExpand(item.name, item.itemCode),
        stats: [
          GenericDocumentCard.buildIconStat(
              context, Icons.emoji_flags, item.countryOfOrigin ?? '-'),
          if (item.variantOf != null)
            GenericDocumentCard.buildIconStat(
                context, Icons.copy, item.variantOf ?? ''),
        ],
        expandedContent: _ExpandedContent(
          item: item,
          stockList: stockList,
          isLoading: isLoadingThisItem,
          colorScheme: cs,
          theme: theme,
        ),
      );
    });
  }

  // ── grid card ───────────────────────────────────────────────────────────────────

  Widget _buildGridCard(Item item) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      // Fix #12: tap shows bottom sheet preview; no direct navigation
      child: InkWell(
        onTap: () => _showGridItemPreview(item),
        onLongPress: () => Get.toNamed(
          AppRoutes.ITEM_FORM,
          arguments: {'itemCode': item.itemCode},
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: _ItemImage(
                  key: ValueKey('grid_${item.itemCode}'),
                  imageUrl:
                      item.image != null ? '$_baseUrl${item.image}' : null,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: cs.onSurface),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.itemCode,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontFeatures: const [FontFeature.slashedZero()],
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

  // Fix #12: bottom sheet preview for grid card tap
  void _showGridItemPreview(Item item) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    controller.fetchStockLevels(item.itemCode);

    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _ItemImage(
                    key: ValueKey('preview_${item.itemCode}'),
                    imageUrl:
                        item.image != null ? '$_baseUrl${item.image}' : null,
                    size: 64,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.itemName,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(item.itemCode,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        Text(item.itemGroup,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: cs.primary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: Obx(() {
                final stockList = controller.getStockFor(item.itemCode);
                final isLoading = controller.isStockLoading(item.itemCode);
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _ExpandedContent(
                    item: item,
                    stockList: stockList,
                    isLoading: isLoading,
                    colorScheme: cs,
                    theme: theme,
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Get.back();
                    Get.toNamed(
                      AppRoutes.ITEM_FORM,
                      arguments: {'itemCode': item.itemCode},
                    );
                  },
                  child: const Text('View Full Details'),
                ),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// _ItemImage  (Fix #6: extracted to StatelessWidget with key)
// ───────────────────────────────────────────────────────────────────────────────

class _ItemImage extends StatelessWidget {
  final String? imageUrl;
  final double? size;
  final BoxFit fit;

  const _ItemImage({
    super.key,
    required this.imageUrl,
    this.size,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: fit,
          // Fix #11: shimmer-style placeholder during network load
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: size,
              height: size,
              color: cs.surfaceContainerHighest,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                    color: cs.primary,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => _placeholder(cs),
        ),
      );
    }
    return _placeholder(cs);
  }

  Widget _placeholder(ColorScheme cs) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          size: size != null ? size! * 0.5 : 30,
        ),
      );
}

// ───────────────────────────────────────────────────────────────────────────────
// _ExpandedContent  (Fix #9: theme colours throughout)
// Shared by list card expanded section and grid preview bottom sheet.
// ───────────────────────────────────────────────────────────────────────────────

class _ExpandedContent extends StatelessWidget {
  final Item item;
  final List<WarehouseStock>? stockList;
  final bool isLoading;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _ExpandedContent({
    required this.item,
    required this.stockList,
    required this.isLoading,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        if (item.description != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              item.description!,
              // Fix #9: theme colour instead of hardcoded Colors.black87
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // Customer References
        if (item.customerItems.isNotEmpty) ...[
          Text(
            'Customer References',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ...item.customerItems.map(
            (ci) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(ci.customerName,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  Text(ci.refCode,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 12),
        ],

        // Stock Balance
        Text(
          'Stock Balance',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),

        // Fix #8: show per-item spinner; only show "no data" when fetched
        if (isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          )
        else if (stockList == null || stockList!.isEmpty)
          Text(
            'No stock data available.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          ...stockList!.map(
            (stock) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${stock.warehouse}'
                      '${stock.rack != null ? " (${stock.rack})" : ""}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    '${stock.quantity.toStringAsFixed(2)} '
                    '${item.stockUom ?? ""}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: stock.quantity > 0
                          ? Colors.green.shade600
                          : cs.error,
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
    );
  }
}
