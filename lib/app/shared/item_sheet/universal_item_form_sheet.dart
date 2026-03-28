import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'item_sheet_controller_base.dart';

/// Universal wrapper around [GlobalItemFormSheet] for all DocType item sheets.
///
/// Commit C-4:
///   Passes [controller.qtyInfoTooltip] as [qtyInfoTooltip] to
///   [GlobalItemFormSheet], which wires it to [QuantityInputWidget.onInfoTap].
///   Sheets whose controller returns null (the base default) are unaffected.
class UniversalItemFormSheet extends StatelessWidget {
  final ItemSheetControllerBase controller;
  final List<Widget> customFields;
  final Future<void> Function() onSubmit;
  final void Function(String)? onScan;
  final String? itemSubtext;
  final bool isSaveEnabled;
  final ScrollController? scrollController;

  const UniversalItemFormSheet({
    super.key,
    required this.controller,
    required this.customFields,
    required this.onSubmit,
    this.onScan,
    this.itemSubtext,
    this.isSaveEnabled = true,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.editingItemName.value != null;

      return GlobalItemFormSheet(
        key: const ValueKey('universal_item_sheet'),

        // ── Identity ────────────────────────────────────────────────────────
        formKey:          controller.formKey,
        scrollController: scrollController,
        title:            isEditing ? 'Update Item' : 'Add Item',
        itemCode:         controller.itemCode.value,
        itemName:         controller.itemName.value,
        itemSubtext:      itemSubtext,

        // ── Metadata footer ─────────────────────────────────────────────
        owner:      controller.itemOwner.value,
        creation:   controller.itemCreation.value,
        modified:   controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // ── Qty ──────────────────────────────────────────────────────────────
        qtyController:  controller.qtyController,
        onIncrement:    () => controller.adjustQty(1),
        onDecrement:    () => controller.adjustQty(-1),
        qtyInfoText:    controller.qtyInfoText,
        qtyInfoTooltip: controller.qtyInfoTooltip,

        // ── Save / delete ──────────────────────────────────────────────
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled:   isSaveEnabled,
        isLoading:       controller.isSheetLoading,
        onSubmit:        onSubmit,
        onDelete: isEditing
            ? () => controller.deleteCurrentItem()
            : null,

        // ── Scan footer ────────────────────────────────────────────────
        onScan:         onScan,
        scanController: controller.sheetScanController,
        isScanning:     controller.isScanning.value,

        // ── DocType-specific fields ─────────────────────────────────────
        customFields: customFields,
      );
    });
  }
}
