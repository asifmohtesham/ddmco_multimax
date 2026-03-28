import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_mixin_pos_serial.dart';

/// Shared Invoice Serial No dropdown for any DocType that mixes in
/// [PosSerialMixin].
///
/// C-5 fix: the POS-cap Obx no longer uses dynamic duck-typing + try/catch
/// to subscribe to liveRemaining.  [liveRemaining] is now a concrete
/// RxDouble on [ItemSheetControllerBase], so the Obx always has at least one
/// Rx subscription — eliminating the GetX "improper use" crash that fired
/// when the try/catch swallowed the exception on non-SE controllers and left
/// the Obx with zero tracked observables.
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
          // ── Serial dropdown ──────────────────────────────────────────
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
                    child: Text('Serial #$s'),
                  );
                }).toList(),
                onChanged: (value) => serial.selectedSerial.value = value,
              )),

          // ── POS cap chip ─────────────────────────────────────────────
          //
          // C-5: subscribe to controller.liveRemaining directly — it is a
          // concrete RxDouble on the base so the Obx always has a tracked
          // observable.  posSerialCapText is still duck-typed via PosSerialMixin
          // (all PosSerialMixin implementors have it), but liveRemaining is no
          // longer duck-typed — no more try/catch, no more zero-subscription Obx.
          Obx(() {
            // Explicit subscription so the chip rebuilds on every qty keystroke.
            final _ = controller.liveRemaining.value;

            String? capText;
            try {
              capText = (controller as dynamic).posSerialCapText as String?;
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
