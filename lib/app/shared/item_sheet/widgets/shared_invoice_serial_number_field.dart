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
/// ## Dropdown row format
///
/// Each row renders as a two-column tile:
///
/// ```
/// ┌──────┐  Item Name (1 line, ellipsis)
/// │  #1  │  ×10
/// └──────┘
/// ```
///
/// The index badge uses [accentColor] at 12 % opacity.  When no item name
/// or qty is available (non-POS context) the right column is omitted and
/// only the badge is shown.
///
/// Rows where [SerialDropdownItem.isFull] is true are rendered at 40 %
/// opacity and disabled — the user cannot select an exhausted serial.
///
/// The closed trigger shows a compact `"#N · Item Name"` summary via
/// [DropdownButtonFormField.selectedItemBuilder].
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

  // ── Dropdown item builder ───────────────────────────────────────────────

  /// Builds a rich two-column tile for each serial:
  ///   Left  — rounded index badge (#N) tinted with [accentColor]
  ///   Right — itemName (1 line, ellipsis) + ×qty sub-label
  ///
  /// Full rows are dimmed (opacity 0.4) and non-selectable.
  List<DropdownMenuItem<String>> _buildItems(
      List<SerialDropdownItem> items, {bool allowFull = false}) {
    return items.map((item) {
      final badge = _IndexBadge(
        serial: item.serial,
        accentColor: accentColor,
      );

      final hasName = item.itemName != null && item.itemName!.isNotEmpty;
      final hasQty  = item.qty != null && item.qty! != double.infinity;

      Widget tile;
      if (hasName || hasQty) {
        tile = Row(
          children: [
            badge,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasName)
                    Text(
                      item.itemName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (item.blockedReason != null)
                    Text(
                      item.blockedReason!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade400,
                      ),
                    )
                  else if (hasQty)
                    Text(
                      item.isFull
                          ? '\u00d7${SerialFieldMixin.fmtQty(item.qty!)}  \u2014  Full'
                          : '\u00d7${SerialFieldMixin.fmtQty(item.qty!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.isFull
                            ? Colors.red.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      } else {
        // No POS context — badge only.
        tile = badge;
      }

      final isBlocked = item.blockedReason != null;
      return DropdownMenuItem<String>(
        value: item.serial,
        enabled: (!item.isFull || allowFull) && !isBlocked,
        child: Opacity(
          opacity: (isBlocked || (item.isFull && !allowFull)) ? 0.4 : 1.0,
          child: tile,
        ),
      );
    }).toList();
  }

  /// Builds the compact summary shown in the closed trigger:
  ///   `"#N · Item Name"` when item name is available
  ///   `"#N"`             otherwise
  List<Widget> _buildSelectedItems(List<SerialDropdownItem> items) {
    return items.map((item) {
      final label = item.itemName != null && item.itemName!.isNotEmpty
          ? '#${item.serial} \u00b7 ${item.itemName}'
          : '#${item.serial}';
      return Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (c.availableSerialNos.isEmpty) return const SizedBox.shrink();

    return Obx(() {
      // Read both reactive values so Obx tracks them.
      final serial    = c.selectedSerial.value;
      final remaining = c.liveRemaining.value;
      final cap       = _capQty();
      final showBadge = serial != null &&
          serial.isNotEmpty &&
          _isBadgeVisible(cap);

      // Also subscribe to serialItemsStamp so the dropdown rebuilds
      // whenever a sibling item is committed (isFull state changes).
      final serialMixin = c is SerialFieldMixin ? c as SerialFieldMixin : null;
      serialMixin?.serialItemsStamp.value; // reactive read

      // Build the items list inside Obx so isFull is re-evaluated
      // whenever liveRemaining changes.
      final dropdownItems = c.serialDropdownItems;

      final supportsToggle = serialMixin?.supportsAllowFullToggle ?? false;
      final allowFull =
          supportsToggle && (serialMixin?.allowFullSerials.value ?? false);
      final anyFull = dropdownItems.any((i) => i.isFull);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Serial dropdown inside its own tinted container ─────────────
          GlobalItemFormSheet.buildInputGroup(
            label: label,
            color: accentColor,
            labelTrailing: anyFull && serialMixin != null && supportsToggle
                ? _AllowFullToggle(c: serialMixin, accentColor: accentColor)
                : null,
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
              items: _buildItems(dropdownItems, allowFull: allowFull),
              selectedItemBuilder: (_) => _buildSelectedItems(dropdownItems),
              onChanged: (value) => c.selectedSerial.value = value,
            ),
          ),

          // ── POS cap badge — sibling, NOT inside the tinted container ────
          if (showBadge)
            _PosCapChip(
              text: 'Qty: ${SerialFieldMixin.fmtQty(cap)}'
                  '  •  Used: ${SerialFieldMixin.fmtQty(cap - remaining)}'
                  '  •  Pending: ${SerialFieldMixin.fmtQty(remaining)}',
              isOverAllocated: remaining < 0,
              isFull:          remaining <= 0 && cap > 0,
            ),
        ],
      );
    });
  }
}

// ── Private widgets ─────────────────────────────────────────────────────────

/// Rounded square index badge — `#N` tinted with [accentColor].
///
/// Used as the left column of each dropdown row tile and recycled for the
/// badge-only fallback when no POS metadata is available.
class _IndexBadge extends StatelessWidget {
  final String serial;
  final Color accentColor;

  const _IndexBadge({required this.serial, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$serial',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accentColor,
        ),
      ),
    );
  }
}

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

  /// True when remaining == 0 and cap > 0 (serial fully consumed).
  /// Renders the chip in the error/red palette to match the "Full" state
  /// shown in the dropdown row for the same serial.
  final bool isFull;

  const _PosCapChip({
    required this.text,
    this.isOverAllocated = false,
    this.isFull = false,
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

/// Inline toggle rendered in the "Invoice Serial No" label row when at
/// least one serial in the dropdown is Full. Toggles [SerialFieldMixin.allowFullSerials].
class _AllowFullToggle extends StatelessWidget {
  final SerialFieldMixin c;
  final Color accentColor;

  const _AllowFullToggle({required this.c, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Allow Full',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 4),
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: c.allowFullSerials.value,
                onChanged: (v) => c.allowFullSerials.value = v,
                activeThumbColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ));
  }
}
