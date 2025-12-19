import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class ItemDetailSheet extends StatelessWidget {
  final Item item;

  const ItemDetailSheet({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final String _baseUrl = Get.find<ApiProvider>().baseUrl;
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                if (item.image != null && item.image!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '$_baseUrl${item.image}',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (c, o, s) => Container(
                        width: 60, height: 60, color: Colors.grey.shade100,
                        child: const Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.inventory_2, color: Colors.blue),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(item.itemName, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildDetailRow('Item Group', item.itemGroup),
            if (item.variantOf != null) _buildDetailRow('Variant Of', item.variantOf!),
            if (item.countryOfOrigin != null) _buildDetailRow('Origin', item.countryOfOrigin!),
            if (item.description != null) ...[
              const SizedBox(height: 12),
              const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(item.description!, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Get.back(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class RackBalanceSheet extends StatelessWidget {
  final String itemCode;
  final List<WarehouseStock> stockData;

  const RackBalanceSheet({super.key, required this.itemCode, required this.stockData});

  @override
  Widget build(BuildContext context) {
    // Filter data to only include entries with racks and positive quantity
    final rackData = stockData.where((s) => s.rack != null && s.rack!.isNotEmpty && s.quantity > 0).toList();

    // Sort by rack name
    rackData.sort((a, b) => a.rack!.compareTo(b.rack!));

    double maxQty = 0;
    for (var s in rackData) {
      if (s.quantity > maxQty) maxQty = s.quantity;
    }
    if (maxQty == 0) maxQty = 1;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Stock Balance by Rack', style: Theme.of(context).textTheme.titleLarge),
            Text('Item: $itemCode', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),

            if (rackData.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No rack-wise stock found for this item.'),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: rackData.length,
                  separatorBuilder: (c, i) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final data = rackData[index];
                    final pct = (data.quantity / maxQty).clamp(0.0, 1.0);

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          data.quantity.toStringAsFixed(0),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: FractionallySizedBox(
                            heightFactor: pct,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 30,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            data.rack!,
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Get.back(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- REDESIGNED WIDGET FOR RACK SCAN ---
class RackContentsSheet extends StatelessWidget {
  final String rackId;
  final List<dynamic> items;

  const RackContentsSheet(
      {super.key, required this.rackId, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rack Contents', style: TextStyle(
                              color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            rackId,
                            style: Theme
                                .of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Get.back(),
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(backgroundColor: Colors.grey
                            .shade100),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // List
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16.0),
                    itemCount: items.length,
                    separatorBuilder: (c, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];

                      // Extract Data with Fallbacks
                      final double qty = (item['bal_qty'] as num?)
                          ?.toDouble() ?? 0.0;
                      final String itemCode = item['item_code'] ?? 'Unknown';
                      final String itemName = item['item_name'] ?? itemCode;
                      final String? itemGroup = item['item_group'];
                      final String? variantOf = item['variant_of'];
                      final String? batchNo = item['batch_no'];

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Row 1: Item Name & Qty
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      itemName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        qty.toStringAsFixed(2),
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: Theme
                                                .of(context)
                                                .primaryColor
                                        ),
                                      ),
                                      const Text('Qty', style: TextStyle(
                                          fontSize: 10, color: Colors.grey)),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Row 2: Item Code & Badges (Group/Variant/Batch)
                              Text(itemCode, style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Colors.black87)),
                              const SizedBox(height: 8),

                              Wrap(
                                spacing: 6.0,
                                runSpacing: 6.0,
                                children: [
                                  if (itemGroup != null)
                                    _buildInfoPill(Icons.category, itemGroup,
                                        Colors.blueGrey),
                                  if (variantOf != null)
                                    _buildInfoPill(
                                        Icons.style, variantOf, Colors.teal),
                                  if (batchNo != null)
                                    _buildInfoPill(
                                        Icons.qr_code, batchNo, Colors.purple,
                                        isMono: true),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String text, MaterialColor color, {bool isMono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: color.shade900,
              fontWeight: FontWeight.w600,
              fontFamily: isMono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

// --- UPDATED: Multi-Item Selection Sheet (Catalogue View) ---
class MultiItemSelectionSheet extends StatelessWidget {
  final List<Item> items;
  final Function(Item) onItemSelected;

  const MultiItemSelectionSheet({
    super.key,
    required this.items,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Get Base URL for images
    final String baseUrl = Get.find<ApiProvider>().baseUrl;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.8, // Taller for catalogue
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Catalogue Search', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('${items.length} Items Found', style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Catalogue Grid
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.70, // Optimized for card content
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final imageUrl = item.image != null ? '$baseUrl${item.image}' : null;

                      return GestureDetector(
                        onTap: () {
                          Get.back();
                          onItemSelected(item);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(color: Colors.grey.shade100, blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Image Section
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      child: imageUrl != null
                                          ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                                      )
                                          : _buildPlaceholder(),
                                    ),
                                    if (imageUrl != null)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: GestureDetector(
                                          onTap: () => _showEnlargedImage(imageUrl),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.6),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Info Section
                              Padding(
                                padding: const EdgeInsets.all(10.0),
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
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.blueGrey),
                                    ),
                                    const SizedBox(height: 6),

                                    if (item.variantOf != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4.0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(4)),
                                          child: Text(
                                            'Var: ${item.variantOf}',
                                            style: TextStyle(fontSize: 10, color: Colors.teal.shade800, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                    Row(
                                      children: [
                                        const Icon(Icons.category_outlined, size: 12, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            item.itemGroup,
                                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade300, size: 40),
      ),
    );
  }

  void _showEnlargedImage(String url) {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Get.back(),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}