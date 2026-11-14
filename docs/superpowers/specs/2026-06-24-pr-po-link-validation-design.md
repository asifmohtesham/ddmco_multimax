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
2. When a valid **open** link can be auto-determined, set it silently.
3. When it is ambiguous, prompt the user to pick the correct **open** PO Item.
4. When no open PO line exists, **block** with a clear message — the operator
   resolves it on the Purchase Order. The app never over-receives.

## Decisions

| Question | Decision |
|---|---|
| When to detect | **Both** — proactive at Add Item time + reactive safety net on the save 417. |
| Prompt UX | **Auto-relink**; show a picker only when ambiguous (≥2 **open** candidates). |
| Zero-open-line case | **Block + message, no picker.** The line is fully received / not on the PO; resolve on the PO side. |

## Revision (2026-06-24) — over-receipt removed

The first iteration shipped an "Allow Over-Receipt" toggle (mirroring DN's
`allowFullSerials`) that lifted the qty cap and let the user link
fully-received PO rows. This was **withdrawn** for two reasons:

1. **The backend doesn't support it by default.** In `frappe/erpnext`
   `version-15` (`controllers/status_updater.py`), over-receipt is governed by
   `over_delivery_receipt_allowance` — resolved from the Item master, then
   Stock Settings, defaulting to **0**. With the default tolerance, `validate_qty`
   throws `OverAllowanceError` on any over-receipt. The app toggle was a *false
   affordance*: toggling it and entering more still failed server-side.
2. **It conflates two orthogonal concerns.** The 417 bug is a *stale/invalid
   reference* (the row no longer exists); the fix is to re-link to a valid
   **open** row. Receiving above ordered is a *policy decision the ERP owns* —
   the app should not be a vehicle for bypassing an audit control.

**Net:** the resolver is open-rows-only. Over-receipt remains possible only the
correct way — an admin sets `over_delivery_receipt_allowance` on the Item /
Stock Settings, and ERPNext enforces it on submit. Sections 2 and 5's
over-receipt mechanics below are superseded by this revision.

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

### Section 1 — Resolver rules (open-rows-only)

Operating over `_cachedPoItems` (each entry `{poName, item: PurchaseOrderItem}`):

- **Candidates** = cached rows where `item.itemCode == itemCode`.
- **Eligible = open candidates only** = candidates with `receivedQty < qty`.
  Fully-received rows are **never** eligible.
- **1 open** → `autoLinked`. **≥2 open** → `needsPicker`. **0 open** → `blocked`.
- Item absent from all linked POs → `blocked`.

Applying a chosen/auto row sets `poItemId`, `poDocName`, `poQty`, `poRate`
(same fields `linkToPurchaseOrder` writes today). The signature is
`resolvePoLink(String itemCode)` — no over-receipt parameter.

> Note: this drops the old silent fallback to fully-received rows.

### Section 2 — Qty cap (over-receipt toggle withdrawn)

The qty ceiling is the PO ordered qty unconditionally:
`effectiveMaxQty => poQtyCeiling(poQty.value)` (PO qty, or `infinity` when the
item carries no PO qty). There is **no** in-sheet toggle and **no**
`allowOverReceipt` field — see the Revision note above. Qty above ordered is
never permitted in-app; ERPNext owns over-receipt via its tolerance setting.

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

- Lists the **open** candidate PO rows only: `item_code`, ordered / received /
  remaining qty, source PO name. No over-receipt switch (withdrawn).
- On tap of a row, returns the chosen `{poName, item}` to the caller.
- Styled after the existing `widgets/purchase_receipt_po_selection_sheet.dart`.

Used by both the proactive and reactive paths whenever a human decision
(`needsPicker`) is required.

### Section 6 — Error handling summary

| Situation | Behaviour |
|---|---|
| 1 open PO line | Auto-link, silent. |
| ≥2 open PO lines | Picker (open lines only). |
| 0 open lines (line fully received) | Block + message; item not added / save aborted. Resolve on the PO. |
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
