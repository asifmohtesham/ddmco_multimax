import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_order_item_card.dart';

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
          appBar: MainAppBar(
            title: controller.purchaseOrder.value?.name ?? 'Loading...',
            status: controller.purchaseOrder.value?.status,
            actions: [
              // ── IT-G: SaveIconButton replaces raw spinner + IconButton ──
              Obx(() => SaveIconButton(
                isSaving:   controller.isSaving.value,
                isDirty:    controller.isDirty.value && controller.isEditable,
                saveResult: controller.saveResult.value,
                onPressed:  (controller.isDirty.value && controller.isEditable)
                    ? controller.savePurchaseOrder
                    : null,
              )),
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
                  _buildDetailsView(context, po),
                  _buildItemsView(context, po),
                ],
              ),
            );
          }),
        ),
      ),
    ));
  }

  // ── Details tab ──────────────────────────────────────────────────────────

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

          // ── IT-G: GestureDetector delegates entirely to controller ──────
          GestureDetector(
            onTap: isEditable
                ? () => controller.openSupplierSelectionSheet()
                : null,
            child: AbsorbPointer(
              child: TextFormField(
                controller: controller.supplierController,
                decoration: const InputDecoration(
                  labelText: 'Supplier',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                readOnly: true,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── IT-G: Date field gains showDatePicker ──────────────────────
          GestureDetector(
            onTap: isEditable
                ? () async {
              final now  = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(now.year - 5),
                lastDate:  DateTime(now.year + 5),
              );
              if (picked != null) {
                controller.dateController.text =
                '${picked.year.toString().padLeft(4, '0')}-'
                    '${picked.month.toString().padLeft(2, '0')}-'
                    '${picked.day.toString().padLeft(2, '0')}';
              }
            }
                : null,
            child: AbsorbPointer(
              child: TextFormField(
                controller: controller.dateController,
                decoration: const InputDecoration(
                  labelText: 'Transaction Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
              ),
            ),
          ),

          const SizedBox(height: 16),
          _buildInfoRow('Currency', po.currency, icon: Icons.attach_money),
          const SizedBox(height: 16),
          _buildInfoRow(
            'Grand Total',
            '${FormattingHelper.getCurrencySymbol(po.currency)} '
                '${po.grandTotal.toStringAsFixed(2)}',
            icon: Icons.account_balance_wallet,
            isBold: true,
          ),
        ],
      ),
    );
  }

  // ── Items tab ─────────────────────────────────────────────────────────────

  Widget _buildItemsView(BuildContext context, dynamic po) {
    return Column(
      children: [
        Expanded(
          child: po.items.isEmpty
              ? const Center(child: Text('No items in this order.'))
              : ListView.builder(
            // ── IT-G: use controller scrollController ─────────────
            controller: controller.scrollController,
            padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
            itemCount: po.items.length,
            itemBuilder: (context, index) {
              final item = po.items[index];

              // Register GlobalKey for scroll-to-highlight
              controller.ensureItemKey(item);
              final key = controller.itemKeys[item.name];

              return _buildItemRow(context, item, index, key);
            },
          ),
        ),
        if (controller.isEditable)
          Obx(() => BarcodeInputWidget(
            onScan:      (code) => controller.scanBarcode(code),
            isLoading:   controller.isScanning.value,
            controller:  controller.barcodeController,
            hintText:    'Scan Item Code',
            activeRoute: AppRoutes.PURCHASE_ORDER_FORM,
          )),
      ],
    );
  }

  Widget _buildItemRow(
      BuildContext context,
      dynamic item,
      int index,
      GlobalKey? key,
      ) {
    return Obx(() {
