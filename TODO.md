# TODO

Things worth solving, found while smoke-testing the Stock Balance filter parity
on 2026-10-17 against the Frappe/ERPNext **v16** staging server
(`erp-v16.multimax.cloud`). Production still runs **v15**; the v16 instance is
scheduled to replace production **before the end of 2026**, so the v16 items
below are a deadline, not a nice-to-have.

## Frappe v16 readiness (due before end of 2026)

- [ ] **Drawer workspaces 417 on v16.** `AppNavDrawer` calls
      `frappe.desk.desktop.get_workspace_sidebar_items`, which no longer exists
      in v16 (`AttributeError`, HTTP 417); the drawer silently falls back to the
      static catalog. Find the v16 replacement, keep the v15 call behind a
      version check (or feature-detect on 417), and cover both in a test.
      Play 2.30.1 already behaves on v16 — check how it does it.
- [ ] **Transient 403 on every `/api/resource/<DocType>` list in the first
      session after login (v16).** Warehouse ×3 and Item ×2 all 403'd for ~2 min
      after a fresh login; a force-stop/relaunch fixed it and it did not recur.
      Root-cause (cookie/session timing? `sid` vs CSRF? v16 session warm-up?).
      Until then the pickers look empty with no explanation.
- [ ] **Stock Balance with two warehouses returned a third (WH-ECOM - KA)** on
      v16 when `warehouse` was sent as a list of two. Reproduce on the v16 desk
      with the same filter; if the desk does it too, it is server-side
      (`apply_warehouse_filter` list handling), otherwise fix the payload.
- [ ] **Audit every `/api/method/frappe.*` and `/api/resource` call against
      v16** (whitelist renames, removed endpoints, stricter `fields`/`order_by`
      validation). Build the list from `ApiProvider` and run each once against
      staging. Add a smoke profile that points a side-by-side build at v16.
- [ ] **Make the base URL switch cheap for testing** — the smoke build had to be
      logged in by hand against v16; a Session Defaults "server" preset or a
      build flavour pointing at staging would let CI/side-by-side builds target
      v16 without touching the Play app.

## Pre-existing defects seen during the smoke

- [ ] **`ApiProvider.getList` swallows errors** (catches, prints, returns `[]`).
      Every picker built on it (`_DoctypeLinkSheet`, `LinkSearchSheet`,
      `WarehousePickerSheet`) therefore shows "No records found" on a 403/417
      and its error/Retry state is unreachable. Rethrow (or return a result
      type) and let the sheets show the error.
- [ ] **Stock Balance: a zero-row result renders the initial state** ("Set
      filters and run the report"), indistinguishable from never having run.
      Track "has run" and show a "No rows for these filters" state instead.
- [ ] **414 URI Too Long on the Item customer-code enrichment** when the report
      returns ~3000 items (`name in [...]` filter in the query string). Chunk
      the lookup or switch that call to POST.
- [ ] **Removing a header filter chip clears the filter but does not re-run**;
      the list keeps the previous rows and the footer still says
      "3 warehouses". Either auto re-run on chip removal or mark the results
      stale.
- [ ] **Alt-UOM chips print raw doubles** (`Balance Qty (Nos) 0.0`,
      `In Qty (Nos) 60.0`); format like the main quantities. Also decide whether
      `Reserved Stock (Nos)` belongs in that chip row.
- [ ] **`Include Zero Stock` FilterChip checkmark overlaps the dark avatar
      circle** (Flutter default `showCheckmark` + avatar). Cosmetic.
- [ ] **Item list filter sheet exposes no `Disabled` field**, so a disabled item
      cannot be found from the app (the only way to prove the new picker filter
      was a disabled UOM). Add `disabled` to the Item filter field list.

## Branch / tooling

- [ ] **`claude/stock-balance-parity-e1394d` is based on 2.25.1+79** while the
      Play app is 2.30.1. Rebase onto the current release line before any
      release; re-run the 78 targeted tests after.
- [ ] **`git fetch origin` fails from `.claude/worktrees/*`** ("correct access
      rights"); side sessions cannot see the remote. Fix the credential/remote
      setup for worktrees so they can diff against `origin/release/play-store`.
