import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_item_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

class PurchaseReceiptFormScreen extends GetView<PurchaseReceiptFormController> {
  const PurchaseReceiptFormScreen({super.key});

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
          // F9: wrap in Obx so status/dirty/saving all rebuild the app bar
          appBar: Obx(() {
            final receipt = controller.purchaseReceipt.value;
            return MainAppBar(
              title:      receipt?.name ?? 'Loading...',
              status:     receipt?.status,
              isDirty:    controller.isDirty.value,
              isSaving:   controller.isSaving.value,
              saveResult: controller.saveResult.value,
              // F9: onSave wired via standardised param (replaces manual actions: list)
              onSave: (receipt?.docstatus == 0 && controller.isDirty.value)
                  ? controller.savePurchaseReceipt
                  : null,
              // F9: onReload wired — was missing entirely
              onReload: (controller.mode != 'new' &&
                      !controller.isDirty.value)
                  ? controller.reloadDocument
                  : null,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Details'),
                  Tab(text: 'Items'),
                ],
              ),
            );
          }),
          body: Obx(() {
            if (controller.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }

            final receipt = controller.purchaseReceipt.value;
            if (receipt == null) {
              return const Center(
                  child: Text('Purchase receipt not found.'));
            }

            return SafeArea(
              child: TabBarView(
                children: [
                  _buildDetailsView(context, receipt),
                  _buildItemsView(context, receipt),
                ],
              ),
            );
          }),
        ),
      ),
    ));
  }

  // ── Details tab ───────────────────────────────────────────────────────

  Widget _buildDetailsView(BuildContext context, PurchaseReceipt receipt) {
    final bool isEditable = controller.isEditable;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Form(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              title: 'General Information',
              children: [
                if (receipt.name != 'New Purchase Receipt') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Receipt ID',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            Text(receipt.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ],
                        ),
                      ),
                      StatusPill(
                          status: controller.isDirty.value
                              ? 'Not Saved'
                              : receipt.status),
                    ],
                  ),
                  const Divider(height: 24),
                ],
                TextFormField(
                  controller: controller.supplierController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.business),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  readOnly: true,
                ),
              ],
            ),

            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Schedule',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: isEditable
                            ? () async {
                                final now    = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: now,
                                  firstDate: DateTime(now.year - 5),
                                  lastDate:  DateTime(now.year + 5),
                                );
                                if (picked != null) {
                                  controller.postingDateController.text =
                                      '${picked.year.toString().padLeft(4, '0')}-'
                                      '${picked.month.toString().padLeft(2, '0')}-'
                                      '${picked.day.toString().padLeft(2, '0')}';
                                }
                              }
                            : null,
                        child: AbsorbPointer(
                          child: TextFormField(
                            controller: controller.postingDateController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Posting Date',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: isEditable
                            ? () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (picked != null) {
                                  controller.postingTimeController.text =
                                      '${picked.hour.toString().padLeft(2, '0')}:'
                                      '${picked.minute.toString().padLeft(2, '0')}:00';
                                }
                              }
                            : null,
                        child: AbsorbPointer(
                          child: TextFormField(
                            controller: controller.postingTimeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Posting Time',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.access_time),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Settings',
              children: [
                Obx(() => DropdownButtonFormField<String>(
                      value: controller.setWarehouse.value,
                      decoration: const InputDecoration(
                        labelText: 'Set Accepted Warehouse',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.store),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                      items: controller.warehouses.map((wh) {
                        return DropdownMenuItem(
                            value: wh,
                            child: Text(wh,
                                overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: isEditable
                          ? (value) =>
                              controller.setWarehouse.value = value
                          : null,
                    )),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Summary',
              children: [
                _buildSummaryRow('Total Quantity',
                    '${receipt.totalQty.toStringAsFixed(2)} Items'),
                const Divider(),
                _buildSummaryRow(
                  'Grand Total',
                  '${FormattingHelper.getCurrencySymbol(receipt.currency)} '
                      '${receipt.grandTotal.toStringAsFixed(2)}',
                  isBold: true,
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────────────

  Widget _buildSectionCard(
      {required String title, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin:    EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize:   isBold ? 16 : 14,
              color:      isBold ? Colors.black87 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // ── Items tab ─────────────────────────────────────────────────────────────

  Widget _buildItemsView(BuildContext context, PurchaseReceipt receipt) {
    final items = receipt.items;

    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No items in this receipt.'))
              : ListView.builder(
                  controller: controller.scrollController,
                  padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    controller.ensureItemKey(item);

                    return Obx(() {
                      final isLoadingThis =
                          controller.isLoadingItemEdit.value &&
                          controller.loadingForItemName.value == item.name;

                      return Dismissible(
                        key:       ValueKey(item.name ?? index),
                        direction: controller.isEditable
                            ? DismissDirection.endToStart
                            : DismissDirection.none,
                        confirmDismiss: (_) async {
                          if (controller.isEditable) {
                            controller.confirmAndDeleteItem(item);
                          }
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding:   const EdgeInsets.only(right: 20),
                          color:     Colors.red.shade400,
                          child:     const Icon(Icons.delete_outline,
                              color: Colors.white, size: 28),
                        ),
                        child: Stack(
                          children: [
                            Container(
                              key: item.name != null
                                  ? controller.itemKeys[item.name]
                                  : null,
                              child: PurchaseReceiptItemCard(
                                item:  item,
                                index: index,
                              ),
                            ),
                            if (isLoadingThis)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width:  24,
                                      height: 24,
                                      child:  CircularProgressIndicator(
                                          strokeWidth: 2.5),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    });
                  },
                ),
        ),
        if (controller.isEditable)
          Obx(() => BarcodeInputWidget(
                onScan:      (code) => controller.scanBarcode(code),
                isLoading:   controller.isScanning.value,
                controller:  controller.barcodeController,
                activeRoute: AppRoutes.PURCHASE_RECEIPT_FORM,
              )),
      ],
    );
  }
}
