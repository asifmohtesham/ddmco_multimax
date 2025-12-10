import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class ItemDetailSheet extends StatelessWidget {
  final Item item;

  const ItemDetailSheet({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
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
                      'https://erp.multimax.cloud${item.image}',
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

// --- NEW WIDGET FOR RACK SCAN ---
class RackContentsSheet extends StatelessWidget {
  final String rackId;
  final List<dynamic> items;

  const RackContentsSheet({super.key, required this.rackId, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rack Contents', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                              rackId,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: items.length,
                    separatorBuilder: (c, i) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      // Note: Fields depend on report output structure
                      final qty = (item['bal_qty'] as num?)?.toDouble() ?? 0.0;
                      final batch = item['batch_no']?.toString();
                      final itemCode = item['item_code']?.toString() ?? 'Unknown';
                      final itemName = item['item_name']?.toString(); // Might need fetch if not in report

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                child: Icon(Icons.inventory, color: Theme.of(context).primaryColor, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemCode,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'monospace'),
                                    ),
                                    if (itemName != null)
                                      Text(itemName, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    if (batch != null && batch.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.purple.shade100)
                                        ),
                                        child: Text(
                                            batch,
                                            style: TextStyle(fontSize: 11, color: Colors.purple.shade800, fontWeight: FontWeight.bold)
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    qty.toStringAsFixed(2),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                  const Text('Qty', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
            ),
          );
        },
      ),
    );
  }
}