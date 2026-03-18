import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Sheet controller (child — owns all bs* state)
import 'package:multimax/app/modules/delivery_note/form/controllers/delivery_note_item_form_controller.dart';

// Parent controller (for isAddingItem / isScanning / barcodeController)
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

// Shared base widgets
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_batch_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_rack_field.dart';

/// Delivery Note item-entry bottom sheet.
///
/// Now a [GetView<DeliveryNoteItemFormController>] — reads the ephemeral child
/// controller only. No direct access to [DeliveryNoteFormController] except for
/// scan routing (isScanning, barcodeController) which lives at document level.
class DeliveryNoteItemBottomSheet
    extends GetView<DeliveryNoteItemFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final parent = Get.find<DeliveryNoteFormController>();

    return Obx(() {
      final isEditing = controller.editingItemName.value != null;

      return GlobalItemFormSheet(
        // ── Identity ─────────────────────────────────────────────────────────
        formKey:    controller.formKey,
        scrollController: scrollController,
        title:      isEditing ? 'Update Item' : 'Add Item',
        itemCode:   controller.itemCode.value,
        itemName:   controller.itemName.value,

        // ── Metadata footer ────────────────────────────────────────────────
        owner:      controller.itemOwner.value,
        creation:   controller.itemCreation.value,
        modified:   controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // ── Qty ──────────────────────────────────────────────────────────────
        qtyController: controller.qtyController,
        onIncrement:   () => controller.adjustQty(1),
        onDecrement:   () => controller.adjustQty(-1),
        qtyInfoText: controller.maxQty.value > 0
            ? 'Max Available: ${controller.maxQty.value}'
            : null,

        // ── Save / delete ───────────────────────────────────────────────────
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled:   true,
        isLoading: controller.isValidatingBatch.value || parent.isAddingItem.value,
        onSubmit:  () => controller.submit(),
        onDelete: isEditing
            ? () {
                final item = parent.deliveryNote.value?.items
                    .firstWhereOrNull((i) => i.name == controller.editingItemName.value);
                if (item != null) parent.confirmAndDeleteItem(item);
              }
            : null,

        // ── Scan footer ──────────────────────────────────────────────────────
        onScan:         (code) => parent.scanBarcode(code),
        scanController: parent.barcodeController,
        isScanning:     parent.isScanning.value,

        // ── Custom fields ───────────────────────────────────────────────────
        customFields: [
          // 1. Invoice Serial No (POS Upload flow only)
          if (controller.availableSerialNos.isNotEmpty)
            GlobalItemFormSheet.buildInputGroup(
              label: 'Invoice Serial No',
              color: Colors.blueGrey,
              child: Obx(() => DropdownButtonFormField<String>(
                value: controller.selectedSerial.value,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  hintText: 'Select Serial',
                ),
                items: controller.availableSerialNos.map((s) {
                  return DropdownMenuItem(
                      value: s, child: Text('Serial #$s'));
                }).toList(),
                onChanged: (value) {
                  controller.selectedSerial.value = value;
                },
              )),
            ),

          // 2. Batch No — shared widget (carries tooltip + validate/edit actions)
          Obx(() => _BatchFieldDN(controller: controller)),

          // 3. Rack — shared widget
          SharedRackField(
            c:           controller,
            accentColor: Colors.orange,
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// DN Batch field: preserves DN-specific purple styling + validate/edit icons
// Cannot use generic SharedBatchField here because DN has a unique
// 'readOnly-when-valid' pattern with an explicit Edit button.
// SharedBatchField can be adopted in Phase 4 once the icon pattern is unified.
// ─────────────────────────────────────────────────────────────────────────────────
class _BatchFieldDN extends StatelessWidget {
  final DeliveryNoteItemFormController controller;
  const _BatchFieldDN({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isValid    = controller.isBatchValid.value;
      final validating = controller.isValidatingBatch.value;

      return GlobalItemFormSheet.buildInputGroup(
        label:   'Batch No',
        color:   Colors.purple,
        bgColor: isValid ? Colors.purple.shade50 : null,
        child: TextFormField(
          key:        const ValueKey('dn_batch_field'),
          controller: controller.batchController,
          readOnly:   isValid,
          autofocus:  false,
          style: const TextStyle(fontFamily: 'ShureTechMono'),
          decoration: InputDecoration(
            hintText: 'Enter or scan batch',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.purple.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.purple, width: 2),
            ),
            filled:    true,
            fillColor: isValid ? Colors.purple.shade50 : Colors.white,
            suffixIcon: validating
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.purple),
                    ),
                  )
                : isValid
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (controller.batchInfoTooltip.value != null)
                            Tooltip(
                              message: controller.batchInfoTooltip.value!,
                              triggerMode: TooltipTriggerMode.tap,
                              child: const Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 8.0),
                                child: Icon(Icons.info_outline,
                                    color: Colors.blue),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit,
                                color: Colors.purple),
                            onPressed: controller.resetBatch,
                            tooltip: 'Edit Batch',
                          ),
                        ],
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () => controller
                            .validateBatch(controller.batchController.text),
                        tooltip: 'Validate',
                      ),
          ),
          onChanged:      (_) => controller.validateSheet(),
          onFieldSubmitted: (val) {
            if (!controller.isBatchValid.value) {
              controller.validateBatch(val);
            }
          },
        ),
      );
    });
  }
}
