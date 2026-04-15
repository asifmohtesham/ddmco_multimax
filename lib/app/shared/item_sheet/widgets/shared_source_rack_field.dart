import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/source_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';

/// Source-rack input field with Browse Rack (shelves) button.
///
/// Accepts any controller that implements [SourceRackDelegate] — including
/// [DualRackDelegate] subclasses, since [DualRackDelegate] extends
/// [SourceRackDelegate]. No cast is required at any call site.
///
/// ## Validation flow
/// - Typed input → `onChanged` → [SourceRackDelegate.onSourceRackChanged]
/// - Browse button → [RackPickerSheet] → [SourceRackDelegate.onSourceRackChanged]
///
/// ## Picker scope
/// The rack picker is scoped to [SourceRackDelegate.sourceRackWarehouse]
/// so only racks in the correct source warehouse are shown.
class SharedSourceRackField extends StatelessWidget {
  /// Controller implementing [SourceRackDelegate].
  ///
  /// Typically a [DualRackDelegate] passed down from [SharedDualRackSection],
  /// but any controller that mixes in [SourceRackDelegate] alone is equally
  /// valid (e.g. a future Delivery Note item controller).
  final SourceRackDelegate controller;

  /// Tint applied to the validated check-circle icon.
  final Color accentColor;

  /// Whether to show the Browse Rack shelves-icon button.
  ///
  /// Callers set this to `false` when picker preconditions are unmet
  /// (no item code or no resolved warehouse).
  final bool canBrowse;

  /// Constructs a source-rack field backed by [controller].
  const SharedSourceRackField({
    super.key,
    required this.controller,
    this.accentColor = Colors.purple,
    this.canBrowse   = true,
  });

  Future<void> _openPicker() async {
    final warehouse = controller.sourceRackWarehouse?.value ?? '';
    final tag = 'src_rack_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl = Get.put(RackPickerController(), tag: tag);
    unawaited(ctrl.load(
      itemCode:     controller.itemCode.value,
      batchNo:      controller.batchController.text.trim(),
      warehouse:    warehouse,
      requestedQty: double.tryParse(controller.qtyController.text) ?? 0.0,
      currentRack:  controller.sourceRackController.text.trim(),
      fallbackMap:  const {},   // live fetch is primary; fallback empty is safe
    ));
    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          controller.sourceRackController.text = rack;
          controller.onSourceRackChanged(rack);
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
      final isValid      = controller.isSourceRackValid.value;
      final isValidating = controller.isValidatingSourceRack.value;
      final error        = controller.rackError.value;

      return TextField(
        controller: controller.sourceRackController,
        decoration: InputDecoration(
          labelText: 'Source Rack',
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
        onChanged: controller.onSourceRackChanged,
      );
    });
  }
}
