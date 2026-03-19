import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/stock_entry/form/controllers/stock_entry_item_form_controller.dart';
import 'derived_warehouse_label.dart';
import 'validated_rack_field.dart';

/// Groups Source Rack, Target Rack, balance chips, warehouse labels, and the
/// rack error message into one self-contained widget.
///
/// Receives [StockEntryItemFormController] — all state lives in the child.
/// Parent state is accessed via the public [StockEntryItemFormController.parent]
/// getter; no private field access from outside the class.
class RackSection extends StatelessWidget {
  final StockEntryItemFormController controller;

  const RackSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final showSource = [
      'Material Issue', 'Material Transfer', 'Material Transfer for Manufacture'
    ].contains(controller.parent.selectedStockEntryType.value);
    final showTarget = [
      'Material Receipt', 'Material Transfer', 'Material Transfer for Manufacture'
    ].contains(controller.parent.selectedStockEntryType.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Source Rack ───────────────────────────────────────────────
        if (showSource) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Obx(() => ValidatedRackField(
                  key:            const ValueKey('source_rack_field'),
                  textController: controller.sourceRackController,
                  isValid:        controller.isSourceRackValid.value,
                  isValidating:   controller.isValidatingSourceRack.value,
                  label:          'Source Rack',
                  color:          Colors.orange,
                  onReset:        controller.resetSourceRackValidation,
                  onValidate:     () => controller.validateDualRack(
                      controller.sourceRackController.text, true),
                  onSubmitted:    (val) => controller.validateDualRack(val, true),
                )),
          ),
          Obx(() => BalanceChip(
                balance:   controller.rackBalance.value,
                isLoading: controller.isLoadingRackBalance.value,
                color:     Colors.orange.shade800,
                prefix:    'Rack Balance:',
              )),
          const SizedBox(height: 4),
          DerivedWarehouseLabel(
            itemWarehouse:    controller.itemSourceWarehouse,
            derivedWarehouse: controller.derivedSourceWarehouse,
            headerWarehouse:  controller.parent.selectedFromWarehouse,
          ),
        ],

        // ── Target Rack ───────────────────────────────────────────────
        if (showTarget) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Obx(() => ValidatedRackField(
                  key:            const ValueKey('target_rack_field'),
                  textController: controller.targetRackController,
                  isValid:        controller.isTargetRackValid.value,
                  isValidating:   controller.isValidatingTargetRack.value,
                  label:          'Target Rack',
                  color:          Colors.green,
                  onReset:        controller.resetTargetRackValidation,
                  onValidate:     () => controller.validateDualRack(
                      controller.targetRackController.text, false),
                  onSubmitted:    (val) => controller.validateDualRack(val, false),
                )),
          ),
          DerivedWarehouseLabel(
            itemWarehouse:    controller.itemTargetWarehouse,
            derivedWarehouse: controller.derivedTargetWarehouse,
            headerWarehouse:  controller.parent.selectedToWarehouse,
          ),
        ],

        // ── Rack error ────────────────────────────────────────────────
        Obx(() {
          final err = controller.rackError.value;
          if (err == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 4.0),
            child: Text(
              err,
              style: TextStyle(
                color:      Colors.red.shade700,
                fontSize:   12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }),
      ],
    );
  }
}
