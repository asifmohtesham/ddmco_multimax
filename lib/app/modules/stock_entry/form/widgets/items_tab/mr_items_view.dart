import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/mr_item_filter_bar.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/items_tab/empty_scan_state.dart';
import 'package:multimax/app/shared/item_card/doc_item_card.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';

/// Items list driven by a Material Request reference.
class MrItemsView extends StatelessWidget {
  final StockEntryFormController controller;
  final StockEntry entry;

  const MrItemsView({
    super.key,
    required this.controller,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final rows = controller.mrFilteredItems;

      if (rows.isEmpty && controller.mrReferenceItems.isEmpty) {
        return const EmptyScanState();
      }

      return Column(
        children: [
          if (controller.isMaterialRequestEntry) const MrItemFilterBar(),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'No ${controller.mrItemFilter.value.toLowerCase()} items.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: controller.scrollController,
                    padding: const EdgeInsets.only(
                        top: 4.0, bottom: 100.0),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 0),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final isEditable =
                          controller.stockEntry.value?.docstatus == 0;

                      final realItem = entry.items.firstWhereOrNull(
                        (i) =>
                            i.itemCode.trim().toLowerCase() ==
                            row.itemCode.trim().toLowerCase(),
                      );

                      // Phantom item for rows not yet received.
                      final displayItem = realItem ??
                          StockEntryItem(
                            name:     null,
                            itemCode: row.itemCode,
                            qty:      0,
                            basicRate: 0.0,
                            itemGroup:          null,
                            customVariantOf:     null,
                            batchNo:             null,
                            itemName:            row.itemCode,
                            rack:                null,
                            toRack:              null,
                            sWarehouse:          null,
                            tWarehouse:          null,
                            customInvoiceSerialNumber: null,
                            materialRequest:     row.materialRequest,
                            materialRequestItem: row.materialRequestItem,
                          );

                      if (realItem != null) {
                        controller.ensureItemKey(realItem);
                      }

                      // Build CardData with targetQty = row.requestedQty so
                      // DocItemProgressBar shows fulfilment progress.
                      final cardData = ItemCardData.fromStockEntryItem(
                        displayItem,
                        index:      index,
                        isEditable: isEditable && realItem != null,
                      ).copyWithTargetQty(row.requestedQty);

                      return DocItemCard(
                        key:  realItem != null
                            ? controller.itemKeys[realItem.name]
                            : null,
                        data: cardData,
                        onTap: realItem != null && isEditable
                            ? () => controller.editItem(realItem)
                            : null,
                        onDelete: realItem != null &&
                                realItem.name != null &&
                                isEditable
                            ? () =>
                                controller.confirmAndDeleteItem(realItem)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }
}
