import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/shared/item_card/doc_item_card.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';
import 'package:multimax/app/shared/pos_upload/item_group_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class DeliveryNoteFormScreen extends GetView<DeliveryNoteFormController> {
  const DeliveryNoteFormScreen({super.key});

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
                title:   controller.deliveryNote.value?.name ?? 'Loading...',
                status:  controller.deliveryNote.value?.status,
                isDirty: controller.isDirty.value,
                onReload: (controller.mode != 'new' &&
                        !controller.isDirty.value)
                    ? controller.reloadDocument
                    : null,
                actions: [
                  Obx(() {
                    if (controller.deliveryNote.value?.docstatus == 1) {
                      return const SizedBox.shrink();
                    }
                    final canSave =
                        controller.isDirty.value &&
                        (controller.deliveryNote.value?.docstatus == 0);
                    return SaveIconButton(
                      isSaving:   controller.isSaving.value,
                      saveResult: controller.saveResult.value,
                      isDirty:    canSave,
                      onPressed:  canSave
                          ? controller.saveDeliveryNote
                          : null,
                    );
                  }),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Details'),
                    Tab(text: 'Items'),
                  ],
                ),
              ),
              body: Obx(() {
                if (controller.isLoading.value &&
                    controller.deliveryNote.value == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final note = controller.deliveryNote.value;
                if (note == null) {
                  return const Center(
                      child: Text('Delivery note not found.'));
                }
                return SafeArea(
                  child: TabBarView(
                    children: [
                      _buildDetailsView(context, note),
                      _buildItemsView(context),
                    ],
                  ),
                );
              }),
            ),
          ),
        ));
  }

  // ── Banner helper ─────────────────────────────────────────────────────────────

  Widget _buildBanner() {
    return Obx(() => InlineBanner(
          visible: controller.bannerVisible.value,
          message: controller.bannerMessage.value,
          type:    controller.bannerType.value,
        ));
  }

  // ── Details tab ───────────────────────────────────────────────────────────────

  Widget _buildDetailsView(BuildContext context, dynamic note) {
    final cs = Theme.of(context).colorScheme;
    final bool isEditable = note.docstatus == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBanner(),
          _buildSectionCard(
            context: context,
            title: 'General Information',
            children: [
              if (note.name != 'New Delivery Note') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Delivery Note ID',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12)),
                          Text(note.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: cs.onSurface)),
                        ],
                      ),
                    ),
                    StatusPill(
                        status: controller.isDirty.value
                            ? 'Not Saved'
                            : note.status),
                  ],
                ),
                const Divider(height: 24),
              ],
              Obx(() => TextFormField(
                    initialValue: note.customer,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Customer',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_outline),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      filled: true,
                      fillColor: cs.surface,
                      errorText: controller.customerError.value,
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
            title: 'Settings',
            children: [
              Obx(() => DropdownButtonFormField<String>(
                    value: controller.setWarehouse.value,
                    decoration: const InputDecoration(
                      labelText: 'Set Source Warehouse',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.store),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    hint: const Text('Select Warehouse'),
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
          if (note.poNo != null && note.poNo!.isNotEmpty)
            _buildSectionCard(
              context: context,
              title: 'References',
              children: [
                TextFormField(
                  initialValue: note.poNo,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Purchase Order (PO)',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long_outlined,
                        color: cs.secondary),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
              ],
            ),
          if (note.poNo != null && note.poNo!.isNotEmpty)
            const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
            title: 'Schedule',
            children: [
              const TextFormField(
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Posting Date',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
            title: 'Summary',
            children: [
              _buildSummaryRow(
                context,
                'Total Quantity',
                '${note.totalQty.toStringAsFixed(2)} Items',
              ),
              const Divider(),
              _buildSummaryRow(
                context,
                'Grand Total',
                '${FormattingHelper.getCurrencySymbol(note.currency)} '
                    '${note.grandTotal.toStringAsFixed(2)}',
                isBold: true,
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Items tab ─────────────────────────────────────────────────────────────────

  Widget _buildItemsView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Obx(() {
      if (controller.setWarehouse.value == null ||
          controller.setWarehouse.value!.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store_outlined,
                  size: 64, color: cs.outlineVariant),
              const SizedBox(height: 16),
              Text('Warehouse Not Selected',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(
                  'Please go to Details tab and set the Source Warehouse.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        );
      }

      return Column(
        children: [
          _buildBanner(),

          // ── Filters ──────────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: 16.0, vertical: 8.0),
            child: Obx(() => Row(
                  children: [
                    _buildFilterChip('All', controller.allCount),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                        'Pending', controller.pendingCount),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                        'Completed', controller.completedCount),
                  ],
                )),
          ),
          const Divider(height: 1),

          // ── Item List ────────────────────────────────────────────────────
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value &&
                  controller.posUpload.value == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final isEditable =
                  controller.deliveryNote.value?.docstatus == 0;
              final currentExpandedKey =
                  controller.expandedInvoice.value;
              final posUpload         = controller.posUpload.value;
              final deliveryNoteItems =
                  controller.deliveryNote.value?.items ?? [];
              final currency =
                  controller.deliveryNote.value?.currency;

              // ── Flat (non-POS) list ───────────────────────────────────
              if (posUpload == null) {
                if (deliveryNoteItems.isEmpty) {
                  return const Center(
                      child: Text('No items to display.'));
                }
                return ListView.builder(
                  controller: controller.scrollController,
                  padding: const EdgeInsets.only(
                      left: 8.0,
                      right: 8.0,
                      top: 8.0,
                      bottom: 80.0),
                  itemCount: deliveryNoteItems.length,
                  itemBuilder: (context, index) {
                    final item = deliveryNoteItems[index];
                    if (item.name != null &&
                        !controller.itemKeys
                            .containsKey(item.name)) {
                      controller.itemKeys[item.name!] = GlobalKey();
                    }
                    final isHighlighted =
                        controller.recentlyAddedItemName.value ==
                            item.name;

                    return Dismissible(
                      key: ValueKey(item.name ?? index),
                      direction: isEditable
                          ? DismissDirection.endToStart
                          : DismissDirection.none,
                      confirmDismiss: (_) async {
                        if (isEditable) {
                          await controller
                              .confirmAndDeleteItem(item);
                        }
                        return false;
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: cs.errorContainer,
                        child: Icon(Icons.delete_outline,
                            color: cs.onErrorContainer, size: 28),
                      ),
                      child: DocItemCard(
                        key:  controller.itemKeys[item.name],
                        data: ItemCardData.fromDeliveryNoteItem(
                          item,
                          isEditable:    isEditable,
                          isHighlighted: isHighlighted,
                        ),
                        onDelete: isEditable
                            ? () => controller
                                .confirmAndDeleteItem(item)
                            : null,
                      ),
                    );
                  },
                );
              }

              // ── POS-grouped list ──────────────────────────────────────
              final posItems       = posUpload.items;
              final groupedDnItems = controller.groupedItems;

              final filteredItems = posItems.where((posItem) {
                final serialNumber = posItem.idx.toString();
                final dnItemsForThisPosItem =
                    groupedDnItems[serialNumber] ?? [];
                final cumulativeQty = dnItemsForThisPosItem.fold(
                    0.0, (sum, item) => sum + item.qty);

                if (controller.itemFilter.value == 'Completed') {
                  return cumulativeQty >= posItem.quantity;
                } else if (controller.itemFilter.value == 'Pending') {
                  return cumulativeQty < posItem.quantity;
                }
                return true;
              }).toList();

              if (filteredItems.isEmpty) {
                return const Center(
                    child: Text('No items match the filter.'));
              }

              return ListView.builder(
                controller: controller.scrollController,
                padding: const EdgeInsets.only(
                    left: 8.0,
                    right: 8.0,
                    top: 8.0,
                    bottom: 80.0),
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final posItem      = filteredItems[index];
                  final serialNumber = posItem.idx.toString();
                  final dnItemsForThisPosItem =
                      groupedDnItems[serialNumber] ?? [];
                  final expansionKey = '${posItem.idx}';

                  if (!controller.itemKeys
                      .containsKey(expansionKey)) {
                    controller.itemKeys[expansionKey] = GlobalKey();
                  }

                  final cumulativeQty = dnItemsForThisPosItem.fold(
                      0.0, (sum, item) => sum + item.qty);

                  return Container(
                    key: controller.itemKeys[expansionKey],
                    child: ItemGroupCard(
                      isExpanded: currentExpandedKey == expansionKey,
                      serialNo:   posItem.idx,
                      itemName:   posItem.itemName,
                      rate:       posItem.rate,
                      totalQty:   posItem.quantity,
                      scannedQty: cumulativeQty,
                      currency:   currency,
                      onToggle: () =>
                          controller.toggleInvoiceExpand(expansionKey),
                      children: dnItemsForThisPosItem
                          .asMap()
                          .entries
                          .map((entry) {
                        final groupIndex = entry.key;
                        final item       = entry.value;
                        if (item.name != null &&
                            !controller.itemKeys
                                .containsKey(item.name)) {
                          controller.itemKeys[item.name!] =
                              GlobalKey();
                        }
                        final isHighlighted =
                            controller.recentlyAddedItemName.value ==
                                item.name;

                        return DocItemCard(
                          key:  controller.itemKeys[item.name],
                          data: ItemCardData.fromDeliveryNoteItem(
                            item,
                            index:         groupIndex,
                            isEditable:    isEditable,
                            isHighlighted: isHighlighted,
                          ),
                          onDelete: isEditable
                              ? () => controller
                                  .confirmAndDeleteItem(item)
                              : null,
                        );
                      }).toList(),
                    ),
                  );
                },
              );
            }),
          ),

          // ── Scanner ───────────────────────────────────────────────────────
          Obx(() {
            if (controller.deliveryNote.value?.docstatus != 0)
              return const SizedBox.shrink();
            if (controller.isItemSheetOpen.value ||
                controller.isLoadingItemEdit.value)
              return const SizedBox.shrink();

            if (controller.isScanning.value ||
                controller.isAddingItem.value) {
              return BarcodeInputWidget(
                onScan:      (code) {},
                isLoading:   controller.isScanning.value,
                isSuccess:   controller.isAddingItem.value,
                controller:  controller.barcodeController,
                activeRoute: AppRoutes.DELIVERY_NOTE_FORM,
              );
            }
            return BarcodeInputWidget(
              onScan:      (code) => controller.scanBarcode(code),
              controller:  controller.barcodeController,
              activeRoute: AppRoutes.DELIVERY_NOTE_FORM,
            );
          }),
        ],
      );
    });
  }

  // ── Shared helpers ────────────────────────────────────────────────────────────

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin:    EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value,
      {bool isBold = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                fontSize:   isBold ? 16 : 14,
                color:      isBold
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
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
