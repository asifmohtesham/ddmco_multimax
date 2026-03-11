import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class BatchWiseBalanceScreen extends GetView<BatchWiseBalanceController> {
  const BatchWiseBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Batch-Wise Balance'),
      body: Column(
        children: [
          // --- Filter Section ---
          ExpansionTile(
            title: const Text("Filters", style: TextStyle(fontWeight: FontWeight.w600)),
            initiallyExpanded: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Date Range
                    Row(
                      children: [
                        Expanded(child: _DateField(label: "From", controller: controller.fromDateController, onTap: () => controller.selectDate(context, controller.fromDateController))),
                        const SizedBox(width: 12),
                        Expanded(child: _DateField(label: "To", controller: controller.toDateController, onTap: () => controller.selectDate(context, controller.toDateController))),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: controller.itemCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Item Code',
                        prefixIcon: Icon(Icons.category_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: controller.batchNoController,
                      decoration: const InputDecoration(
                        labelText: 'Batch No',
                        prefixIcon: Icon(Icons.qr_code_2),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: controller.warehouseController,
                      decoration: const InputDecoration(
                        labelText: 'Warehouse (Optional)',
                        prefixIcon: Icon(Icons.warehouse_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: controller.runReport,
                        icon: const Icon(Icons.search),
                        label: const Text("Search History"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1),

          // --- Report Results ---
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.reportData.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                          "Enter filters to search history",
                          style: TextStyle(color: Colors.grey.shade500)
                      ),
                    ],
                  ),
                );
              }

              return SafeArea(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: controller.reportData.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = controller.reportData[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Item and Quantity
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row['item'] ?? 'Unknown Item',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      if (row['item_name'] != null && row['item_name'] != row['item'])
                                        Text(row['item_name'], style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.teal.withOpacity(0.2)),
                                  ),
                                  child: Text(
                                    "${row['balance_qty'] ?? 0}", // Field name might vary based on specific Frappe version report
                                    style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // Details Grid
                            Row(
                              children: [
                                Expanded(child: _DetailItem(label: "Batch", value: row['batch'])),
                                Expanded(child: _DetailItem(label: "Warehouse", value: row['warehouse'])),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                // Add Expiry Date if available in your specific report output
                                if (row['expiry_date'] != null)
                                  Expanded(child: _DetailItem(label: "Expiry", value: row['expiry_date'])),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String? value;
  const _DetailItem({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today, size: 16),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}