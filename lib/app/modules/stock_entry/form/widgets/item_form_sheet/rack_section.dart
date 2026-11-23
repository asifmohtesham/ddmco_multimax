// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/dual_rack_adapters.dart';
import 'package:multimax/app/shared/item_sheet/widgets/rack_warehouse_controls.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_rack_field.dart';

class RackSection extends StatelessWidget {
  const RackSection({super.key, required this.controller});

  final StockEntryItemFormController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // The purpose and loaded role can affect which warehouse controls appear.
      final sourceApplies = controller.sourceApplies;
      final targetApplies = controller.targetApplies;
      final sourceWarehouse = controller.resolvedWarehouse;
      final targetWarehouse = controller.resolvedTargetWarehouse;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.showSourceRack)
            _RackSideFields(
              controller: controller,
              source: true,
              applies: sourceApplies,
              warehouse: sourceWarehouse,
            ),
          if (controller.showSourceRack && controller.showTargetRack)
            const SizedBox(height: 16),
          if (controller.showTargetRack)
            _RackSideFields(
              controller: controller,
              source: false,
              applies: targetApplies,
              warehouse: targetWarehouse,
            ),
        ],
      );
    });
  }
}

class _RackSideFields extends StatelessWidget {
  const _RackSideFields({
    required this.controller,
    required this.source,
    required this.applies,
    required this.warehouse,
  });

  final StockEntryItemFormController controller;
  final bool source;
  final bool applies;
  final String? warehouse;

  @override
  Widget build(BuildContext context) {
    final adapter = source
        ? SourceRackFieldAdapter(controller)
        : TargetRackFieldAdapter(controller);
    final label = source ? 'Source' : 'Target';

    Future<void> pickRack() async {
      final rack = await adapter.browseRacks();
      if (rack != null) {
        await controller.validateDualRack(
          rack.rackId,
          source,
          allowInitialization: true,
        );
      }
    }

    return Obx(() {
      final verdict = source
          ? controller.sourceRackVerdict.value
          : controller.targetRackVerdict.value;
      final busy = source
          ? controller.isValidatingSourceRack.value
          : controller.isValidatingTargetRack.value;
      final canBrowse = !busy && applies && adapter.canBrowseRacks;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (applies)
            RowWarehouseField(
              label: '$label Warehouse',
              value: warehouse,
              company: controller.parent.company,
              onChanged: (value) =>
                  controller.chooseRowWarehouse(value, source: source),
            ),
          Focus(
            onFocusChange: (focused) =>
                controller.focusRackSide(source: source, focused: focused),
            child: SharedRackField(
              key: ValueKey('dual_rack_${label.toLowerCase()}'),
              c: adapter,
              label: '$label Rack',
              hint: 'Enter or scan ${label.toLowerCase()} rack ID',
              editMode: true,
              errorOverride: () => controller.rackMessage(source),
              checkingWarehouse: () => source
                  ? (controller.isCheckingSourceWarehouse.value ||
                        controller.isFindingAutoFillRack.value)
                  : controller.isCheckingTargetWarehouse.value,
              balanceOverride: () =>
                  source ? controller.rackBalance.value : null,
              onPickerTap: canBrowse ? pickRack : null,
            ),
          ),
          RackWarehouseActions(
            verdict: verdict,
            onChooseRack: canBrowse ? pickRack : null,
            onUseRackWarehouse: !busy && applies && verdict?.warehouse != null
                ? () => controller.chooseRowWarehouse(
                    verdict!.warehouse!,
                    source: source,
                  )
                : null,
            onRetry: busy ? null : () => controller.retryRack(source),
          ),
        ],
      );
    });
  }
}
