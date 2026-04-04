// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart';
import 'package:multimax/app/shared/item_sheet/widgets/validated_rack_field.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/dual_rack_delegate.dart';

/// Shared dual-rack section: Source Rack + Target Rack, balance chips,
/// warehouse derivation labels, and the rack error banner.
///
/// ## Decoupling (Commit 8)
///
/// Previously typed to the concrete [StockEntryItemFormController].  Now
/// depends on [DualRackDelegate] — the narrow interface that covers exactly
/// the members this widget reads.  Any controller that implements
/// [DualRackDelegate] can drive this widget without inheriting the SE
/// item-sheet base class.
///
/// [StockEntryItemFormController] implements [DualRackDelegate] additively;
/// all existing call sites (SE form) compile without change.
///
/// ## Picker lifecycle
/// [_openRackPicker] registers a scoped [RackPickerController] with a unique
/// tag, fires [RackPickerController.load] in the background, presents
/// [RackPickerSheet], and disposes the controller when the sheet closes.
///
/// P2-2: extracted from SE module into shared/item_sheet/widgets.
/// Commit 5: import ValidatedRackField from canonical shared layer path
///      instead of the SE-module re-export stub.
/// Commit 7: rack-error banner now checks `err.isEmpty` instead of
///      `err == null` — rackError is RxString (never null).
/// Commit 8: field type changed from StockEntryItemFormController to
///      DualRackDelegate — see class-level doc above.
/// Commit 9 (build-2): fallbackMap reverted to `const {}`.
///      DualRackDelegate intentionally does not expose rackStockMap; the
///      live batch-ledger API inside RackPickerController.load() is the
///      authoritative source, making the snapshot fallback redundant here.
class SharedDualRackSection extends StatelessWidget {
  final DualRackDelegate controller;

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
               controller.selectedFromWarehouse.value ??
               '')
        : (controller.itemTargetWarehouse.value ??
               controller.derivedTargetWarehouse.value ??
               controller.selectedToWarehouse.value ??
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
      // DualRackDelegate does not expose rackStockMap — it was removed
      // during the controller-decoupling refactor (Commit 8).
      // RackPickerController.load() fetches live rack data from the
      // batch-ledger API as its primary source; const {} is a safe
      // no-op fallback that does not regress picker behaviour.
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
    ].contains(controller.selectedStockEntryType.value);

    final showTarget = [
      'Material Receipt',
      'Material Transfer',
      'Material Transfer for Manufacture',
    ].contains(controller.selectedStockEntryType.value);

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
            headerWarehouse:  controller.selectedFromWarehouse,
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
            headerWarehouse:  controller.selectedToWarehouse,
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
