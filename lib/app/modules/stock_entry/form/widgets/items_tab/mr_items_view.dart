import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_card.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/mr_item_filter_bar.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/items_tab/empty_scan_state.dart';

/// Items list driven by a Material Request reference.
/// Step 6 — extracted from StockEntryFormScreen._buildMaterialRequestItemsView().
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

                      final realItem = entry.items.firstWhereOrNull(
                        (i) =>
                            i.itemCode.trim().toLowerCase() ==
                            row.itemCode.trim().toLowerCase(),
                      );

                      final displayItem = realItem ??
                          StockEntryItem(
                            name: null,
                            itemCode: row.itemCode,
                            qty: 0,
                            basicRate: 0.0,
                            itemGroup: null,
                            customVariantOf: null,
                            batchNo: null,
                            itemName: row.itemCode,
                            rack: null,
                            toRack: null,
                            sWarehouse: null,
                            tWarehouse: null,
                            customInvoiceSerialNumber: null,
                            materialRequest: row.materialRequest,
                            materialRequestItem:
                                row.materialRequestItem,
                          );

                      if (realItem != null) {
                        controller.ensureItemKey(realItem);
                      }

                      return StockEntryItemCard(
                        item: displayItem,
                        maxQty: row.requestedQty,
                        onTap: realItem != null &&
                                controller.stockEntry.value
                                        ?.docstatus ==
                                    0
                            ? () => controller.editItem(realItem)
                            : null,
                        onDelete: realItem != null &&
                                realItem.name != null &&
                                controller.stockEntry.value
                                        ?.docstatus ==
                                    0
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
