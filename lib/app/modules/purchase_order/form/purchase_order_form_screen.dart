import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_order_item_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class PurchaseOrderFormScreen extends GetView<PurchaseOrderFormController> {
  const PurchaseOrderFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => PopScope(
      canPop: !controller.isDirty.value,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await controller.confirmDiscard();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Obx(() => Text(controller.purchaseOrder.value?.name ?? 'Loading...')),
            actions: [
              Obx(() => controller.isSaving.value
                  ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
                  : IconButton(
                icon: Icon(Icons.save, color: (controller.isDirty.value && controller.isEditable) ? Colors.white : Colors.white54),
                onPressed: (controller.isDirty.value && controller.isEditable) ? controller.savePurchaseOrder : null,
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

            return SafeArea(
              child: TabBarView(
                children: [
                  _buildDetailsView(context, po), // Passed context for bottom sheet
                  _buildItemsView(po),
                ],
              ),
            );
          }),
        ),
      ),
    ));
  }

  Widget _buildDetailsView(BuildContext context, dynamic po) {
    final bool isEditable = controller.isEditable;

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

          // SEARCHABLE SUPPLIER FIELD
          GestureDetector(
            onTap: isEditable ? () => _showSupplierSelectionSheet(context) : null,
            child: AbsorbPointer(
              child: TextFormField(
                controller: controller.supplierController,
                decoration: const InputDecoration(
                  labelText: 'Supplier',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                readOnly: true, // Always read-only, tap handled by parent
              ),
            ),
          ),

          const SizedBox(height: 16),
          TextFormField(
            controller: controller.dateController,
            decoration: const InputDecoration(
              labelText: 'Transaction Date',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today),
            ),
            readOnly: !isEditable,
            // Add date picker onTap if needed
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

  void _showSupplierSelectionSheet(BuildContext context) {
    final searchController = TextEditingController();
    final RxList<String> filteredSuppliers = RxList<String>(controller.suppliers);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Supplier', style: Theme.of(context).textTheme.titleLarge),
                      IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Suppliers',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      if (val.isEmpty) {
                        filteredSuppliers.assignAll(controller.suppliers);
                      } else {
                        filteredSuppliers.assignAll(controller.suppliers.where(
                                (s) => s.toLowerCase().contains(val.toLowerCase())));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingSuppliers.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (filteredSuppliers.isEmpty) {
                        return const Center(child: Text('No suppliers found'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: filteredSuppliers.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final supplier = filteredSuppliers[index];
                          final isSelected = supplier == controller.supplierController.text;
                          return ListTile(
                            title: Text(supplier, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor) : null,
                            onTap: () {
                              controller.supplierController.text = supplier;
                              Get.back();
                            },
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
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
    return Column(
      children: [
        Expanded(
          child: po.items.isEmpty
              ? const Center(child: Text('No items in this order.'))
              : ListView.builder(
            padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
            itemCount: po.items.length,
            itemBuilder: (context, index) {
              final item = po.items[index];
              return InkWell(
                onTap: () => controller.editItem(item),
                child: PurchaseOrderItemCard(item: item, index: index),
              );
            },
          ),
        ),
        if (controller.isEditable)
          Obx(() => BarcodeInputWidget(
            onScan: (code) => controller.scanBarcode(code),
            isLoading: controller.isScanning.value,
            controller: controller.barcodeController,
            hintText: 'Scan Item Code',
            activeRoute: AppRoutes.PURCHASE_ORDER_FORM,
          )),
      ],
    );
  }
}