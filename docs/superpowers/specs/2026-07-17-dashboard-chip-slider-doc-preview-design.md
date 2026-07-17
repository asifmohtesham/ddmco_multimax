# Dashboard chip slider + document preview — design

**Date:** 2026-07-17
**Status:** Approved design, pending spec review
**Builds on:** `docs/superpowers/specs/2026-07-16-dashboard-actionable-docs-design.md` (shipped in 2.11.0+50)
**Module:** `lib/app/modules/home/` (+ `packing_slip`, `purchase_order` provider)

## 1. Goal

Rework the shipped "Upcoming & actionable" strip into a **horizontally-scrolling
chip slider that selects a DocType**, with a **3-document preview** and a
**View All** button beneath it.

Three requested changes:
1. `Tasks, PO, PR, SE, DN, PS` become a **chip slider** (adds **Packing Slip**;
   no more wrapping to a second row — see the shipped screenshot where `Tasks`
   spilled onto row 2).
2. Chips use the **full DocType name** (`Purchase Order`, not `PO`). The ToDo
   chip keeps the friendlier label **`Tasks`**.
3. Selecting a chip shows **three documents** of that DocType, with a
   **View All** button opening that **DocType List View**.

## 2. The slider

- One horizontal, scrollable row (`SingleChildScrollView(scrollDirection: Axis.horizontal)`)
  — never wraps. Replaces the current `Wrap`.
- Chip order (as requested): **Tasks · Purchase Order · Purchase Receipt ·
  Stock Entry · Delivery Note · Packing Slip**.
- Each chip keeps its **count badge** (`Purchase Order 34`).
- **States:**
  - *Selected* — filled with `colorScheme.primary` tint + primary ink/border.
  - *Unselected* — today's outlined pill (`scheme.fg` + `scheme.border`).
  - *Zero count* — **dim and inert** (not selectable; there is nothing to
    preview). Still rendered, so the at-a-glance picture stays complete.
- The **Mine ⇄ Everyone** toggle stays in the section header and scopes the five
  document chips (counts **and** their previews). **Tasks stays personal** in
  both scopes, as shipped.

## 3. Selection model

- **Default: `Tasks`** (first chip) on every load — the dashboard opens the same
  way each time, keeping personal ToDos front-and-centre. Not persisted.
- **Fall-through:** if `Tasks` has a zero count it is inert, so selection falls
  through to the **first chip (in order) with a non-zero count**.
- If **every** chip is zero, no chip is selected and no preview renders (the
  section still shows the muted chips, per the shipped zero-state rule).
- Selection is transient UI state on `HomeController` (not persisted).

## 4. Preview panel

The selected chip drives a panel of **3 documents**, then a **View All** button.

- **Ordering** matches each list screen's default (`creation desc`), so the three
  rows are literally the top of the list that **View All** opens. `Tasks` keeps
  its existing due-date ordering via `selectUpcomingTodos`, now capped at **3**
  (was 5).
- **Row tap** → that document's form: `Get.toNamed(<FORM route>, arguments: {'name': <name>, 'mode': 'view'})`.
- **View All** → that DocType's list, pre-filtered, reusing the shipped
  `filters` route argument: `Get.toNamed(<LIST route>, arguments: {'filters': actionableFiltersFor(doctype, scope, email)})`.
  For `Tasks` it calls the existing `goToToDo()` (unchanged).
- **Loading:** a 3-row skeleton while the preview fetch resolves.

### Row content

Every previewed document **is a Draft** (that is the actionable definition), so a
status pill would be redundant noise. Rows show identity, owner, and date:

| DocType | Title | Subtitle |
|---|---|---|
| Purchase Order | `name` | `supplier · <owner> · transaction_date` |
| Purchase Receipt | `name` | `supplier · <owner> · posting_date` |
| Stock Entry | `name` | `stock_entry_type · <owner> · posting_date` |
| Delivery Note | `name` | `customer · <owner> · posting_date` |
| Packing Slip | `name` | `delivery_note · <owner> · creation` |
| Tasks | *(existing `DashboardTodoCard`)* | `priority · due` — unchanged |

- A missing/empty party or date segment is omitted (no stray `·` separators).
- Packing Slip has **no `posting_date`** in its list fields — it uses `creation`.
- Dates render short (`d MMM`, e.g. `12 Jul`), matching `dueLabelFor`.

### Owner

- **Always shown**, in both scopes. (Noted: under **Mine** the filter *is*
  `owner = <selected user>`, so the value is by definition that user — it is
  displayed anyway, per decision.)
- Frappe stores `owner` as an **email**. Render the **display name** resolved
  from the already-loaded `HomeController.userList`; when the owner is not in
  that list (likely under **Everyone**, where any user can own a doc), fall back
  to the **email's local part** (`jawwad@x.com` → `jawwad`).
- Resolution is a pure helper: `String ownerLabelFor(String email, Map<String,String> namesByEmail)`.

**Field gap:** `owner` is already requested by the PR, SE, DN, PS and ToDo
providers, but **`PurchaseOrderProvider` does not request it** — add `'owner'`
to its `fields` list (`purchase_order_provider.dart:20`).

**Tasks rows keep their existing card unchanged** (no owner added): a ToDo's
meaningful "who" is `allocated_to`/`assigned_by`, not `owner`, and the shipped
card already carries `priority · due`. Flagged for review.

## 5. Packing Slip integration

- New chip + `ActionableDocConfig('Packing Slip', 'Packing Slip', Icons.inventory_2_outlined, AppRoutes.PACKING_SLIP)`.
- **CRITICAL:** Packing Slip's `status` is a **virtual field** — requesting or
  filtering it via `getDocumentList` raises a Frappe `FieldError`
  (`packing_slip_provider.dart:9-11` omits it deliberately; the model derives
  status from `docstatus`). So PS **must** filter on `{'docstatus': 0}`, never
  `{'status': 'Draft'}`. `actionableFiltersFor` extends its Stock-Entry branch:

  ```dart
  if (doctype == 'Stock Entry' || doctype == 'Packing Slip') {
    filters['docstatus'] = 0;
  } else {
    filters['status'] = 'Draft';
  }
  ```

- **`PackingSlipController` needs the filter-seed hook** — the shipped fix added
  it to PO/PR/SE/DN only. PS's `onInit` (`packing_slip_controller.dart:67-71`)
  sets `activeScreen` then calls `fetchPackingSlips()`, so seed **before** that
  call (single filtered fetch; no unfiltered-fetch race):

  ```dart
  final args = Get.arguments;
  if (args is Map && args['filters'] is Map) {
    activeFilters.value = Map<String, dynamic>.from(args['filters'] as Map);
  }
  ```

  Its `applyFilters` exists (`:83`) and stays untouched; `onReady` keeps its
  `openCreate` branch.

## 6. Data flow

- **Counts:** unchanged mechanism — one `getDocumentCount` per accessible
  DocType, cached per `(scope, email)`. Now **six** chips (PS added; Tasks count
  still derives from the existing ToDo fetch).
- **Preview:** a **lazy fetch of the selected DocType only** — `limit: 3`,
  `filters: actionableFiltersFor(doctype, scope, email)`, `orderBy: 'creation desc'`,
  via that DocType's existing provider method (`getPurchaseOrders`,
  `getPurchaseReceipts`, `getStockEntries`, `getDeliveryNotes`,
  `getPackingSlips`). Rows are mapped straight from the raw
  `response.data['data']` JSON — **no new model classes**.
- **Cached** per `(doctype, scope, email)` so re-selecting a chip is instant;
  invalidated by the same `force: true` path as counts (`fetchDashboardData`,
  user switch, pull-to-refresh).
- Only DocTypes the user can read are counted/previewed (existing
  `PermissionService.hasAccess` gate).
- Same-filter guarantee holds: the preview, the count, and the View All list all
  use `actionableFiltersFor`, so the three rows are the top of that list.

## 7. Components

Extending `lib/app/modules/home/widgets/dashboard_actionable_strip.dart`
(controller-free, widget-testable — the shipped convention):

- `kActionableDocConfigs` — labels become full DocType names; **Packing Slip
  added**. Order in the slider is Tasks (built in the screen) then this list.
- `ActionableChipData` gains `selected: bool`; `ActionableCountChip` renders the
  selected/unselected/muted states.
- `DashboardActionableStrip` becomes a **selector**: `selectedDoctype` +
  `ValueChanged<String> onSelect`, horizontal scroll instead of `Wrap`.
- **New** `ActionableDocRowData { String name; String subtitle; }` +
  pure `ActionableDocRowData docRowFor(String doctype, Map<String,dynamic> json, String Function(String) ownerLabel)`.
- **New** `ActionableDocRow` widget (title + subtitle + chevron) and
  `ActionableDocPreview` panel (3 rows | skeleton | View All).
- **New** pure `ownerLabelFor(String email, Map<String,String> namesByEmail)`.

`HomeController` additions: `selectedActionable` (`RxnString`), `previewDocs`
(`RxList<ActionableDocRowData>`), `isLoadingPreview` (`RxBool`), a
`Map<String, List<ActionableDocRowData>>` preview cache, `selectActionable(String doctype)`,
`Future<void> fetchPreviewDocs({bool force})`, `openActionableList` (exists) and a
`namesByEmail` map derived from `userList`. Default/fall-through selection is a
pure helper: `String? defaultActionableSelection(Map<String,int> counts, int todoCount)`.

## 8. Testing

- **Unit:** `docRowFor` per DocType (incl. PS `delivery_note` subtitle and its
  `creation` date fallback; omitted empty segments); `ownerLabelFor` (known user
  → name, unknown → local part, empty → ''); `actionableFiltersFor('Packing Slip', …)`
  → `{'docstatus': 0}` (**never** `status`); `defaultActionableSelection`
  (Tasks default, fall-through when Tasks is 0, null when all zero).
- **Widget:** slider scrolls horizontally and never wraps; selected vs
  unselected vs muted-inert chips (muted has no InkWell / is not selectable);
  tapping a chip reports its doctype; preview renders 3 rows + View All;
  loading skeleton; empty state; dark mode.
- **Regression:** existing `actionable_filters_test`, `dashboard_actionable_strip_test`,
  `home_controller_actionable_test`, `dashboard_todo_card_test` stay green (the
  `selectUpcomingTodos` cap change 5 → 3 touches its test's expectations).

## 9. Files touched (anticipated)

- `lib/app/modules/home/widgets/dashboard_actionable_strip.dart` — configs,
  chip selection, slider, row/preview widgets, `docRowFor`, `ownerLabelFor`.
- `lib/app/modules/home/home_controller.dart` — selection state, preview fetch +
  cache, `namesByEmail`.
- `lib/app/modules/home/home_screen.dart` — Tasks chip in the slider, preview
  panel, View All.
- `lib/app/modules/home/widgets/dashboard_todo_card.dart` — `selectUpcomingTodos`
  default cap 5 → 3.
- `lib/app/data/providers/purchase_order_provider.dart` — add `'owner'` field.
- `lib/app/modules/packing_slip/packing_slip_controller.dart` — `onInit` filter seed.
- `test/unit/…` — new + updated tests.

## 10. Out of scope

- Changing the actionable definition (still **Draft only**).
- The `showTasksFirst` persona rule and `DashboardSectionOrder`.
- Adding owner/assigned-by to the Tasks card.
- Persisting the selected chip (default is always Tasks).
- Any list-screen change beyond the PS `onInit` hook.
