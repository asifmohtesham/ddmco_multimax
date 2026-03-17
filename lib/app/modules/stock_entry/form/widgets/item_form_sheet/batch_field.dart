import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'balance_chip.dart';

/// Step 5 — extracts the inline Batch No block from customFields.
/// Handles its own Obx subscription; the parent sheet does not need to
/// observe batch state directly.
class BatchField extends StatelessWidget {
  final StockEntryFormController controller;

  const BatchField({super.key, required this.controller});

  Widget _suffixIcon() {
    if (controller.isValidatingBatch.value) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.purple),
        ),
      );
    }
    if (controller.bsIsBatchValid.value) {
      return IconButton(
        icon: const Icon(Icons.edit, color: Colors.purple),
        onPressed: controller.resetBatchValidation,
        tooltip: 'Edit Batch',
      );
    }
    return IconButton(
      icon: const Icon(Icons.check),
      onPressed: () =>
          controller.validateBatch(controller.bsBatchController.text),
      tooltip: 'Validate',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlobalItemFormSheet.buildInputGroup(
              label: 'Batch No',
              color: Colors.purple,
              bgColor: controller.bsIsBatchValid.value
                  ? Colors.purple.shade50
                  : null,
              child: TextFormField(
                key: const ValueKey('batch_field'),
                controller: controller.bsBatchController,
                readOnly: controller.bsIsBatchValid.value,
                autofocus: false,
                style: const TextStyle(fontFamily: 'ShureTechMono'),
                decoration: InputDecoration(
                  hintText: 'Enter or scan batch',
                  helperText: controller.batchError.value,
                  helperStyle: TextStyle(
                    color: controller.batchError.value != null
                        ? Colors.red
                        : Colors.grey,
                    fontWeight: controller.batchError.value != null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: controller.batchError.value != null
                          ? Colors.red
                          : Colors.purple.shade200,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: controller.batchError.value != null
                          ? Colors.red
                          : Colors.purple,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: controller.bsIsBatchValid.value
                      ? Colors.purple.shade50
                      : Colors.white,
                  suffixIcon: _suffixIcon(),
                ),
                onFieldSubmitted: (value) =>
                    controller.validateBatch(value),
              ),
            ),
            BalanceChip(
              balance: controller.bsBatchBalance,
              isLoading: controller.isLoadingBatchBalance,
              label: 'Batch Balance',
              color: Colors.purple.shade700,
            ),
          ],
        ));
  }
}
