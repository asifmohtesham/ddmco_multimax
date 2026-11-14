# Multi-word ("all words, any order") Global Search — Design

**Date:** 2026-07-04
**Status:** Proposed

## Problem

`GlobalSearchService.search` builds `orFilters[field] = ['like', '%$query%']` with
the **entire query string** as one substring, OR'd across searchable fields
(`global_search_service.dart:60-63`). A multi-word query only matches a field that
contains that **exact contiguous phrase**, so `"belts reversible"` returns nothing
unless an item literally contains "belts reversible" — an item named "Reversible
Belts 30mm" (different word order) is missed. This affects the Dashboard search
fan-out ("All"), the scoped chips, and voice search (all route through `search`).

## Desired behaviour

**All words, any order.** Split the query into whitespace-separated tokens; a
result must contain **every** token (each as a case-insensitive substring, in any
order) somewhere across its searchable fields. `"belts reversible"` matches
"Reversible Belts 30mm". No plural/singular stemming (substring only — chosen).

## Approach — one request per doctype: server OR, client AND

- **Tokenize:** `searchTokens(query)` splits on whitespace, drops empties.
- **1 token (or 0):** unchanged — today's single `LIKE %token%` across fields is
  already correct; no client filtering, `limit` stays 20.
- **≥2 tokens:**
  - **Server:** OR every *(searchable field × token)* `LIKE %token%`. Returns rows
    matching *any* token in *any* field (a superset). `limit` bumped to **50** so
    the superset isn't truncated before the client filter.
  - **Client:** keep only rows where **every** token is a case-insensitive
    substring of the row's concatenated searchable-field values.

Rejected: per-token request + client intersect (N requests × the doctype fan-out —
too heavy); client-only filtering over a broad fetch (no broad server term to fetch
with).

## Components

### `ApiProvider.getDocumentList` (`lib/app/data/providers/api_provider.dart`)

The current `orFilters` is a `Map<String, dynamic>` keyed by field, so it cannot
hold two LIKE conditions on the same field (needed: one per token). Add an
additive optional param:

- `List<List<dynamic>>? orFilterList` — when non-null/non-empty, it is used
  **as-is** as the `or_filters` payload (each entry a complete Frappe tuple
  `[doctype, field, operator, value]`); the existing `orFilters` Map path is used
  only when `orFilterList` is null. Every existing caller (which passes only
  `orFilters`) is unchanged.

### `GlobalSearchService.search` (`lib/app/data/services/global_search_service.dart`)

- Compute `tokens = searchTokens(query)`.
- **≤1 token:** keep the exact current Map-based request (behaviour unchanged).
- **≥2 tokens:** build `orFilterList` = `[for each field in searchTargets, for each
  token: [doctype, field, 'like', '%$token%']]`; request with
  `orFilterList:` + `limit: 50`; map rows; then retain only rows where
  `rowMatchesAllTokens(rawData, searchTargets, tokens)`.
- New pure statics (unit-tested, no DI):
  - `static List<String> searchTokens(String query)` — `query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList()`.
  - `static bool rowMatchesAllTokens(Map<String, dynamic> row, List<String> fields, List<String> tokens)` — concatenate `fields`' string values (space-joined), lowercase, return `tokens.every((t) => hay.contains(t.toLowerCase()))`.

`searchTargets` (the fields actually searched: `name` + validated `search_fields`)
are a subset of `selectFields`, so every searched field is present on the returned
row for the client filter. For Item this covers `name` (=item_code) + `item_name`.

## Data flow

```
query "belts reversible"
  → searchTokens → ["belts","reversible"]
  → server or_filters: (name|item_name|… LIKE %belts%) OR (… LIKE %reversible%)
     → superset rows (match any token), limit 50
  → rowMatchesAllTokens keeps rows containing BOTH tokens
  → grouped results (unchanged downstream)
```

## Error handling

- Unchanged: `search` already wraps the request in try/catch → returns `[]` on
  failure. The new path adds only pure client-side filtering, no new failure modes.
- A query of only whitespace → `searchTokens` returns `[]` → treated as the ≤1
  path with an empty phrase (same as an empty query today).

## Testing

- **Unit** — `searchTokens`: `'belts reversible'` → `['belts','reversible']`;
  collapses runs of whitespace (`'  a   b '` → `['a','b']`); `''`/`'   '` → `[]`;
  single word → one element.
- **Unit** — `rowMatchesAllTokens`: a row `{name:'FG-1', item_name:'Reversible Belts 30mm'}`
  with fields `['name','item_name']` matches `['belts','reversible']` (order-independent,
  case-insensitive) and fails `['belts','strap']`; empty tokens → true (no constraint).
- The full networked `search` multi-token path (server OR + client AND) is verified
  on-device — consistent with the suite's DI-free-unit convention.

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/data/providers/api_provider.dart` (`orFilterList` param) |
| Modify | `lib/app/data/services/global_search_service.dart` (tokenized multi-word path + `searchTokens`/`rowMatchesAllTokens`) |
| Add    | `test/unit/global_search_tokens_test.dart` |

## Out of scope / YAGNI

- Plural/singular stemming (substring only).
- Relevance ranking / fuzzy matching / typo tolerance.
- The separate `_ensureMetadata` 403 log for restricted doctypes (independent; no
  decision taken).

## Versioning

New search capability → **MINOR** at release time per `docs/versioning_conventions.md`.
