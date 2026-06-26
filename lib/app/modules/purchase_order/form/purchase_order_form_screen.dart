import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/realtime_sync_status_icon.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/shared/item_card/doc_item_card.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';

class PurchaseOrderFormScreen extends GetView<PurchaseOrderFormController> {
  const PurchaseOrderFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final po         = controller.purchaseOrder.value;
      final isDirty    = controller.isDirty.value;
      final isSaving   = controller.isSaving.value;
      final saveResult = controller.saveResult.value;
      final isLoading  = controller.isLoading.value;

      return PopScope(
        canPop: !isDirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await controller.confirmDiscard();
        },
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                DocTypeFormHeader(
                  title:       po?.name ?? 'Loading...',
                  docType:     'Purchase Order',
                  statusLabel: po?.status,
                  canSave:    isDirty && controller.isEditable,
                  docStatus:  po?.docstatus ?? 0,
                  isSaving:   isSaving,
                  saveResult: saveResult,
                  onSave: (isDirty && controller.isEditable)
                      ? controller.saveDocument
                      : null,
                  onReload: (controller.mode != 'new' && !isDirty)
                      ? controller.reloadDocument
                      : null,
                  extraActions: [
                    if (controller.canCreateReceipt)
                      // Wrapped in its own Obx: the form header is a
                      // SliverPersistentHeader whose shouldRebuild keys on
                      // extraActions.length, so a content-only swap (icon ->
                      // spinner) would not rebuild the header. The Obx makes
                      // this action self-react to isCreatingReceipt.
                      Obx(() => IconButton(
                        tooltip: 'Create Purchase Receipt',
                        icon: controller.isCreatingReceipt.value
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                ),
                              )
                            : const Icon(Icons.receipt_long),
                        onPressed: controller.isCreatingReceipt.value
                            ? null
                            : controller.createPurchaseReceipt,
                      )),
                    RealtimeSyncStatusIcon(
                      isConnected: controller.isRealtimeConnected,
                      isSyncing:   controller.isRemoteSyncing,
                    ),
                  ],
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: 'Details'),
                      Tab(text: 'Items'),
                    ],
                  ),
                ),
              ],
              body: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : po == null
                      ? const Center(child: Text('Not found'))
                      : TabBarView(
                          children: [
                            _buildDetailsView(context, po),
                            _buildItemsView(context, po),
                          ],
                        ),
            ),
          ),
        ),
      );
    });
  }

  // ── Details tab ────────────────────────────────────────────────────────────────

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

          GestureDetector(
            onTap: isEditable
                ? () async {
                    final now    = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate:   DateTime(now.year - 5),
                      lastDate:    DateTime(now.year + 5),
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

  // ── Items tab ───────────────────────────────────────────────────────────────────

  Widget _buildItemsView(BuildContext context, dynamic po) {
    return Column(
      children: [
        Expanded(
          child: po.items.isEmpty
              ? const Center(child: Text('No items in this order.'))
              : ListView.builder(
                  controller: controller.scrollController,
                  padding:    const EdgeInsets.only(top: 8.0, bottom: 80.0),
                  itemCount:  po.items.length,
                  itemBuilder: (context, index) {
                    final item = po.items[index];
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
        if (controller.canCreateReceipt)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: controller.isCreatingReceipt.value
                    ? null
                    : controller.createPurchaseReceipt,
                icon: controller.isCreatingReceipt.value
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.receipt_long),
                label: Text(controller.isCreatingReceipt.value
                    ? 'Creating…'
                    : 'Create Purchase Receipt'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
        SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
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
      final isHighlighted =
          controller.recentlyAddedItemName.value == item.name;
      final isLoadingThis =
          controller.isLoadingItemEdit.value &&
          controller.loadingForItemName.value == item.name;

      final cardData = ItemCardData.fromPurchaseOrderItem(
        item,
        index:         index,
        isEditable:    controller.isEditable,
        isHighlighted: isHighlighted,
      );

      return Dismissible(
        key:       ValueKey(item.name ?? index),
        direction: controller.isEditable
            ? DismissDirection.endToStart
            : DismissDirection.none,
        confirmDismiss: (_) async {
          bool confirmed = false;
          await Future.microtask(() {
            controller.deleteItem(item);
            confirmed = false;
          });
          return confirmed;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding:   const EdgeInsets.only(right: 20),
          color:     Colors.red.shade400,
          child:     const Icon(Icons.delete_outline,
              color: Colors.white, size: 28),
        ),
        child: DocItemCard(
          key:           key,
          data:          cardData,
          isLoadingEdit: isLoadingThis,
          onTap: controller.isEditable
              ? () => controller.editItem(item)
              : null,
          onDelete: controller.isEditable
              ? () => controller.deleteItem(item)
              : null,
        ),
      );
    });
  }

  // ── Shared helpers ────────────────────────────────────────────────────────────

  Widget _buildInfoRow(
    String label,
    String value, {
    IconData? icon,
    bool isBold = false,
  }) {
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
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                value,
                style: TextStyle(
                  fontSize:   16,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
