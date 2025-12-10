import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/item/form/widgets/stock_balance_chart.dart';

class ItemFormScreen extends GetView<ItemFormController> {
  const ItemFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.item.value?.itemName ?? 'Item Details')),
          automaticallyImplyLeading: false, // Don't show back arrow in bottom sheet
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Get.back(),
            )
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Dashboard'),
              Tab(text: 'Attachments'),
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
              _buildOverviewTab(context, item),
              _buildDashboardTab(context),
              _buildAttachmentsTab(context),
            ],
          );
        }),
      ),
    );
  }

  // ... (Rest of the widget methods _buildOverviewTab, _buildDashboardTab, etc. remain unchanged)
  Widget _buildOverviewTab(BuildContext context, dynamic item) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Header
          if (item.image != null)
            GestureDetector(
              onTap: () => _openFullScreenImage(context, 'https://erp.multimax.cloud${item.image}'),
              child: Container(
                height: 200,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Hero(
                  tag: 'item_image_${item.itemCode}',
                  child: Image.network(
                    'https://erp.multimax.cloud${item.image}',
                    fit: BoxFit.contain,
                    errorBuilder: (c, o, s) => const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                  ),
                ),
              ),
            ),

          // 1. General Section
          _buildSectionCard(
            title: 'General',
            children: [
              _buildDetailRow('Item Code', item.itemCode, isCopyable: true),
              const Divider(),
              _buildDetailRow('Item Name', item.itemName),
              const Divider(),
              _buildDetailRow('Item Group', item.itemGroup),
            ],
          ),

          const SizedBox(height: 16),

          // 2. Inventory Section
          _buildSectionCard(
            title: 'Inventory',
            children: [
              _buildDetailRow('Default UOM', item.stockUom ?? '-'),
              // Add Valuation Method here if available in model later
              if (item.countryOfOrigin != null) ...[
                const Divider(),
                _buildDetailRow('Country of Origin', item.countryOfOrigin!),
              ]
            ],
          ),

          const SizedBox(height: 16),

          // 3. Variants & Description
          if (item.variantOf != null || item.description != null)
            _buildSectionCard(
              title: 'Description',
              children: [
                if (item.variantOf != null) ...[
                  _buildDetailRow('Variant Of', item.variantOf!),
                  const Divider(),
                ],
                if (item.description != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Detailed Description', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(item.description!, style: const TextStyle(fontSize: 14, height: 1.4)),
                    ],
                  ),
              ],
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Stock Balance
          const Text('Stock Balance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Obx(() {
            if (controller.isLoadingStock.value) return const LinearProgressIndicator();

            // Empty State Handling
            if (controller.stockLevels.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200)
                ),
                child: const Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No stock available in any warehouse.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }

            return Column(
              children: [
                StockBalanceChart(stockLevels: controller.stockLevels),
                const SizedBox(height: 12),
                _buildSectionCard(
                    title: 'Warehouse Details',
                    children: [
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: controller.stockLevels.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final stock = controller.stockLevels[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(stock.warehouse, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: stock.rack != null ? Text('Rack: ${stock.rack}', style: const TextStyle(fontSize: 12)) : null,
                            trailing: Text(
                              stock.quantity.toStringAsFixed(2),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 14),
                            ),
                          );
                        },
                      ),
                    ]
                ),
              ],
            );
          }),

          const SizedBox(height: 24),

          // 2. Ledger
          const Text('Recent Ledger Entries', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Obx(() {
            if (controller.isLoadingLedger.value) return const LinearProgressIndicator();
            if (controller.stockLedgerEntries.isEmpty) {
              return const Text('No recent transactions.', style: TextStyle(color: Colors.grey));
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: controller.stockLedgerEntries.length,
              itemBuilder: (context, index) {
                final entry = controller.stockLedgerEntries[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(entry['voucher_type'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${entry['voucher_no']} • ${entry['posting_date']}', style: const TextStyle(fontSize: 12)),
                    trailing: Text(
                      '${(entry['actual_qty'] as num).toDouble() > 0 ? '+' : ''}${entry['actual_qty']}',
                      style: TextStyle(
                          color: (entry['actual_qty'] as num).toDouble() > 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAttachmentsTab(BuildContext context) {
    return Obx(() {
      if (controller.attachments.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.perm_media_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text('No attachments found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ],
          ),
        );
      }

      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: controller.attachments.length,
        itemBuilder: (ctx, i) {
          final file = controller.attachments[i];
          final String fileUrl = file['file_url'] ?? '';
          final String fileName = file['file_name'] ?? 'Unknown';
          final bool isImg = controller.isImage(fileUrl);
          final fullUrl = 'https://erp.multimax.cloud$fileUrl';

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Content (Image or Icon)
                InkWell(
                  onTap: () {
                    if (isImg) {
                      _openFullScreenImage(context, fullUrl);
                    } else {
                      controller.copyLink(fileUrl);
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: isImg
                            ? Hero(
                          tag: fileUrl,
                          child: Image.network(
                            fullUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => Container(
                              color: Colors.grey.shade100,
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                        )
                            : Container(
                          color: Colors.grey.shade100,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.insert_drive_file,
                            size: 48,
                            color: Colors.blueGrey.shade300,
                          ),
                        ),
                      ),
                      const SizedBox(height: 48), // Spacer for footer
                    ],
                  ),
                ),

                // 2. Footer Info Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.white,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                isImg ? 'Image' : 'File',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_outlined, size: 20, color: Colors.blueGrey),
                          onPressed: () => controller.shareFile(fileUrl, fileName),
                          tooltip: 'Share',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isCopyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    textAlign: TextAlign.right,
                  ),
                ),
                if (isCopyable) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, size: 14, color: Colors.grey),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreenImage(BuildContext context, String url) {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(child: Center(child: Image.network(url))),
            Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Get.back())),
          ],
        ),
      ),
    );
  }
}