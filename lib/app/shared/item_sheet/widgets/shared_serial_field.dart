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
/// POS cap chip (Commit A):
///   The chip below the serial dropdown reads [posSerialCapText] (duck-typed)
///   which is a dedicated getter on StockEntryItemFormController, decoupled
///   from [qtyInfoText]. The Obx also subscribes to [liveRemaining] (duck-typed)
///   so the chip text re-computes on every qty keystroke, not only on serial
///   selection changes.
class SharedSerialField extends StatelessWidget {
  final ItemSheetControllerBase controller;
  final Color accentColor;

  const SharedSerialField({
    super.key,
    required this.controller,
    this.accentColor = Colors.blueGrey,
  });

  @override
  Widget build(BuildContext context) {
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
          // Reads posSerialCapText via duck-typing.
          // Also subscribes to liveRemaining (duck-typed) so the chip
          // rebuilds on every qty keystroke, not only on serial changes.
          // Both duck-type accesses are guarded in try/catch so non-SE
          // controllers (which lack these getters) silently collapse to
          // SizedBox.shrink() — no type guard needed at the call site.
          Obx(() {
            final dynamic c = controller;

            // Subscribe to liveRemaining to trigger rebuilds on qty change.
            // The value itself is unused here; posSerialCapText re-reads it.
            try {
              final _ = (c.liveRemaining as RxDouble).value;
            } catch (_) {}

            String? capText;
            try {
              capText = c.posSerialCapText as String?;
            } catch (_) {}

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
