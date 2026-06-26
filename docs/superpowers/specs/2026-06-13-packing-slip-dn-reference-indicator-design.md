# Packing Slip — DN-Reference Validity Indicator + Resolve

**Date:** 2026-06-13
**Module:** `lib/app/modules/packing_slip`
**Status:** Design approved — ready for implementation plan

## Problem

Submitting a Packing Slip in the ERPNext web UI fails with:

> Row #: missing a valid Delivery Note Item reference

### Root cause (verified against `frappe/erpnext` `version-15`)

`erpnext/stock/doctype/packing_slip/packing_slip.py` → `PackingSlip.validate()` →
`validate_items()` runs, for every row:

```python
remaining_qty = frappe.db.get_value(
    "Delivery Note Item" if item.dn_detail else "Packed Item",
    {"name": item.dn_detail or item.pi_detail, "docstatus": 0},  # docstatus: 0
    ["sum(qty - packed_qty)"],
)
if remaining_qty is None:
    frappe.throw(_("Row {0}: Please provide a valid Delivery Note Item or Packed Item reference."))
```

`remaining_qty` is `None` (→ throw) in two situations:

1. **Unresolved reference** — `dn_detail` is empty, or points to a DN Item row name
   that no longer exists (DN amended/re-keyed, or the REST read stripped the field).
2. **Submitted Delivery Note** — `dn_detail` is correct, but the query filters
   `docstatus: 0`; a submitted DN's child rows carry `docstatus = 1`, so the
   aggregate matches zero rows and returns `None`.

### Scope decision (confirmed with user)

- Delivery Notes are **always Draft** when packed in this app.
- Backend is **stock version-15** (no customised `validate_items`).

Therefore **case 1 is the only failure mode in scope.** A correctly-resolved
reference against a Draft DN *will* submit. Case 2 cannot arise in this workflow
and is explicitly out of scope.

### Why the app's existing repair is not enough

The controller already auto-repairs references on load via `_refreshDnDetails`
(re-match by item code + serial + batch). Two gaps remain:

- When the re-match finds no candidate (`match == null`), the orphan is left in
  place silently.
- **The Items tab is DN-anchored.** `_buildChecklistRow` iterates the *Delivery
  Note's* items and looks up the slip row via `getCurrentSlipItem(dnItem.name)`
  (`dnDetail == dnItem.name`). A slip row with empty/stale `dn_detail` matches no
  DN row, so it **never renders** — it is an *invisible orphan* that rides along
  to the server and detonates at submit.

Frappe runs `validate()` on **every save**, not only submit. So orphans almost
always originate from a **DN amended/re-keyed after the slip was last saved from
the app**. The practical guarantee we lean on: *if the app can successfully save
the slip, ERPNext can submit it* (reference-wise).

## Goals

1. Surface, on the Items tab, whether every slip row resolves to a valid linked
   DN Item — including the invisible orphans.
2. Provide a one-tap, robust **Resolve** action that re-matches orphaned
   references and persists, so the slip becomes immediately submittable in ERPNext.
3. Positive confirmation when all references are valid.

## Non-Goals (YAGNI)

- Do **not** fold in the separate `validate_items` throws for
  qty-exceeds-remaining or already-packed — they are different errors than the
  one reported.
- Do **not** handle submitted-DN (case 2) — out of workflow scope.
- Do **not** modify the legacy `PackingSlipItemCard` (unused by this screen).
- No form-header validity icon (the rejected "Approach C") in this iteration.

## Design

### 1. Validity model (controller)

Added to `PackingSlipFormController`. All are pure getters over existing
observables (`linkedDeliveryNote`, `packingSlip`), so `Obx` reacts automatically.

```dart
enum DnRefStatus { checking, allLinked, hasUnlinked }

Set<String> get _validDnNames; // names of linked DN items (non-empty only)

/// Slip rows whose dnDetail is empty or not in _validDnNames.
/// Returns [] while the linked DN is not loaded.
List<PackingSlipItem> get unlinkedItems;

DnRefStatus get dnRefStatus; // delegates to computeDnRefStatus(...)
```

The status decision is a **pure top-level function** so it is testable without
GetX:

```dart
DnRefStatus computeDnRefStatus({
  required List<PackingSlipItem> items,
  required Set<String> validNames,
  required bool dnLoaded,
});
// !dnLoaded            -> checking
// no orphans           -> allLinked
// >= 1 orphan          -> hasUnlinked
```

### 2. Resolve mechanism

New pure resolver in
`lib/app/modules/packing_slip/form/ps_dn_reference_resolver.dart`:

```dart
({List<PackingSlipItem> items, int fixed, int unresolved}) resolveDnReferences({
  required List<PackingSlipItem> slipItems,
  required List<DeliveryNoteItem> dnItems,
  double Function(DeliveryNoteItem)? remainingQty, // optional preference
});
```

Per orphan (a row that is empty or not in valid DN names), candidate DN rows are
those with:

- non-empty `name`,
- `itemCode` equal to the slip row's,
- serial equal (`customInvoiceSerialNumber ?? '0'` on both sides),
- `batchNo` equal **when** the slip row carries a non-empty batch.

**Selection (robustness upgrade over current logic):** among candidates, prefer
one with `remainingQty(candidate) > 0` (mirrors `findScannedDnItem`); otherwise
fall back to the first candidate. Rows already valid are returned unchanged.
`fixed` counts patched rows; `unresolved` counts orphans with no candidate.

`_refreshDnDetails` is **refactored to delegate** to this resolver, so the
load-time auto-repair and the explicit Resolve action share one code path (DRY),
and load-time repair gains the remaining-qty preference.

Controller action:

```dart
Future<void> resolveDnReferencesAndSave() async {
  // guard: linkedDeliveryNote loaded && packingSlip.docstatus == 0
  //        else snackbar "Delivery Note not loaded yet." and return
  // run resolveDnReferences over packingSlip.items
  //   (remainingQty: _calcRemainingQtyForDnItem)
  // if fixed > 0: patch packingSlip.value, _checkForChanges(), await saveDocument()
  // snackbar summary: "Linked N item(s) to the Delivery Note"
  //                   + ", M could not be matched" when unresolved > 0
}
```

Unresolvable orphans remain listed in the banner for manual removal via the
existing `deleteItem(item)` (confirmation dialog + save).

### 3. UI — banner on the Items tab

New widget `PackingSlipDnLinkBanner` under
`lib/app/modules/packing_slip/form/widgets/`, placed in `_buildItemsView`
between the filter-chip `Divider` and the `Expanded` list, wrapped in `Obx`.

| `dnRefStatus` | Render |
|---|---|
| `checking`    | `SizedBox.shrink()` — assert nothing while the DN loads |
| `allLinked`   | Slim green chip: ✓ "All items linked to Delivery Note" |
| `hasUnlinked` | Amber banner: ⚠ "N packed item(s) aren't linked to the Delivery Note — they will block submission in ERPNext." A **Resolve** button (spinner bound to `isSaving`), and an expandable list of orphan rows (item code · qty · `#serial`), each with a **Remove** trailing action. |

Resolve / Remove affordances render only when `packingSlip.docstatus == 0`.
(Submitted slips cannot hold orphans — they passed `validate` — but the guard is
kept for safety.)

### 4. Reactivity / lifecycle

No new GetX workers — the feature is entirely user-triggered. The banner's `Obx`
depends on `linkedDeliveryNote` and `packingSlip`, both already `.obs`. On-load
`_refreshDnDetails` continues to auto-repair; the banner reflects whatever
remains unresolved afterward.

### 5. Error handling

`resolveDnReferencesAndSave` persists through the existing `saveDocument` →
`_handleSaveError` path, so a server-side validation failure surfaces via the
existing Frappe-exception snackbar (`_parseFrappeException`). Resolve invoked
while the DN is not loaded is a guarded no-op with an explanatory snackbar.

## Testing

- Rework `test/unit/packing_slip_refresh_dn_details_test.dart` to exercise the
  shared `resolveDnReferences`:
  - back-compat: all-valid (no change), empty `dn_detail` matched, stale
    `dn_detail` matched, no-match left untouched, batch match, batch mismatch;
  - new: `fixed` / `unresolved` counts; candidate **preference by remaining qty**
    when multiple DN rows match.
- New unit test for `computeDnRefStatus`: `checking` (DN not loaded),
  `allLinked`, `hasUnlinked`.
- Banner widget test is optional / low priority, consistent with project norms
  (existing `status_pill` / `doctype_form_header` widget-test failures pre-exist
  on `release/play-store`).

## Files

**New**
- `lib/app/modules/packing_slip/form/ps_dn_reference_resolver.dart` — pure resolver + `computeDnRefStatus`.
- `lib/app/modules/packing_slip/form/widgets/packing_slip_dn_link_banner.dart` — banner widget.

**Modified**
- `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart` — validity getters, `resolveDnReferencesAndSave`, `_refreshDnDetails` delegates to resolver.
- `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart` — mount banner in `_buildItemsView`.
- `test/unit/packing_slip_refresh_dn_details_test.dart` — reworked around the shared resolver; add status + count tests.
