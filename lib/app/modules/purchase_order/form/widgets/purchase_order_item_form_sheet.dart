import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class PurchaseOrderItemFormSheet extends GetView<PurchaseOrderFormController> {
  final ScrollController? scrollController;

  const PurchaseOrderItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final bool isEditing = controller.currentItemNameKey != null;

    return GlobalItemFormSheet(
      owner: controller.bsItemOwner.value,
      creation: controller.bsItemCreation.value,
      modified: controller.bsItemModified.value,
      modifiedBy: controller.bsItemModifiedBy.value,

      formKey: controller.itemFormKey,
      scrollController: scrollController,
      title: isEditing ? 'Update Item' : 'Add to Order',
      itemCode: controller.currentItemCode ?? '',
      itemName: controller.currentItemName ?? '',

      qtyController: controller.bsQtyController,
      onIncrement: () => controller.adjustSheetQty(1),
      onDecrement: () => controller.adjustSheetQty(-1),

      isSaveEnabled: true,
      onSubmit: controller.submitItem,
      onDelete: isEditing
          ? () {
        final item = controller.purchaseOrder.value!.items.firstWhere((i) => i.name == controller.currentItemNameKey);
        controller.deleteItem(item);
      }
          : null,

      customFields: [
        // Reqd By Date Input
        GlobalItemFormSheet.buildInputGroup(
          label: 'Reqd by Date',
          color: Colors.orange,
          child: TextFormField(
            controller: controller.bsScheduleDateController,
            readOnly: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.calendar_today, size: 18),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                controller.bsScheduleDateController.text = DateFormat('yyyy-MM-dd').format(picked);
              }
            },
            validator: (value) => value == null || value.isEmpty ? 'Required' : null,
          ),
        ),

        const SizedBox(height: 16),

        // Rate Input
        GlobalItemFormSheet.buildInputGroup(
          label: 'Rate',
          color: Colors.grey,
          child: TextFormField(
            key: const ValueKey('po_rate_field'),
            controller: controller.bsRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.attach_money, size: 18),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              if (double.tryParse(value) == null) return 'Invalid number';
              return null;
            },
          ),
        ),

        const SizedBox(height: 16),

        // Amount Display
        Obx(() => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Amount', style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold)),
              Text(
                '${FormattingHelper.getCurrencySymbol(controller.purchaseOrder.value?.currency ?? 'AED')} ${NumberFormat('#,##0.00').format(controller.sheetAmount)}',
                style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        )),
      ],
    );
  }
}