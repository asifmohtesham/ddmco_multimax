import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/shared/item_card/doc_item_card.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';

/// Items list for manual / standard Stock Entries.
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
    final isEditable = entry.docstatus == 0;

    return ListView.separated(
      controller: controller.scrollController,
      padding: const EdgeInsets.only(top: 8.0, bottom: 100.0),
      itemCount: entry.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (context, index) {
        final item = entry.items[index];
        controller.ensureItemKey(item);

        return DocItemCard(
          key:  controller.itemKeys[item.name],
          data: ItemCardData.fromStockEntryItem(
            item,
            index:      index,
            isEditable: isEditable,
          ),
          onTap:    isEditable ? () => controller.editItem(item) : null,
          onDelete: isEditable
              ? () => controller.confirmAndDeleteItem(item)
              : null,
        );
      },
    );
  }
}
