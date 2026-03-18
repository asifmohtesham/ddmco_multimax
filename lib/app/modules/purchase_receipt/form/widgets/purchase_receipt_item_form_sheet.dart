import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/purchase_receipt/form/controllers/purchase_receipt_item_form_controller.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_batch_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_rack_field.dart';

/// Purchase Receipt item-entry bottom sheet.
///
/// Phase 4: both inline Obx batch + rack fields replaced with
/// [SharedBatchField] and [SharedRackField] in [editMode].
/// No private helper classes remain in this file.
class PurchaseReceiptItemFormSheet
    extends GetView<PurchaseReceiptItemFormController> {
  final ScrollController? scrollController;

  const PurchaseReceiptItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final parent = Get.find<PurchaseReceiptFormController>();

    return Obx(() {
      final bool isEditable = parent.isEditable;
      final bool isEditing  = controller.editingItemName.value != null;

      return GlobalItemFormSheet(
        formKey:      controller.formKey,
        scrollController: scrollController,
        title: isEditing
            ? (isEditable ? 'Update Item' : 'View Item')
            : 'Add Item',
        itemCode:    controller.itemCode.value,
        itemName:    controller.itemName.value,
        itemSubtext: controller.variantOf.value,

        // ── Metadata footer ───────────────────────────────────────────────
        owner:      controller.itemOwner.value,
        creation:   controller.itemCreation.value,
        modified:   controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // ── Qty ──────────────────────────────────────────────────────────
        qtyController: controller.qtyController,
        onIncrement:   () => controller.adjustQty(1),
        onDecrement:   () => controller.adjustQty(-1),
        isQtyReadOnly: !isEditable,
        qtyInfoText: controller.poQty.value > 0
            ? 'PO Ordered: ${controller.poQty.value}'
            : null,

        // ── Save / delete ─────────────────────────────────────────────────
        isSaveEnabled: controller.isSheetValid.value && isEditable,
        isLoading:     controller.isValidatingBatch.value,
        onSubmit: () async {
          await controller.submit();
          Get.back();
        },
        onDelete: (isEditing && isEditable)
            ? () => parent.deleteItem(controller.editingItemName.value!)
            : null,

        // ── Custom fields ─────────────────────────────────────────────────
        customFields: [
          // 1. Batch No — editMode (purple, readOnly-when-valid + Edit btn)
          SharedBatchField(
            c:           controller,
            accentColor: Colors.purple,
            editMode:    true,
            readOnly:    !isEditable,
            fieldKey:    'pr_batch_field',
          ),

          // 2. Target Rack — editMode (green, required, readOnly-when-valid)
          SharedRackField(
            c:           controller,
            accentColor: Colors.green,
            label:       'Target Rack',
            hint:        'Rack',
            editMode:    true,
          ),
        ],
      );
    });
  }
}
