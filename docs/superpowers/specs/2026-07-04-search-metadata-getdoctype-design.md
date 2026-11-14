# Search Metadata via getdoctype (fix operator name-only search) — Design

**Date:** 2026-07-04
**Status:** Proposed

## Problem

`GlobalSearchService._ensureMetadata` fetches a doctype's field metadata with
`getDocument('DocType', <name>)` → `GET /api/resource/DocType/<name>`. That
endpoint requires **read access on the `DocType` doctype**, which
non-System-Manager operators do not have, so it returns **403**
(`frappe.exceptions.PermissionError`, observed live for adnan@multimax.cloud on
`DocType/Material Request`).

On 403 the exception is caught, `_metadataCache[doctype]` stays unset, and
`search` proceeds with `meta == null` → `searchTargets` is **`['name']` only**.
The search then matches just the document name/ID. For Item that is the
**item_code**, never `item_name`, so an operator searching "belts reversible"
(or any descriptive term) gets **no results** — the recently-shipped multi-word
matching is moot because `item_name` is never queried. This degrades global search
for every non-SM operator, and emits a noisy 403 log per restricted doctype.

## Fix

Fetch the metadata through the **operator-reachable** desk endpoint the app
already uses for the same class of 403 — `frappe.desk.form.load.getdoctype`
(see `ApiProvider.fetchDocTypeRoles`, `api_provider.dart:419`) — instead of the
`DocType` resource API. `getdoctype` is gated on the *target* doctype, not on
reading `DocType`, so operators receive the metadata.

### `ApiProvider` (`lib/app/data/providers/api_provider.dart`)

Add a thin wrapper mirroring `fetchDocTypeRoles`:

- `Future<Response> getDocTypeMeta(String doctype)` →
  `callMethod('frappe.desk.form.load.getdoctype', params: {'doctype': doctype, 'with_parent': 1})`.

### `GlobalSearchService` (`lib/app/data/services/global_search_service.dart`)

- `_ensureMetadata(doctype)` calls `_apiProvider.getDocTypeMeta(doctype)`, then
  resolves the DocType meta doc via a new pure static and caches it exactly as
  today (`_metadataCache[doctype] = meta`, and the `_fieldTypesCache` built from
  `meta['fields']`). The rest of `search` / `_mapToModel` is unchanged — the
  getdoctype DocType doc carries the same attributes the resource response did:
  `search_fields`, `title_field`, `image_field`, and the `fields` child list
  (each `{fieldname, fieldtype}`).
- New pure static:
  `static Map<String, dynamic>? extractDocTypeMeta(dynamic data, String doctype)`
  — returns the entry in the getdoctype `docs` list where
  `doctype == 'DocType' && name == <doctype>`, or null. Tolerates both the
  `{docs: [...]}` and `{message: {docs: [...]}}` shapes (mirroring the existing
  `ApiProvider.rolesWithPermission`). Fail-closed: any unexpected shape → null.

### Behaviour on failure

If `getdoctype` still fails (network, or a doctype the user genuinely can't
access even via the desk endpoint), the catch leaves `meta == null` → the current
`name`-only fallback is preserved. No new failure modes; the search never throws.

## Data flow

```
search('Item', q)
  → _ensureMetadata('Item')
      → ApiProvider.getDocTypeMeta('Item')  [getdoctype — reachable for operators]
      → extractDocTypeMeta(data, 'Item')    → {search_fields:'item_name,…', title_field, fields:[…]}
      → _metadataCache['Item'] = meta;  _fieldTypesCache['Item'] = {item_name: 'Data', …}
  → searchTargets = ['name','item_name',…]  → server matches item_name too
```

## Testing

- **Unit** — `extractDocTypeMeta`:
  - finds the target doc in a canned `{docs: [<parent>, {doctype:'DocType', name:'Item', search_fields:'item_name,item_group', title_field:'item_name', fields:[{fieldname:'item_name',fieldtype:'Data'}]}]}` response;
  - tolerates the `{message: {docs: [...]}}` wrapper;
  - returns null when the doc is absent, when `data` isn't a Map, or when `docs` isn't a List.
- The networked `_ensureMetadata` / `getDocTypeMeta` path is verified on-device
  (operator account): a descriptive multi-word query now returns items, and the
  `DocType … 403` log no longer appears. (Consistent with the suite's DI-free
  unit convention — no live-HTTP unit test.)

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/data/providers/api_provider.dart` (add `getDocTypeMeta`) |
| Modify | `lib/app/data/services/global_search_service.dart` (`_ensureMetadata` via getdoctype + `extractDocTypeMeta`) |
| Add    | `test/unit/global_search_metadata_test.dart` |

## Out of scope / YAGNI

- Sharing the getdoctype fetch between `PermissionService` and search (each
  caches independently; a shared cache is a later optimization).
- A static per-doctype search-field fallback (the getdoctype fetch is the general
  fix; name-only remains the last-resort fallback).
- Relevance ranking / the limit-50 superset caveat (tracked with the multi-word
  change).

## Versioning

Search bugfix for operators → at least **PATCH**; bundled with the pending
multi-word commit for the next release (bump tool decides the exact field at
release time).
