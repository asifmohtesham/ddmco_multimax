// ignore_for_file: lines_longer_than_80_chars

import 'package:get/get.dart';

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
}
