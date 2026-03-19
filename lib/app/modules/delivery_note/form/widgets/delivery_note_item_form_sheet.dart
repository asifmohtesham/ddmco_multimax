import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Sheet controller (child)
import 'package:multimax/app/modules/delivery_note/form/controllers/delivery_note_item_form_controller.dart';

// Parent controller (for scan routing only — not for state bindings)
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

// Universal sheet wrapper
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';

// Shared field widgets
import 'package:multimax/app/shared/item_sheet/widgets/shared_batch_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_rack_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_serial_field.dart';

/// Delivery Note item-entry bottom sheet.
///
/// Now a thin wrapper around [UniversalItemFormSheet] — all common param
/// wiring (isLoading, isScanning, qtyInfoText, onDelete, scanController,
/// formKey) has moved to the base controller and is handled by the universal
/// wrapper.  Only DN-specific params remain here:
///   • onScan routing via parent.scanBarcode
///   • customFields (SharedSerialField, SharedBatchField, SharedRackField)
///   • onSubmit → controller.submit()
class DeliveryNoteItemBottomSheet
    extends GetView<DeliveryNoteItemFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    // Parent needed only for scan routing — no state bindings.
    final parent = Get.find<DeliveryNoteFormController>();

    return UniversalItemFormSheet(
      controller:       controller,
      scrollController: scrollController,
      onSubmit:         controller.submit,
      onScan:           (code) => parent.scanBarcode(code),

      customFields: [
        // 1. Invoice Serial No (POS Upload flow only)
        SharedSerialField(
          controller: controller,
          accentColor: Colors.blueGrey,
        ),

        // 2. Batch No
        SharedBatchField(
          c:           controller,
          accentColor: Colors.purple,
          editMode:    true,
          fieldKey:    'dn_batch_field',
        ),

        // 3. Rack
        SharedRackField(
          c:           controller,
          accentColor: Colors.orange,
        ),
      ],
    );
  }
}
