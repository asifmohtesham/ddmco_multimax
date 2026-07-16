# Dashboard "Upcoming & actionable" section — design

**Date:** 2026-07-16
**Status:** Approved design, pending spec review
**Module:** `lib/app/modules/home/` (dashboard)

## 1. Goal

Rework the dashboard's **Upcoming tasks** section so that all *actionable*
documents across **Purchase Order, Purchase Receipt, Stock Entry, Delivery
Note, and ToDo** are visible **at a glance on load**.

Today the section (`_buildUpcomingTasks`, `home_screen.dart:301`) shows only
open ToDos as individual cards. It is broadened into **"Upcoming &
actionable"**: a compact per-DocType **count strip** on top (all five
categories always visible), followed by the existing individual **ToDo task
cards**.

> **Rename note:** header text changes from "Upcoming tasks" to "Upcoming &
> actionable". The ToDo sub-area keeps its "View all tasks" link. The rename
> is cosmetic and trivially reversible if rejected at review.

## 2. Definition of "actionable"

Confirmed during brainstorming (Drafts-only, uniform):

| Chip | DocType | Count filter | Rationale |
|---|---|---|---|
| PO | Purchase Order   | `{docstatus: 0}` | Draft POs (unfinished/unsubmitted) |
| PR | Purchase Receipt | `{docstatus: 0}` | Draft PRs |
| SE | Stock Entry      | `{docstatus: 0}` | Draft SEs — SE has **no** `status` field; status is derived from `docstatus` (`stock_entry_model.dart:102`) |
| DN | Delivery Note    | `{docstatus: 0}` | Draft DNs |
| Tasks | ToDo           | derived from existing OR-filtered fetch | user's open ToDos |

`docstatus: 0` is the reliable machine field and is equivalent to
`status: 'Draft'` for PO/PR/DN (their models default `status` to `Draft` when
`docstatus == 0`). It is the only choice for SE.

*Explicitly out of scope:* submitted-but-pending states (PO "To Receive",
PR "To Bill"). The design keeps a single uniform "Draft" definition per the
brainstorming decision; broadening later is a one-line filter change.

## 3. Scope toggle — Mine / Everyone

The section header carries a small **Mine ⇄ Everyone** segmented toggle,
styled after the existing `DashboardColumnsToggle` (`home_screen.dart:90`).

- **Mine** (default): the four **document** chips add
  `owner: <selected dashboard user email>` to their count filter — scoped to
  the "Viewing …" user in the dashboard's user switcher
  (`controller.selectedFilterUser`). Consistent with the performance
  timeline, which already scopes by `owner` (`home_controller.dart:395`).
- **Everyone**: the `owner` filter is dropped — company-wide draft counts.
- **The Tasks chip stays personal in both states.** It mirrors the task cards
  directly below it, so it always reflects the selected user's open ToDos.
  Only the four document chips flip.
- The toggle choice is **persisted per session** via `StorageService`
  (mirroring `getDashboardColumns`/`saveDashboardColumns`). Default = Mine.

## 4. Data flow

Counts use `ApiProvider.getDocumentCount(doctype, {filters})`
(`api_provider.dart:1948`) — a single server-side `frappe.client.get_count`
returning `{"message": <int>}`, already parsed by `_extractCount`
(`home_controller.dart:655`).

- **On load:** fetch counts for the **current** scope only — 4 parallel
  `getDocumentCount` calls, added to the existing `Future.wait` in
  `fetchDashboardData` (`home_controller.dart:240`).
- **On first toggle** to the other scope: **lazy-fetch** its 4 counts, then
  **cache** both scopes. Cache keyed by `(scope, userEmail)`. Company-wide
  (Everyone) counts are user-independent; Mine counts refresh on user-switch
  (`onUserFilterChanged`) and pull-to-refresh.
- **Access gating:** only fire a count query for a DocType the user can read,
  using the same access source `DocTypeGuard` consults (permissions
  prefetched at login). Each chip is *also* wrapped in `DocTypeGuard` as
  defence-in-depth, so an inaccessible DocType's chip simply doesn't render.

### Tasks (ToDo) count

`getDocumentCount` takes an **AND-only** filter map — it cannot express the
ToDo query's `allocated_to` **OR** `owner` condition
(`home_controller.dart:271`). So the Tasks count is **derived from the
existing `fetchUpcomingTodos` result**, not a count call:

- Raise the existing fetch limit (currently `limit: 20`) to a comfortable
  ceiling (e.g. 50) and set `openTodoCount = fetchedList.length`.
- Display `"50+"` if the fetch hits the ceiling (rare on this dashboard).
- Task **cards** still display the first 5 via `selectUpcomingTodos`
  (`dashboard_todo_card.dart:12`) — unchanged.

## 5. Chip tap → pre-filtered list

Each **document** chip deep-links to its list screen, pre-filtered to Draft
(+ owner when scope = Mine), reusing the controller's existing `applyFilters`
(confirmed on `DeliveryNoteController.applyFilters`,
`delivery_note_controller.dart:83` — sets `activeFilters` and refetches with
pagination reset).

- **New uniform hook** in each list controller's `onReady`, mirroring the
  existing `openCreate` argument hook (`delivery_note_controller.dart:74`):

  ```dart
  if (Get.arguments is Map && Get.arguments['filters'] is Map) {
    applyFilters(Map<String, dynamic>.from(Get.arguments['filters']));
  }
  ```

- **Filter passed per chip:**
  - PO / PR / DN → `{status: 'Draft', if(mine) owner: email}` — renders a
    removable "Status: Draft" chip on the list (the list filter-chip UIs
    recognise `status`).
  - SE → `{docstatus: 0, if(mine) owner: email}` — SE has no `status` field.
- **Tasks chip** taps to the existing ToDo list via `goToToDo`
  (`home_controller.dart:698`) — unchanged, no arg filter.

**Verification needed in the plan:** confirm `PurchaseOrderController`,
`PurchaseReceiptController`, and `StockEntryController` each expose an
`applyFilters(Map)` equivalent (their filter bottom sheets write
`activeFilters`, so an equivalent should exist); add one if missing, matching
the DN shape (`activeFilters.value = filters; fetch(clear: true);`).

**Minor open point:** the SE list won't render a visible "Draft" filter-chip
for a `docstatus` filter (its chip UI keys on `status`, which SE lacks). The
filter still *applies* correctly; only the removable chip is absent. Accept
as-is, or add a small `docstatus: 0 → "Draft"` label to the SE chip renderer.

## 6. Zero-state & visibility

- **Show a chip for every accessible DocType, even at 0.** A zero count
  renders **muted and non-interactive**. This keeps the strip stable (no
  reflow as counts change) and every category "visible at a glance" even when
  empty — the core intent of the request. (Deliberately unlike "Needs
  attention", `home_screen.dart:274`, which hides empty rows.)
- The **section renders** whenever the user can access ≥1 of the five
  DocTypes. Task **cards** render only when open ToDos exist (unchanged).
- `showTasksFirst` persona rule (`home_controller.dart:161`) and
  `DashboardSectionOrder` (`home_screen.dart:1631`) are **unchanged** — the
  broadened section keeps its persona-driven position. Note the section may
  now be non-empty even with zero ToDos (the strip is present); this is fine
  because `DashboardSectionOrder` renders whatever the tasks widget returns.

## 7. Components (controller-free & testable)

Following the codebase convention that dashboard widgets are stateless and
controller-free (`DashboardSectionOrder`, `DashboardTodoCard`,
`AttentionRow`) so widget tests need no DI graph:

- **`ActionableChipData`** — plain immutable model:
  `{doctype, label, icon, count, listRoute, tapFilters, muted}`.
- **`ActionableCountChip`** — stateless pill: leading icon + label + trailing
  count badge. `muted == true` (zero) → dimmed, `onTap` null. Theme tokens
  only per contrast rules: surface `scheme.fg`, `border` `scheme.border`,
  count/label inks `scheme.text`/`scheme.textMuted`, status accents from the
  `AppColors` ramp (never hardcoded greys/whites).
- **`DashboardActionableStrip`** — stateless: header row (title + Mine/Everyone
  toggle) + a `Wrap` of `ActionableCountChip`s + a loading shimmer while
  counts resolve. Inputs: `List<ActionableChipData> chips`, `scope`,
  `onToggleScope`, `isLoading`. No `HomeController` dependency.
- **Scope toggle** — reuse/adapt the `DashboardColumnsToggle` segmented-control
  idiom (a two-segment "Mine | Everyone").

### `HomeController` additions

- `enum ActionableScope { mine, everyone }` + persisted
  `Rx<ActionableScope> actionableScope` (seed from `StorageService`).
- `actionableCounts` (`RxMap<String,int>` for the current scope) + a
  `Map<ActionableScope, Map<String,int>>` cache; `openTodoCount` (`RxInt`).
- `Future<void> fetchActionableCounts({ActionableScope? scope})` — parallel
  `getDocumentCount` for accessible document DocTypes; writes cache + current
  `actionableCounts`.
- `void toggleActionableScope()` — flip, persist, lazily ensure the new
  scope's counts (re-entrancy-guarded; light shimmer while fetching).
- Pure helper `Map<String,dynamic> actionableFiltersFor(String doctype,
  ActionableScope scope, String? email)` — the single source of truth for
  both count filters and tap filters (unit-testable).
- Chip-tap navigators → `Get.toNamed(listRoute, arguments: {'filters': ...})`.

### `StorageService` additions

- `ActionableScope getDashboardActionableScope()` /
  `void saveDashboardActionableScope(ActionableScope)` — mirroring the
  existing `getDashboardColumns`/`saveDashboardColumns` pair.

### List controllers (PO, PR, SE, DN)

- Add the `Get.arguments['filters']` hook in `onReady` (§5).
- Ensure an `applyFilters(Map)` method exists (present on DN; verify/add on
  the other three).

## 8. Async feedback

Per the CLAUDE.md async-feedback convention: the strip shows a **shimmer/
skeleton** while counts resolve (like `PulseSkeleton`, `home_screen.dart:108`).
`toggleActionableScope` guards re-entrancy and clears its busy flag in a
`finally`. Counts are cheap and cached, so post-first-flip toggles are
instant.

## 9. Testing

- **Unit:** `actionableFiltersFor` (scope → filter map; SE `docstatus` vs
  PO/PR/DN `status`; owner present only under Mine). ToDo-count derivation
  (ceiling → `"N+"`).
- **Widget** (`DashboardActionableStrip`, no DI): renders one chip per
  supplied `ActionableChipData`; toggle fires `onToggleScope`; a muted (zero)
  chip is non-tappable; `isLoading` shows the shimmer; **dark-mode contrast**
  holds (theme tokens only).
- **Regression:** existing `selectUpcomingTodos` / `dashboard_todo_card`
  tests stay green; `theme_contrast_test` extended to the new chip if needed.

## 10. Files touched (anticipated)

- `lib/app/modules/home/home_controller.dart` — scope enum/state, count
  fetch + cache, toggle, `actionableFiltersFor`, chip-tap navigators, ToDo
  count.
- `lib/app/modules/home/home_screen.dart` — replace `_buildUpcomingTasks`
  header/body with the strip + existing cards; rename section.
- `lib/app/modules/home/widgets/dashboard_actionable_strip.dart` — **new**
  (`ActionableChipData`, `ActionableCountChip`, `DashboardActionableStrip`).
- `lib/app/data/services/storage_service.dart` — scope persistence.
- `lib/app/modules/{purchase_order,purchase_receipt,stock_entry,delivery_note}/*_controller.dart`
  — `onReady` filter hook (+ `applyFilters` where missing).
- `test/unit/…`, `test/widget/…` — new unit + widget tests.

## 11. Out of scope

- Submitted/pending actionable states (PO To Receive, PR To Bill).
- Changing the `showTasksFirst` persona rule.
- Any change to the list screens beyond the `onReady` filter hook (and the
  optional SE "Draft" chip label).
- Company-wide ToDo counting.
