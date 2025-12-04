
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/item/form/item_form_controller.dart';

class ItemFormScreen extends GetView<ItemFormController> {
  const ItemFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Details'),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final item = controller.item.value;
        if (item == null) {
          return const Center(child: Text('Item not found'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.image != null)
                Center(
                  child: SizedBox(
                    height: 200,
                    child: Image.network(
                      'https://erp.multimax.cloud${item.image}',
                      fit: BoxFit.contain,
                      errorBuilder: (c, o, s) => const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _buildDetailRow('Item Code', item.itemCode),
              _buildDetailRow('Item Name', item.itemName),
              _buildDetailRow('Item Group', item.itemGroup),
              if (item.variantOf != null) _buildDetailRow('Variant Of', item.variantOf!),
              if (item.countryOfOrigin != null) _buildDetailRow('Country of Origin', item.countryOfOrigin!),
              if (item.description != null) ...[
                const SizedBox(height: 16),
                const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(item.description!),
              ],
            ],
          ),
        );
      }),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const Divider(),
        ],
      ),
    );
  }
}
