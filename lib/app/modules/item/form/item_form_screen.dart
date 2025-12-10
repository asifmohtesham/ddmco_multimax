import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/item/form/widgets/stock_balance_chart.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:intl/intl.dart';

class ItemFormScreen extends GetView<ItemFormController> {
  const ItemFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isModal = Get.currentRoute != AppRoutes.ITEM_FORM;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.item.value?.itemName ?? 'Item Details')),
          leading: isModal
              ? IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Get.back(),
          )
              : null,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Stock Levels'),
              Tab(text: 'Attributes'),
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
              _buildStockLevelsTab(context),
              _buildAttributesTab(context, item),
              _buildAttachmentsTab(context),
            ],
          );
        }),
      ),
    );
  }

  // --- Tab 2: Stock Levels (Revamped with Compact Batch Layout) ---
  Widget _buildStockLevelsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Stock Balance Chart
          const Text('Warehouse Balance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Obx(() {
            if (controller.isLoadingStock.value) return const LinearProgressIndicator();
            if (controller.stockLevels.isEmpty) {
              return _buildEmptyState('No stock available in any warehouse.');
            }
            return StockBalanceChart(stockLevels: controller.stockLevels);
          }),

          const SizedBox(height: 24),

          // 2. Batch-Wise History (Compact Layout)
          const Text('Batch-Wise Balance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Obx(() {
            if (controller.isLoadingBatches.value) return const LinearProgressIndicator();
            if (controller.batchHistory.isEmpty) {
              return const Text('No batch history found.', style: TextStyle(color: Colors.grey));
            }

            // Using Wrap for "At a Glance" view without scrolling
            return Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: controller.batchHistory.map((batch) {
                final dateStr = batch['stock_age_date'];
                final ageString = controller.getFormattedStockAge(dateStr);
                final batchNo = batch['batch_no'] ?? batch['batch'] ?? 'N/A';
                final qty = batch['balance_qty'];
                final warehouse = batch['warehouse'];

                return Container(
                  width: (MediaQuery.of(context).size.width / 1) - 18, // 1 items per row approx
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              batchNo,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (warehouse != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                              child: Text(warehouse, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                          '$qty ${controller.item.value?.stockUom ?? ''}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).primaryColor)
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Age: $ageString',
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          }),

          const SizedBox(height: 24),

          // 3. Ledger Entries
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Stock Ledger', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: Icon(
                    Icons.calendar_month,
                    color: controller.ledgerDateRange.value != null ? Theme.of(context).primaryColor : Colors.grey
                ),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: controller.ledgerDateRange.value
                  );
                  if (picked != null) controller.updateLedgerDateRange(picked);
                },
              ),
            ],
          ),

          if (controller.ledgerDateRange.value != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Chip(
                label: Text('${DateFormat('MM/dd').format(controller.ledgerDateRange.value!.start)} - ${DateFormat('MM/dd').format(controller.ledgerDateRange.value!.end)}'),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: controller.clearLedgerDateRange,
                visualDensity: VisualDensity.compact,
              ),
            ),

          Obx(() {
            if (controller.isLoadingLedger.value) return const LinearProgressIndicator();
            if (controller.stockLedgerEntries.isEmpty) {
              return const Text('No transactions found in this period.', style: TextStyle(color: Colors.grey));
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: controller.stockLedgerEntries.length,
              separatorBuilder: (c,i) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = controller.stockLedgerEntries[index];
                final qty = (entry['actual_qty'] as num).toDouble();
                final isPositive = qty > 0;

                String subtitle = '${entry['voucher_no']}';
                String? extraInfo;

                if (entry['voucher_type'] == 'Delivery Note' && entry['customer'] != null) {
                  extraInfo = 'Customer: ${entry['customer']}';
                } else if (entry['voucher_type'] == 'Stock Entry' &&
                    entry['stock_entry_type'] == 'Material Issue' &&
                    entry['custom_reference_no'] != null) {
                  extraInfo = 'Ref: ${entry['custom_reference_no']}';
                }

                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry['voucher_type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              '${isPositive ? '+' : ''}$qty',
                              style: TextStyle(
                                  color: isPositive ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                        if (extraInfo != null)
                          Text(extraInfo, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (entry['warehouse'] != null)
                              Text(entry['warehouse'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(
                                FormattingHelper.getRelativeTime('${entry['posting_date']} ${entry['posting_time']}'),
                                style: const TextStyle(fontSize: 11, color: Colors.grey)
                            ),
                          ],
                        )
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

  // ... (Other Tabs: Overview, Attributes, Attachments - No Changes) ...
  Widget _buildAttributesTab(BuildContext context, Item item) {
    if (item.attributes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.list_alt, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No attributes defined.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: item.attributes.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final attr = item.attributes[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(attr.attributeName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          trailing: Text(attr.attributeValue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        );
      },
    );
  }

  Widget _buildOverviewTab(BuildContext context, dynamic item) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _buildSectionCard(
            title: 'Inventory',
            children: [
              _buildDetailRow('Default UOM', item.stockUom ?? '-'),
              if (item.countryOfOrigin != null) ...[
                const Divider(),
                _buildDetailRow('Country of Origin', item.countryOfOrigin!),
              ]
            ],
          ),
          const SizedBox(height: 16),
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
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
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

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200)
      ),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: Colors.grey)),
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