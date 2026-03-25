import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/stock_entry/form/controllers/stock_entry_item_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'derived_warehouse_label.dart';
import 'validated_rack_field.dart';

/// Groups Source Rack, Target Rack, balance chips, warehouse labels, and the
/// rack error message into one self-contained widget.
///
/// Receives [StockEntryItemFormController] — all state lives in the child.
/// Parent state is accessed via the public [StockEntryItemFormController.parent]
/// getter; no private field access from outside the class.
///
/// Commit-F: Both [ValidatedRackField] widgets now carry an [onPickerTap]
/// callback that opens [RackPickerSheet] pre-loaded with per-rack availability
/// for the current item + batch.  Tapping a tile writes directly to the
/// source or target rack controller and triggers dual-rack validation.
class RackSection extends StatelessWidget {
  final StockEntryItemFormController controller;

  const RackSection({super.key, required this.controller});

  // ── Picker lifecycle helper ───────────────────────────────────────────────────────────
  //
  // Opens [RackPickerSheet] for either the source rack ([isSource]=true) or
  // the target rack ([isSource]=false).
  //
  // Lifecycle:
  //   1. Register a scoped [RackPickerController] with a unique tag.
  //   2. Call ctrl.load() — fetches SLE data; shows spinner inside the sheet.
  //   3. Present [RackPickerSheet] via Get.bottomSheet.
  //   4. [onSelected] fires when the operator taps a tile:
  //        • writes the rack name to the correct TEC
  //        • calls validateDualRack(rack, isSource)
  //   5. Delete the scoped controller after the sheet closes.
  Future<void> _openRackPicker(
    BuildContext context, {
    required bool isSource,
  }) async {
    final tag = 'rack_picker_se_${isSource ? 'source' : 'target'}_'
        '${DateTime.now().microsecondsSinceEpoch}';

    // Resolve the effective warehouse for the relevant rack side.
    final String warehouse = isSource
        ? (controller.itemSourceWarehouse.value ??
               controller.derivedSourceWarehouse.value ??
               controller.parent.selectedFromWarehouse.value ??
               '')
        : (controller.itemTargetWarehouse.value ??
               controller.derivedTargetWarehouse.value ??
               controller.parent.selectedToWarehouse.value ??
               '');

    final ctrl = Get.put(RackPickerController(), tag: tag);

    // load() fires the SLE network call in the background.
    // RackPickerSheet shows a spinner while isLoading == true.
    unawaited(ctrl.load(
      itemCode:     controller.itemCode.value,
      batchNo:      controller.batchController.text,
      warehouse:    warehouse,
      requestedQty:
          double.tryParse(controller.qtyController.text) ?? 0.0,
      currentRack: isSource
          ? controller.sourceRackController.text
          : controller.targetRackController.text,
      fallbackMap: const {},
    ));

    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          if (isSource) {
            controller.sourceRackController.text = rack;
            controller.validateDualRack(rack, true);
          } else {
            controller.targetRackController.text = rack;
            controller.validateDualRack(rack, false);
          }
        },
      ),
      isScrollControlled: true,
    );

    if (Get.isRegistered<RackPickerController>(tag: tag)) {
      Get.delete<RackPickerController>(tag: tag);
    }
  }

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
        // ── Source Rack ────────────────────────────────────────────────────────────
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
                  onPickerTap: () => _openRackPicker(
                    context,
                    isSource: true,
                  ),
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

        // ── Target Rack ────────────────────────────────────────────────────────────
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
                  onPickerTap: () => _openRackPicker(
                    context,
                    isSource: false,
                  ),
                )),
          ),
          DerivedWarehouseLabel(
            itemWarehouse:    controller.itemTargetWarehouse,
            derivedWarehouse: controller.derivedTargetWarehouse,
            headerWarehouse:  controller.parent.selectedToWarehouse,
          ),
        ],

        // ── Rack error ───────────────────────────────────────────────────────────────
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
