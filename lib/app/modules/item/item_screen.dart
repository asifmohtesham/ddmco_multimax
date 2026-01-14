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
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/controllers/frappe_filter_sheet_controller.dart';

class ItemScreen extends GetView<ItemController> {
  const ItemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent * 0.9 &&
          controller.hasMore.value &&
          !controller.isFetchingMore.value) {
        controller.loadMore();
      }
    });

    final String baseUrl = Get.find<ApiProvider>().baseUrl;

    return Obx(() {
      final isGrid = controller.isGridView.value;

      return GenericListPage(
        title: 'Item Master',
        isLoading: controller.isLoading,
        data: controller.items,
        onRefresh: () async => controller.refreshList(),
        scrollController: scrollController,

        onSearch: controller.onSearchChanged,
        searchHint: 'Search Items...',
        searchDoctype: 'Item',

        // FIX: Added Floating Action Button for creation
        // FIX: Ensure this passes {'mode': 'new'}
        // FIX: Ensure FAB is present and passes correct args
        fab: FloatingActionButton(
          backgroundColor: FrappeTheme.primary,
          child: const Icon(Icons.add, color: Colors.white),
          onPressed: () => Get.toNamed(
              AppRoutes.ITEM_FORM,
              arguments: {'mode': 'new'}
          ),
        ),

        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: controller.filterCount > 0,
              backgroundColor: FrappeTheme.primary,
              label: Text('${controller.filterCount}'),
              child: Icon(
                Icons.filter_list_rounded,
                color: controller.filterCount > 0
                    ? FrappeTheme.primary
                    : FrappeTheme.textBody,
              ),
            ),
            onPressed: () {
              final sheetCtrl = Get.put(FrappeFilterSheetController());
              sheetCtrl.initialize(
                controller,
                initialShowImages: controller.showImagesOnly.value,
              );
              Get.bottomSheet(
                const ItemFilterBottomSheet(),
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
              ).then((_) => Get.delete<FrappeFilterSheetController>());
            },
          ),
          IconButton(
            icon: Icon(
              isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: FrappeTheme.textBody,
            ),
            onPressed: controller.toggleLayout,
          ),
        ],

        sliverBody: isGrid
            ? SliverPadding(
                padding: const EdgeInsets.all(12.0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index >= controller.items.length)
                      return const SizedBox.shrink();
                    return _buildGridCard(controller.items[index], baseUrl);
                  }, childCount: controller.items.length),
                ),
              )
            : null,

        itemBuilder: (context, index) {
          if (index >= controller.items.length) {
            return controller.hasMore.value
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : const SizedBox.shrink();
          }
          return _buildListCard(context, controller.items[index], baseUrl);
        },
      );
    });
  }

  // ... (Keep _buildListCard, _buildGridCard, _buildImage methods exactly as they were)
  Widget _buildListCard(BuildContext context, Item item, String baseUrl) {
    return Obx(() {
      final isExpanded = controller.expandedItemName.value == item.name;
      final stockList = controller.getStockFor(item.itemCode);
      final isLoadingStock = controller.isLoadingStock.value && isExpanded;

      return GenericDocumentCard(
        title: item.itemName,
        subtitle: item.itemCode,
        status: item.itemGroup,
        leading: _buildImage(item, baseUrl, size: 48),

        isExpanded: isExpanded,
        isLoadingDetails: isLoadingStock,
        onTap: () => controller.toggleExpand(item.name, item.itemCode),

        stats: [
          GenericDocumentCard.buildIconStat(
            context,
            Icons.emoji_flags_rounded,
            item.countryOfOrigin ?? '-',
          ),
          if (item.variantOf != null)
            GenericDocumentCard.buildIconStat(
              context,
              Icons.copy_rounded,
              item.variantOf ?? '',
            ),
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
                    fontSize: 13,
                    color: FrappeTheme.textBody,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // ... Customer refs ...
            if (item.customerItems.isNotEmpty) ...[
              const Text(
                'Customer References',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: FrappeTheme.textLabel,
                ),
              ),
              const SizedBox(height: 8),
              ...item.customerItems.map(
                (ci) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ci.customerName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: FrappeTheme.textBody,
                        ),
                      ),
                      Text(
                        ci.refCode,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'ShureTechMono',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
            ],

            const Text(
              'Stock Balance',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: FrappeTheme.textLabel,
              ),
            ),
            const SizedBox(height: 8),

            if (stockList == null || stockList.isEmpty)
              const Text(
                'No stock data available.',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ...stockList.map(
                (stock) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${stock.warehouse}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: FrappeTheme.textBody,
                        ),
                      ),
                      Text(
                        '${stock.quantity.toStringAsFixed(2)} ${item.stockUom ?? ''}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: stock.quantity > 0
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: FrappeTheme.surface,
                  foregroundColor: FrappeTheme.primary,
                  elevation: 0,
                  side: const BorderSide(color: FrappeTheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FrappeTheme.radius),
                  ),
                ),
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

  Widget _buildGridCard(Item item, String baseUrl) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
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
                child: _buildImage(item, baseUrl, fit: BoxFit.cover),
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
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: FrappeTheme.textBody,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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

  Widget _buildImage(
    Item item,
    String baseUrl, {
    double? size,
    BoxFit fit = BoxFit.contain,
  }) {
    if (item.image != null && item.image!.isNotEmpty) {
      return Image.network(
        '$baseUrl${item.image}',
        width: size,
        height: size,
        fit: fit,
        errorBuilder: (c, o, s) =>
            Icon(Icons.broken_image, size: size, color: Colors.grey.shade300),
      );
    }
    return Icon(
      Icons.image_not_supported,
      size: size,
      color: Colors.grey.shade300,
    );
  }
}
