// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';

/// Delegate-driven Invoice Serial No dropdown + POS cap badge.
///
/// Replaces [SharedSerialField] (which will be deleted in commit 7).
///
/// ## Zero concrete-controller coupling
///
/// This widget depends exclusively on [SerialNumberFieldDelegate].
/// Any DocType controller that implements that narrow interface — whether via
/// [SerialFieldMixin], a hand-rolled implementation, or a test double — can
/// host this widget without modification.
///
/// ## POS qty matching
///
/// The cap badge reads [SerialNumberFieldDelegate.posItemQtyForSerial] using
/// the currently selected serial.  The controller resolves
/// `serial → idx → PosUploadItem.qty` internally; the widget is idx-agnostic.
///
/// [liveRemaining] is the pressure-gauge value already computed by
/// [SerialFieldMixin.computeLiveRemaining] and stored reactively on the
/// delegate.  The badge displays `"$liveRemaining / $cap"`.
///
/// When [liveRemaining] is negative the badge switches to the theme's error
/// colour, giving the user immediate over-allocation feedback.
///
/// ## posItemQtyOverride
///
/// Pass [posItemQtyOverride] to bypass [posItemQtyForSerial] entirely and
/// supply an alternative qty getter at the call site.
/// Mirrors [SharedRackField.balanceOverride].
///
/// ## Usage
///
/// ```dart
/// SharedInvoiceSerialNumberField(c: controller)
///
/// // with accent colour:
/// SharedInvoiceSerialNumberField(
///   c: controller,
///   accentColor: Colors.teal,
/// )
///
/// // with override (e.g. POS Upload screen):
/// SharedInvoiceSerialNumberField(
///   c: controller,
///   posItemQtyOverride: () => _parent.posQtyForSerial(
///       controller.selectedSerial.value ?? ''),
/// )
/// ```
class SharedInvoiceSerialNumberField extends StatelessWidget {
  final SerialNumberFieldDelegate c;
  final Color accentColor;
  final String label;
  final String hint;

  /// Optional override for the POS item qty cap.
  ///
  /// When non-null the badge calls this getter on every rebuild instead of
  /// [SerialNumberFieldDelegate.posItemQtyForSerial].  Useful when the call
  /// site has cheaper / more direct access to the cap value.
  final double? Function()? posItemQtyOverride;

  const SharedInvoiceSerialNumberField({
    super.key,
    required this.c,
    this.accentColor = Colors.blueGrey,
    this.label = 'Invoice Serial No',
    this.hint = 'Select Serial',
    this.posItemQtyOverride,
  });

  // ── Internal helpers ────────────────────────────────────────────────────

  double _capQty() {
    final serial = c.selectedSerial.value;
    if (serial == null || serial.isEmpty) return 0.0;
    return posItemQtyOverride?.call()
        ?? c.posItemQtyForSerial(serial);
  }

  bool _isBadgeVisible(double cap) =>
      cap > 0 && cap != double.infinity;

  @override
  Widget build(BuildContext context) {
    if (c.availableSerialNos.isEmpty) return const SizedBox.shrink();

    return Obx(() {
      // Read both reactive values so Obx tracks them.
      final serial = c.selectedSerial.value;
      final remaining = c.liveRemaining.value;
      final cap = _capQty();
      final showBadge = serial != null &&
          serial.isNotEmpty &&
          _isBadgeVisible(cap);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Serial dropdown inside its own tinted container ─────────────
          GlobalItemFormSheet.buildInputGroup(
            label: label,
            color: accentColor,
            child: DropdownButtonFormField<String>(
              value: serial,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                hintText: hint,
                // Collapse the ~20px invisible helper/error/counter reserved
                // space so the buildInputGroup tinted Container ends exactly
                // at the field's bottom border with no colour tail.
                isDense: true,
              ),
              items: c.availableSerialNos.map((s) {
                return DropdownMenuItem(
                  value: s,
                  child: Text('Serial #$s'),
                );
              }).toList(),
              onChanged: (value) => c.selectedSerial.value = value,
            ),
          ),

          // ── POS cap badge — sibling, NOT inside the tinted container ────
          if (showBadge)
            _PosCapChip(
              text: '${SerialFieldMixin.fmtQty(remaining)}'  
                    ' / '
                    '${SerialFieldMixin.fmtQty(cap)}',
              isOverAllocated: remaining < 0,
            ),
        ],
      );
    });
  }
}

// ── Private widgets ─────────────────────────────────────────────────────────

/// Teal pill chip shown below the Invoice Serial No dropdown when a POS
/// Upload is loaded and a serial is selected.
///
/// Displays: `"$liveRemaining / $cap"`
///
/// Switches to [ColorScheme.error] palette when [isOverAllocated] is true.
class _PosCapChip extends StatelessWidget {
  final String text;

  /// True when liveRemaining < 0; renders the badge in the error colour.
  final bool isOverAllocated;

  const _PosCapChip({
    required this.text,
    this.isOverAllocated = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bgColor = isOverAllocated
        ? cs.errorContainer.withOpacity(0.55)
        : cs.secondaryContainer.withOpacity(0.55);
    final borderColor = isOverAllocated
        ? cs.error.withOpacity(0.35)
        : cs.secondary.withOpacity(0.35);
    final iconColor =
        isOverAllocated ? cs.error : cs.secondary;
    final textColor =
        isOverAllocated ? cs.error : cs.secondary;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 13,
              color: iconColor,
            ),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
