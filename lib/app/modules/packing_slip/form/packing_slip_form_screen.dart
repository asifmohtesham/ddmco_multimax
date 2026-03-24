import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/item_group_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';

class PackingSlipFormScreen extends GetView<PackingSlipFormController> {
  const PackingSlipFormScreen({super.key});

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
          appBar: Obx(() {
            final slip = controller.packingSlip.value;
            final titleWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slip?.name ?? 'Loading...',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                if (slip?.customPoNo != null)
                  Text(
                    slip!.customPoNo!,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
              ],
            );
            return MainAppBar(
              title:      slip?.name ?? 'Packing Slip',
              titleWidget: titleWidget,
              status:     slip?.status,
              isDirty:    controller.isDirty.value,
              isSaving:   controller.isSaving.value,
              saveResult: SaveResult.idle,
              onSave: (slip?.docstatus == 0 && controller.isDirty.value)
                  ? controller.savePackingSlip
                  : null,
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
      ),
    ));
  }

  // ── Details tab ──────────────────────────────────────────────────────────

  Widget _buildDetailsView(PackingSlip slip) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          _buildSectionCard(
            title: 'General Information',
            children: [
              if (slip.name != 'New Packing Slip') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(slip.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16))),
                    StatusPill(status: slip.status),
                  ],
                ),
                const Divider(height: 24),
              ],
              TextFormField(
                key:          ValueKey(slip.customer),
                initialValue: slip.customer ?? '',
                readOnly:     true,
                decoration:   const InputDecoration(
                  labelText:  'Customer',
                  border:     OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                  filled:     true,
                  fillColor:  Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Package Details',
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: slip.fromCaseNo?.toString() ?? '',
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: 'From Case No',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: slip.toCaseNo?.toString() ?? '',
                      readOnly: true,
                      decoration: const InputDecoration(
                          labelText: 'To Case No',
                          border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'References',
            children: [
              TextFormField(
                initialValue: slip.deliveryNote,
                readOnly:     true,
                decoration:   const InputDecoration(
                  labelText:  'Delivery Note',
                  prefixIcon: Icon(Icons.description_outlined),
                  border:     OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: slip.customPoNo ?? '',
                readOnly:     true,
                decoration:   const InputDecoration(
                  labelText:  'PO Number',
                  prefixIcon: Icon(Icons.receipt_long),
                  border:     OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  // ── Items tab ─────────────────────────────────────────────────────────────

  Widget _buildItemsView(PackingSlip slip) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: 16.0, vertical: 8.0),
          child: Obx(() => Row(
            children: [
              _buildFilterChip('All',       controller.allCount),
              const SizedBox(width: 8),
              _buildFilterChip('Pending',   controller.pendingCount),
              const SizedBox(width: 8),
              _buildFilterChip('Completed', controller.completedCount),
            ],
          )),
        ),
        const Divider(height: 1),
        Expanded(
          child: Obx(() {
            final visibleGroups = controller.visibleGroupKeys;
            if (visibleGroups.isEmpty) {
              return const Center(child: Text('No items to display.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.only(
                  top: 8.0, bottom: 80.0, left: 8.0, right: 8.0),
              itemCount: visibleGroups.length,
              itemBuilder: (context, index) {
                final serial        = visibleGroups[index];
                final totalRequired = controller.getTotalDnQtyForSerial(serial);
                final globalPacked  = controller.getGlobalPackedQty(serial);

                String itemName = controller.getPosItemName(serial);
                if (itemName.isEmpty) {
                  final dnItems = controller.getDnItemsForSerial(serial);
                  itemName = dnItems.isNotEmpty
                      ? (dnItems.first.itemName ?? '')
                      : 'Unknown Item';
                }

                final sectionItems = controller.getDnItemsForSerial(serial);

                return Obx(() {
                  final isExpanded =
                      controller.expandedInvoice.value == serial;
                  return ItemGroupCard(
                    isExpanded: isExpanded,
                    serialNo:   int.tryParse(serial) ?? 0,
                    itemName:   itemName,
                    rate:       0.0,
                    totalQty:   totalRequired,
                    scannedQty: globalPacked,
                    onToggle:   () => controller.toggleInvoiceExpand(serial),
                    children: sectionItems.map((dnItem) {
                      final reqQty          = dnItem.qty;
                      final packedQty       = controller.getPackedQtyForDnItem(dnItem.name);
                      final currentSlipItem = controller.getCurrentSlipItem(dnItem.name);
                      return _buildChecklistRow(
                          dnItem, reqQty, packedQty, currentSlipItem);
                    }).toList(),
                  );
                });
              },
            );
          }),
        ),
        if (slip.docstatus == 0)
          Obx(() => BarcodeInputWidget(
            onScan:      (code) => controller.scanBarcode(code),
            isLoading:   controller.isScanning.value,
            hintText:    'Scan Item / Batch',
            controller:  controller.barcodeController,
            activeRoute: AppRoutes.PACKING_SLIP_FORM,
          )),
      ],
    );
  }

  // ── Checklist row with F6 Dismissible + F7 loading overlay ──────────────────

  Widget _buildChecklistRow(
    dynamic dnItem,
    double reqQty,
    double packedQty,
    PackingSlipItem? currentItem,
  ) {
    final bool isComplete      = packedQty >= reqQty;
    final bool isInCurrentSlip = currentItem != null;
    final bool canEdit         = controller.packingSlip.value?.docstatus == 0;

    // F7: wrap in Obx so loading flag is reactive
    return Obx(() {
      final isLoadingThis =
          controller.isLoadingItemEdit.value &&
          controller.loadingForItemName.value == (currentItem?.name ?? '');

      // F6: Dismissible only when the item exists in the current slip
      //     and the document is editable. Non-slip rows are plain InkWell.
      final inner = InkWell(
        onTap: () {
          if (isInCurrentSlip) {
            controller.isLoadingItemEdit.value  = true;
            controller.loadingForItemName.value = currentItem!.name;
            controller.editItem(currentItem);
            controller.isLoadingItemEdit.value  = false;
            controller.loadingForItemName.value = null;
          } else {
            if (canEdit) controller.prepareSheetForAdd(dnItem);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              // Status icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isComplete
                      ? Colors.green.shade50
                      : (packedQty > 0
                          ? Colors.orange.shade50
                          : Colors.grey.shade100),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isComplete
                      ? Icons.check
                      : Icons.inventory_2_outlined,
                  size:  16,
                  color: isComplete
                      ? Colors.green.shade700
                      : (packedQty > 0
                          ? Colors.orange.shade700
                          : Colors.grey),
                ),
              ),
              const SizedBox(width: 12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dnItem.itemCode,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      dnItem.itemName,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dnItem.batchNo != null)
                      Text(
                        'Batch: ${dnItem.batchNo}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade700),
                      ),
                  ],
                ),
              ),

              // Progress
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${FormattingHelper.formatQty(packedQty)} / ${FormattingHelper.formatQty(reqQty)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isComplete
                          ? Colors.green.shade700
                          : Colors.black87,
                    ),
                  ),
                  Text(
                    dnItem.uom,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),

              // Edit chevron
              if (canEdit)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.chevron_right,
                      size: 18, color: Colors.grey),
                ),
            ],
          ),
        ),
      );

      // F6: Dismissible wraps only items already in the slip
      final Widget rowWidget = (isInCurrentSlip && canEdit)
          ? Dismissible(
              key:       ValueKey(currentItem!.name),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                controller.confirmAndDeleteItem(currentItem);
                return false; // dialog owns the actual removal
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding:   const EdgeInsets.only(right: 20),
                color:     Colors.red.shade400,
                child:     const Icon(Icons.delete_outline,
                    color: Colors.white, size: 28),
              ),
              child: inner,
            )
          : inner;

      // F7: per-item loading overlay
      if (!isLoadingThis) return rowWidget;
      return Stack(
        children: [
          rowWidget,
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.65),
              child: const Center(
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildFilterChip(String label, int count) {
    return ChoiceChip(
      label:    Text('$label ($count)'),
      selected: controller.itemFilter.value == label,
      onSelected: (bool selected) {
        if (selected) controller.setFilter(label);
      },
    );
  }
}
