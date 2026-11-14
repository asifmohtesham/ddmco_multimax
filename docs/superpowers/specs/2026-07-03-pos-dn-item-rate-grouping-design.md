# POS & DN Item Rate — Group-by on Fields

**Date:** 2026-07-03
**Branch:** `feature/pos-dn-item-rate-grouping` (worktree, off `release/play-store`)
**Screen:** Selling → Reports → POS & DN Item Rate
(`lib/app/modules/selling/reports/pos_dn_item_rate/`)

## Goal

Let the user group the report's flat row list under collapsible headers by a
chosen field, with **two-level nested** grouping (primary + optional secondary).

## Principles / constraints

- **Client-side, presentational only.** No API/backend changes. Grouping runs
  over rows already fetched. Server status stays authoritative — grouping never
  re-derives status or any other value.
- **Composes with existing filters.** Grouping applies to `filteredRows`
  (i.e. after the status chip + text search), not the raw `reportRows`.
- **Existing conventions preserved:** scrollbar (shared `ScrollController`),
  bottom safe-area (`MediaQuery.padding.bottom`), end-of-list totals footer
  (qty sums only, never rate), result-count pill, refresh, tile taps.

## Grouping model — two-level nested

- **Primary** field: selecting one turns grouping on.
- **Secondary** field: optional; its menu excludes the current Primary (a field
  cannot be grouped by itself).
- Primary = **None** → today's flat list, unchanged (default on entry).

## Groupable fields (5)

| Label          | Row field        | Group-key formatting              |
|----------------|------------------|-----------------------------------|
| Item Group     | `item_group`     | text; blank → `—`                 |
| Customer       | `customer`       | text; blank → `—`                 |
| Customer Group | `customer_group` | text; blank → `—`                 |
| POS Item Name  | `upload_item`    | text; blank → `—`                 |
| Rate           | `upload_rate`    | formatted number, exact-value key |

Modeled as a `PosDnGroupField` enum, each case carrying `key`, `label`, and a
`valueOf(Map row) → String` extractor (and a `numeric` flag for Rate, used by
the sort). Adding/removing a field later is a one-line change.

## Group headers (value + count + qty totals)

Each header shows:
- the **group value** (formatted key),
- the **row count** in the group (recursive for primary when a secondary is set),
- **summed POS Qty / DN Qty** via the existing `PosDnItemRateController.sumTotals`
  (qty only — never rate).

Primary headers are bold; secondary headers are indented and lighter. Leaf rows
render with the existing `PosDnItemRateTile`, unchanged.

## Pure, testable core — `pos_dn_grouping.dart` (new)

No GetX, no network. Contains:

- `enum PosDnGroupField { itemGroup, customer, customerGroup, posItemName, rate }`
  with `key`, `label`, `numeric`, and `valueOf(row)`.
- `GroupNode { String key; List<Map<String,dynamic>> rows; List<GroupNode> children;
  int count; num posQty; num dnQty; }`
- `groupRows(rows, primary, {secondary})` → ordered `List<GroupNode>`.
  - Groups keyed by the formatted value; blank/missing → `—`.
  - When `secondary` set, each primary node's `children` are the sub-groups and
    its `rows` is empty; `count`/`posQty`/`dnQty` aggregate recursively.
  - **Sort:** ascending by key; Rate sorted **numerically**; `—` (blank) always
    last. Same comparator at both levels.
- `flattenForDisplay(nodes, collapsedKeys)` → `List<DisplayItem>` where
  `DisplayItem` is a tagged union (`primaryHeader` / `secondaryHeader` / `row`),
  honoring collapse state. A single `SliverList` renders this flattened list
  (keeps scrolling/scrollbar fast; no nested scroll views).

Collapse key scheme (stable, unique):
- primary: `"P␟<primaryKey>"`
- secondary: `"S␟<primaryKey>␟<secondaryKey>"`

(`␟` = US separator, avoids collisions with real values.)

## Controller changes — `pos_dn_item_rate_controller.dart`

- `final primaryGroup = Rxn<PosDnGroupField>();`
- `final secondaryGroup = Rxn<PosDnGroupField>();`
- `final collapsedGroups = <String>{}.obs;`
- Setters: `setPrimaryGroup`, `setSecondaryGroup` — setting/clearing primary to
  None clears secondary and `collapsedGroups`; changing any field clears
  `collapsedGroups` (keys change → everything expands). Secondary is forced back
  to None if it equals the new primary.
- `toggleGroupCollapsed(String key)`, `expandAll()`, `collapseAll(List<String> keys)`.
- A derived getter returning the display list for the current grouping (or a
  flat marker when Primary = None) so the screen stays thin.
- `clearFilters()` also resets grouping state.

## UI — `pos_dn_item_rate_screen.dart`

- New **"Group by:" bar** sliver directly under the status chips:
  - a Primary chip + optional Secondary chip; tapping either opens a menu of
    **None + the 5 fields** (Secondary menu hides the current Primary). Chips are
    removable (✕ clears that level).
  - an **expand/collapse-all** icon button, shown only when grouping is active.
- Body:
  - Primary = None → existing flat `SliverList` of tiles (unchanged branch).
  - Grouping active → one `SliverList` over `flattenForDisplay(...)`, rendering
    `PosDnGroupHeader` (primary/secondary) and `PosDnItemRateTile` (row).
- Result-count pill, end-of-list totals footer, scrollbar, safe-area: unchanged.

## New widget — `widgets/pos_dn_group_header.dart`

`PosDnGroupHeader` — a tappable (toggle-collapse) header with a chevron
(`AnimatedExpandIcon`), the group value, a count badge, and POS/DN qty totals.
A `level` param (`primary` / `secondary`) drives weight + indent. Theme-aware
colours only (no hardcoded surfaces/inks), per the contrast conventions.

## Tests — `test/unit/pos_dn_grouping_test.dart` (new)

- Single-level grouping: correct buckets, counts, POS/DN totals.
- Two-level nesting: child buckets + recursive primary aggregates.
- Rate grouping: numeric sort (2, 10, 100 not "10, 100, 2"); exact-value keys.
- Blank/missing values bucket into `—`, sorted last.
- `flattenForDisplay`: collapse hides children; expand shows them; correct item
  ordering and tags.
- `valueOf` for each field; Secondary-excludes-Primary invariant (in controller
  or a light controller test).

## Decisions (confirmed)

1. **Two-level nested** grouping (primary + optional secondary).
2. Fields: Item Group, Customer, Customer Group, POS Item Name, Rate.
3. Headers show **value + count + qty totals**.
4. Selector placement: **on-screen "Group by" bar** under the status chips.
5. Default group state: **expanded**, with an expand/collapse-all toggle.

## YAGNI — explicitly out of scope

3+ grouping levels; per-group search; group reordering; cross-session
persistence of the grouping choice; server-side grouping.
