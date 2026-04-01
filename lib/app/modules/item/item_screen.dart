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
import 'package:multimax/app/modules/item/widgets/item_image.dart';
import 'package:multimax/app/modules/item/widgets/item_expanded_content.dart';
import 'package:multimax/app/modules/item/widgets/item_grid_preview_sheet.dart';

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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                  return _buildEmptyState(context);
                }

                if (controller.isGridView.value) {
                  return _buildGrid();
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

  // ── grid ─────────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    final items = controller.displayedItems;
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

  // ── list ──────────────────────────────────────────────────────────────────────

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

  // ── empty state ───────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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

  // ── list card ──────────────────────────────────────────────────────────────────

  Widget _buildListCard(Item item) {
    return Obx(() {
      final isExpanded = controller.expandedItemName.value == item.name;
      final stockList = controller.getStockFor(item.itemCode);
      final isLoadingThisItem = controller.isStockLoading(item.itemCode);
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      return GenericDocumentCard(
        title: item.itemName,
        subtitle: item.itemCode,
        status: item.itemGroup,
        leading: ItemImage(
          key: ValueKey(item.itemCode),
          imageUrl: item.image != null ? '$_baseUrl${item.image}' : null,
          size: 56,
        ),
        isExpanded: isExpanded,
        isLoadingDetails: isLoadingThisItem,
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
        expandedContent: ItemExpandedContent(
          item: item,
          stockList: stockList,
          isLoading: isLoadingThisItem,
          colorScheme: cs,
          theme: theme,
        ),
      );
    });
  }

  // ── grid card ──────────────────────────────────────────────────────────────────

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
      child: InkWell(
        onTap: () => Get.bottomSheet(
          ItemGridPreviewSheet(item: item, baseUrl: _baseUrl),
          isScrollControlled: true,
        ),
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
                child: ItemImage(
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
}
