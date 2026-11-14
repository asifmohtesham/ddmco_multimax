# To-Do — Redesign the Stock Balance report card

**DocType:** ToDo
**Priority:** Medium
**Reference Type:** Report
**Reference Name:** Stock Balance
**Assigned module:** `lib/app/modules/stock/reports/stock_balance/`

---

## Description

Replace the flat "attribute-chip dump" in the Stock Balance result tile with a
layout that ranks information by operational value, so a warehouse user reads
each row at a glance: **how much is on hand, where it is, how it moved, and how
much is free vs committed.**

The data is already loaded by `StockBalanceController.runReport()` — this is a
**presentation-only** change to the `_BalanceTile` widget (and its helpers) in
`stock_balance_screen.dart`. No API or controller logic changes are required
beyond surfacing three already-present fields (`reserved_stock`, `balance_value`,
`valuation_rate`/rack) explicitly instead of letting them fall through to chips.

## Why

The current tile gives equal visual weight to Rack, Balance Qty, Balance Value,
Valuation Rate, Reserved Stock, Company and Customer Code as identical pink
pills. There is no hierarchy, and the hero badge (top-right) shows
`balance_qty` while a separate **"Balance Qty: 12.0"** chip shows a different
number — the two disagree because the field leaking into the chip is the
dimension-wise per-rack column, not the skipped `balance_qty`. The redesign
consumes every standard field explicitly, which removes the duplicate-chip bug.

## Acceptance criteria

- [ ] Balance qty is the single hero figure, colour-coded by stock state
      (healthy / heavily-reserved / negative / out-of-stock).
- [ ] Opening → In → Out → Balance render as one ledger strip; In is green,
      Out is red.
- [ ] Warehouse **and** rack/location appear on a dedicated line (rack is
      currently buried in a chip).
- [ ] Free vs Reserved is shown as a proportion bar + labels when balance > 0.
- [ ] Valuation rate, balance value and customer code are demoted to a quiet
      footer; **Company is dropped** (it is always "Multimax").
- [ ] `_skipFields` is reconciled with the real report fieldnames so no standard
      column leaks into a chip (verify `balance_value` vs `balance_val`,
      `valuation_rate`, `reserved_stock`, and the dimension/rack column against a
      live response).
- [ ] Negative and zero/out-of-stock rows show their status note instead of the
      availability bar.
- [ ] **Variant attributes** (ERPNext "Show Variant Attributes") render as a
      compact key/value chip row per card (UPPERCASE micro-label + value), led by
      a tag glyph — one chip per Item Attribute (Colour, Buckle/Material, Width/
      Style…). Source from the variant's attribute values; show the row only when
      the item is a variant. Keep them visually quiet (subtle fill) so they don't
      compete with the hero/ledger.
- [ ] **Report total row** is pinned to the bottom of the screen (outside the
      scrolling list, ERPNext `add_total_row`): a "TOTAL · N items" label, total
      balance **Value**, and a 4-cell Opening / In / Out / Balance grid summing
      **all** report rows (not just the visible page). Balance cell tinted in
      primary; In green / Out red — mirrors the per-card ledger.
- [ ] Light + dark themes both pass; all colours come from `Theme.colorScheme`
      plus the defined status palette (no hard-coded surface colours).

## Design reference

`Stock Balance Report.html` in this bundle (open in a browser). See `README.md`
for the full spec and `CLAUDE_CODE_PROMPT.md` for an implementation prompt.
