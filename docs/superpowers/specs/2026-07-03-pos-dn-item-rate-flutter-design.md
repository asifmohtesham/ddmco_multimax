# POS & DN Item Rate — Flutter Report Screen (Design)

**Date:** 2026-07-03 · **Status:** Approved design, pending implementation plan

Bring the backend Desk Script Report **"POS and Delivery Note Item Rate"** into the
Flutter app as a full mobile report screen: all four statuses, all filters, summary
counts. Read-only — no write-back; customer codes are still transcribed manually
into Item → Customer Items on Desk.

Canonical backend source: `docs/pos_delivery_note_item_rate_report.md` (report
script + client script, join model, field gotchas).

## Decisions made

| Question | Decision |
|---|---|
| Purpose | Full mirror of the Desk report on mobile |
| Entry point | Drawer only — new **Selling → Reports** subheading |
| Data source | **Approach A:** call the server Script Report by name via `frappe.desk.query_report.run` |

### Why Approach A (server report, not client-side join)

- Single source of truth: SQL join + status classification (including the
  `Item Customer Detail` triple check) live only in the server script. No drift.
- Sidesteps the known **Item Customer Detail 403** for non-System-Manager users —
  the report runs server-side under its own SQL, so "Already mapped" vs "New"
  is correct for every user with report access.
- One HTTP round trip; matches how every other report screen in the app works
  (`bom_stock_customer_code` is the closest template).
- Trade-off accepted: hard dependency on the Desk artifact being deployed (step 0).

## Step 0 — backend prerequisite (blocks everything)

> **Status: DONE (verified live 2026-07-03).** Report deployed and running on
> `erp.multimax.cloud` — banner showed 797 new / 238 no-delivery / 27,872 no-code
> lines unfiltered (~29k rows), confirming the 30-day default date filter is
> mandatory for the mobile fetch.

Deploy the staged Desk artifacts on `erp.multimax.cloud`:

1. Report `POS and Delivery Note Item Rate` (Script Report, Ref DocType POS Upload,
   Module Stock, Is Standard No) — script per §6 of the canonical doc.
2. Client Script (Script Type Report) — per §7 of the canonical doc.
3. Grant the report's Roles to the roles app users hold.

Until this exists, the Flutter screen has nothing to call.

## Module layout

```
lib/app/modules/selling/reports/pos_dn_item_rate/
  pos_dn_item_rate_binding.dart
  pos_dn_item_rate_screen.dart
  pos_dn_item_rate_controller.dart
  widgets/pos_dn_item_rate_tile.dart
```

New route pair in `app_routes.dart` / `app_pages.dart`:
`/reports/pos-dn-item-rate`, `Transition.rightToLeftWithFade`, binding registers the
controller and reuses the global `ApiProvider`.

## Data flow

1. Controller builds server filters → `ApiProvider.runPosDnItemRateReport(filters)` —
   thin named wrapper over the existing `getReport` / `query_report.run` pattern with
   `report_name: "POS and Delivery Note Item Rate"`.
2. Parse `message.columns` + `message.result`, tolerating both list-of-maps and
   positional (list-of-lists) rows and `` `tabX`.field `` fieldname prefixes — same
   approach as `parseStockBalanceResponse`. Parsing is **static/pure functions** on
   the controller (unit-testable without GetX).
3. Rows land in `RxList<Map<String, dynamic>> reportRows`; a derived getter applies
   client-side quick filters (status chips, text search) — mirroring
   `stock_balance_controller.filterAndSortRows`. Row order is the server's
   (`POS Upload, idx, item_code`); **no sort UI in v1**.
4. Status (`New` / `Already mapped` / `No delivery line` / `No code`) and summary
   counts come **from server rows as-is**; the app never re-derives status.

### Filter split

- **Server-side** (via shared `ReportFilterSheet`; sent as report filters):
  POS Upload (multi), From Date / To Date, Customer (multi), Customer Group (multi),
  Item Group (multi), Show already-mapped (check), Only coded (check).
  Multi-selects use `ReportFilterType.doctypeLink`; dates `datePicker`.
- **Client-side** (instant, on fetched rows): status chips
  (All / New / No delivery line / No code — plus Already mapped only when present
  in the data), free-text search over ref_code / item names / customer.

**Default filter:** From Date preset to *last 30 days* on first open, so the initial
fetch never runs the full unfiltered scan (the report's `MAX_JOIN_SIZE` /
performance caveat). User may clear it.

## UI

- **Drawer:** new `Reports` subheading under **Selling** (standard `_GuardedSection`
  + `DocTypeGuard(permType: 'report')`), item "POS & DN Item Rate".
- **Header:** `AppShellScaffold` + `DocTypeListHeader`; singular title, search field
  (client-side text filter), filter icon → `ReportFilterSheet`, refresh re-runs the
  report.
- **Summary strip** (mobile equivalent of the Desk banner): compact row of
  `StatusPill`-style count chips — *N new / N no delivery / N no code* — derived
  from fetched rows; tapping a chip applies that status filter.
- **Status chip row:** `SelectableFilterChip` group as listed above.
- **Body:** `CustomScrollView` + `SliverList` of tiles; `DocCardSkeleton` while
  loading; glyph `ListEmptyState` when empty; `ResultCountPill` + `ListEndFooter`.

### Row card (`PosDnItemRateTile`) — one per (upload line, item_code)

- **Leading:** `StatusPill`, app colour ramp (never the Desk hex codes):
  New = green, No delivery line = orange, No code = neutral/muted,
  Already mapped = subtle/grey. x700 light / x300 dark for text; tint fill
  `x500 @ alpha 0.13` per the contrast conventions.
- **Hero line:** `ref_code` prominent + `item_code` beside it.
- **Detail rows:** DN item name vs POS item name (both shown — the naming gap is
  the point), Customer, Item Group.
- **Numbers row:** POS Qty · POS Rate · DN Qty.
- **Footer links:** DN # → Delivery Note form; POS # + line idx → POS Upload form.

## Permissions

- Add `('POS Upload', permType: 'report')` to `kSellingPermissions`
  (`permission_entries.dart`) so access is prefetched at login (no drawer flicker).
- Screen fail-closes: 403 from `query_report.run` renders a "no access / report
  unavailable" state, never a crash.

## Error handling

- **Report missing** (`DoesNotExistError`): distinct "Report not deployed on this
  instance" message — reachable because the app can point at other ERPNext
  instances (step 0 not done there).
- **Fetch lifecycle:** `RxBool isLoading` set/cleared in `finally`, re-entrancy
  guard, per the async-feedback convention; on failure show a snackbar and retain
  previously fetched rows.

## Model note

`PosUploadItem` has no `ref_code` field today and this feature does **not** add
one — all data arrives in the report rows. No model changes.

## Testing

- **Unit:** response parsing (both row shapes, fieldname prefixes), filter-map
  building (multi-select → JSON arrays, checks → 0/1, 30-day default),
  client-side status/text filtering, summary-count derivation.
- **Widget:** tile renders all four statuses with correct `StatusPill` colours in
  **light and dark**; loading/empty/error states; chip filtering updates the list.
- **Fixture:** canned `query_report.run` response containing all four statuses.

## Sequencing

1. **Step 0** — deploy Desk report + Client Script, grant roles (scripts already
   staged; see canonical doc §5–§7).
2. Flutter module + route + drawer entry + permission registry entry.
3. Tests → `flutter analyze` → full suite → on-device smoke against the live report.
