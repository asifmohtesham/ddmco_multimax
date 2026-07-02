# Dashboard Global Document Search — Design

**Date:** 2026-07-02
**Status:** Approved (pending spec review)
**Module:** `lib/app/modules/home/` + `lib/app/data/`

## Summary

Two Dashboard requests:

1. **Drag to refresh** — already implemented and committed (`RefreshIndicator`
   at `home_screen.dart:40`, calling `fetchDashboardData()` +
   `fetchPerformanceData()`). Verified working on-device by the user. **No code
   change.** Documented here only so it is not "re-implemented" by mistake.

2. **Replace the header Refresh button with a global document search** — a
   single search entry point on the Dashboard that searches **any document
   across all routed doctypes** at once, presents results grouped by doctype,
   and on tap opens that document's form. Pull-to-refresh remains the refresh
   path, so removing the Refresh button loses nothing.

This spec covers item 2.

## Goals

- One Search icon in the Dashboard header opens a unified search overlay.
- Typing (≥ 3 chars) searches every routed doctype the user can read.
- Results are grouped by doctype (section header per type), matching the
  approved mockup.
- Tapping a result opens the correct form with the arguments that form expects.
- Respect DocType read permissions (mirrors `DocTypeGuard`).
- Reuse the existing, proven single-doctype search (`GlobalSearchService.search`)
  rather than inventing a new query path.

## Non-goals (YAGNI)

- No server-side unified "global search" endpoint — we fan out over the
  existing per-doctype list API.
- No "see all N results in {DocType}" drill-in row (possible later extension).
- No recent-searches / history.
- No change to the 11 list screens that already use `DocTypeSearchDelegate`.

## Existing infrastructure (reused)

- `GlobalSearchService.search(doctype, query)`
  (`lib/app/data/services/global_search_service.dart`) — metadata-aware,
  builds `orFilters` over searchable fields, maps rows to `GlobalSearchItem`,
  caches doctype metadata per session. **Reused as the per-doctype primitive.**
- `GlobalSearchItem` (`lib/app/data/models/global_search_item.dart`) — result
  model (`id`, `title`, `subtitle`, `imageUrl`, `rawData`).
- `PermissionService.hasAccess(doctype, permType: 'read')` → `bool?`
  (synchronous, cached, prefetched at login). **Reused to filter targets.**
- `ApiProvider.getDocumentList(..., orFilters:, fields:, limit:)`.
- `DocTypeListHeader.extraActions` — where the current Refresh `IconButton`
  lives (`home_screen.dart:51`).

## Architecture

Three new units + one edit.

### 1. Search-target registry — `lib/app/data/constants/global_search_targets.dart`

A model + a `const` list. Single source of truth for what is searchable and how
each result navigates.

```dart
class GlobalSearchTarget {
  final String doctype;   // Frappe DocType queried, e.g. 'Delivery Note'
  final String label;     // Section header, e.g. 'Delivery Notes'
  final IconData icon;    // Reuse Quick-Create tile icon
  final Color color;      // Reuse Quick-Create tile colour
  final String route;     // Form route (AppRoutes.*)
  final Object Function(String id) argsFor; // Args the form expects

  const GlobalSearchTarget({...});
}

const List<GlobalSearchTarget> kGlobalSearchTargets = [ ... ];
```

Per-doctype navigation contract (traced from each form controller / list-row
tap — this is the canonical "open this document" path for each doctype):

| Doctype          | Route                  | `argsFor(id)`                     |
|------------------|------------------------|-----------------------------------|
| Item             | `ITEM_FORM`            | `{'itemCode': id}`                |
| Delivery Note    | `DELIVERY_NOTE_FORM`   | `{'name': id, 'mode': 'view'}`    |
| Purchase Receipt | `PURCHASE_RECEIPT_FORM`| `{'name': id, 'mode': 'view'}`    |
| Stock Entry      | `STOCK_ENTRY_FORM`     | `{'name': id, 'mode': 'view'}`    |
| Purchase Order   | `PURCHASE_ORDER_FORM`  | `{'name': id, 'mode': 'view'}`    |
| Packing Slip     | `PACKING_SLIP_FORM`    | `{'name': id, 'mode': 'view'}`    |
| Material Request | `MATERIAL_REQUEST_FORM`| `{'name': id, 'mode': 'view'}`    |
| POS Upload       | `POS_UPLOAD_FORM`      | `{'name': id, 'mode': 'view'}`    |
| ToDo             | `TODO_FORM`            | `{'name': id, 'mode': 'view'}`    |
| Work Order       | `WORK_ORDER_FORM`      | `{'name': id, 'mode': 'view'}`    |
| Batch            | `BATCH_FORM`           | `{'name': id, 'mode': 'edit'}`    |
| Job Card         | `JOB_CARD_FORM`        | `{'name': id}`                    |
| BOM              | `BOM_FORM`             | `{'name': id}`                    |

Notes:
- **Item** form reads `args['itemCode']` (not `'name'`) —
  `item_form_controller.dart:98`.
- **Batch** form defaults `mode` to `'new'` when absent, so an explicit
  `'edit'` is required to open an existing batch — `batch_form_controller.dart:185`.
- **Job Card / BOM** forms read only `args['name']`; an extra `mode` key would
  be ignored, but we pass the minimal map they use at their own row taps.
- **POS Upload**: the doctype **name** queried is `'POS Upload'` (the POS Upload
  list screen's `searchDoctype: 'POS Invoice'` is an unrelated oddity; we query
  the real doctype).

### 2. Fan-out search — new method on `GlobalSearchService`

```dart
/// Runs [search] across every permitted target concurrently and returns the
/// hits grouped by target, preserving [kGlobalSearchTargets] order. Empty
/// groups are omitted.
Future<List<GlobalSearchGroup>> searchAll(String query) async { ... }
```

- **Permission filter:** include a target when
  `permission.hasAccess(target.doctype) != false` (true, or null when the cache
  is not yet warm — degrade permissive rather than show nothing).
- **Concurrency:** `Future.wait` over the filtered targets. Each per-doctype
  `search` already catches its own errors and returns `[]`, so a failing group
  contributes nothing and never rejects the whole call.
- **Cap:** each group limited to a small display count (8). (`search` already
  requests `limit: 20`; we trim for the grouped view.)
- `GlobalSearchGroup` = `{ GlobalSearchTarget target, List<GlobalSearchItem> items }`.

`PermissionService` becomes a dependency of `GlobalSearchService`
(`Get.find<PermissionService>()`), consistent with how other services resolve
dependencies.

### 3. `GlobalDocumentSearchDelegate` — new `SearchDelegate<void>`

New file `lib/app/modules/global_widgets/global_document_search_delegate.dart`.
Deliberately **separate** from `DocTypeSearchDelegate` (which 11 list screens
depend on) to keep that widget stable and this one single-purpose.

Behaviour:
- `searchFieldLabel`: "Search any document…".
- `buildLeading`: back arrow → `close`.
- `buildActions`: clear (`×`) when query non-empty.
- `buildSuggestions` / `buildResults`:
  - query trimmed length < 3 → message state "Type at least 3 characters".
  - ≥ 3 → **debounced** `FutureBuilder<List<GlobalSearchGroup>>` on
    `searchAll(query)`:
    - waiting → `LinearProgressIndicator`.
    - error → theme-correct error message state.
    - empty → "No documents found matching \"query\"".
    - results → a `CustomScrollView`/`ListView` of sections. Each section: a
      pinned-style header row (`target.icon` + `target.label`), then rows.
      Row = leading icon (image thumb when `imageUrl` present, else target
      icon), `title`, `subtitle` (ellipsised), trailing chevron.
  - Tap → `close(context, null)` then
    `Get.toNamed(target.route, arguments: target.argsFor(item.id))`.

**Debounce:** the delegate holds a small debouncer (300 ms) so rapid keystrokes
don't fan out ~13 queries each. Implementation: cache the in-flight
`(query → Future)` and only issue a new `searchAll` after the debounce window;
identical consecutive queries reuse the cached future.

**Theming:** all colours via `context.scheme` / `colorScheme` — no
`Colors.grey.shadeX` / hardcoded inks (per CLAUDE.md contrast rules). Section
headers use `scheme.textMuted`; body text `scheme.text`; secondary
`scheme.textMuted`.

### 4. Dashboard wiring — edit `home_screen.dart`

Replace the Refresh `IconButton` in `DocTypeListHeader.extraActions`
(`home_screen.dart:51-60`) with:

```dart
IconButton(
  icon: const Icon(Icons.search),
  tooltip: 'Search documents',
  onPressed: () => showSearch(
    context: context,
    delegate: GlobalDocumentSearchDelegate(),
  ),
)
```

The `RefreshIndicator` (item 1) is untouched.

## Data flow

```
Dashboard header Search icon
  └─ showSearch → GlobalDocumentSearchDelegate
       └─ (≥3 chars, debounced) searchAll(query)
            └─ for each permitted GlobalSearchTarget (concurrently):
                 GlobalSearchService.search(target.doctype, query)
                   └─ ApiProvider.getDocumentList(orFilters, fields)
            └─ group → [GlobalSearchGroup]
       └─ render grouped sections
            └─ tap → Get.toNamed(target.route, target.argsFor(item.id))
```

## Error handling

- Per-doctype failures are already swallowed inside `search` → empty group.
- `searchAll` never throws for a partial failure; the `FutureBuilder` error
  branch only triggers on an unexpected top-level exception.
- No results across all groups → friendly empty state, not an error.

## Testing

- **Registry unit test** (`test/unit/global_search_targets_test.dart`): every
  target's `argsFor('X')` returns the documented map/shape; every `route` is a
  known `AppRoutes` constant; no duplicate doctypes.
- **`searchAll` unit test** (`test/unit/global_search_all_test.dart`): with a
  mocked `ApiProvider` + `PermissionService` — (a) groups are returned in
  registry order, (b) targets the user cannot read are excluded, (c) a doctype
  that errors is omitted without failing the whole call, (d) empty groups are
  dropped.
- **Existing suite** stays green; `flutter analyze` clean.
- Manual on-device smoke: search a known Item code, DN, Work Order → correct
  form opens for each; permission-restricted doctype absent for a
  limited-role user.

## Files

**New**
- `lib/app/data/constants/global_search_targets.dart`
- `lib/app/modules/global_widgets/global_document_search_delegate.dart`
- `test/unit/global_search_targets_test.dart`
- `test/unit/global_search_all_test.dart`

**Modified**
- `lib/app/data/services/global_search_service.dart` — add `searchAll` +
  `GlobalSearchGroup`; depend on `PermissionService`.
- `lib/app/modules/home/home_screen.dart` — Refresh button → Search button.

## Rollout

Feature is additive and Dashboard-local. No migration. Ship on
`release/play-store` following the usual smoke + tag flow.
