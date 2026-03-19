import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_card.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/item_group_card.dart';

/// Items list grouped by POS Upload invoice serial.
class PosUploadItemsView extends StatelessWidget {
  final StockEntryFormController controller;
  final StockEntry entry;

  const PosUploadItemsView({
    super.key,
    required this.controller,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.posUpload.value == null) {
        return const Center(child: CircularProgressIndicator());
      }

      final posUpload = controller.posUpload.value!;
      final groupedItems = controller.groupedItems;

      return ListView.builder(
        controller: controller.scrollController,
        padding: const EdgeInsets.only(
            top: 8.0, bottom: 100.0, left: 8.0, right: 8.0),
        itemCount: posUpload.items.length,
        itemBuilder: (context, index) {
          final posItem = posUpload.items[index];
          final serialNumber = posItem.idx.toString();
          final expansionKey = serialNumber;

          final itemsInGroup = groupedItems[serialNumber] ?? [];
          final currentScannedQty =
              itemsInGroup.fold(0.0, (sum, item) => sum + item.qty);

          return Obx(() {
            final isExpanded =
                controller.expandedInvoice.value == expansionKey;

            return ItemGroupCard(
              isExpanded: isExpanded,
              serialNo: posItem.idx,
              itemName: posItem.itemName,
              rate: posItem.rate,
              totalQty: posItem.quantity,
              scannedQty: currentScannedQty,
              onToggle: () => controller.toggleInvoiceExpand(expansionKey),
              children: itemsInGroup.map((item) {
                controller.ensureItemKey(item);
                return Container(
                  key: item.name != null
                      ? controller.itemKeys[item.name]
                      : null,
                  child: StockEntryItemCard(
                    item: item,
                    onTap: controller.stockEntry.value?.docstatus == 0
                        ? () => controller.editItem(item)
                        : null,
                    onDelete: controller.stockEntry.value?.docstatus == 0
                        ? () => controller.confirmAndDeleteItem(item)
                        : null,
                  ),
                );
              }).toList(),
            );
          });
        },
      );
    });
  }
}
