# "Set a Default Warehouse" hint in Item search results — Design

**Date:** 2026-07-04
**Status:** Proposed

## Problem

The inline Default-Warehouse stock balance on Item search rows is **silently
warehouse-gated**: with no Default Warehouse set, `_trailingFor` renders the
chevron (balances null) and the user gets no hint that a setting would surface
balances. A user reported the missing balances as a "regression"; the cause was
an empty Default Warehouse. Make the gate discoverable.

## Goal

When Item results are shown and no Default Warehouse is set, show a **tappable
banner** above the Item rows — "Set a Default Warehouse to see stock balances" —
that opens Session Defaults. It disappears once a warehouse is set.

## Trigger

The delegate computes a single nullable callback:

- `VoidCallback? _onSetWarehouse(BuildContext context)` — returns a callback
  (`close(context, null)` then `Get.toNamed(AppRoutes.SESSION_DEFAULTS)`) **only
  when** `_defaultWarehouse == null && _itemReadable`; otherwise `null`.

Non-null ⇒ show the banner (on the Item group/scope only); null ⇒ no banner. This
encodes both "show it" and "what tapping does" in one value, and self-dismisses
(next search recomputes once a warehouse exists).

## Components (`lib/app/modules/global_widgets/global_document_search_delegate.dart`)

- **Banner** — private `Widget _setWarehouseBanner(BuildContext context, VoidCallback onTap)`:
  a themed, tappable `InkWell`/`Material` row — `Icons.info_outline` +
  "Set a Default Warehouse to see stock balances" + `Icons.chevron_right`, filled
  `scheme.subtle`, text `scheme.text`/`scheme.textMuted`, radius `AppRadius`-style.
  All colours via `context.scheme.*`.
- **`buildResultsList`** (the "All" view, already `@visibleForTesting`) gains an
  optional `{VoidCallback? onSetWarehouse}`. While emitting groups, for the group
  whose `target.doctype == 'Item'`, if `onSetWarehouse != null`, insert
  `_setWarehouseBanner(context, onSetWarehouse)` immediately after that group's
  section header (before its rows). No banner for other groups or when null.
- **`_ScopedResults`** gains an `onSetWarehouse` field; in `build`, when
  `widget.target.doctype == 'Item'` and `onSetWarehouse != null`, insert the
  banner right after the section header (index 1), before the item rows.
- **`_buildResultsArea` wiring:**
  - "All" branch → `buildResultsList(..., onSetWarehouse: _onSetWarehouse(context))`.
  - Scoped branch → `_ScopedResults(..., onSetWarehouse: _onSetWarehouse(context))`.
- Add `import '.../data/routes/app_routes.dart';` for `AppRoutes.SESSION_DEFAULTS`.

## Data flow

```
search shows Item results
  → _onSetWarehouse(context): _defaultWarehouse == null && _itemReadable ?
        (() => close + Get.toNamed(SESSION_DEFAULTS)) : null
  → All view: buildResultsList inserts banner after the Item group header (if non-null)
  → Items scope: _ScopedResults inserts banner after its header (if non-null)
  → tap → Session Defaults; user sets warehouse → next search: callback null → banner gone
```

## Error handling / edge cases

- Balances only apply to Items → the banner is Item-only (guarded by
  `target.doctype == 'Item'` at the insertion sites).
- No behaviour change to the balance fetch/gating; the chevron still shows on the
  rows while no warehouse is set (the banner explains why).
- If `_itemReadable` is false (Item not accessible) the banner is suppressed
  (callback null) — no point prompting for a warehouse the user can't use.

## Testing

- **Widget** — `buildResultsList`:
  - an Item group with `onSetWarehouse` non-null → the banner text renders once,
    and tapping it fires the callback;
  - `onSetWarehouse` null → no banner;
  - a non-Item group with `onSetWarehouse` non-null → no banner (Item-only).
- The scoped-view insertion and the `_defaultWarehouse == null && _itemReadable`
  gate are verified on-device (the gate reads live DI); the banner widget itself
  is covered by the `buildResultsList` tests.

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/modules/global_widgets/global_document_search_delegate.dart` (banner + `onSetWarehouse` on `buildResultsList`/`_ScopedResults` + wiring + route import) |
| Modify | `test/widget/global_document_search_delegate_test.dart` (banner cases) |

## Out of scope / YAGNI

- Dismiss/"don't show again" persistence (it self-dismisses once a warehouse is set).
- Prompting on non-Item doctypes (balances are Item-only).
- Any change to balance fetching, `_trailingFor`, or the warehouse-gating logic.

## Versioning

Small UX addition to search → **PATCH** at release time (bundle with the pending
search Part 1 + 2 commits).
