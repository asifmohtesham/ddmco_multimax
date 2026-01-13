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
import 'package:multimax/theme/frappe_theme.dart'; // Theme Import

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
      searchHint: 'Search Items...',

      actions: [
        Obx(() {
          final count = controller.filterCount;
          return IconButton(
            icon: Badge(
              isLabelVisible: count > 0,
              backgroundColor: FrappeTheme.primary,
              label: Text('$count'),
              child: Icon(
                Icons.filter_list_rounded,
                color: count > 0 ? FrappeTheme.primary : FrappeTheme.textBody,
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
          icon: Icon(
            controller.isGridView.value ? Icons.view_list_rounded : Icons.grid_view_rounded,
            color: FrappeTheme.textBody,
          ),
          onPressed: controller.toggleLayout,
        )),
      ],

      // Custom Body for Grid View Toggle
      sliverBody: Obx(() {
        if (controller.isGridView.value) {
          return SliverPadding(
            padding: const EdgeInsets.all(12.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
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

  // --- List View Card ---
  Widget _buildListCard(Item item) {
    return Obx(() {
      final isExpanded = controller.expandedItemName.value == item.name;
      final stockList = controller.getStockFor(item.itemCode);
      final isLoadingStock = controller.isLoadingStock.value && isExpanded;

      return GenericDocumentCard(
        title: item.itemName,
        subtitle: item.itemCode,
        status: item.itemGroup,
        leading: _buildImage(item, size: 48), // Smaller, tighter image

        isExpanded: isExpanded,
        isLoadingDetails: isLoadingStock,
        onTap: () => controller.toggleExpand(item.name, item.itemCode),

        stats: [
          GenericDocumentCard.buildIconStat(context, Icons.emoji_flags_rounded, item.countryOfOrigin ?? '-'),
          if (item.variantOf != null)
            GenericDocumentCard.buildIconStat(context, Icons.copy_rounded, item.variantOf ?? ''),
        ],

        expandedContent: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                    item.description!,
                    style: const TextStyle(fontSize: 13, color: FrappeTheme.textBody),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis
                ),
              ),

            // --- Customer Items Section ---
            if (item.customerItems.isNotEmpty) ...[
              const Text('Customer References', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: FrappeTheme.textLabel)),
              const SizedBox(height: 8),
              ...item.customerItems.map((ci) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(ci.customerName, style: const TextStyle(fontSize: 12, color: FrappeTheme.textBody)),
                    Text(ci.refCode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'ShureTechMono')),
                  ],
                ),
              )),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
            ],

            const Text('Stock Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: FrappeTheme.textLabel)),
            const SizedBox(height: 8),

            if (stockList == null || stockList.isEmpty)
              const Text('No stock data available.', style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic))
            else
              ...stockList.map((stock) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${stock.warehouse}${stock.rack != null ? " (${stock.rack})" : ""}', style: const TextStyle(fontSize: 12, color: FrappeTheme.textBody)),
                    Text(
                      '${stock.quantity.toStringAsFixed(2)} ${item.stockUom ?? ''}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: stock.quantity > 0 ? Colors.green[700] : Colors.red[700]
                      ),
                    ),
                  ],
                ),
              )),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: FrappeTheme.surface,
                    foregroundColor: FrappeTheme.primary,
                    elevation: 0,
                    side: const BorderSide(color: FrappeTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FrappeTheme.radius))
                ),
                onPressed: () => Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': item.itemCode}),
                child: const Text('View Full Details'),
              ),
            ),
          ],
        ),
      );
    });
  }

  // --- Grid View Card ---
  Widget _buildGridCard(Item item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 2),
            blurRadius: 4,
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: FrappeTheme.textBody),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.itemCode,
                    style: const TextStyle(
                      fontFamily: 'ShureTechMono',
                      fontSize: 11,
                      color: FrappeTheme.textLabel,
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
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade100)
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          '$_baseUrl${item.image}',
          fit: fit,
          errorBuilder: (c, o, s) => Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade300, size: size != null ? size * 0.5 : 24),
          ),
        ),
      );
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
          color: FrappeTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200)
      ),
      child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: size != null ? size * 0.5 : 24),
    );
  }
}