# Create Purchase Receipt from Purchase Order — Design

**Date:** 2026-06-26
**Status:** Approved (pre-implementation)
**Branch context:** `release/play-store`

## Problem

A Purchase Receipt (PR) can be created from the PR list screen today, but that
path starts with no PO context: the user must first hunt for the right Purchase
Order, and the receipt opens empty. There is no way to start *from* a submitted
Purchase Order — the place where the operator already knows exactly which goods
are arriving and how much remains to receive.

We want a **Create Purchase Receipt** action on the submitted Purchase Order
form (Items tab + header) that launches the existing scan-driven PR flow already
bound to this PO, so every received line links back to its Purchase Order Item.

## Goals

- One-tap path from a submitted PO to a new, PO-bound Purchase Receipt.
- Every PR item links to the correct **open** PO Item line.
- Avoid accidental duplicate receipts by offering to resume an existing draft.
- Fail-closed on permissions; never present a dead-end action.

## Non-Goals

- No pre-population of the receipt with all PO lines / pending quantities. The
  chosen flow is **empty receipt + scan** (operator scans physical goods; each
  scan auto-links). A "review-and-receive" pre-filled sheet was considered and
  rejected for this iteration.
- No over-receipt handling. The existing resolver is open-rows-only by design
  (`resolvePoLinkFor`); ERPNext owns over-receipt tolerance. Unchanged here.
- No changes to the Purchase Receipt form, route, link resolver, or 417 recovery.

## Chosen Approach

Reuse the existing, proven linking backbone. The Purchase Receipt form already:

- accepts `purchaseOrder` + `supplier` navigation arguments and, in
  `_initNewPurchaseReceipt`, fetches the linked PO into its cache;
- resolves each scanned item to an open PO line via `resolvePoLinkFor`
  (auto-link / picker / blocked);
- guards scanning so only items on the linked PO can be added;
- recovers from ERPNext 417 "Invalid reference Purchase Order Item" on save.

So the new work is **only** the entry point on the PO form, the gating, and a
resume-or-create branch. No PR-side code changes.

## Entry Points (both)

Both surfaces call one controller method, `createPurchaseReceipt()`:

1. **Header action** — a `receipt_long` icon added to
   `DocTypeFormHeader.extraActions` in `purchase_order_form_screen.dart`.
   Available from both Details and Items tabs.
2. **Items-tab button** — a prominent filled button pinned at the bottom of the
   Items tab. On submitted POs the `BarcodeInputWidget` (which only renders when
   `isEditable`, i.e. `docstatus == 0`) is absent, so the bottom slot is free.

## Visibility Gating

A reactive getter `canCreateReceipt` drives both surfaces. It is true only when
**all** hold:

- `po.docstatus == 1` (submitted)
- `po.status != 'Closed'`
- `hasOpenQty` — at least one line with `receivedQty < qty`
  (the action is **hidden** once the PO is fully received)
- `PermissionService.hasAccess('Purchase Receipt', permType: 'create') == true`
  (cached, reactive, fail-closed — the same mechanism used by `DocTypeGuard`
  and the nav drawer). Returns `null` while loading → treated as not-yet-allowed
  (surfaces hidden until the probe resolves; typically pre-warmed at login).

Note on the permission check: Frappe v15's `frappe.client.has_permission`
requires a docname, so a true create-permission probe on a not-yet-created doc
is unavailable. `PermissionService.hasAccess` uses the list-access probe
(`frappe.client.get_list`), which is the app-wide proxy for DocType access and
is already how every other guarded surface is gated. This is the intended,
consistent behaviour — not a workaround gap.

## Tap Behaviour — `createPurchaseReceipt()`

1. **Re-assert permission** (defence in depth): if `hasAccess(...) != true`,
   show a snackbar ("You don't have permission to create a Purchase Receipt.")
   and return.
2. **Existing-draft check.** Query open draft PRs linked to this PO (new
   provider call, below).
   - **Drafts found** → open `PurchaseReceiptResumeSheet`, listing each draft
     (`name` • posting date), each tappable to open in `edit` mode, with a
     footer action **"Start a new receipt"**. One widget handles 1..n drafts.
   - **No drafts** → proceed directly to *create new*.
   - **Lookup error** → fail-open to *create new* (resume is a convenience, not
     a correctness gate) with a quiet log; never block receiving on this query.
3. **Create new** →
   `Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: { 'name': '', 'mode': 'new', 'purchaseOrder': po.name, 'supplier': po.supplier })`.
   The PR form's existing `_initNewPurchaseReceipt` handles the rest.
4. **Resume existing** →
   `Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: { 'name': <prName>, 'mode': 'edit' })`.

## Provider: open-draft lookup

Add to `PurchaseOrderProvider`:

```text
getOpenDraftReceiptsForPo(String poName) -> List<DraftReceiptSummary>
```

Implementation:

1. `GET /api/resource/Purchase Receipt Item`
   filters `[["purchase_order","=",poName],["docstatus","=",0]]`,
   fields `["parent"]`, `limit_page_length = 0`.
   Child rows mirror the parent docstatus, so `docstatus == 0` selects rows
   belonging to draft receipts.
2. Reduce to **distinct** `parent` names via `parseDraftReceiptParents`.
3. If any, one header fetch:
   `GET /api/resource/Purchase Receipt` filters `[["name","in",[...]]]`,
   fields `["name","posting_date","modified"]` to populate the resume sheet.

`DraftReceiptSummary` is a small value object (`name`, `postingDate`) — or a
plain `Map` if a model feels heavy; the implementation plan will pick one.

## Files

| File | Change |
|------|--------|
| `purchase_order_form_controller.dart` | add `PermissionService`; `createPurchaseReceipt()`; getters `hasOpenQty` / `canCreateReceipt`; resume orchestration |
| `purchase_order_form_screen.dart` | header action in `extraActions`; Items-tab bottom button; both gated by `canCreateReceipt` |
| `purchase_order_provider.dart` | `getOpenDraftReceiptsForPo()` + `parseDraftReceiptParents()` static helper |
| `purchase_order/form/widgets/purchase_receipt_resume_sheet.dart` | **new** resume-or-create sheet |
| Purchase Receipt form / route / resolver / 417 recovery | **unchanged** (reused) |

## Pure Helpers (testability)

Extracted so the core logic is unit-testable without GetX/widget scaffolding:

- `bool hasOpenReceiptQty(List<PurchaseOrderItem> items)` — true if any
  `receivedQty < qty`.
- `List<String> parseDraftReceiptParents(dynamic responseData)` — distinct,
  order-preserving `parent` names from the child-list response; tolerant of
  null / non-Map / missing `data`.

## Testing

- **Unit**
  - `hasOpenReceiptQty`: empty list, all-received, partially-received, over-received.
  - `parseDraftReceiptParents`: normal multi-row dedup, empty, malformed/null,
    duplicate parents collapse to one.
- **Widget (light)** — mirror existing PO form patterns; keep minimal given known
  pre-existing test fragility on this branch (status_pill / doctype_form_header):
  - action surfaces hidden when `docstatus == 0`, when fully received, when
    permission denied; shown when submitted + open qty + permitted.

## Error Handling & Edge Cases

- Permission probe loading (`null`) → surfaces hidden until resolved; tap path
  blocks fail-closed.
- Draft-lookup network failure → fail-open to create-new (logged), never blocks.
- PO not submitted / Closed / fully received → surfaces hidden.
- Duplicate parents in the child query → collapsed by `parseDraftReceiptParents`.

## Rollout

Presentation/flow-only on the PO side; no schema or PR-side changes. Ships on
`release/play-store`. On-device smoke: submitted PO with open qty → both entry
points appear; create new → scan links correctly; resume path opens an existing
draft; fully-received PO hides the action.
