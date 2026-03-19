import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/controllers/stock_entry_item_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_serial_field.dart';
import 'item_form_sheet/batch_field.dart';
import 'item_form_sheet/rack_section.dart';

/// Stock Entry item-entry bottom sheet.
///
/// Now a thin wrapper around [UniversalItemFormSheet].
/// Differences from Delivery Note:
///   • onScan is null (SE scan bar lives at document level, not inside sheet)
///   • isSaveEnabled guarded by docstatus == 0
///   • onSubmit → parentController.addItem (SE centralises save in parent)
///   • itemSubtext shows variant-of code
///   • customFields: BatchField (SE-specific), SharedSerialField, RackSection
///
/// formKey now comes from itemController.formKey (base field) rather than
/// parentController.itemFormKey — the parent field is kept for compatibility
/// but no longer used here.
class StockEntryItemFormSheet extends StatelessWidget {
  final StockEntryFormController     parentController;
  final StockEntryItemFormController itemController;
  final ScrollController?            scrollController;

  const StockEntryItemFormSheet({
    super.key,
    required this.parentController,
    required this.itemController,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final docStatus = parentController.stockEntry.value?.docstatus ?? 0;

      return UniversalItemFormSheet(
        key:              ValueKey(itemController.editingItemName.value ?? 'new'),
        controller:       itemController,
        scrollController: scrollController,
        onSubmit:         parentController.addItem,
        onScan:           null, // SE routes scans at doc level
        itemSubtext:      parentController.currentVariantOf,
        isSaveEnabled:    docStatus == 0,

        customFields: [
          // 1. Batch No (SE-specific widget with dual-balance chips)
          BatchField(controller: itemController),

          // 2. Invoice Serial No (POS Upload flow only)
          SharedSerialField(
            controller: itemController,
            accentColor: Colors.blueGrey,
          ),

          // 3. Source + Target Rack (SE dual-rack layout)
          RackSection(controller: itemController),
        ],
      );
    });
  }
}
