# Delivery Note — Slow Submit Investigation Brief (for the ERPNext/backend owner)

**Audience:** whoever administers the ERPNext instance (server access, can run
`bench`, change Stock Settings, upgrade patch level).
**Author context:** raised from the Flutter app side (KA-ML Fulfillment). The app
cannot influence any of the suspected causes — they are all server-side.
**Goal:** determine *where* Delivery Note submit time actually goes, so we stop
guessing and fix the right thing.

---

## 1. Symptom

- Delivery Notes with **300+ item rows** are **excruciatingly slow to *submit***
  (docstatus 0 → 1). They **succeed** — there is **no timeout / no error**.
- *Saving* the draft is comparatively fine; the pain is specifically **submit**.

## 2. Verified context (don't re-investigate these)

- Backend is **ERPNext v15**.
- **Every delivered item is batch-tracked** (`has_batch_no = 1`) and **every DN
  row carries a `batch_no`**. This is 100% batch coverage, not occasional.
- The app's `custom_invoice_serial_number` field is an **external-system
  reference only**. It is **not** ERPNext serial tracking (`has_serial_no`) and
  does **not** participate in stock or valuation.
- The app submits **synchronously**: `PUT /api/resource/Delivery Note/<name>`
  with `{docstatus: 1}` (blocking HTTP request; the device waits on it).

## 3. Causes already ruled out (with reasoning)

| Hypothesis | Verdict | Why |
|---|---|---|
| Serial-number valuation (`get_incoming_value_for_serial_nos` / `SerialNoValuation`, erpnext#41452) | **Ruled out** | Items are not serial-tracked; the custom serial field is external-only. |
| "Implement Serial and Batch Bundle to speed it up" | **Moot** | On v15, batch rows already go through the Serial and Batch Bundle automatically (created server-side at submit). There is nothing to "turn on." |
| Splitting DNs into ≤100-row documents | **Rejected** | Splitting only avoids a *timeout*, which we don't have. Total work is unchanged or worse (3× doc overhead), and it forces a large app-side rework (one `po_no` → many DNs breaks every "find the DN for this po_no" assumption). |
| `Use Serial / Batch Fields` mode (Stock Settings) | **Likely already on; no proven submit speedup** | The app sends inline `batch_no` strings successfully, which implies this mode is active. It changes data-entry workflow, not submit-time valuation. |

## 4. Remaining hypotheses (what the profile must distinguish)

The submit cost for an all-batch, 300-row document is some mix of:

1. **Serial & Batch Bundle creation per row** — v15 builds a bundle + entries
   for every batch row at submit. Has known perf/correctness churn
   (erpnext#39162 DB bulk-insert, erpnext#50341 draft-bundle rollback).
2. **Per-batch valuation** — computing the cost of each outgoing batch.
3. **Future Stock Ledger reposting (`update_entries_after`)** — if a DN's
   `posting_date` is *behind* later stock transactions for the same
   item+warehouse, ERPNext recomputes **all subsequent** ledger entries. This is
   often the single biggest, most surprising cost on busy items. (The app
   defaults `posting_date` to "today", so check whether real submits are ever
   backdated, and how heavily transacted these item+warehouses are.)
4. **Plain volume** — N× Stock Ledger Entry + GL Entry + Bin updates. Linear,
   inherent, not reducible by any feature.

## 5. The measurement — do this on ONE representative slow submit

**Option A — Frappe Recorder (easiest, no code):**
1. In the Desk, search the awesomebar for **"Recorder"** (or go to `/app/recorder`).
2. Click **Start**.
3. Submit one representative large (300-row) Delivery Note.
4. Click **Stop**.
5. Open the captured request and read:
   - **Total time** vs **total time in SQL** (is it CPU-bound or query-bound?).
   - **Number of SQL queries** (does it scale ~linearly or worse with rows? N+1?).
   - **Slowest queries** and the **call stack** — note which functions dominate.

**Option B — cProfile via bench console (if you want a function-level flamegraph):**
```bash
bench --site <site> console
```
```python
import cProfile, pstats, frappe
doc = frappe.get_doc("Delivery Note", "<DRAFT-DN-NAME>")
cProfile.run("doc.submit()", "/tmp/dn_submit.prof")
pstats.Stats("/tmp/dn_submit.prof").sort_stats("cumulative").print_stats(30)
# run on a test/clone site — submit is irreversible
```

**Also capture, while you're in there:**
- Stock Settings → **Valuation Method** (Moving Average vs FIFO/LIFO; batch-wise
  valuation under FIFO does more per-batch work).
- Stock Settings → **"Use Serial / Batch Fields"** state.
- Whether **future-SLE reposting** is enqueued or runs inline on submit.
- Current **ERPNext patch level** (`bench version`).

## 6. Decision tree (what each result means)

- **Time dominated by `update_entries_after` / future-SLE repost**
  → busy item+warehouses and/or backdated posting. Fixes: ensure DNs post at
  current date; review reposting settings; possibly schedule reposting. *This is
  the best-case outcome — a real, targetable cause.*
- **Time dominated by `SerialBatchBundle` / `SerialBatchCreation` / batch
  valuation** → largely inherent to v15 batch handling. Action: confirm you're
  on the **latest v15.x point release** (bundle perf fixes land continuously);
  beyond that, limited tuning room.
- **Time spread evenly across plain `Stock Ledger Entry` / `GL Entry` inserts**
  → pure row volume. No server feature shortens it. **Only the app-side
  background-submit mitigation (§7) helps the experience.**

## 7. App-side mitigation (independent of the above — recommended regardless)

Replace the blocking submit with a **background submit** so the device is not
held on a long HTTP request:

- Add a whitelisted server method, e.g.
  `erpnext_custom.api.enqueue_submit(doctype, name)` →
  `frappe.get_doc(doctype, name).queue_action("submit")`
  (this is exactly what Stock Reconciliation does for >100 rows).
- App calls it via the existing `callMethodPost`, then relies on the **existing
  realtime-sync** (it already listens for the doc's `modified`/`docstatus`) to
  flip the form to *Submitted* when the job finishes.
- This does **not** make the work faster — it stops the phone blocking on it.
  It's the only lever fully within the app's control and directly addresses
  "excruciatingly slow to succeed".

## 8. Bottom line

There is **no "enable a feature → fast submit" switch**. The honest path is:
1. **Profile** one slow submit (§5) to attribute the time.
2. If it's repost/backdating → fix that (real win).
3. Ensure **latest v15.x** patch level either way.
4. Ship **background-submit** in the app for the UX, regardless of §6 outcome.

## References

- erpnext#41452 — DN submit timeout via deprecated serial valuation (the path we *ruled out*): https://github.com/frappe/erpnext/issues/41452
- erpnext#39162 — Serial & Batch Bundle DB bulk-insert issue: https://github.com/frappe/erpnext/issues/39162
- erpnext#50341 — bundle stuck in Draft / rollback: https://github.com/frappe/erpnext/issues/50341
- erpnext PR#41843 — patch enabling old serial/batch fields ("Use Serial / Batch Fields"): https://github.com/frappe/erpnext/pull/41843
- Serial and Batch Bundle docs: https://docs.frappe.io/erpnext/serial-and-batch-bundle
- Frappe background jobs / `queue_action`: https://docs.frappe.io/framework/user/en/api/background_jobs
