import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/target_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';

/// Target-rack input field with optional Browse Rack button.
///
/// Renders a validated text field wired to [TargetRackDelegate]. The
/// shelves-icon button opens [RackPickerSheet] scoped to
/// [TargetRackDelegate.targetRackWarehouse].
///
/// Used for Material Receipt / Material Transfer target-side fields, and
/// for the Manufacture finished-good row via [_ManufactureTargetRackSection]
/// in `rack_section.dart`.
class SharedTargetRackField extends StatelessWidget {
  /// The controller that implements [TargetRackDelegate].
  final TargetRackDelegate delegate;

  /// Tint color for the validated-state icon and focus ring.
  final Color accentColor;

  /// Whether to show the Browse Rack (shelves) icon button.
  final bool canBrowse;

  /// Constructs a target-rack field backed by [delegate].
  const SharedTargetRackField({
    super.key,
    required this.delegate,
    required this.accentColor,
    required this.canBrowse,
  });

  Future<void> _openPicker() async {
    final warehouse = delegate.targetRackWarehouse?.value ?? '';
    final tag = 'tgt_rack_picker_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl = Get.put(RackPickerController(), tag: tag);
    unawaited(ctrl.load(
      itemCode:     '',
      batchNo:      delegate.targetRackController.text.trim(),
      warehouse:    warehouse,
      requestedQty: 0.0,
      currentRack:  delegate.targetRackController.text.trim(),
      fallbackMap:  {},
    ));
    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          delegate.targetRackController.text = rack;
          delegate.onTargetRackChanged(rack);
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
      final isValid      = delegate.isTargetRackValid.value;
      final isValidating = delegate.isValidatingTargetRack.value;
      final error        = delegate.rackError.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: delegate.targetRackController,
            decoration: InputDecoration(
              labelText:  'Target Rack',
              errorText:  error.isNotEmpty ? error : null,
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
                      icon: const Icon(Icons.shelves),
                      tooltip: 'Browse Racks',
                      onPressed: _openPicker,
                    ),
                ],
              ),
            ),
            onChanged: delegate.onTargetRackChanged,
          ),
        ],
      );
    });
  }
}
