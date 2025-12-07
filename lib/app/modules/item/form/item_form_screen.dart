import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/item/form/item_form_controller.dart';
import 'package:ddmco_multimax/app/data/utils/formatting_helper.dart';
import 'package:ddmco_multimax/app/modules/item/form/widgets/stock_balance_chart.dart'; // Added Import

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
              _buildDashboardTab(context),
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
                Get.dialog(
                  Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: EdgeInsets.zero,
                    child: Stack(
                      children: [
                        InteractiveViewer(
                          child: Center(
                            child: Image.network('https://erp.multimax.cloud${item.image}'),
                          ),
                        ),
                        Positioned(
                          top: 40,
                          right: 20,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 30),
                            onPressed: () => Get.back(),
                          ),
                        ),
                      ],
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
        return const Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.attachment_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No attachments found.'),
          ],
        ));
      }

      final images = controller.attachments.where((f) => controller.isImage(f['file_url'])).toList();
      final docs = controller.attachments.where((f) => !controller.isImage(f['file_url'])).toList();

      return ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (images.isNotEmpty) ...[
            Text('Images (${images.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                return _buildImageCard(context, images[index]);
              },
            ),
            const SizedBox(height: 24),
          ],

          if (docs.isNotEmpty) ...[
            Text('Documents (${docs.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...docs.map((doc) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                leading: _getFileIcon(doc['file_url']),
                title: Text(doc['file_name'] ?? 'File', overflow: TextOverflow.ellipsis),
                subtitle: Text(doc['file_url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share, size: 20),
                      onPressed: () => controller.shareFile(doc['file_url'], doc['file_name']),
                    ),
                  ],
                ),
                onTap: () => controller.copyLink(doc['file_url']),
              ),
            )),
          ],
        ],
      );
    });
  }

  Widget _buildDashboardTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Stock Balance Section
          const Text('Stock Balance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Obx(() {
            if (controller.isLoadingStock.value) return const LinearProgressIndicator();
            if (controller.stockLevels.isEmpty) return const Text('No stock data.', style: TextStyle(color: Colors.grey));

            return Column(
              children: [
                // Insert Graph Here
                StockBalanceChart(stockLevels: controller.stockLevels),
                const SizedBox(height: 12),

                // Detailed List
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: controller.stockLevels.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final stock = controller.stockLevels[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        title: Text(stock.warehouse, style: const TextStyle(fontSize: 14)),
                        subtitle: stock.rack != null && stock.rack!.isNotEmpty
                            ? Text('Rack: ${stock.rack}', style: TextStyle(fontSize: 12, color: Colors.blueGrey[400], fontFamily: 'monospace'))
                            : null,
                        trailing: Text(
                          stock.quantity.toStringAsFixed(2),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: stock.quantity > 0 ? Colors.green[700] : Colors.red[700],
                              fontFamily: 'monospace'
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: 24),

          // 2. Batch-Wise Balance Section
          const Text('Batch-Wise Balance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Obx(() {
            if (controller.isLoadingBatches.value) return const LinearProgressIndicator();
            if (controller.batchHistory.isEmpty) return const Text('No batch data available.', style: TextStyle(color: Colors.grey));

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: controller.batchHistory.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final batchRow = controller.batchHistory[index];
                    final batchNo = batchRow['batch_no'] ?? '-';
                    final warehouse = batchRow['warehouse'] ?? '';
                    final qty = (batchRow['balance_qty'] as num?)?.toDouble() ?? 0.0;

                    // Only show if there is a balance or recent activity
                    if (qty == 0) return const SizedBox.shrink();

                    return ListTile(
                      dense: true,
                      title: Text(batchNo, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      subtitle: Text(warehouse, style: const TextStyle(fontSize: 12)),
                      trailing: Text(
                        qty.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                    );
                  },
                ),
              ),
            );
          }),

          const SizedBox(height: 24),

          // 3. Stock Ledger Section
          const Text('Recent Ledger Entries', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Obx(() {
            if (controller.isLoadingLedger.value) return const LinearProgressIndicator();
            if (controller.stockLedgerEntries.isEmpty) return const Text('No recent transactions.', style: TextStyle(color: Colors.grey));

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: controller.stockLedgerEntries.length,
              itemBuilder: (context, index) {
                final entry = controller.stockLedgerEntries[index];
                final qtyChange = (entry['actual_qty'] as num?)?.toDouble() ?? 0.0;
                final isPositive = qtyChange >= 0;

                final type = entry['voucher_type'] ?? 'Transaction';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        // Row 1: Icon, Type, Qty
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isPositive ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text(entry['voucher_no'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace')),
                                ],
                              ),
                            ),
                            Text(
                              (isPositive ? '+' : '') + qtyChange.toStringAsFixed(2),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPositive ? Colors.green : Colors.red,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),

                        // Row 2: Details Context (Customer, PO, Ref)
                        if (type == 'Delivery Note' && (entry['customer'] != null || entry['po_no'] != null)) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entry['customer'] != null)
                                  _buildContextRow(Icons.person_outline, entry['customer']),
                                if (entry['po_no'] != null)
                                  _buildContextRow(Icons.receipt_long, 'PO: ${entry['po_no']}'),
                              ],
                            ),
                          ),
                        ] else if (type == 'Stock Entry' && (entry['stock_entry_type'] == 'Material Issue' || entry['custom_reference_no'] != null)) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entry['stock_entry_type'] != null)
                                  _buildContextRow(Icons.category_outlined, entry['stock_entry_type']),
                                if (entry['custom_reference_no'] != null)
                                  _buildContextRow(Icons.link, 'Ref: ${entry['custom_reference_no']}'),
                              ],
                            ),
                          ),
                        ],

                        // Row 3: Warehouse & Batch
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${entry['posting_date']} ${entry['posting_time']}',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                            Row(
                              children: [
                                if (entry['warehouse'] != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(entry['warehouse'], style: TextStyle(fontSize: 10, color: Colors.blue.shade900)),
                                  ),
                                if (entry['batch_no'] != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(entry['batch_no'], style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontFamily: 'monospace')),
                                  ),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildContextRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildImageCard(BuildContext context, Map<String, dynamic> file) {
    final url = 'https://erp.multimax.cloud${file['file_url']}';
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Container(
              color: Colors.grey.shade100,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ),
              ),
              child: Text(
                file['file_name'] ?? 'Image',
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showImageDialog(context, url, file),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.share, color: Colors.white, size: 16),
                onPressed: () => controller.shareFile(file['file_url'], file['file_name']),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, String url, Map<String, dynamic> file) {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.1,
              maxScale: 4.0,
              child: Image.network(url),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Get.back(),
              ),
            ),
            Positioned(
              bottom: 40,
              child: ElevatedButton.icon(
                  onPressed: () {
                    Get.back();
                    controller.shareFile(file['file_url'], file['file_name']);
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share Image')
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getFileIcon(String? url) {
    if (url == null) return const Icon(Icons.insert_drive_file);
    if (url.endsWith('.pdf')) return const Icon(Icons.picture_as_pdf, color: Colors.red);
    if (url.endsWith('.csv') || url.endsWith('.xlsx')) return const Icon(Icons.table_chart, color: Colors.green);
    return const Icon(Icons.insert_drive_file, color: Colors.blueGrey);
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