# Stock Entry — Rack-Derived Item Warehouses

> Date: 2026-06-11 | Status: Approved | Branch: `release/play-store`

## Problem

In the Stock Entry item sheet (Material Transfer flow: scan item → scan batch →
scan source rack → scan target rack), the committed item rows get their
`s_warehouse` / `t_warehouse` from the document-level **Default Source/Target
Warehouse** instead of the warehouse the scanned rack actually belongs to.

### Expected behaviour (validated against frappe/erpnext `version-15`)

In ERPNext v15 `stock_entry.js`, the parent `from_warehouse` / `to_warehouse`
fields are *defaults copied into new rows* (`items_add`); the row-level
`s_warehouse` / `t_warehouse` are what the stock ledger posts against, and a
row's own value takes precedence. The app must match:

- **Priority 1:** item warehouse derived from the scanned rack.
- **Priority 2:** document default source/target warehouse.

### Root causes (current code)

`lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`:

1. `validateDualRack()` derives the warehouse **only** from a local string
   parse of the rack name (`RackLocation.tryParse`: `KA-WH-DXB1-101A` →
   `'WH-DXB1 - KA'`). Racks that don't follow the 4-part naming convention
   parse to `null`, so the default warehouse silently wins at `submit()`.
   The Rack DocType's authoritative `warehouse` field is never consulted.
2. `resolvedWarehouse` reads only `_parent.fromWarehouse` — a refactor dropped
   the documented cascade (`itemSourceWarehouse ?? … ?? header`). All balance
   lookups (`fetchRackBalance`, batch balance, pickers) are therefore scoped
   to the **default** source warehouse, so a source rack in a different
   warehouse reads balance 0 and is falsely rejected.
3. Target racks get no server-side existence check at all
   (`isTargetRackValid` is set `true` unconditionally).

`submit()` already implements the correct cascade
(`itemSourceWarehouse ?? fromWarehouse`); only the derivation feeding it is
broken.

## Design

Scope: `stock_entry_item_form_controller.dart` only; the shared
`item_sheet_controller_base.dart` is untouched. No server-side changes — the
Rack DocType already carries a `warehouse` link field (the API layer filters
on it in `ApiProvider.getRacksByWarehouse`).

### 1. Warehouse derivation in `validateDualRack(rack, isSource)`

For both source and target sides:

- Immediately set `itemSourceWarehouse` / `itemTargetWarehouse` from
  `RackLocation.tryParse(rack)?.warehouseName` (optimistic, zero-latency
  label update — current behaviour).
- Concurrently call `GET /api/resource/Rack/{rack}` via the existing
  `ApiProvider.getDocument('Rack', rack)`:
  - **200** → overwrite the item-level warehouse with the document's
    `warehouse` field (authoritative; works for any rack naming).
  - **404** → mark the rack invalid, clear the derived warehouse, show an
    error snackbar.
  - **Other failure (timeout / network)** → keep the optimistic parse value,
    log; do not block scanning.
- This also gives target racks a real existence check (fixes root cause 3).

### 2. Balance scoping

`resolvedWarehouse` becomes:

```dart
String? get resolvedWarehouse =>
    itemSourceWarehouse.value ?? _parent.fromWarehouse.value;
```

This re-scopes `fetchRackBalance`, batch balance, the batch picker, the rack
browse picker, and `_preloadRackStockMap` to the rack's actual warehouse.
Ordering inside `validateDualRack` for the source side: **await** the Rack
doc fetch (success, 404, or failure-with-parse-fallback) so the warehouse is
settled, *then* fetch the balance against it. The optimistic parse value only
serves the UI label during that window.

The source-rack zero-balance guard is kept (reject rack when item/batch
balance in the rack's own warehouse is 0) — it now just tests the right
warehouse, so valid racks in non-default warehouses stop being falsely
rejected. The server still blocks negative stock at submit as a backstop.

### 3. Batch re-scope worker

Add `ever(itemSourceWarehouse, …)` that re-fetches the batch balance when a
rack scan resolves the warehouse *after* the batch was already validated
(batch-first scan order). Stored in a field and cancelled in `onClose()`,
per project convention for GetX workers.

### 4. Commit path — no change

`submit()` keeps `sWh = itemSourceWarehouse ?? fromWarehouse` and
`tWh = itemTargetWarehouse ?? toWarehouse`. Header autofill from the first
item (`saveStockEntry`) stays as-is.

## Error handling summary

| Condition | Behaviour |
|---|---|
| Rack not found (404) | Rack invalid, derived warehouse cleared, snackbar |
| Source rack balance 0 in its own warehouse | Rack invalid, existing balance error message |
| Rack API timeout / network failure | Optimistic name-parse value stands; logged |
| Rack name not 4-part parseable | No optimistic value; API result is sole source |

## Testing

Unit tests (`test/`):

- Derivation priority: Rack API `warehouse` overwrites name-parse; name-parse
  used when API errors (non-404); document default used when both absent.
- Source rack with zero balance in **its own** warehouse → rejected; non-zero
  balance in a non-default warehouse → accepted (regression test).
- Target rack 404 → `isTargetRackValid` false.
- Batch-first scan order: batch balance re-fetched when
  `itemSourceWarehouse` resolves afterwards.
- `submit()` cascade: rack-derived warehouses land on the item row; defaults
  only when derivation absent.
