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
      child: Obx(() => DropdownButtonFormField<String>(
            value: serial.selectedSerial.value,
            decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
    );
  }
}
