import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'item_form_sheet/batch_field.dart';
import 'item_form_sheet/rack_section.dart';

/// Slim orchestrator — all sub-blocks live in item_form_sheet/.
///
/// Steps applied:
///   1  BalanceChip        → item_form_sheet/balance_chip.dart
///   2  ValidatedRackField → item_form_sheet/validated_rack_field.dart
///   3  DerivedWarehouseLabel → item_form_sheet/derived_warehouse_label.dart
///   4  SE-type booleans   → use controller.requiresSourceWarehouse / requiresTargetWarehouse
///   5  BatchField         → item_form_sheet/batch_field.dart
///   6  RackSection        → item_form_sheet/rack_section.dart
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

      final maxStock = controller.bsMaxQty.value;
      final maxMr = controller.bsValidationMaxQty.value;
      String? qtyInfoText;
      if (maxStock > 0 && maxMr > 0) {
        qtyInfoText =
            'Avail: ${maxStock.toStringAsFixed(0)} \u2022 MR max: ${maxMr.toStringAsFixed(0)}';
      } else if (maxStock > 0) {
        qtyInfoText = 'Available: ${maxStock.toStringAsFixed(0)}';
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
            ? () => controller.deleteItem(controller.currentItemNameKey.value!)
            : null,

        owner: controller.bsItemOwner.value,
        creation: controller.bsItemCreation.value,
        modified: controller.bsItemModified.value,
        modifiedBy: controller.bsItemModifiedBy.value,

        customFields: [
          // ── Batch No (Step 5) ───────────────────────────────────────────
          BatchField(controller: controller),

          // ── Invoice Serial (conditional) ──────────────────────────────
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
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        controller.selectedSerial.value = value,
                  ),
                )),

          // ── Rack section (Steps 2, 3, 4, 6) ────────────────────────────
          RackSection(controller: controller),
        ],
      );
    });
  }
}
