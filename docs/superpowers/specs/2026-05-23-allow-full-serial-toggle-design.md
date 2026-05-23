# Allow Full Serial Toggle — Design Spec

**Date:** 2026-05-23  
**Feature:** Delivery Note › Item Form › Invoice Serial Number field  
**Author:** Asif Mohtesham

---

## Problem

When a POS Upload is loaded on a Delivery Note, serials whose allocated qty has reached the POS cap are marked `isFull` and rendered as disabled, dimmed dropdown items. Floor workers cannot select them even when operational circumstances require assigning additional qty to an already-full serial.

---

## Proposed Behaviour

A small "Allow Full" toggle appears inline on the "Invoice Serial No" label row **only when at least one serial in the dropdown is currently Full**. When switched on:

- Full serials become selectable (no longer disabled or dimmed).
- The POS qty cap is bypassed in `effectiveMaxQty` — the user can enter any qty.
- Batch balance and rack balance caps remain enforced.
- The `"Full"` sub-label and red colour on Full rows are preserved so workers still see capacity state.

When switched off (or when no serial is Full), behaviour is unchanged from current.

---

## Approach

**Approach A — Mixin + delegate interface** (chosen).  
Toggle state lives in `SerialFieldMixin` as `allowFullSerials = false.obs`. The `SerialNumberFieldDelegate` interface exposes a default-returning getter. The widget reads from the delegate. Controllers read from the mixin field in `effectiveMaxQty`. All adopters (DN, SE, Packing Slip) inherit the flag automatically.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/app/shared/item_sheet/serial_number_field_delegate.dart` | Add `RxBool get allowFullSerials` with default `false.obs` |
| `lib/app/shared/item_sheet/serial_field_mixin.dart` | Add `final allowFullSerials = false.obs` |
| `lib/app/modules/global_widgets/global_item_form_sheet.dart` | Add optional `Widget? labelTrailing` to `buildInputGroup` |
| `lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart` | Toggle rendering + `_buildItems` override logic |
| `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart` | Reset `allowFullSerials` on sheet open; guard POS cap block |
| `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` | Same POS cap guard |

---

## Detailed Design

### 1. `SerialNumberFieldDelegate` — new getter

```dart
RxBool get allowFullSerials => false.obs;
```

Default returns a permanent `false.obs` so non-mixin adopters require no change.

### 2. `SerialFieldMixin` — new field

```dart
final allowFullSerials = false.obs;
```

Concrete implementation of the delegate getter. Shared across all mixin adopters.

### 3. `GlobalItemFormSheet.buildInputGroup` — `labelTrailing` slot

```dart
static Widget buildInputGroup({
  required String label,
  required Color color,
  required Widget child,
  Color? bgColor,
  Widget? labelTrailing,   // new — optional
})
```

When `labelTrailing` is non-null, the label `Padding` child becomes a `Row(mainAxisAlignment: spaceBetween)` containing the existing `Text` on the left and `labelTrailing` on the right. All existing call sites are unaffected (parameter is optional).

### 4. `SharedInvoiceSerialNumberField` — widget changes

Inside `Obx`:

- Subscribe to `allowFullSerials` when the delegate is a `SerialFieldMixin`:
  ```dart
  final allowFull = (c is SerialFieldMixin)
      ? (c as SerialFieldMixin).allowFullSerials.value
      : false;
  ```

- Compute visibility gate:
  ```dart
  final anyFull = dropdownItems.any((i) => i.isFull);
  ```

- Pass `labelTrailing` to `buildInputGroup` when `anyFull`:
  ```dart
  labelTrailing: anyFull ? _AllowFullToggle(c: c, accentColor: accentColor) : null,
  ```

- In `_buildItems`, override disabled/opacity per item:
  ```dart
  enabled: !item.isFull || allowFull,
  opacity: (item.isFull && !allowFull) ? 0.4 : 1.0,
  ```

`_AllowFullToggle` is a private stateless widget containing a compact `Row`:
- Label: `"Allow Full"`, 11px, `Colors.grey.shade600`
- Switch: `Switch(value: allowFull, onChanged: (v) => (c as SerialFieldMixin).allowFullSerials.value = v)`
- Switch uses `activeColor: accentColor` for visual consistency

### 5. Reset `allowFullSerials` on sheet open

`_seedNewItemModeFlags()` and `_seedEditModeFlags()` each add:

```dart
allowFullSerials.value = false;
```

This ensures the toggle is always off when a new sheet session begins, regardless of controller reuse across navigations.

### 6. `DeliveryNoteItemFormController.effectiveMaxQty` — POS cap guard

```dart
if (serial.isNotEmpty && !allowFullSerials.value) {
  final posQty = posItemQtyForSerial(serial);
  if (posQty != double.infinity) {
    final used = sumQtyUsedForSerial(serial, excludeRowId: editingItemName.value);
    final allowedByPos = (posQty - used).clamp(0.0, posQty);
    ceil = _applyConstraint(ceil, allowedByPos);
  }
}
```

Batch and rack balance constraints above this block are unchanged.

### 7. `StockEntryItemFormController.effectiveMaxQty` — same guard

Identical `!allowFullSerials.value` guard applied to the equivalent POS cap block in the SE controller.

---

## Behaviour Matrix

| State | Full serial selectable? | POS cap enforced? | Batch/Rack cap enforced? |
|-------|------------------------|-------------------|--------------------------|
| No Full serials in list | n/a | Yes | Yes |
| Toggle hidden (all serials available) | n/a | Yes | Yes |
| Toggle visible, OFF | No | Yes | Yes |
| Toggle visible, ON | Yes | No | Yes |

---

## Non-Goals

- Toggle state does not persist across sheet sessions (resets to `false` on each `initForNewItem` / `initForEdit`).
- The "Full" visual indicator on dropdown rows is never hidden — workers always see capacity state.
- Packing Slip read-only serial mode is unaffected (its `availableSerialNos` is a single-element list; the toggle would never show because a single pre-seeded serial cannot be "Full" in the dropdown sense).
