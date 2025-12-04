
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/item/form/item_form_controller.dart';

class ItemFormScreen extends GetView<ItemFormController> {
  const ItemFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.item.value?.itemName ?? 'Item Details')),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Attachments'),
              Tab(text: 'Dashboard'),
            ],
          ),
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          final item = controller.item.value;
          if (item == null) {
            return const Center(child: Text('Item not found'));
          }

          return TabBarView(
            children: [
              _buildDetailsTab(context, item),
              _buildAttachmentsTab(),
              _buildDashboardTab(),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailsTab(BuildContext context, dynamic item) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.image != null)
            GestureDetector(
              onTap: () {
                // Show full screen image
                Get.dialog(
                  Dialog(
                    backgroundColor: Colors.transparent,
                    child: InteractiveViewer(
                      child: Image.network('https://erp.multimax.cloud${item.image}'),
                    ),
                  ),
                );
              },
              child: Center(
                child: SizedBox(
                  height: 250,
                  child: Hero(
                    tag: 'item_image_${item.itemCode}',
                    child: Image.network(
                      'https://erp.multimax.cloud${item.image}',
                      fit: BoxFit.contain,
                      errorBuilder: (c, o, s) => const Icon(Icons.image_not_supported, size: 80, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text('Basic Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildDetailRow('Item Code', item.itemCode),
                  _buildDetailRow('Item Group', item.itemGroup),
                  if (item.variantOf != null) _buildDetailRow('Variant Of', item.variantOf!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (item.description != null || item.countryOfOrigin != null) ...[
             const Text('Specifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
             const SizedBox(height: 12),
             Card(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      if (item.countryOfOrigin != null) _buildDetailRow('Country of Origin', item.countryOfOrigin!),
                      if (item.description != null) ...[
                        const SizedBox(height: 8),
                        const Text('Description', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(item.description!),
                      ],
                   ],
                 ),
               ),
             ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentsTab() {
    return Obx(() {
      if (controller.attachments.isEmpty) {
        return const Center(child: Text('No attachments found.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: controller.attachments.length,
        separatorBuilder: (c, i) => const Divider(),
        itemBuilder: (context, index) {
          final file = controller.attachments[index];
          final url = 'https://erp.multimax.cloud${file['file_url']}';
          final isImage = url.toLowerCase().endsWith('.png') || url.toLowerCase().endsWith('.jpg') || url.toLowerCase().endsWith('.jpeg');

          return ListTile(
            leading: Icon(isImage ? Icons.image : Icons.insert_drive_file),
            title: Text(file['file_name'] ?? 'Unknown File'),
            onTap: () {
              if (isImage) {
                 Get.dialog(Dialog(child: Image.network(url)));
              } else {
                Get.snackbar('Info', 'File download not implemented in this demo');
              }
            },
          );
        },
      );
    });
  }

  Widget _buildDashboardTab() {
    return Obx(() {
      if (controller.isLoadingStock.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.stockLevels.isEmpty) {
        return const Center(child: Text('No stock data available.'));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: controller.stockLevels.length,
        itemBuilder: (context, index) {
          final stock = controller.stockLevels[index];
          return Card(
            child: ListTile(
              title: Text(stock.warehouse),
              trailing: Text(
                stock.quantity.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
