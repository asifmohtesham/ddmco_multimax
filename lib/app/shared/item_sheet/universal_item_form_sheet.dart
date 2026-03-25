import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'item_sheet_controller_base.dart';

/// Universal wrapper around [GlobalItemFormSheet] for all DocType item sheets.
///
/// Reads every common binding directly from [ItemSheetControllerBase]:
///   • [formKey]          — base field
///   • [isSheetLoading]   — merged validating + parent-saving flag (Step 1)
///   • [isScanning]       — base Rx (wired to parent in DN; false in SE)
///   • [sheetScanController] — base field (non-null in DN; null in SE)
///   • [qtyInfoText]      — abstract getter implemented in Step 2
///   • [deleteCurrentItem] — abstract method implemented in Step 2
///   • [isAddMode]        — base bool set in initialise()
///   • metadata fields    — itemOwner, itemCreation, itemModified, itemModifiedBy
///
/// What stays DocType-specific (passed as params):
///   • [customFields]    — the DocType-specific field widgets
///   • [onSubmit]        — SE calls parentController.addItem;
///                          DN calls controller.submit()
///   • [itemSubtext]     — SE passes currentVariantOf; DN does not
///   • [isSaveEnabled]   — SE passes docStatus == 0; DN always true
///   • [scrollController] — provided by DraggableScrollableSheet builder
///
/// The scan bar is shown automatically when [controller.sheetScanController]
/// is non-null. For DN this is the parent barcodeController; for SE it is null
/// so the bar is hidden (SE scans route at document level).
///
/// ## Stable key contract
///
/// [GlobalItemFormSheet] is given [key: const ValueKey('universal_item_sheet')].
/// A stable [ValueKey] tells Flutter’s element reconciler that this is the
/// same widget across [Obx] rebuilds, so the existing element (and its
/// subtree, including [QuantityInputWidget] with its `final` [_decKey] /
/// [_incKey] fields) is updated in-place rather than unmounted and remounted.
/// This prevents:
///   (a) [_QtyRepeatController] GetX tag churn (tag derived from [UniqueKey])
///   (b) In-progress press-and-hold timer cancellation on every Rx tick
/// One sheet instance is mounted per [showModalBottomSheet] call, so a
/// single constant key is correct for the entire lifetime of a sheet.
class UniversalItemFormSheet extends StatelessWidget {
  final ItemSheetControllerBase controller;

  /// DocType-specific field widgets inserted above the Quantity field.
  final List<Widget> customFields;

  /// Called when the user taps Save. Receives no arguments.
  /// SE: `() => parentController.addItem()`
  /// DN: `() => controller.submit()`
  final Future<void> Function() onSubmit;

  /// Optional inline scan handler.
  /// DN provides `(code) => parent.scanBarcode(code)`.
  /// SE leaves null — the scan bar is suppressed entirely.
  final void Function(String)? onScan;

  /// Extra item sub-label shown next to the item code (SE: variantOf).
  final String? itemSubtext;

  /// Whether the Save button is enabled by docstatus. Default true.
  final bool isSaveEnabled;

  /// Scroll controller provided by DraggableScrollableSheet.
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
        // ── Stable key ─────────────────────────────────────────────────────────
        //
        // CRITICAL: prevents GlobalItemFormSheet from being unmounted and
        // remounted on every Obx rebuild. Without a stable key, each Rx
        // change creates a new widget object → new QuantityInputWidget
        // instance → new _decKey / _incKey UniqueKeys → new GetX tags for
        // _QtyRepeatController → mid-hold timer cancellation and (in the
        // unbounded path) the GetWidget null-cast crash.
        //
        // One UniversalItemFormSheet is mounted per sheet open, so this
        // constant key is correct for the entire lifetime of one sheet.
        key: const ValueKey('universal_item_sheet'),

        // ── Identity ───────────────────────────────────────────────────────────
        formKey:          controller.formKey,
        scrollController: scrollController,
        title:            isEditing ? 'Update Item' : 'Add Item',
        itemCode:         controller.itemCode.value,
        itemName:         controller.itemName.value,
        itemSubtext:      itemSubtext,

        // ── Metadata footer ───────────────────────────────────────────────────
        owner:      controller.itemOwner.value,
        creation:   controller.itemCreation.value,
        modified:   controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // ── Qty ─────────────────────────────────────────────────────────────────
        qtyController: controller.qtyController,
        onIncrement:   () => controller.adjustQty(1),
        onDecrement:   () => controller.adjustQty(-1),
        qtyInfoText:   controller.qtyInfoText,

        // ── Save / delete ───────────────────────────────────────────────────
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled:   isSaveEnabled,
        isLoading:       controller.isSheetLoading,
        onSubmit:        onSubmit,
        // onDelete delegates to deleteCurrentItem() which reads
        // editingItemName at call time — not at build time — ensuring
        // the closure always resolves the live item even if the Rx
        // value changes between build and tap.
        onDelete: isEditing
            ? () => controller.deleteCurrentItem()
            : null,

        // ── Scan footer (shown only when controller has a scan TEC) ──────────
        onScan:         onScan,
        scanController: controller.sheetScanController,
        isScanning:     controller.isScanning.value,

        // ── DocType-specific fields ─────────────────────────────────────────
        customFields: customFields,
      );
    });
  }
}
