import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'balance_chip.dart';
import 'derived_warehouse_label.dart';
import 'validated_rack_field.dart';

/// Step 6 — groups Source Rack, Target Rack, balance chips, warehouse labels,
/// and the rack error message into one self-contained widget.
/// Uses controller.requiresSourceWarehouse / requiresTargetWarehouse (Step 4)
/// instead of re-deriving SE-type booleans inline.
class RackSection extends StatelessWidget {
  final StockEntryFormController controller;

  const RackSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Step 4: use controller getters — no inline SE-type boolean derivation.
    final showSource = controller.requiresSourceWarehouse;
    final showTarget = controller.requiresTargetWarehouse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Source Rack ──────────────────────────────────────────────────
        if (showSource) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: ValidatedRackField(
              key: const ValueKey('source_rack_field'),
              textController: controller.bsSourceRackController,
              isValid: controller.isSourceRackValid,
              isValidating: controller.isValidatingSourceRack,
              label: 'Source Rack',
              color: Colors.orange,
              onReset: controller.resetSourceRackValidation,
              onValidate: () => controller.validateRack(
                  controller.bsSourceRackController.text, true),
              onSubmitted: (val) => controller.validateRack(val, true),
            ),
          ),
          BalanceChip(
            balance: controller.bsRackBalance,
            isLoading: controller.isLoadingRackBalance,
            label: 'Rack Balance',
            color: Colors.orange.shade800,
          ),
          const SizedBox(height: 4),
          DerivedWarehouseLabel(
            itemWarehouse: controller.bsItemSourceWarehouse,
            derivedWarehouse: controller.derivedSourceWarehouse,
            headerWarehouse: controller.selectedFromWarehouse,
          ),
        ],

        // ── Target Rack ──────────────────────────────────────────────────
        if (showTarget) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: ValidatedRackField(
              key: const ValueKey('target_rack_field'),
              textController: controller.bsTargetRackController,
              isValid: controller.isTargetRackValid,
              isValidating: controller.isValidatingTargetRack,
              label: 'Target Rack',
              color: Colors.green,
              onReset: controller.resetTargetRackValidation,
              onValidate: () => controller.validateRack(
                  controller.bsTargetRackController.text, false),
              onSubmitted: (val) => controller.validateRack(val, false),
            ),
          ),
          DerivedWarehouseLabel(
            itemWarehouse: controller.bsItemTargetWarehouse,
            derivedWarehouse: controller.derivedTargetWarehouse,
            headerWarehouse: controller.selectedToWarehouse,
          ),
        ],

        // ── Rack error ───────────────────────────────────────────────────
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
