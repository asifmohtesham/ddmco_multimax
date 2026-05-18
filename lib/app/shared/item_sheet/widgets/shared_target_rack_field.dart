import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/target_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';

/// Target-rack input field with Browse Rack (shelves) button.
///
/// Accepts any controller that implements [TargetRackDelegate] — including
/// [DualRackDelegate] subclasses, since [DualRackDelegate] extends
/// [TargetRackDelegate]. No cast is required at any call site.
///
/// ## Validation flow
/// - Typed input → `onChanged` → [TargetRackDelegate.onTargetRackChanged]
/// - Browse button → [RackPickerSheet] → [TargetRackDelegate.onTargetRackChanged]
///
/// ## Picker scope
/// The rack picker is scoped to [TargetRackDelegate.targetRackWarehouse]
/// so only racks in the correct destination warehouse are shown.
///
/// ## Typical callers
/// - [SharedDualRackSection]: Material Transfer / Transfer for Manufacture
///   (both source + target shown)
/// - `_ManufactureTargetRackSection` in `rack_section.dart`: Manufacture
///   finished-good row (target only — no source rack for output items)
class SharedTargetRackField extends StatelessWidget {
  /// Controller implementing [TargetRackDelegate].
  ///
  /// Typically a [DualRackDelegate] passed down from [SharedDualRackSection],
  /// but any controller that mixes in [TargetRackDelegate] alone is equally
  /// valid.
  final TargetRackDelegate controller;

  /// Tint applied to the validated check-circle icon.
  final Color accentColor;

  /// Whether to show the Browse Rack shelves-icon button.
  final bool canBrowse;

  /// Constructs a target-rack field backed by [controller].
  const SharedTargetRackField({
    super.key,
    required this.controller,
    this.accentColor = Colors.purple,
    this.canBrowse   = true,
  });

  Future<void> _openPicker() async {
    final warehouse = controller.targetRackWarehouse?.value ?? '';
    final tag = 'tgt_rack_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl = Get.put(RackPickerController(), tag: tag);
    unawaited(ctrl.load(
      itemCode:     controller.itemCode.value,
      batchNo:      controller.batchController.text.trim(),
      warehouse:    warehouse,
      requestedQty: double.tryParse(controller.qtyController.text) ?? 0.0,
      currentRack:  controller.targetRackController.text.trim(),
      fallbackMap:  const {},
    ));
    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          controller.targetRackController.text = rack;
          controller.onTargetRackChanged(rack);
        },
      ),
      isScrollControlled: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isValid      = controller.isTargetRackValid.value;
      final isValidating = controller.isValidatingTargetRack.value;
      final error        = controller.rackError.value;

      return TextField(
        controller: controller.targetRackController,
        decoration: InputDecoration(
          labelText: 'Target Rack',
          errorText: error.isNotEmpty ? error : null,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isValidating)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (isValid)
                Icon(Icons.check_circle, color: accentColor, size: 20),
              if (canBrowse)
                IconButton(
                  icon:    const Icon(Icons.shelves),
                  tooltip: 'Browse Racks',
                  onPressed: _openPicker,
                ),
            ],
          ),
        ),
        onChanged: controller.onTargetRackChanged,
      );
    });
  }
}