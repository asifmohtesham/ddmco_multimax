import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:ddmco_multimax/app/data/models/packing_slip_model.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';

class PackingSlipFormScreen extends GetView<PackingSlipFormController> {
  const PackingSlipFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.packingSlip.value?.name ?? 'Packing Slip')),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final slip = controller.packingSlip.value;
        if (slip == null) {
          return const Center(child: Text('Document not found'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(slip),
              const SizedBox(height: 24),
              const Text('Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildItemsList(slip.items),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildHeader(PackingSlip slip) {
    return Card(
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (slip.customPoNo != null && slip.customPoNo!.isNotEmpty)
                        Text(
                          slip.customPoNo!,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      if (slip.customPoNo == null || slip.customPoNo != slip.name)
                        Text(slip.name, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                StatusPill(status: slip.status),
              ],
            ),
            const SizedBox(height: 16),
            if (slip.customer != null && slip.customer!.isNotEmpty)
              _buildDetailRow('Customer', slip.customer!),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(child: _buildDetailBox('From Package No', '${slip.fromCaseNo ?? "-"}')),
                const SizedBox(width: 16),
                Expanded(child: _buildDetailBox('To Package No', '${slip.toCaseNo ?? "-"}')),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Delivery Note', slip.deliveryNote),
            _buildDetailRow('Created', slip.creation),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDetailBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, textBaseline: TextBaseline.alphabetic)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildItemsList(List<PackingSlipItem> items) {
    if (items.isEmpty) return const Text('No items found.');
    
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (item.customInvoiceSerialNumber != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          '#${item.customInvoiceSerialNumber}',
                          style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    Text('${item.qty} ${item.uom}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                if (item.itemName.isNotEmpty)
                  Text(item.itemName, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (item.batchNo.isNotEmpty) _buildItemStat('Batch', item.batchNo),
                    if (item.customVariantOf != null) _buildItemStat('Variant Of', item.customVariantOf!),
                    if (item.customCountryOfOrigin != null) _buildItemStat('Origin', item.customCountryOfOrigin!),
                    _buildItemStat('Net Weight', '${item.netWeight} kg'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
