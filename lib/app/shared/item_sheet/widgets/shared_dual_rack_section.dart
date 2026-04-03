import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/item_form_sheet/validated_rack_field.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';

/// Shared dual-rack section: Source Rack + Target Rack, balance chips,
/// warehouse derivation labels, and the rack error banner.
///
/// This is the canonical implementation extracted from SE's RackSection.
/// Typed to [StockEntryItemFormController] — SE is the only DocType that
/// uses a dual-rack (source + target) layout, so no false generality is
/// needed here.
///
/// ## Picker lifecycle
/// [_openRackPicker] registers a scoped [RackPickerController] with a unique
/// tag, fires [RackPickerController.load] in the background, presents
/// [RackPickerSheet], and disposes the controller when the sheet closes.
///
/// P2-2: extracted from SE module into shared/item_sheet/widgets.
/// fix: pass rackStockMap as fallbackMap so the Available Rack Balance
///      bottom sheet is populated (was always empty due to `const {}`).
/// Commit 7: rack-error banner now checks `err.isEmpty` instead of
///      `err == null` — rackError is RxString (never null).
class SharedDualRackSection extends StatelessWidget {
  final StockEntryItemFormController controller;

  const SharedDualRackSection({super.key, required this.controller});

  // -- Picker lifecycle helper --------------------------------------------------
  Future<void> _openRackPicker(
    BuildContext context, {
    required bool isSource,
  }) async {
    final tag = 'rack_picker_se_${isSource ? 'source' : 'target'}_'
        '${DateTime.now().microsecondsSinceEpoch}';

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

    unawaited(ctrl.load(
      itemCode:     controller.itemCode.value,
      batchNo:      controller.batchController.text,
      warehouse:    warehouse,
      requestedQty:
          double.tryParse(controller.qtyController.text) ?? 0.0,
      currentRack: isSource
          ? controller.sourceRackController.text
          : controller.targetRackController.text,
      // Pass a point-in-time snapshot of the live rackStockMap as the
      // fallback / merge-base for RackPickerController.load().
      // Previously `const {}` caused the Available Rack Balance sheet
      // to always render empty when the primary batch-ledger API returned
      // no data (non-batch items, API hiccup, or first-open before batch
      // validation). Matches the pattern used in DN's openRackPicker().
      fallbackMap: Map<String, double>.from(controller.rackStockMap),
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

    // Defer deletion by one frame so any in-flight Obx rebuild notifications
    // triggered by onSelected() / selectRack() can drain before the
    // controller is removed from GetX's registry. Immediate deletion caused
    // a "RackPickerController not found" crash on the final Obx rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSource = [
      'Material Issue',
      'Material Transfer',
      'Material Transfer for Manufacture',
    ].contains(controller.parent.selectedStockEntryType.value);

    final showTarget = [
      'Material Receipt',
      'Material Transfer',
      'Material Transfer for Manufacture',
    ].contains(controller.parent.selectedStockEntryType.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // -- Source Rack ----------------------------------------------------------
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

        // -- Target Rack ----------------------------------------------------------
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

        // -- Rack error banner ----------------------------------------------------
        // Commit 7: rackError is RxString (never null); use isEmpty, not == null.
        Obx(() {
          final err = controller.rackError.value;
          if (err.isEmpty) return const SizedBox.shrink();
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
