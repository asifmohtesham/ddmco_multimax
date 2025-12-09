import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_order_item_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class PurchaseOrderFormScreen extends GetView<PurchaseOrderFormController> {
  const PurchaseOrderFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.purchaseOrder.value?.name ?? 'Loading...')),
          actions: [
            Obx(() => controller.isSaving.value
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
                : IconButton(
              icon: const Icon(Icons.save),
              onPressed: controller.purchaseOrder.value?.docstatus == 0 ? controller.savePurchaseOrder : null,
            )
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Items'),
            ],
          ),
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          final po = controller.purchaseOrder.value;
          if (po == null) return const Center(child: Text('Not found'));

          return TabBarView(
            children: [
              _buildDetailsView(po),
              _buildItemsView(po),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(dynamic po) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Status', style: TextStyle(color: Colors.grey[600])),
              StatusPill(status: po.status),
            ],
          ),
          const Divider(height: 24),
          TextFormField(
            controller: controller.supplierController,
            decoration: const InputDecoration(labelText: 'Supplier', border: OutlineInputBorder()),
            readOnly: po.docstatus != 0,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: controller.dateController,
            decoration: const InputDecoration(
              labelText: 'Transaction Date',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today),
            ),
            readOnly: true, // Typically date picker
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Currency', po.currency, icon: Icons.attach_money),
          const SizedBox(height: 16),
          _buildInfoRow(
            'Grand Total',
            '${FormattingHelper.getCurrencySymbol(po.currency)} ${po.grandTotal.toStringAsFixed(2)}',
            icon: Icons.account_balance_wallet,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon, bool isBold = false}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.normal
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemsView(dynamic po) {
    if (po.items.isEmpty) return const Center(child: Text('No items'));
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: po.items.length,
      itemBuilder: (context, index) {
        return PurchaseOrderItemCard(item: po.items[index]);
      },
    );
  }
}