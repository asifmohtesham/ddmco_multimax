# Purchase Receipt — Valid PO-Item Linkage & Over-Receipt Toggle

**Date:** 2026-06-24
**Module:** `lib/app/modules/purchase_receipt`
**Status:** Design approved, pending spec review

## Problem

Saving a Purchase Receipt fails with HTTP **417** and ERPNext error:

```
frappe.exceptions.ValidationError: Invalid reference Purchase Order Item h03g3r24ji
```

### Root cause

ERPNext's `compare_values` (`accounts_controller.py`) resolves each PR item's
`purchase_order_item` via `frappe.db.get_value("Purchase Order Item", <name>)`.
When that row name does not exist in the server's `tabPurchase Order Item`
table, it throws `Invalid reference Purchase Order Item <name>`. **The message
means the app sent a PO child-row name the server does not recognise** (stale
cache after a PO amend/cancel-recreate, or a row matched to the wrong/closed
line).

How the app produces the bad value (`purchase_receipt_form_controller.dart`):

- `linkToPurchaseOrder()` (line ~310) matches an added item to a cached PO row
  **by `item_code` only**, prefers a row with `receivedQty < qty`, but **falls
  back to ANY row including fully-received ones** (line ~316), then copies
  `item.name` into `purchase_order_item`.
- The cache is built by `_fetchLinkedPurchaseOrders()` (line ~287) at form load.
  If the PO is amended mid-session, the cached row names become invalid.
- Nothing validates the linkage before save: `validateSheet()` checks only
  qty + rack; `addItem()` checks only edit-state + qty. The invalid reference
  reaches ERPNext, which rejects the **entire** save with a 417.

## Goals

1. Prevent invalid/missing `purchase_order_item` references from being saved.
2. When a valid link can be auto-determined, set it silently.
3. When it is ambiguous, prompt the user to pick the correct PO Item.
4. When no open PO line exists, block by default; allow deliberate
   over-receipt via a toggle that mirrors the Delivery Note "Allow Full" toggle.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| When to detect | **Both** — proactive at Add Item time + reactive safety net on the save 417. |
| Prompt UX | **Auto-relink**; show a picker only when ambiguous (≥2 candidates). |
| Zero-candidate case | **Block by default**, plus an **over-receipt toggle** (like DN "Allow Full") that surfaces fully-received rows as link candidates. |

## Architecture: one shared resolver, two call sites

Centralise all linking rules in a single function on the PR **form** controller
so the proactive and reactive paths stay thin and the rules live in one place.

```
PoLinkResult resolvePoLink(String itemCode, {required bool allowOverReceipt})
```

Result is one of:

- **autoLinked(row)** — exactly 1 eligible candidate; caller applies it silently.
- **needsPicker(candidates)** — ≥2 eligible candidates; caller opens the picker.
- **blocked(reason)** — 0 eligible candidates; caller notifies and refuses.

This replaces the current `linkToPurchaseOrder` first-match-wins behaviour,
including removing the "any row incl. fully-received" silent fallback.

### Section 1 — Resolver rules

Operating over `_cachedPoItems` (each entry `{poName, item: PurchaseOrderItem}`):

- **Candidates** = cached rows where `item.itemCode == itemCode`.
- **Open candidates** = candidates with `receivedQty < qty`.
- **Over-receipt candidates** = candidates with `receivedQty >= qty`, eligible
  **only when `allowOverReceipt == true`**.
- **Eligible set** = open candidates ∪ (over-receipt candidates if toggle on).
- **1 eligible** → `autoLinked`. **≥2** → `needsPicker`. **0** → `blocked`.

Applying a chosen/auto row sets `poItemId`, `poDocName`, `poQty`, `poRate`
(same fields `linkToPurchaseOrder` writes today).

> Note: this intentionally drops the silent fallback to fully-received rows that
> currently runs whenever the toggle would be off.

### Section 2 — Over-receipt toggle (mirrors `allowFullSerials`)

- `RxBool allowOverReceipt = false.obs` on
  `PurchaseReceiptItemFormController`.
- **Reset to `false` on every sheet open** (in `initForCreate` / `initForEdit`,
  matching how DN resets `allowFullSerials` in its seed methods).
- Surfaced as a `Switch` in the item-form sheet labelled **"Allow Over-Receipt"**.
- When **ON**:
  1. Bypasses the PO-qty cap. In `validateSheet()` the ceiling block
     (lines ~211–215) and `effectiveMaxQty` gain a `&& !allowOverReceipt.value`
     guard so qty above ordered is permitted.
  2. Makes fully-received PO rows eligible in the resolver
     (`resolvePoLink(..., allowOverReceipt: allowOverReceipt.value)`).
- When **OFF** (default): qty above ordered is blocked, fully-received lines are
  not linkable, and a no-open-line item is **blocked** with message:
  *"No open Purchase Order line for `<item_code>` on `<PO>` — enable Allow
  Over-Receipt to receive against a closed line."*

### Section 3 — Proactive path (Add Item)

In `PurchaseReceiptItemFormController.submit()` (line ~256), before
`parent.addItem(...)` for the new-item branch:

1. `final result = parent.resolvePoLink(itemCode.value, allowOverReceipt: allowOverReceipt.value);`
2. `autoLinked` → apply link fields onto the controller's `poItemId`/etc., then `addItem`.
3. `needsPicker` → open the link-picker sheet; on selection apply + `addItem`.
4. `blocked` → `AppNotification`, keep the sheet open, **do not** add the item.

The existing `linkToPurchaseOrder` call in `initialise` (line ~192) is replaced
by a best-effort `resolvePoLink` so the PO Qty chip/progress still populate on
open; final authority is the submit-time resolve above.

### Section 4 — Reactive path (save 417 safety net)

In `saveDocument`'s `DioException` handler (line ~658), before the generic
error branch, detect the specific failure:

- `e.response?.statusCode == 417` **and** the body `exception` string contains
  `Invalid reference Purchase Order Item`.

Then:

1. Parse the offending row name(s) from the message
   (`Invalid reference Purchase Order Item (\S+)`), de-duplicated.
2. Find PR items whose `purchaseOrderItem` is in that set.
3. **Re-fetch** the linked PO(s) fresh via `_fetchLinkedPurchaseOrders(poNames)`
   (this is what catches the mid-session amend/stale-cache root cause).
4. Re-run `resolvePoLink` per offending item (toggle off for the silent pass).
   - All `autoLinked` → apply, then **re-save once**.
   - Any `needsPicker`/`blocked` → open the picker (with its own over-receipt
     switch) / show the block message; re-save after the user resolves.
5. **Loop guard:** the automatic re-save runs at most once. A second 417 falls
   through to the normal error notification.

### Section 5 — Link-picker sheet (new widget)

`form/widgets/purchase_receipt_po_link_sheet.dart` — a bottom sheet that:

- Lists candidate PO rows: `item_code`, ordered / received / remaining qty,
  source PO name.
- Includes an **"Allow Over-Receipt"** switch that reveals fully-received rows
  (disabled/greyed until toggled, mirroring how the DN serial picker reveals
  full rows).
- On tap of a row, returns the chosen `{poName, item}` to the caller.
- Styled after the existing `widgets/purchase_receipt_po_selection_sheet.dart`.

Used by both the proactive and reactive paths whenever a human decision
(`needsPicker`) is required.

### Section 6 — Error handling summary

| Situation | Behaviour |
|---|---|
| 1 open PO line | Auto-link, silent. |
| ≥2 open PO lines | Picker. |
| 0 open lines, toggle off | Block + guidance message; item not added / save aborted. |
| 0 open lines, toggle on, ≥1 closed line | Closed lines become eligible (auto/picker per count). |
| No PO line at all for item_code | Block (cannot link); user must fix on PO side. |
| Save still 417 after one auto re-link re-save | Normal error notification (no further auto-retry). |

## Testing

- **Resolver unit tests** (`test/unit/`): item_code with 1 / many / zero
  open candidates × `allowOverReceipt` on/off → asserts
  `autoLinked` / `needsPicker` / `blocked`.
- **417 parser test**: extracts row name(s) from the ERPNext exception string,
  including the multi-item case.
- **Qty-cap guard test**: `effectiveMaxQty` / `validateSheet` permit qty above
  ordered iff `allowOverReceipt` is on.
- Follows existing `test/unit` + `test/widget` conventions
  (cf. `allow_full_serial_toggle_test.dart`).

## Out of scope

- Server-side ERPNext customisation.
- Changing ERPNext's over-receipt tolerance (`Stock Settings`); the app surfaces
  a valid reference, ERPNext still enforces its own tolerance on submit.
- Other DocTypes — only Purchase Receipt emits `purchase_order_item`.

## Affected files

| File | Change |
|---|---|
| `purchase_receipt_form_controller.dart` | Add `resolvePoLink` + `PoLinkResult`; replace `linkToPurchaseOrder`; 417 detection + one-shot re-save in `saveDocument`. |
| `purchase_receipt_item_form_controller.dart` | Add `allowOverReceipt` RxBool (reset on open); guard qty cap in `validateSheet`/`effectiveMaxQty`; resolve at `submit()`. |
| `form/widgets/purchase_receipt_po_link_sheet.dart` | **New** picker sheet with over-receipt switch. |
| `form/purchase_receipt_item_form_sheet.dart` | Add the "Allow Over-Receipt" switch to the sheet. |
| `test/unit/…`, `test/widget/…` | Resolver, parser, qty-cap tests. |
