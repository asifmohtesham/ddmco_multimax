import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/item/widgets/item_filter_bottom_sheet.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
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
    if (_isBottom && controller.hasMore.value && !controller.isFetchingMore.value) {
      controller.fetchItems(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  Widget build(BuildContext context) {
    return GenericListPage(
      title: 'Item Master',
      isLoading: controller.isLoading,
      data: controller.displayedItems,
      onRefresh: () => controller.fetchItems(clear: true),
      scrollController: _scrollController,

      // Global API Search Configuration
      searchDoctype: 'Item',
      searchRoute: AppRoutes.ITEM_FORM,

      // Local List Search
      onSearch: controller.onSearchChanged,
      searchHint: 'Search Items (Name, Code, Desc...)',

      actions: [
        Obx(() {
          final count = controller.filterCount;
          return IconButton(
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: Icon(
                Icons.filter_list,
                color: count > 0 ? Colors.amber : null,
              ),
            ),
            onPressed: () => Get.bottomSheet(
              const ItemFilterBottomSheet(),
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
            ),
          );
        }),
        Obx(() => IconButton(
          icon: Icon(controller.isGridView.value ? Icons.view_list : Icons.grid_view),
          onPressed: controller.toggleLayout,
        )),
      ],

      // Custom Body for Grid View Toggle
      sliverBody: Obx(() {
        if (controller.isGridView.value) {
          return SliverPadding(
            padding: const EdgeInsets.all(8.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  if (index >= controller.displayedItems.length) return const SizedBox.shrink();
                  return _buildGridCard(controller.displayedItems[index]);
                },
                childCount: controller.displayedItems.length,
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              if (index >= controller.displayedItems.length) {
                return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
              }
              return _buildListCard(controller.displayedItems[index]);
            },
            childCount: controller.displayedItems.length + (controller.hasMore.value ? 1 : 0),
          ),
        );
      }),
      itemBuilder: (ctx, idx) => const SizedBox.shrink(), // Not used due to sliverBody override
    );
  }

  // --- List View Card (Standard GenericDocumentCard) ---
  Widget _buildListCard(Item item) {
    return Obx(() {
      final isExpanded = controller.expandedItemName.value == item.name;
      final stockList = controller.getStockFor(item.itemCode);
      final isLoadingStock = controller.isLoadingStock.value && isExpanded;

      return GenericDocumentCard(
        title: item.itemName,
        subtitle: item.itemCode,
        status: item.itemGroup,
        leading: _buildImage(item, size: 56),

        isExpanded: isExpanded,
        isLoadingDetails: isLoadingStock,
        onTap: () => controller.toggleExpand(item.name, item.itemCode),

        stats: [
          GenericDocumentCard.buildIconStat(context, Icons.emoji_flags, item.countryOfOrigin ?? '-'),
          if (item.variantOf != null)
            GenericDocumentCard.buildIconStat(context, Icons.copy, item.variantOf ?? ''),
        ],

        expandedContent: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(item.description!, style: const TextStyle(fontSize: 13, color: Colors.black87), maxLines: 3, overflow: TextOverflow.ellipsis),
              ),

            // --- Customer Items Section ---
            if (item.customerItems.isNotEmpty) ...[
              const Text('Customer References', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ...item.customerItems.map((ci) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(ci.customerName, style: const TextStyle(fontSize: 12)),
                    Text(ci.refCode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              )),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
            ],

            const Text('Stock Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),

            if (stockList == null || stockList.isEmpty)
              const Text('No stock data available.', style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic))
            else
              ...stockList.map((stock) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${stock.warehouse}${stock.rack != null ? " (${stock.rack})" : ""}', style: const TextStyle(fontSize: 12)),
                    Text(
                      '${stock.quantity.toStringAsFixed(2)} ${item.stockUom ?? ''}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: stock.quantity > 0 ? Colors.green : Colors.red),
                    ),
                  ],
                ),
              )),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': item.itemCode}),
                child: const Text('View Full Details'),
              ),
            ),
          ],
        ),
      );
    });
  }

  // --- Grid View Card (Custom M3 Style) ---
  Widget _buildGridCard(Item item) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: () => Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': item.itemCode}),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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

  Widget _buildImage(Item item, {double? size, BoxFit fit = BoxFit.contain}) {
    if (item.image != null && item.image!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          '$_baseUrl${item.image}',
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (c, o, s) => Container(
            width: size, height: size,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      );
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: size != null ? size * 0.5 : 30),
    );
  }
}