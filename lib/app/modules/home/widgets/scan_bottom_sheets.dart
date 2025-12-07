import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';

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