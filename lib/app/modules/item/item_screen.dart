
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/item/item_controller.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () { /* TODO: Implement filter sheet */ },
          ),
          Obx(() => IconButton(
            icon: Icon(controller.isGridView.value ? Icons.view_list : Icons.grid_view),
            onPressed: controller.toggleLayout,
          )),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.items.isEmpty) {
          return const Center(child: Text('No items found.'));
        }

        return RefreshIndicator(
          onRefresh: () => controller.fetchItems(clear: true),
          child: Obx(() => controller.isGridView.value
              ? _buildGridView(controller.items)
              : _buildListView(controller.items)),
        );
      }),
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
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
      final stockList = controller.getStockFor(item.itemCode);

      return Card(
        margin: const EdgeInsets.all(8.0),
        child: InkWell(
          onTap: () => controller.toggleExpand(item.name, item.itemCode),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              AspectRatio(
                aspectRatio: 16 / 9,
                child: item.image != null
                    ? Image.network('https://erp.multimax.cloud${item.image}', fit: BoxFit.cover)
                    : Container(color: Colors.grey.shade200, child: const Icon(Icons.image_not_supported, color: Colors.grey)),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(item.itemCode, style: const TextStyle(fontFamily: 'monospace', color: Colors.grey)),
                  ],
                ),
              ),

              // Expanded Details
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: !isExpanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          if (item.countryOfOrigin != null) ...[Text('Origin: ${item.countryOfOrigin}')],
                          if (item.variantOf != null) ...[Text('Variant of: ${item.variantOf}')],
                          if (item.description != null) ...[Text(item.description!)],
                          const SizedBox(height: 8),
                          const Text('Stock Levels:', style: TextStyle(fontWeight: FontWeight.bold)),
                          controller.isLoadingStock.value
                            ? const LinearProgressIndicator()
                            : stockList == null || stockList.isEmpty
                              ? const Text('No stock data')
                              : SizedBox(
                                  height: 60, // Constrained height to prevent overflow
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: stockList.map((stock) => 
                                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(stock.warehouse), Text(stock.quantity.toString())])
                                    ).toList(),
                                  ),
                                ),
                        ],
                      ),
                    ),
              )
            ],
          ),
        ),
      );
    });
  }
}
