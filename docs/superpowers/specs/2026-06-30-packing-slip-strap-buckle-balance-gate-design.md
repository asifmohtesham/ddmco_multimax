# Packing Slip — Strap/Buckle balance gate

**Date:** 2026-06-30
**Status:** Design (awaiting review)
**Module:** `lib/app/modules/packing_slip/`

## Problem

Each Invoice Serial Number on a Delivery Note pairs **Straps** with **Buckles**:
the delivered Strap quantity and Buckle quantity for a serial are meant to match.
Packing a serial's straps and buckles in separate batches (or shipping straps
without their matching buckles) does more harm than good — the matched set gets
split across packages.

Rather than enforce the balance on the Delivery Note form, we gate it at
**Packing Slip** time: a user may not pack a Strap- or Buckle-group item for an
Invoice Serial Number whose linked-DN Strap and Buckle quantities are mismatched.

## Rule (gate predicate)

For an Invoice Serial Number, read the **linked Delivery Note's** rows for that
serial and sum qty by item group:

- `strapQty`  = Σ `qty` where `itemGroup == 'Straps'`  and `customInvoiceSerialNumber == serial`
- `buckleQty` = Σ `qty` where `itemGroup == 'Buckles'` and `customInvoiceSerialNumber == serial`

A serial is **unbalanced** when:

```
strapQty > 0 && buckleQty > 0 && (strapQty - buckleQty).abs() > 1e-9
```

Quantities are `double`; the equality check uses a small epsilon tolerance
(`1e-9`) rather than raw `!=` to avoid false mismatches from floating-point
representation of integer-valued quantities.

If either group is entirely absent (qty 0) the serial is **balanced** — this is
the "equal **or 0**" rule (a strap-only or buckle-only serial has nothing to
mismatch).

The gate applies **only when the item being packed is itself a Strap- or
Buckle-group item**. Items of any other group pack freely, even within an
otherwise-unbalanced serial.

### Quantities are DN-delivered

The comparison uses the linked DN's *delivered* quantities — not packed-so-far
and not remaining-to-pack. An unbalanced serial is a data problem in the DN; it
cannot be fixed by packing, so packing it is disallowed until the DN is
corrected.

## Group names

The two item-group names are the exact (case-sensitive) ERPNext leaf names,
**plural**: `'Straps'` and `'Buckles'`. They are centralized as constants in one
file so a future rename is a single change-point.

## New pure helper — `lib/app/modules/packing_slip/form/ps_serial_balance.dart`

Follows the existing extracted-pure-function pattern (`ps_serial_options.dart`,
`dn_scan_item_matcher.dart`) so it is unit-testable with zero GetX scaffolding.

```dart
import 'package:multimax/app/data/models/delivery_note_model.dart';

/// Item-group leaf names that must ship together in matched quantities.
const String kStrapItemGroup  = 'Straps';
const String kBuckleItemGroup = 'Buckles';

/// True when [itemGroup] participates in the strap/buckle pairing rule.
bool isPairedItemGroup(String? itemGroup) =>
    itemGroup == kStrapItemGroup || itemGroup == kBuckleItemGroup;

/// Strap and Buckle delivered totals for [serial] across all [items].
({double strap, double buckle}) strapBuckleQtyFor(
    List<DeliveryNoteItem> items, String serial);

/// True when [serial]'s delivered Strap/Buckle quantities are mismatched.
///
/// Balanced (false) when either group is absent (the "or 0" rule) or the two
/// group totals are equal. An empty / sentinel ('0') serial is balanced.
bool isSerialStrapBuckleUnbalanced(
    List<DeliveryNoteItem> items, String serial);
```

`strapBuckleQtyFor` is exposed so callers can build the user-facing message
("Strap qty (10) ≠ Buckle qty (8)") without re-summing.

## Enforcement point 1 — serial dropdown (in-sheet retarget)

When the item sheet is open for a Strap/Buckle item, unbalanced serials appear
in the serial dropdown **visible but disabled** (mirrors the existing "Full"
serial lockout exactly).

Changes:

1. `lib/app/shared/item_sheet/serial_number_field_delegate.dart`
   — add an optional field to `SerialDropdownItem`:
   ```dart
   /// Non-null marks this serial non-selectable; the string is the reason
   /// shown in the dropdown row (e.g. "Strap ≠ Buckle").
   final String? blockedReason;
   ```

2. `lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart`
   `_buildItems`:
   - `enabled: (!item.isFull || allowFull) && item.blockedReason == null`
   - dim to 40% opacity when `blockedReason != null` (same as Full)
   - render `blockedReason` in the error/red colour in place of the
     `×qty` / "Full" sub-label, taking priority over the Full note.

3. `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart`
   `posDropdownItemFor(serial)` — set
   `blockedReason: 'Strap ≠ Buckle'` when
   `isPairedItemGroup(itemGroup.value)` **and**
   `isSerialStrapBuckleUnbalanced(parent.linkedDeliveryNote.items, serial)`.
   The DN row list is read from the parent controller.

Blocked serials are **not** removed from `availableSerialNos` — they stay listed
so the user can see *why* a serial is unavailable. Because the dropdown disables
them, the `selectedSerial` retarget worker can never fire for a blocked serial,
so no extra guard is needed in `retargetSheetToSerial`.

## Enforcement point 2 — scan (auto-skip, reject-if-all-blocked)

A scan resolves a barcode → DN row → serial, then opens the add sheet. The gate
makes scan resolution **skip** serials that are blocked for the scanned item, and
only reject when every matching serial is blocked.

Changes:

1. `lib/app/modules/packing_slip/form/dn_scan_item_matcher.dart`
   `findScannedDnItem` — add an optional predicate parameter, backward-compatible
   (default null → no skipping, existing tests unaffected):
   ```dart
   bool Function(DeliveryNoteItem)? skipRow,
   ```
   Rows for which `skipRow` returns true are excluded from **both** the
   first-with-remaining pick **and** the first-match fallback. Returns null when
   no code/batch match exists *or* when every match is skipped.

2. `packing_slip_form_controller.dart` `_findItemInDN(code, batch)` — pass:
   ```dart
   skipRow: (row) =>
       isPairedItemGroup(row.itemGroup) &&
       isSerialStrapBuckleUnbalanced(dnItems, row.customInvoiceSerialNumber ?? ''),
   ```

3. `packing_slip_form_controller.dart` `_handleScanResult` — when `_findItemInDN`
   returns null, distinguish blocked-by-balance from not-found by checking
   whether any code/batch match exists at all:
   - **any match exists** (so all were skipped) → snackbar:
     *"All serials for {code} have mismatched Strap/Buckle quantities. Packing
     blocked until the Delivery Note is balanced."*
   - **no match at all** → existing *"Item {code} not found in Delivery Note or
     Batch mismatch."* message (unchanged).

### Skip vs Full interaction

`findScannedDnItem` already falls back to the first match when all remaining are
exhausted (so the caller surfaces the fully-packed sheet flow). A balanced but
fully-packed serial therefore still opens its sheet (showing "Full"); an
unbalanced serial is never auto-targeted by scan.

## Testing

- **`test/unit/ps_serial_balance_test.dart`** (new, pure):
  - balanced equal qty → false
  - one side zero (10 straps / 0 buckles) → false (the "or 0" rule)
  - both present, mismatched → true
  - both zero / serial absent → false
  - `isPairedItemGroup`: 'Straps'/'Buckles' → true; other groups / null → false
  - `strapBuckleQtyFor` returns correct sums across mixed serials/item-codes
- **`test/unit/packing_slip_scan_item_matcher_test.dart`** (extend):
  - `skipRow` excludes a blocked row from the remaining-pick → advances to the
    next packable serial
  - all matches skipped → returns null
  - no `skipRow` passed → unchanged legacy behaviour
- **`test/widget/shared_invoice_serial_field_toggle_test.dart`** (extend or new
  sibling): a `SerialDropdownItem` with `blockedReason` renders disabled, dimmed,
  and shows the reason text.

## Out of scope (YAGNI)

- No change to the Delivery Note form (the rule lives entirely in the PS flow).
- No backend / ERPNext server-side validation.
- No configurable group names beyond the two centralized constants.
- No change to packed-qty or remaining-qty caps — the existing per-row caps are
  untouched; this gate sits on top of them.
