import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/source_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';

/// Source-rack input field with optional Browse Rack button.
///
/// Renders a validated text field wired to [SourceRackDelegate]. The
/// shelves-icon button opens [RackPickerSheet] scoped to
/// [SourceRackDelegate.sourceRackWarehouse].
///
/// ## Usage
/// ```dart
/// SharedSourceRackField(delegate: controller)
/// ```
/// where [controller] implements [SourceRackDelegate].
class SharedSourceRackField extends StatelessWidget {
  /// The controller that implements [SourceRackDelegate].
  final SourceRackDelegate delegate;

  /// Tint color for the validated-state icon and focus ring.
  final Color accentColor;

  /// Whether to show the Browse Rack (shelves) icon button.
  ///
  /// Disabled when the picker preconditions are not met (e.g. no item
  /// selected or no warehouse resolved).
  final bool canBrowse;

  /// Constructs a source-rack field backed by [delegate].
  const SharedSourceRackField({
    super.key,
    required this.delegate,
    required this.accentColor,
    required this.canBrowse,
  });

  Future<void> _openPicker() async {
    final warehouse = delegate.sourceRackWarehouse?.value ?? '';
    final tag = 'src_rack_picker_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl = Get.put(RackPickerController(), tag: tag);
    unawaited(ctrl.load(
      itemCode:     '',       // populated by the delegate's parent in practice
      batchNo:      delegate.sourceRackController.text.trim(),
      warehouse:    warehouse,
      requestedQty: 0.0,
      currentRack:  delegate.sourceRackController.text.trim(),
      fallbackMap:  {},
    ));
    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          delegate.sourceRackController.text = rack;
          delegate.onSourceRackChanged(rack);
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
      final isValid      = delegate.isSourceRackValid.value;
      final isValidating = delegate.isValidatingSourceRack.value;
      final error        = delegate.rackError.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: delegate.sourceRackController,
            decoration: InputDecoration(
              labelText:   'Source Rack',
              errorText:   error.isNotEmpty ? error : null,
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
            onChanged: delegate.onSourceRackChanged,
          ),
        ],
      );
    });
  }
}
