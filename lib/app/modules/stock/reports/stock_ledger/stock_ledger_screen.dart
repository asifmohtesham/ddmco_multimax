import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/stock_ledger/stock_ledger_controller.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class StockLedgerScreen extends GetView<StockLedgerController> {
  const StockLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Stock Ledger'),
      body: Column(
        children: [
          ExpansionTile(
            title: const Text("Filters", style: TextStyle(fontWeight: FontWeight.w600)),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: Column(
                  children: [
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
                      decoration: const InputDecoration(labelText: 'Item Code', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(onPressed: controller.runReport, child: const Text("Run Ledger")),
                    )
                  ],
                ),
              )
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) return const Center(child: CircularProgressIndicator());
              if (controller.reportData.isEmpty) return const Center(child: Text("No transactions found"));

              return SafeArea(
                child: ListView.builder(
                  itemCount: controller.reportData.length,
                  itemBuilder: (context, index) {
                    final row = controller.reportData[index];
                    final isIncoming = (row['actual_qty'] ?? 0) > 0;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(row['posting_date'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              const SizedBox(width: 8),
                              Text('${row['voucher_type'] ?? ''}: ${row['voucher_no'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const Spacer(),
                              // StatusPill(status: isIncoming ? 'In' : 'Out', color: isIncoming ? Colors.green : Colors.orange),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${row['item_code'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          if(row['batch_no'] != null)
                            Text("Batch: ${row['batch_no']}", style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                          if(row['rack'] != null)
                            Text("${row['rack']}", style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Qty: ${row['actual_qty']}", style: TextStyle(color: isIncoming ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.bold)),
                              Text("Bal: ${row['qty_after_transaction']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          )
                        ],
                      ),
                    );
                  },
                ),
              );
            }),
          )
        ],
      ),
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