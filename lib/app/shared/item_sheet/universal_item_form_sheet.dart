import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'item_sheet_controller_base.dart';

/// Universal wrapper around [GlobalItemFormSheet] for all DocType item sheets.
///
/// ## Qty wiring (Commit 7)
///
/// The five raw qty params that previously bridged [ItemSheetControllerBase]
/// to [GlobalItemFormSheet] have been removed:
///
/// | Removed param       | Replaced by                                      |
/// |---------------------|--------------------------------------------------|
/// | `qtyController`     | [GlobalItemFormSheet.qtyDelegate] → controller   |
/// | `onIncrement`       | [SharedQtyField] reads QtyPlusMinusDelegate      |
/// | `onDecrement`       | [SharedQtyField] reads QtyPlusMinusDelegate      |
/// | `qtyInfoText`       | [QtyCapBadge] reads QtyCapDelegate.qtyInfoText   |
/// | `qtyInfoTooltip`    | [QtyCapBadge] reads QtyCapDelegate.qtyInfoTooltip|
/// | `isQtyReadOnly`     | [SharedQtyField] reads isQtyReadOnly Rx directly |
///
/// [controller] satisfies [QtyFieldWithPlusMinusDelegate] (which extends
/// [QtyFieldDelegate]) so it can be passed directly as `qtyDelegate`.
/// [controller.accentColor] is forwarded as `qtyAccentColor` so the field
/// matches the DocType's brand colour.
///
/// ## Other notes (unchanged from previous version)
///
/// Fix (compiler): GlobalItemFormSheet expects plain Dart types, not GetX Rx
/// wrappers.  Unwrap inside the Obx builder:
///   • isLoading       → controller.isSheetLoading.value  (RxBool → bool)
///   • scanController  → null (MobileScannerController ≠ TextEditingController;
///                        sheets that embed a scan bar do so in customFields)
///
/// Group C fix: saveButtonState was never forwarded to GlobalItemFormSheet.
/// The animated Save button is driven by Rx<SaveButtonState> inside an Obx;
/// without the real controller field the button was wired to a dead idle.obs
/// and never transitioned through loading/success/error states.
class UniversalItemFormSheet extends StatelessWidget {
  final ItemSheetControllerBase controller;
  final List<Widget> customFields;
  final Future<void> Function() onSubmit;
  final void Function(String)? onScan;
  final String? itemSubtext;
  final bool isSaveEnabled;
  final ScrollController? scrollController;

  const UniversalItemFormSheet({
    super.key,
    required this.controller,
    required this.customFields,
    required this.onSubmit,
    this.onScan,
    this.itemSubtext,
    this.isSaveEnabled = true,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.editingItemName.value != null;

      return GlobalItemFormSheet(
        key: const ValueKey('universal_item_sheet'),

        // ── Identity ────────────────────────────────────────────────────────────
        formKey:          controller.formKey,
        scrollController: scrollController,
        title:            isEditing ? 'Update Item' : 'Add Item',
        itemCode:         controller.itemCode.value,
        itemName:         controller.itemName.value,
        itemSubtext:      itemSubtext,

        // ── Metadata footer ───────────────────────────────────────────────
        owner:      controller.itemOwner.value,
        creation:   controller.itemCreation.value,
        modified:   controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // ── Qty ──────────────────────────────────────────────────────────────────
        // controller implements QtyFieldWithPlusMinusDelegate (which extends
        // QtyFieldDelegate) — pass it directly.  SharedQtyField reads all
        // reactive qty state (isQtyReadOnly, effectiveMaxQty, qtyError,
        // qtyInfoText, qtyInfoTooltip, adjustQty) from the delegate's Rx fields
        // without any unwrapping needed here.
        qtyDelegate:     controller,
        qtyAccentColor:  controller.accentColor,

        // ── Save / delete ────────────────────────────────────────────────
        isSaveEnabledRx:  controller.isSheetValid,
        isSaveEnabled:    isSaveEnabled,
        // Unwrap RxBool → bool.
        isLoading:        controller.isSheetLoading.value,
        // Group C fix: forward the controller's live save-button state machine
        // so _AnimatedSaveButton transitions correctly through loading / success
        // / error states.  Without this the button observed a dead idle.obs.
        saveButtonState:  controller.saveButtonState,
        onSubmit:         onSubmit,
        onDelete: isEditing
            ? () => controller.deleteCurrentItem()
            : null,

        // ── Scan footer ─────────────────────────────────────────────────
        onScan:         onScan,
        // MobileScannerController is not a TextEditingController; pass null.
        // Sheets that embed a live camera scanner wire it inside customFields.
        scanController: null,
        isScanning:     controller.isScanning.value,

        // ── DocType-specific fields ───────────────────────────────────────
        customFields: customFields,
      );
    });
  }
}
