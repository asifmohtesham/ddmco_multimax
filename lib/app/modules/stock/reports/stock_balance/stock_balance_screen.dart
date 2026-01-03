import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class StockBalanceScreen extends GetView<StockBalanceController> {
  const StockBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Stock Balance'),
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
                    // Warehouse Dropdown
                    Obx(() => DropdownButtonFormField<String>(
                      value: controller.selectedWarehouse.value,
                      items: controller.warehouseList.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                      onChanged: (val) => controller.selectedWarehouse.value = val,
                      decoration: InputDecoration(
                        labelText: 'Warehouse *',
                        prefixIcon: const Icon(Icons.warehouse_rounded),
                        border: const OutlineInputBorder(),
                        suffix: controller.isWarehousesLoading.value
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                      ),
                    )),
                    const SizedBox(height: 12),

                    // Item Code Field
                    TextFormField(
                      controller: controller.itemCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Item Code (Optional)',
                        prefixIcon: Icon(Icons.qr_code),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: controller.runReport,
                        icon: const Icon(Icons.bar_chart_rounded),
                        label: const Text("Generate Report"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1),

          // --- Results Section ---
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
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text("No stock data found", style: TextStyle(color: Colors.grey.shade500)),
                      TextButton(
                          onPressed: controller.runReport,
                          child: const Text("Retry")
                      )
                    ],
                  ),
                );
              }
              return ListView.separated(
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(row['item_code'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                    "${row['bal_qty'] ?? 0} ${row['stock_uom'] ?? ''}",
                                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)
                                ),
                              ),
                            ],
                          ),
                          if (row['item_name'] != null && row['item_name'] != row['item_code'])
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(row['item_name'], style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _InfoColumn("Warehouse", row['warehouse']),
                              _InfoColumn("Rack", "${row['rack'] ?? 0}"),
                              // _InfoColumn("Valuation Rate", "${row['val_rate'] ?? 0}"),
                              // _InfoColumn("Total Value", "${row['bal_val'] ?? 0}"),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final String? value;
  const _InfoColumn(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}