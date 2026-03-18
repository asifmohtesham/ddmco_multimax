import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'derived_warehouse_label.dart';
import 'validated_rack_field.dart';

/// Groups Source Rack, Target Rack, balance chips, warehouse labels, and the
/// rack error message into one self-contained widget.
class RackSection extends StatelessWidget {
  final StockEntryFormController controller;

  const RackSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final showSource = controller.requiresSourceWarehouse;
    final showTarget = controller.requiresTargetWarehouse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Source Rack ───────────────────────────────────────────────
        if (showSource) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Obx(() => ValidatedRackField(
                  key: const ValueKey('source_rack_field'),
                  textController: controller.bsSourceRackController,
                  isValid: controller.isSourceRackValid.value,
                  isValidating: controller.isValidatingSourceRack.value,
                  label: 'Source Rack',
                  color: Colors.orange,
                  onReset: controller.resetSourceRackValidation,
                  onValidate: () => controller.validateRack(
                      controller.bsSourceRackController.text, true),
                  onSubmitted: (val) => controller.validateRack(val, true),
                )),
          ),
          Obx(() => BalanceChip(
                balance: controller.bsRackBalance.value,
                isLoading: controller.isLoadingRackBalance.value,
                color: Colors.orange.shade800,
                prefix: 'Rack Balance:',
              )),
          const SizedBox(height: 4),
          DerivedWarehouseLabel(
            itemWarehouse: controller.bsItemSourceWarehouse,
            derivedWarehouse: controller.derivedSourceWarehouse,
            headerWarehouse: controller.selectedFromWarehouse,
          ),
        ],

        // ── Target Rack ───────────────────────────────────────────────
        if (showTarget) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Obx(() => ValidatedRackField(
                  key: const ValueKey('target_rack_field'),
                  textController: controller.bsTargetRackController,
                  isValid: controller.isTargetRackValid.value,
                  isValidating: controller.isValidatingTargetRack.value,
                  label: 'Target Rack',
                  color: Colors.green,
                  onReset: controller.resetTargetRackValidation,
                  onValidate: () => controller.validateRack(
                      controller.bsTargetRackController.text, false),
                  onSubmitted: (val) => controller.validateRack(val, false),
                )),
          ),
          DerivedWarehouseLabel(
            itemWarehouse: controller.bsItemTargetWarehouse,
            derivedWarehouse: controller.derivedTargetWarehouse,
            headerWarehouse: controller.selectedToWarehouse,
          ),
        ],

        // ── Rack error ───────────────────────────────────────────────
        Obx(() {
          final err = controller.rackError.value;
          if (err == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 4.0),
            child: Text(
              err,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }),
      ],
    );
  }
}
