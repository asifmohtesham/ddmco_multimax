import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/item/widgets/item_filter_bottom_sheet.dart';

class ItemScreen extends StatefulWidget {
  const ItemScreen({super.key});

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  final ItemController controller = Get.find();
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
      controller.fetchItems(isLoadMore: true);
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
      const ItemFilterBottomSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Master'), // ERPNext Terminology
        actions: [
          IconButton(
            icon: Obx(() => Icon(
                Icons.filter_list,
                color: controller.activeFilters.isNotEmpty || !controller.showImagesOnly.value
                    ? Colors.amber
                    : Colors.white
            )),
            onPressed: () => _showFilterBottomSheet(context),
          ),
          Obx(() => IconButton(
            icon: Icon(controller.isGridView.value ? Icons.view_list : Icons.grid_view),
            onPressed: controller.toggleLayout,
          )),
        ],
      ),
      body: Column(
        children: [
          // Filter Summary Bar
          Obx(() {
            if (controller.activeFilters.isEmpty && controller.showImagesOnly.value) return const SizedBox.shrink();

            final filters = <String>[];
            if (controller.showImagesOnly.value) filters.add('Has Image');
            if (controller.activeFilters.containsKey('item_group')) filters.add('Group: ${controller.activeFilters['item_group'][1].replaceAll('%','')}');
            if (controller.activeFilters.containsKey('variant_of')) filters.add('Variant');

            return Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filters.join(", "),
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: controller.clearFilters,
                    child: Text('CLEAR', style: TextStyle(fontSize: 12, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.items.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.category_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No items found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      if (controller.showImagesOnly.value)
                        TextButton(
                          onPressed: () {
                            controller.setImagesOnly(false);
                            controller.fetchItems(clear: true);
                          },
                          child: const Text('Show all items'),
                        ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => controller.fetchItems(clear: true),
                child: Obx(() => controller.isGridView.value
                    ? _buildGridView(controller.items)
                    : _buildListView(controller.items)),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<Item> items) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: items.length + (controller.hasMore.value ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()));
        }
        final item = items[index];
        return ItemCard(item: item);
      },
    );
  }

  Widget _buildGridView(List<Item> items) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length + (controller.hasMore.value ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final item = items[index];
        return ItemCard(item: item);
      },
    );
  }
}

class ItemCard extends GetView<ItemController> {
  final Item item;

  const ItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isExpanded = controller.expandedItemName.value == item.name;
      final isGrid = controller.isGridView.value;

      return Card(
        margin: isGrid ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        clipBehavior: Clip.antiAlias,
        elevation: 1, // Flatter, modern look
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: InkWell(
          onTap: () {
            if (isGrid) {
              Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': item.itemCode});
            } else {
              controller.toggleExpand(item.name, item.itemCode);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section
              if (isGrid)
                Expanded(child: _buildImage(context))
              else if (isExpanded)
                SizedBox(height: 200, width: double.infinity, child: _buildImage(context)),

              // Content Section
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isGrid && !isExpanded)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Thumbnail in list view collapsed state
                          if (item.image != null && item.image!.isNotEmpty)
                            Container(
                              width: 40, height: 40,
                              margin: const EdgeInsets.only(right: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: _buildImage(context),
                              ),
                            ),
                          Expanded(child: _buildHeader(isGrid)),
                        ],
                      )
                    else
                      _buildHeader(isGrid),

                    if (!isGrid && isExpanded) ...[
                      const Divider(height: 24),
                      _buildExpandedContent(context, item),
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildImage(BuildContext context) {
    if (item.image != null && item.image!.isNotEmpty) {
      return Image.network(
        'https://erp.multimax.cloud${item.image}',
        fit: BoxFit.contain, // Contain preserves aspect ratio better for products
        errorBuilder: (c, o, s) => Container(color: Colors.grey.shade50, child: const Icon(Icons.broken_image_outlined, color: Colors.grey)),
      );
    }
    return Container(color: Colors.grey.shade50, child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade300, size: 30));
  }

  Widget _buildHeader(bool isGrid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.itemName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                item.itemCode,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.slashedZero()],
                ),
              ),
            ),
            if (item.stockUom != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                child: Text(item.stockUom!, style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        if (!isGrid) ...[
          const SizedBox(height: 4),
          Text(item.itemGroup, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]
      ],
    );
  }

  Widget _buildExpandedContent(BuildContext context, Item item) {
    final stockList = controller.getStockFor(item.itemCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.variantOf != null)
              Expanded(child: _buildDetailBox('Template', item.variantOf!)),
            if (item.variantOf != null) const SizedBox(width: 12),
            if (item.countryOfOrigin != null)
              Expanded(child: _buildDetailBox('Origin', item.countryOfOrigin!)),
          ],
        ),

        if (item.description != null) ...[
          const SizedBox(height: 12),
          const Text('Description', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(item.description!, style: const TextStyle(fontSize: 13, color: Colors.black87), maxLines: 3, overflow: TextOverflow.ellipsis)
        ],

        const SizedBox(height: 16),
        const Text('Actual Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),

        // Stock List Handling
        controller.isLoadingStock.value
            ? const LinearProgressIndicator(minHeight: 2)
            : (stockList == null || stockList.isEmpty)
            ? Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: const Text('No stock available', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
        )
            : ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stockList.length,
          separatorBuilder: (c, i) => const Divider(height: 1, indent: 0),
          itemBuilder: (context, index) {
            final stock = stockList[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stock.warehouse, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        if (stock.rack != null && stock.rack!.isNotEmpty)
                          Text('Rack: ${stock.rack}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Text(
                      '${stock.quantity.toStringAsFixed(2)} ${item.stockUom ?? ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: stock.quantity > 0 ? Colors.green[700] : Colors.red[700],
                        fontFeatures: const [FontFeature.slashedZero()],
                      )
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': item.itemCode});
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact
            ),
            child: const Text('Full Details & History'),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailBox(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
      ],
    );
  }
}