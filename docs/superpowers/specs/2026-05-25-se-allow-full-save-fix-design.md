# SE Allow Full — Save-Path Fix Design

**Date:** 2026-05-25
**Branch:** release/play-store-beta-1-build-5

## Background

The "Allow Full" toggle was implemented in the previous session for both Delivery Note and Stock Entry item forms. The toggle appears in the Invoice Serial No label row when at least one serial has hit its POS Upload qty cap (`isFull = remaining <= 0`), and bypasses the POS cap in `effectiveMaxQty` so the user can enter a qty.

**Gap discovered:** `StockEntryFormController.addItemLocally` and `updateItemLocally` run a hard `if (projected > cap)` check unconditionally, independent of `allowFullSerials`. Even with the toggle ON and `effectiveMaxQty` bypassed, submitting from the SE item form hits "Qty Cap Exceeded" and the item is never committed.

Additionally, `notifySerialItemsChanged()` is never called in the SE flow, whereas Delivery Note calls it from `_scheduleParentRefresh()` after each item commit.

## Affected flow

Dashboard → Stock Entry (Material Issue, `customReferenceNo` starts with KX or MX) → Items → Scan Barcode → Item Form Sheet → Invoice Serial No → Allow Full toggle ON → submit → blocked by secondary cap check.

## Design

### Section 1 — `bypassPosCap` flag in save methods

**Files:** `stock_entry_form_controller.dart`, `stock_entry_item_form_controller.dart`

Add `{bool bypassPosCap = false}` as a named optional parameter to both `addItemLocally` and `updateItemLocally` in `StockEntryFormController`. Gate the cap-exceeded block with `&& !bypassPosCap` so the check is skipped when the user has explicitly enabled Allow Full.

```dart
// addItemLocally — gate added
if (resolvedSerial != '0' && posUpload.value != null && !bypassPosCap) {
  // existing cap-exceeded check and GlobalDialog.showQtyCapExceeded unchanged
}

// updateItemLocally — gate added (same pattern)
if (resolvedSerial != '0' && posUpload.value != null && !bypassPosCap) {
  // existing cap-exceeded check and GlobalDialog.showQtyCapExceeded unchanged
}
```

In `StockEntryItemFormController.submit()`, pass `bypassPosCap: allowFullSerials.value` to both parent calls:

```dart
if (rowId != null) {
  _parent.updateItemLocally(
    rowId, qty, batch, srcRack, tgtRack, sWh, tWh, serial,
    bypassPosCap: allowFullSerials.value,
  );
} else {
  _parent.addItemLocally(
    qty, batch, srcRack, tgtRack, sWh, tWh, serial,
    bypassPosCap: allowFullSerials.value,
  );
}
```

**Invariants preserved:**
- Batch balance cap (`effectiveMaxQty` path) — not touched.
- Rack balance cap (`effectiveMaxQty` path) — not touched.
- POS cap still enforced when `allowFullSerials = false` (default).
- No changes to any other DocType (DN, PS, PO, PR).

### Section 2 — `notifySerialItemsChanged()` in `addItem()` coordinator

**File:** `stock_entry_form_controller.dart`

Mirrors DN's `_scheduleParentRefresh()` which calls `notifySerialItemsChanged()` after each item commit. In SE, the equivalent hook is the `addItem()` coordinator, right after `child.submitWithFeedback()` returns `true` — while the child controller is still alive.

```dart
final success = await child.submitWithFeedback();
if (!success) return;
child.notifySerialItemsChanged();   // mirrors DN _scheduleParentRefresh
```

This increments `serialItemsStamp` on the child, triggering an `Obx` rebuild in `SharedInvoiceSerialNumberField`. Any serial whose remaining just reached zero will now be marked Full in the dropdown before the sheet closes.

## What is NOT changing

- `SerialFieldMixin.allowFullSerials` — already present.
- `StockEntryItemFormController.effectiveMaxQty` bypass — already present.
- `initForNewItem` / `_loadExistingItem` reset of `allowFullSerials` — already present.
- `SharedInvoiceSerialNumberField` toggle widget — already present.
- All other DocType controllers.

## File changes summary

| File | Change |
|------|--------|
| `stock_entry_form_controller.dart` | Add `bypassPosCap` param to `addItemLocally` + `updateItemLocally`; call `child.notifySerialItemsChanged()` in `addItem()` |
| `stock_entry_item_form_controller.dart` | Pass `bypassPosCap: allowFullSerials.value` in `submit()` |

Total: ~8 lines changed / added across 2 files.
