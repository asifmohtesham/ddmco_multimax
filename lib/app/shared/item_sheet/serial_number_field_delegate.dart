// ignore_for_file: lines_longer_than_80_chars

import 'package:get/get.dart';

/// Metadata for one row in the [SharedInvoiceSerialNumberField] dropdown.
///
/// Returned by [SerialNumberFieldDelegate.serialDropdownItems].
/// Controllers that have POS Upload context supply [itemName] and [qty];
/// controllers without POS context leave them null (widget falls back to
/// showing only the index badge).
class SerialDropdownItem {
  /// The serial / idx string used as the [DropdownMenuItem] value.
  final String serial;

  /// Human-readable POS Upload item name, or null when unavailable.
  final String? itemName;

  /// POS Upload qty cap for this serial, or null when unavailable.
  final double? qty;

  /// Live remaining qty (mirrors [SerialNumberFieldDelegate.liveRemaining]
  /// at list-build time).  Used to decide whether this row is "full".
  final double remaining;

  /// Total qty already committed across all rows for this serial.
  ///
  /// Computed at list-build time as `cap − remaining`.
  /// Displayed in the cap chip as "Used: N".
  final double used;

  /// Non-null marks this serial non-selectable in the dropdown; the string is
  /// the reason shown in the row (e.g. "Strap ≠ Buckle"). Null = selectable.
  final String? blockedReason;

  const SerialDropdownItem({
    required this.serial,
    this.itemName,
    this.qty,
    required this.remaining,
    this.used = 0.0,
    this.blockedReason,
  });

  /// True when a finite qty cap is set and no allocation remains.
  bool get isFull =>
      qty != null && qty! != double.infinity && remaining <= 0;
}

/// Narrow interface that [SharedInvoiceSerialNumberField] depends on.
///
/// Any DocType item-sheet controller that carries an invoice serial number
/// field implements this interface — either directly or by adopting
/// [SerialFieldMixin], which supplies concrete implementations of every
/// member except the three abstract hooks.
///
/// ## Why a narrow interface?
///
/// The previous implementation cast the controller to `PosSerialMixin`
/// inside the widget, tying the widget permanently to
/// [ItemSheetControllerBase].  Extracting this interface lets any controller
/// — including ones that do not extend [ItemSheetControllerBase] (e.g.
/// a future lightweight Packing-Slip-only controller) — drive the widget
/// with zero extra ceremony.
///
/// ## Composition
///
/// This interface is intentionally kept minimal.  It covers exactly the
/// reactive state that [SharedInvoiceSerialNumberField] needs to render:
///
/// | Member                          | Responsibility                                  |
/// |---------------------------------|-------------------------------------------------|
/// | [selectedSerial]                | Reactive currently-selected serial (nullable)   |
/// | [availableSerialNos]            | Ordered list for the dropdown                   |
/// | [posItemQtyForSerial]           | POS Upload qty cap for a given serial / idx     |
/// | [liveRemaining]                 | Live pressure-gauge qty (updated per keystroke) |
/// | [serialDropdownItems]           | Rich metadata list for the dropdown rows        |
///
/// ## POS qty matching
///
/// [posItemQtyForSerial] receives the currently selected serial string and
/// returns the POS Upload qty cap for that serial at the current item `idx`.
/// The controller is responsible for resolving `serial → idx → qty`
/// internally; the widget remains `idx`-agnostic.
///
/// Return semantics:
/// - `> 0 && != double.infinity` → cap badge shown as "liveRemaining / cap"
/// - `0` or `double.infinity`   → cap badge hidden
///
/// ## Live remaining
///
/// [liveRemaining] is updated by [SerialFieldMixin.computeLiveRemaining]
/// on every call to `validateSheet()`.  The formula accounts for edit mode
/// to avoid double-counting the row currently open for editing:
///
/// ```
/// liveRemaining = cap
///               − sumQtyUsedForSerial(serial)   // all committed rows
///               + savedQtyForRow(editingRowId)   // undo double-count in edit mode
///               − currentTypedQty               // react to every keystroke
/// ```
///
/// Negative values indicate over-allocation; the widget renders the badge
/// in the error colour in that case.
///
/// ## Rich dropdown rows
///
/// Override [serialDropdownItems] to supply per-row [SerialDropdownItem]
/// metadata (item name, qty cap, remaining).  The default implementation
/// wraps [availableSerialNos] with null metadata so existing adopters
/// require no change.
///
/// ## Adoption pattern
///
/// | DocType           | Serial source                     | Widget mode            | Activation gate                          |
/// |-------------------|-----------------------------------|------------------------|------------------------------------------|
/// | Delivery Note     | User selects from dropdown        | Interactive            | `availableSerialNos.isNotEmpty` (auto)   |
/// | Stock Entry       | User selects from dropdown        | Interactive            | same                                     |
/// | Packing Slip      | Pre-seeded from linked DN item    | Read-only cap badge    | `posUpload.value != null && serial != null` |
///
/// ## Commit series (in progress)
///
/// | Commit | Action                                                                         |
/// |--------|--------------------------------------------------------------------------------|
/// | 1      | Add [SerialNumberFieldDelegate] interface (this file)                          |
/// | 2      | Add [SerialFieldMixin] with `computeLiveRemaining`, dirty-check helpers        |
/// | 3      | Replace legacy `SharedSerialField` widget with delegate-driven implementation  |
/// | 4      | Migrate `DeliveryNoteItemFormController` — `with SerialFieldMixin`             |
/// | 5      | Migrate `StockEntryItemFormController` — `with SerialFieldMixin`               |
/// | 6      | Adopt `SerialFieldMixin` on `PackingSlipItemFormController` (new capability)   |
/// | 7      | Delete `PosSerialMixin` and legacy `SharedSerialField` widget                  |
/// | 8      | Rich dropdown rows — `SerialDropdownItem` + `serialDropdownItems` (this file)  |
abstract interface class SerialNumberFieldDelegate {
  /// Currently selected invoice serial number.
  ///
  /// Nullable — `null` means no serial has been chosen yet.
  /// The dropdown writes back to this field on selection.
  RxnString get selectedSerial;

  /// Ordered list of valid serial numbers to populate the dropdown.
  ///
  /// When empty, [SharedInvoiceSerialNumberField] returns
  /// `SizedBox.shrink()` and renders nothing.
  List<String> get availableSerialNos;

  /// POS Upload qty cap for [serial] at the current item idx.
  ///
  /// The concrete controller resolves `serial → idx → PosUploadItem.qty`
  /// internally.  The widget never sees an idx value.
  ///
  /// Return `double.infinity` when no finite cap applies (badge hidden).
  /// Return `0` when no POS Upload is loaded (badge hidden).
  double posItemQtyForSerial(String serial);

  /// Live remaining qty for the currently selected serial.
  ///
  /// Updated by [SerialFieldMixin.computeLiveRemaining] on every
  /// `validateSheet()` call.  Negative values indicate over-allocation.
  RxDouble get liveRemaining;

  /// Rich metadata list used by [SharedInvoiceSerialNumberField] to render
  /// each dropdown row as a two-line tile:
  ///   `#N  [itemName]  ×qty`
  ///
  /// Default implementation wraps [availableSerialNos] with null metadata —
  /// existing adopters that do not override this getter continue to work;
  /// the widget falls back gracefully to showing only the index badge.
  ///
  /// Override (via [SerialFieldMixin.serialDropdownItems] or directly) to
  /// supply POS Upload item names and qty caps.
  List<SerialDropdownItem> get serialDropdownItems =>
      availableSerialNos
          .map((s) => SerialDropdownItem(
                serial: s,
                remaining: posItemQtyForSerial(s),
              ))
          .toList();
}
