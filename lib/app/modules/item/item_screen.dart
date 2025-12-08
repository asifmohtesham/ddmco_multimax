import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/item/item_controller.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/item/widgets/item_filter_bottom_sheet.dart';
import 'package:intl/intl.dart';

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
        title: const Text('Items'),
        actions: [
          IconButton(
            icon: Obx(() => Icon(
                Icons.filter_list,
                color: controller.activeFilters.isNotEmpty || !controller.showImagesOnly.value
                    ? Colors.amber // Highlight if filters are active or default is changed
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
          // Filter Status Indicator
          Obx(() {
            if (controller.activeFilters.isEmpty && controller.showImagesOnly.value) return const SizedBox.shrink();

            final filters = <String>[];
            if (controller.showImagesOnly.value) filters.add('Images Only');
            if (controller.activeFilters.containsKey('item_group')) filters.add('Group');
            if (controller.activeFilters.containsKey('description')) filters.add('Attr');

            return Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    'Active: ${filters.join(", ")}',
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: controller.clearFilters,
                    child: const Text('Reset', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
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
                      const Icon(Icons.image_not_supported_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No items found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      if (controller.showImagesOnly.value)
                        TextButton(
                          onPressed: () {
                            controller.setImagesOnly(false);
                            controller.fetchItems(clear: true);
                          },
                          child: const Text('Show items without images'),
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
        childAspectRatio: 0.75, // Taller for grid items
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
      // In Grid View, we don't expand inline, just show basics
      final isGrid = controller.isGridView.value;

      return Card(
        margin: isGrid ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        child: InkWell(
          onTap: () {
            if (isGrid) {
              // In Grid, maybe just navigate directly or show dialog? 
              // For consistency, let's keep expand logic if list, else navigate
              Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': item.itemCode});
            } else {
              controller.toggleExpand(item.name, item.itemCode);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Expanded(
                flex: isGrid ? 3 : 0,
                child: Container(
                  width: double.infinity,
                  height: isGrid ? null : 200, // Fixed height in List view
                  color: Colors.white,
                  child: item.image != null && item.image!.isNotEmpty
                      ? Image.network(
                      'https://erp.multimax.cloud${item.image}',
                      fit: BoxFit.contain,
                      errorBuilder: (c, o, s) => Container(color: Colors.grey.shade100, child: const Icon(Icons.broken_image, color: Colors.grey))
                  )
                      : Container(color: Colors.grey.shade100, child: const Icon(Icons.image_not_supported, color: Colors.grey)),
                ),
              ),

              // Content
              Expanded(
                flex: isGrid ? 2 : 0,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          item.itemName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis
                      ),
                      const SizedBox(height: 4),
                      Text(item.itemCode, style: const TextStyle(fontFamily: 'monospace', color: Colors.grey, fontSize: 12)),

                      if (!isGrid && isExpanded) ...[
                        const Divider(height: 16),
                        _buildExpandedContent(item),
                      ]
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildExpandedContent(Item item) {
    final stockList = controller.getStockFor(item.itemCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.countryOfOrigin != null) _buildDetailRow('Origin', item.countryOfOrigin!),
        if (item.variantOf != null) _buildDetailRow('Variant of', item.variantOf!),
        if (item.description != null) ...[
          const SizedBox(height: 4),
          Text(item.description!, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 3, overflow: TextOverflow.ellipsis)
        ],
        const SizedBox(height: 12),
        const Text('Stock Levels:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        controller.isLoadingStock.value
            ? const LinearProgressIndicator(minHeight: 2)
            : stockList == null || stockList.isEmpty
            ? const Text('No stock data', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))
            : ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stockList.length,
          separatorBuilder: (c, i) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final stock = stockList[index];
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(stock.rack!, style: const TextStyle(fontSize: 12)),
                Text(NumberFormat.decimalPattern().format(stock.quantity), style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12)),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': item.itemCode});
            },
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('View Full Details'),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
        ],
      ),
    );
  }
}