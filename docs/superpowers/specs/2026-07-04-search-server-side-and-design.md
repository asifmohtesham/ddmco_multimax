# Server-side AND for multi-word search — Design

**Date:** 2026-07-04
**Status:** Proposed
**Part 1 of 2** — the AND-matching fix. Scoped pagination follows in a separate
spec (it builds on this).

## Problem

Multi-word search (shipped in 2.4.1+36) does **server OR (any token) → limit 50,
`modified desc` → client keeps rows with ALL tokens** (`rowMatchesAllTokens`).
Live result: "Belts Reversible" returns **one** item though **51** items are
named "BELTS REVERSIBLE …". Cause: "belts" and "reversible" are common across the
Belts/Straps catalog, so the 50-row OR-superset (newest first) is dominated by
items containing only *one* word; the (older) genuine two-word items fall outside
the window and never reach the client filter. This is the truncation the final
review flagged as an accepted risk — now confirmed as a real defect.

## Fix

Do the AND **server-side** so the query returns genuine all-word matches directly,
with no superset dilution. Frappe's REST filters can't express AND-of-ORs across
fields, so the AND runs against **one primary text field** per doctype.

### `ApiProvider.getDocumentList` (`lib/app/data/providers/api_provider.dart`)

Add an additive AND-list param, symmetric to the existing `orFilterTuples`:

- `List<List<dynamic>>? filterTuples` — when non-null/non-empty it is used **as-is**
  as the `filters` (AND) payload (each entry a complete `[doctype, field, op,
  value]`); the existing `filters` Map path runs only when `filterTuples` is null.
  Existing callers unchanged.

### `GlobalSearchService.search` (`lib/app/data/services/global_search_service.dart`)

- **1 token / empty:** unchanged — OR the phrase across all `searchTargets`
  (matches code *or* name), `limit 20`.
- **≥2 tokens:** AND each token on the **primary search field** via `filterTuples`:
  `[[doctype, primaryField, 'like', '%$token%'] for each token]`, `limit 20`. No
  client-side filtering — the server result is authoritative.
- New pure static:
  `static String resolvePrimarySearchField(Map<String, dynamic>? meta, List<String> searchTargets)`
  — returns `meta['title_field']` when it's a non-empty String (e.g. `item_name`
  for Item); else the first `searchTargets` entry that isn't `'name'` (the first
  descriptive search field); else `'name'`.
- Remove `rowMatchesAllTokens` (now dead — the server does the AND) and its tests.
  Keep `searchTokens` (still used to tokenise and to branch ≤1 vs ≥2).

### Behaviour

- "Belts Reversible" → `item_name LIKE %belts%` AND `item_name LIKE %reversible%`
  → all matching items (up to the limit, `modified desc`), matching the Desk.
- Word order stays flexible (each token is its own LIKE, any order within the field).
- Trade-off (accepted): a multi-word query with one word in the item **code** and
  another in the **name** won't combine — multi-word matches within the primary
  field. Single-word search still ORs across all fields, so code lookups are
  unaffected.
- Metadata-unavailable fallback: if getdoctype gave no meta, `title_field` is null
  and `searchTargets == ['name']`, so `primaryField == 'name'` → multi-word ANDs on
  the code (few matches) — but with the shipped getdoctype fix, meta is normally
  present, so Item resolves to `item_name`.

## Data flow

```
"belts reversible" → searchTokens → [belts, reversible]  (≥2 → AND path)
  primaryField = resolvePrimarySearchField(meta, searchTargets)   // item_name
  filters(AND) = [[Item,item_name,like,%belts%],[Item,item_name,like,%reversible%]]
  → server returns all matching Items (limit 20, modified desc)
  → _mapToModel → results (no client filter)
```

## Testing

- **Unit** — `resolvePrimarySearchField`:
  - `title_field` present → returns it (`{'title_field':'item_name'}` → `item_name`);
  - no title, `searchTargets=['name','item_name']` → `item_name` (first non-name);
  - no title, `searchTargets=['name']` → `name`;
  - null meta → falls to the searchTargets rule (`['name']` → `name`).
- **Unit** — `searchTokens` tests retained (unchanged).
- The networked multi-token AND path is verified on-device (operator account):
  "belts reversible" returns the belt items, not one — DI-free-unit convention.

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/data/providers/api_provider.dart` (add `filterTuples`) |
| Modify | `lib/app/data/services/global_search_service.dart` (≥2-token server AND; `resolvePrimarySearchField`; remove `rowMatchesAllTokens`) |
| Modify | `test/unit/global_search_tokens_test.dart` (drop `rowMatchesAllTokens` group; add `resolvePrimarySearchField`) |

## Out of scope

- **Pagination / load-more** — Part 2 (separate spec); this part keeps `limit 20`
  and the existing display cap.
- Multi-field AND-of-ORs (not expressible in one Frappe REST call; primary-field
  AND is the pragmatic choice).
- Plural/singular stemming (the reported case is plural-named; not needed).

## Versioning

Search behaviour fix → **PATCH** at release time (bundled with Part 2 if that
lands first, else released on its own).
