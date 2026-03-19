import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'item_form_sheet/batch_field.dart';
import 'item_form_sheet/rack_section.dart';

/// Slim orchestrator — all sub-blocks live in item_form_sheet/.
class StockEntryItemFormSheet extends StatelessWidget {
  final StockEntryFormController controller;
  final ScrollController? scrollController;

  const StockEntryItemFormSheet({
    super.key,
    required this.controller,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.currentItemNameKey.value != null;
      final docStatus = controller.stockEntry.value?.docstatus ?? 0;

      // Explicitly read every Rx field that effectiveMaxQty depends on so
      // that Obx registers them as reactive dependencies.
      // ignore: unused_local_variable
      final _ = controller.bsMaxQty.value;
      // ignore: unused_local_variable
      final __ = controller.bsBatchBalance.value;
      // ignore: unused_local_variable
      final ___ = controller.bsRackBalance.value;
      // ignore: unused_local_variable
      final ____ = controller.isSourceRackValid.value;

      final effectiveMax = controller.effectiveMaxQty;
      final maxMr = controller.bsValidationMaxQty.value;

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
        key: ValueKey(controller.currentItemNameKey.value ?? 'new'),
        formKey: controller.itemFormKey,
        scrollController: scrollController,
        title: isEditing ? 'Update Item' : 'Add Item',
        itemCode: controller.currentItemCode,
        itemName: controller.currentItemName,
        itemSubtext: controller.currentVariantOf,

        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),
        qtyInfoText: qtyInfoText,

        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: docStatus == 0,

        isLoading: controller.isAddingItem.value,
        onSubmit: controller.addItem,
        onDelete: isEditing
            ? () => controller.confirmAndDeleteItem(
                  controller.stockEntry.value!.items.firstWhere(
                    (i) => i.name == controller.currentItemNameKey.value,
                  ),
                )
            : null,

        owner: controller.bsItemOwner.value,
        creation: controller.bsItemCreation.value,
        modified: controller.bsItemModified.value,
        modifiedBy: controller.bsItemModifiedBy.value,

        customFields: [
          BatchField(controller: controller),

          if (controller.posUploadSerialOptions.isNotEmpty)
            Obx(() => GlobalItemFormSheet.buildInputGroup(
                  label: 'Invoice Serial No',
                  color: Colors.blueGrey,
                  child: DropdownButtonFormField<String>(
                    value: controller.selectedSerial.value,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    items: controller.posUploadSerialOptions
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        controller.selectedSerial.value = value,
                  ),
                )),

          RackSection(controller: controller),
        ],
      );
    });
  }
}
