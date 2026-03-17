import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_card.dart';

/// Items list for manual / standard Stock Entries.
/// Step 6 — extracted from StockEntryFormScreen._buildStandardItemsView().
class StandardItemsView extends StatelessWidget {
  final StockEntryFormController controller;
  final StockEntry entry;

  const StandardItemsView({
    super.key,
    required this.controller,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller.scrollController,
      padding: const EdgeInsets.only(top: 8.0, bottom: 100.0),
      itemCount: entry.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (context, index) {
        final item = entry.items[index];
        controller.ensureItemKey(item);
        return StockEntryItemCard(
          item: item,
          onTap: controller.stockEntry.value?.docstatus == 0
              ? () => controller.editItem(item)
              : null,
          onDelete: controller.stockEntry.value?.docstatus == 0
              ? () => controller.deleteItem(item.name!)
              : null,
        );
      },
    );
  }
}
