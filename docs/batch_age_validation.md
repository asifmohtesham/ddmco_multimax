# Oldest stock first (batch age validation)

When a floor user scans, types or picks a batch on an outbound sheet, the app refuses it
while an **older batch of the same item still has stock**. There is no override in the app:
a supervisor makes the exception directly in Desk. Decided with the business on
19 November 2026; a role-based override by Server Script may follow (see the last section).

## The rule

A batch `B` of item `I`, picked from warehouse `W`, is refused when another batch `O` of `I`:

1. is **older** than `B`, and
2. still has **stock left** in the warehouses that count for `W`.

| Term | Meaning |
|---|---|
| Age of a batch | The posting date of its **earliest submitted Purchase Receipt** (returns excluded), wherever it was received. A batch that was never on a Purchase Receipt falls back to its `manufacturing_date`, then to the day the Batch record was created. |
| Older | Strictly earlier **day**. Two batches with the same day never block each other. |
| Warehouses that count | Every warehouse under the **parent** of `W` whose name starts with `WH-`. A top-level warehouse counts alone. |
| Stock left | Book balance **minus quantities on draft documents** (draft Delivery Notes and outward rows of draft Stock Entries), per warehouse and never below zero. The open document counts by its rows in memory, not by what was last saved. |

Batch `creation` is deliberately not the age: a newer batch can be created, received and
submitted before an older one.

Only `WH-` warehouses take part. A pick from any other warehouse (the `POS-` shops, Goods In
Transit) is not checked, and stock held there never blocks.

With the warehouse tree as it stood on 19 November 2026:

| Pick warehouse | Older stock must be exhausted in |
|---|---|
| `WH-DXB1 - KA`, `WH-DXB3 - KA` | both (parent: Finished Goods) |
| `WH-WIP1 - KA`, `WH-WIP3 - KA` | both (parent: Work In Progress) |
| `WH-ECOM - KA` | itself (no parent) |
| `POS-DXB1 - KA`, `POS-DXB2 - KA`, `Goods In Transit - KA` | rule does not apply |

## Where it applies

| Sheet | Applies |
|---|---|
| Delivery Note item (POS upload and Sales Order scan-to-pick) | Yes |
| Stock Entry item — Material Issue, Material Transfer for Manufacture | Yes |
| Stock Entry item — Material Transfer, Material Receipt, the finished-good row of a Manufacture | No |
| Purchase Receipt, Packing Slip, Sales Order, Purchase Order | No |

Sheets opt in with `enforcesBatchAge` on `ItemSheetControllerBase`; the default is off.

## What the user sees

- **Refusal.** The batch field turns to an error ("Older stock must ship first.") and a
  bottom sheet opens (`OlderStockSheet`). It names the refused batch, lists up to three
  older batches oldest first (received date, quantity left, warehouse), and lists the racks
  the item is kept in. The only action is **Scan older batch**, which clears the batch field.
  A **View older stock** link under the field reopens the sheet.
- **Racks are item-level.** They come from the Stock Balance report with the rack inventory
  dimension, which cannot split a rack by batch. The sheet therefore says "This item is
  stored in", not which rack holds the older batch. Racks with a zero or negative balance are
  dropped; stock with no rack shows as "No rack recorded". If the rack lookup fails the
  refusal still stands and the sheet says rack information is not available.
- **Lookup failure.** If the check itself cannot be completed the batch is refused with
  "Could not check for older stock…" (fail closed). Scanning again retries.
- **Batch picker.** On sheets that enforce the rule the picker lists batches oldest first and
  shows each batch's date. Ordering is a convenience: if the age lookup fails the picker keeps
  its balance order and the scan-time check still decides.

## Edits after the fact

Reducing or removing an older-batch row frees that stock again. The edit is refused when it
would leave a **newer** batch of the same item on the document out of order
(`batchesPutOutOfOrder`). Rows that already broke the rule — added by a supervisor in Desk,
or saved before the rule existed — are left alone, and re-opening a row never refuses the
batch it was saved with.

The guard runs on: item-sheet save in edit mode (quantity reduced, batch or warehouse
changed), delete from the item sheet, and delete from the document's item list. It makes no
server call unless the document holds two batches of the item.

## When the warehouse is not known yet

On a Delivery Note the row's warehouse comes from the header, the Sales Order line, or the
scanned rack — and the batch is usually scanned before the rack. The check is skipped while
the pick warehouse is unknown and runs (`recheckBatchAge`) as soon as a rack scan resolves or
changes it. Stock Entry does the same when the item-level source warehouse resolves.

## Code map

| File | Role |
|---|---|
| `lib/app/shared/item_sheet/batch_age_rule.dart` | The pure rule: `findOlderBatches`, `batchesPutOutOfOrder`, `resolveBatchAge`, the `WH-` prefix. No I/O. |
| `lib/app/data/providers/batch_age_provider.dart` | `BatchAgeDataSource` and its server implementation; the response parsers are static and unit-tested. |
| `lib/app/shared/item_sheet/batch_age_checker.dart` | Orchestration: scope warehouse, stock, ages, drafts → verdict. |
| `lib/app/shared/item_sheet/item_sheet_controller_base.dart` | The gate inside `validateBatch` (covers scanned, typed and picked batches), `recheckBatchAge`, `showOlderStock`. |
| `lib/app/shared/item_sheet/widgets/older_stock_sheet.dart` | The refusal sheet and the "View older stock" link. |
| `delivery_note_form_controller.dart`, `stock_entry_form_controller.dart` | `batchAgeLines`, `batchOrderBreak` (the edit guard). |

## Server calls

All standard endpoints; nothing site-specific. Verified on Frappe 16.56 / ERPNext 16.55 on
19 November 2026. **Not verified on v15** — each list call has a second standard form the
code falls back to, but no v15 server was available to test either.

| Need | Call | Notes |
|---|---|---|
| Parent warehouse | `GET /api/resource/Warehouse` (`name`, `parent_warehouse`) | Cached for the app session. |
| Batch balances | Report **Batch-Wise Balance History**, `item_code` + `warehouse` = the parent | Accepts a group warehouse and returns one row per leaf. Refuses to run without an item or a warehouse. Rows carry no dates. |
| First receipt date | `GET /api/resource/Purchase Receipt` joined on `Purchase Receipt Item.batch_no in (…)`, `docstatus = 1`, `is_return = 0` | One call. Fallback: the item rows through `frappe.client.get_list` with `parent`, then the receipts. |
| Fallback dates | `GET /api/resource/Batch` (`manufacturing_date`, `creation`), explicit row limit | The list default of 20 would truncate. |
| Draft quantities | `Delivery Note` / `Stock Entry` joined on their item rows, `docstatus = 0` | Same two forms as above. |
| Racks | Report **Stock Balance** with `show_dimension_wise_stock` | Ignores `batch_no` on both versions — hence item-level. |

Things that look usable and are not:

- `Stock Ledger Entry.batch_no` is empty on this server (batches live in the bundle).
- `Serial and Batch Bundle` has `posting_datetime` on v16 where v15 has `posting_date`.

A check costs one report call when the item has a single batch in scope (the common case —
87% of item/warehouse pairs on the day measured), and four more calls in parallel otherwise.

## Permissions

A floor user needs read on Batch, Warehouse, Purchase Receipt, Delivery Note and Stock Entry,
and both reports. On 19 November 2026 every user who had created a Delivery Note in the
previous 60 days held Stock User, which covers all of them. This was worked out from the role
tables as a System Manager, **not tested as a floor user**. Because the check fails closed, a
user who cannot read one of these is refused every batch in a `WH-` warehouse.

## Live data, 19 November 2026

Read-only queries against production, kept here so the numbers can be re-run later.

- 5,619 batches; every one has a `manufacturing_date`; none has an expiry date.
- 3,226 batches were created by one import on 9 June 2025, so `creation` says nothing about
  their age.
- Only 1,338 of 3,658 in-stock batches were ever on a Purchase Receipt. The rest are opening
  stock from the import (2,138) or came in by Stock Entry / Stock Reconciliation (182) — the
  reason the fallback date exists.
- 117 batches were received on more than one date ("earliest" matters).
- Of 607 in-stock pairs where both batches have receipts, 17 have creation order
  contradicting receipt order.
- 162 in-stock batches carry a placeholder date in July 2004 (`BRQ` and `7CY`). They have no
  Purchase Receipt and therefore always count as oldest.
- Under the final rule, 11 of the 101 rows on open draft Delivery Notes and 28 of the 162
  outward batch rows on open draft Stock Entries would have been refused. The Stock Entry
  figure counts every outward row; the rule only covers two entry types, so the real number
  is lower.

## Not covered

- **Desk.** Nothing here stops an entry made in Desk; that is the supervisor's path by
  design, and it is open to anyone with Desk access until a server-side rule exists.
- **Stock reservations.** Older stock reserved for another order still blocks.
- **Stale drafts.** A draft that will never be submitted keeps its quantity off the balance.

## A later Server Script

If a role-based override is added on the server, it should apply the rule above so app and
server agree: same age (earliest submitted non-return Purchase Receipt, else
`manufacturing_date`, else creation day), same day-level comparison, same warehouses (`WH-`
leaves under the pick warehouse's parent), same netting of drafts. The app does not call
site scripts; it only needs to surface the script's error message when a save is rejected.
