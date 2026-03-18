import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

/// Batch No field for the Stock Entry item sheet.
///
/// Delegates rendering to [ValidatedFieldWidget] and [BalanceChip] from
/// global_widgets, keeping all Rx reads scoped inside a single Obx.
class BatchField extends StatelessWidget {
  final StockEntryFormController controller;

  const BatchField({super.key, required this.controller});

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
              child: ValidatedFieldWidget(
                fieldKey: const ValueKey('batch_field'),
                controller: controller.bsBatchController,
                color: Colors.purple,
                hintText: 'Enter or scan batch',
                isReadOnly: controller.bsIsBatchValid.value,
                isValid: controller.bsIsBatchValid.value,
                isValidating: controller.isValidatingBatch.value,
                hasError: controller.batchError.value != null,
                helperText: controller.batchError.value,
                onValidate: () =>
                    controller.validateBatch(controller.bsBatchController.text),
                onReset: controller.resetBatchValidation,
                onFieldSubmitted: (val) => controller.validateBatch(val),
              ),
            ),
            BalanceChip(
              balance: controller.bsBatchBalance.value,
              isLoading: controller.isLoadingBatchBalance.value,
              color: Colors.purple.shade700,
              prefix: 'Batch Balance:',
            ),
          ],
        ));
  }
}
