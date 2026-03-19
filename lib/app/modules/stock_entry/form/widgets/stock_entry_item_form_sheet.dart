import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/controllers/stock_entry_item_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'item_form_sheet/batch_field.dart';
import 'item_form_sheet/rack_section.dart';

/// Slim orchestrator — all sub-blocks live in item_form_sheet/.
///
/// Receives both the parent [StockEntryFormController] (for docStatus guard,
/// confirmAndDeleteItem, posUploadSerialOptions) and the child
/// [StockEntryItemFormController] (for all sheet state).
class StockEntryItemFormSheet extends StatelessWidget {
  final StockEntryFormController       parentController;
  final StockEntryItemFormController   itemController;
  final ScrollController?              scrollController;

  const StockEntryItemFormSheet({
    super.key,
    required this.parentController,
    required this.itemController,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = itemController.editingItemName.value != null;
      final docStatus = parentController.stockEntry.value?.docstatus ?? 0;

      // Register effectiveMaxQty dependencies explicitly.
      // ignore: unused_local_variable
      final _a = itemController.maxQty.value;
      // ignore: unused_local_variable
      final _b = itemController.batchBalance.value;
      // ignore: unused_local_variable
      final _c = itemController.rackBalance.value;
      // ignore: unused_local_variable
      final _d = itemController.isSourceRackValid.value;

      final effectiveMax = itemController.effectiveMaxQty;
      final maxMr        = itemController.validationMaxQty.value;

      String? qtyInfoText;
      if (effectiveMax < 999999.0 && maxMr > 0) {
        qtyInfoText =
            'Avail: ${effectiveMax.toStringAsFixed(0)} \u2022 MR max: ${maxMr.toStringAsFixed(0)}';
      } else if (effectiveMax < 999999.0) {
        qtyInfoText = 'Available: ${effectiveMax.toStringAsFixed(0)}';
      } else if (maxMr > 0) {
        qtyInfoText = 'MR max: ${maxMr.toStringAsFixed(0)}';
      }

      return GlobalItemFormSheet(
        key:            ValueKey(itemController.editingItemName.value ?? 'new'),
        formKey:        parentController.itemFormKey,
        scrollController: scrollController,
        title:          isEditing ? 'Update Item' : 'Add Item',
        itemCode:       itemController.itemCode.value,
        itemName:       itemController.itemName.value,
        itemSubtext:    parentController.currentVariantOf,

        qtyController:  itemController.qtyController,
        onIncrement:    () => itemController.adjustQty(1),
        onDecrement:    () => itemController.adjustQty(-1),
        qtyInfoText:    qtyInfoText,

        isSaveEnabledRx: itemController.isSheetValid,
        isSaveEnabled:   docStatus == 0,

        isLoading:  parentController.isAddingItem.value,
        onSubmit:   parentController.addItem,
        onDelete:   isEditing
            ? () => parentController.confirmAndDeleteItem(
                  parentController.stockEntry.value!.items.firstWhere(
                    (i) => i.name == itemController.editingItemName.value,
                  ),
                )
            : null,

        owner:      itemController.itemOwner.value,
        creation:   itemController.itemCreation.value,
        modified:   itemController.itemModified.value,
        modifiedBy: itemController.itemModifiedBy.value,

        customFields: [
          BatchField(controller: itemController),

          if (parentController.posUploadSerialOptions.isNotEmpty)
            Obx(() => GlobalItemFormSheet.buildInputGroup(
                  label: 'Invoice Serial No',
                  color: Colors.blueGrey,
                  child: DropdownButtonFormField<String>(
                    value: itemController.selectedSerial.value,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    items: parentController.posUploadSerialOptions
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        itemController.selectedSerial.value = value,
                  ),
                )),

          RackSection(controller: itemController),
        ],
      );
    });
  }
}
