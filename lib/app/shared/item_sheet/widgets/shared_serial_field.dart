import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_pos_serial.dart';

/// Shared Invoice Serial No dropdown for any DocType that mixes in
/// [PosSerialMixin].
///
/// Replaces the two divergent inline implementations in:
///   • StockEntryItemFormSheet  (wrapped in manual Obx, plain label)
///   • DeliveryNoteItemBottomSheet (inner Obx, 'Serial #s' label)
///
/// Usage:
/// ```dart
/// // In customFields:
/// SharedSerialField(controller: itemController),
/// ```
///
/// The widget renders nothing when [PosSerialMixin.availableSerialNos] is
/// empty, so callers do not need an `if` guard.
///
/// POS cap chip (added in P5):
///   When the controller exposes a non-null [qtyInfoText] (duck-typed via
///   dynamic — only SE's item controller does this in the POS branch),
///   a teal pill chip is rendered directly below the dropdown showing
///   the remaining invoice cap, e.g.:
///       Invoice #1 — Remaining: 3 / 5 pcs
///   This moves the cap feedback to its semantic home (the serial field)
///   rather than cluttering the Quantity label row.
class SharedSerialField extends StatelessWidget {
  /// The item-sheet controller. Must implement [PosSerialMixin].
  final ItemSheetControllerBase controller;

  /// Accent colour used for the field group label. Defaults to blueGrey.
  final Color accentColor;

  const SharedSerialField({
    super.key,
    required this.controller,
    this.accentColor = Colors.blueGrey,
  });

  @override
  Widget build(BuildContext context) {
    // Runtime cast — safe because every DocType that shows this field
    // mixes in PosSerialMixin. If the mixin is absent the field is never
    // added to customFields, so this path is unreachable in practice.
    final serial = controller as PosSerialMixin;

    final serials = serial.availableSerialNos;
    if (serials.isEmpty) return const SizedBox.shrink();

    return GlobalItemFormSheet.buildInputGroup(
      label: 'Invoice Serial No',
      color: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Serial dropdown ─────────────────────────────────────────────
          Obx(() => DropdownButtonFormField<String>(
                value: serial.selectedSerial.value,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  hintText: 'Select Serial',
                ),
                items: serials.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text('Serial #\$s'),
                  );
                }).toList(),
                onChanged: (value) => serial.selectedSerial.value = value,
              )),

          // ── POS cap chip ─────────────────────────────────────────────────
          // Reads qtyInfoText from the controller via duck-typing.
          // Non-null only when:
          //   • controller is StockEntryItemFormController, AND
          //   • a serial is selected, AND
          //   • a POS Upload is loaded on the parent.
          // Collapses to nothing for every other DocType / flow.
          Obx(() {
            final dynamic c = controller;
            final String? capText =
                c.qtyInfoText as String?;
            if (capText == null || capText.isEmpty) {
              return const SizedBox.shrink();
            }
            return _PosCapChip(text: capText);
          }),
        ],
      ),
    );
  }
}

/// Teal pill chip shown below the Invoice Serial No dropdown when a POS
/// Upload is loaded and a serial is selected.
///
/// Mirrors the visual language of the existing Batch Balance / Rack Balance
/// chips in the item sheet (rounded container, accent background, small text).
class _PosCapChip extends StatelessWidget {
  final String text;
  const _PosCapChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.secondary.withOpacity(0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 13,
              color: cs.secondary,
            ),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
