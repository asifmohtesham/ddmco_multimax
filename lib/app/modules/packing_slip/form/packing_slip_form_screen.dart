import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/packing_slip/form/widgets/packing_slip_item_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';

class PackingSlipFormScreen extends GetView<PackingSlipFormController> {
  const PackingSlipFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() {
            final slip = controller.packingSlip.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slip?.name ?? 'Loading...', style: const TextStyle(fontSize: 14, color: Colors.white70)),
                if (slip?.customPoNo != null)
                  Text(slip!.customPoNo!, style: const TextStyle(fontSize: 16)),
              ],
            );
          }),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Items'),
            ],
          ),
          actions: [
            Obx(() => controller.isSaving.value
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
                : IconButton(
              icon: const Icon(Icons.save),
              onPressed: controller.packingSlip.value?.docstatus == 0 ? controller.savePackingSlip : null,
            )
            ),
          ],
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          final slip = controller.packingSlip.value;
          if (slip == null) {
            return const Center(child: Text('Document not found'));
          }

          return SafeArea(
            child: TabBarView(
              children: [
                _buildDetailsView(slip),
                _buildItemsView(slip),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(PackingSlip slip) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // 1. General Info
          _buildSectionCard(
            title: 'General Information',
            children: [
              if (slip.name != 'New Packing Slip') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(slip.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                    StatusPill(status: slip.status),
                  ],
                ),
                const Divider(height: 24),
              ],
              TextFormField(
                initialValue: slip.customer ?? '',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Customer',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Package Details
          _buildSectionCard(
            title: 'Package Details',
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: slip.fromCaseNo?.toString() ?? '',
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'From Case No', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: slip.toCaseNo?.toString() ?? '',
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'To Case No', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 3. References
          _buildSectionCard(
            title: 'References',
            children: [
              TextFormField(
                initialValue: slip.deliveryNote,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Delivery Note',
                  prefixIcon: Icon(Icons.description_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: slip.customPoNo ?? '',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'PO Number',
                  prefixIcon: Icon(Icons.receipt_long),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildItemsView(PackingSlip slip) {
    final items = slip.items;

    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No items packed yet.'))
              : ListView.builder(
            padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return PackingSlipItemCard(item: item, index: index);
            },
          ),
        ),
        if (slip.docstatus == 0)
          Obx(() => BarcodeInputWidget(
            onScan: (code) => controller.scanBarcode(code),
            isLoading: controller.isScanning.value,
            hintText: 'Scan Item / Batch',
            controller: controller.barcodeController,
            activeRoute: AppRoutes.PACKING_SLIP_FORM, // Add this
          )),
      ],
    );
  }
}