# DocType List View Conventions

This document defines the standard structure for every **DocType List View** in
the app (the list/overview screens under `lib/app/modules/*/*_screen.dart`). It
extends [`app_bar_conventions.md`](app_bar_conventions.md), which covers only the
header; this document covers the whole screen.

The goal: every list screen looks and behaves identically except for its rows.
Anything shared is a widget, not copy-paste.

---

## 1. Anatomy of a standard list screen

```
AppShellScaffold
└─ RefreshIndicator          (color: cs.primary, backgroundColor: cs.surfaceContainerHighest)
   └─ CustomScrollView
      ├─ DocTypeListHeader    (automaticallyImplyLeading: false)
      ├─ ResultCountPill      (SliverToBoxAdapter + Obx)
      └─ Obx → one of:
         ├─ loading  → SliverFillRemaining(CircularProgressIndicator)
         ├─ empty    → SliverFillRemaining(ListEmptyState)
         └─ data     → SliverList(rows… + ListEndFooter)
```

Shared building blocks (all in `lib/app/modules/global_widgets/`):

| Concern              | Widget               | Notes |
|----------------------|----------------------|-------|
| Header               | `DocTypeListHeader`  | See `app_bar_conventions.md`. |
| Result count pill    | `ResultCountPill`    | Pass singular `noun`; plural is derived. |
| Empty / no-match     | `ListEmptyState`     | Two variants via `hasActiveFilters`. |
| End-of-list sentinel | `ListEndFooter`      | Loader when `hasMore`, else "End of results". |
| Active filter chip   | `FilterChipWidget`   | The only chip; never hand-roll a `Chip`. |
| Row card             | `GenericDocumentCard`| Standard row; see §4. |

---

## 2. Title — singular DocType name

The header `title` is the **singular** DocType label, matching ERPNext/Frappe
v15 (`base_list.js`: `page_title = … || __(this.doctype)`; primary action
`"Add {DocType}"`; empty state `"You haven't created a {DocType} yet"` — all
singular).

✅ `'Item'`, `'Delivery Note'`, `'Work Order'`, `'Purchase Receipt'`
❌ `'Items'`, `'Delivery Notes'`, `'Work Orders'`

For custom (non-DocType) screens, use the singular feature name (`'POS Upload'`).

---

## 3. Filter state — one contract

Every list controller exposes filter state as `RxMap<String, dynamic> activeFilters`,
which `DocTypeListHeader` consumes directly. Screens that need a richer internal
model (e.g. Item's `FilterRow` list with operators / Link / Attribute support)
keep it internal but **must still expose a real `RxMap`** — do not invent a
synthetic sentinel-key shim.

Active filters and the current search query are rendered as `FilterChipWidget`s
via the header's `filterChipsBuilder`. Surface the search query as its own chip
where the screen supports free-text search.

---

## 4. Row interaction — `navigatesOnTap`

Row rendering uses `GenericDocumentCard`. Pick the open-record gesture per
DocType and document it in the screen:

- **Expandable** (inline detail preview): `navigatesOnTap: false` (default).
  Tap expands; opening the form is a secondary action (a button inside the
  expanded panel, or long-press).
- **Navigational** (no inline detail): `navigatesOnTap: true`. Tap opens the
  form.

Never combine `navigatesOnTap: true` with a non-null `expandedContent` — the
affordances contradict.

---

## 5. Conformance checklist (per list screen)

- [ ] Wrapped in `AppShellScaffold`.
- [ ] `RefreshIndicator` with `color: cs.primary` + `backgroundColor: cs.surfaceContainerHighest`.
- [ ] `DocTypeListHeader` with `automaticallyImplyLeading: false`.
- [ ] Title is the **singular** DocType name.
- [ ] `ResultCountPill` below the header.
- [ ] `ListEmptyState` for the empty/no-match state (no hand-rolled empty column).
- [ ] `ListEndFooter` as the trailing list sentinel.
- [ ] Active filters/search rendered with `FilterChipWidget` (no inline `Chip`).
- [ ] Rows use `GenericDocumentCard` with a documented `navigatesOnTap` choice.
- [ ] `activeFilters` is an `RxMap<String, dynamic>` (no sentinel shim).

---

## 6. Migration status

Routed through the shared widgets: **Item**, **Delivery Note**, **Work Order**,
**Purchase Order**, **Purchase Receipt**, **Material Request**, **Stock Entry**,
**Packing Slip**, **Job Card**.

> Job Card and Packing Slip are partial by design: Job Card uses its KPI strip
> as the count affordance (no `ResultCountPill`); Packing Slip groups rows and
> keeps its per-group `_countPill`. Both use `ListEmptyState` / `ListEndFooter`
> and the shared `FilterChipWidget`.

Remaining list screens to migrate: POS Upload, BOM, and the Stock report
screens (Stock Balance, Batch-Wise Balance, Item Variant Details, Job Card
Summary, BOM Search). These are table/report-style views; assess per screen.
Titles for all list screens have already been singularised.

> **Future:** a custom `dart analyze` lint (per `app_bar_conventions.md` §4.1)
> could enforce items in §5 at CI time.
