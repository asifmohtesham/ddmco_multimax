# Search Metadata via getdoctype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fetch global-search DocType metadata via the operator-reachable `frappe.desk.form.load.getdoctype` endpoint so non-System-Manager users get full-field search instead of name-only (and the 403 log stops).

**Architecture:** Add a thin `ApiProvider.getDocTypeMeta` wrapping the `getdoctype` method call (as `fetchDocTypeRoles` already does), and rewrite `GlobalSearchService._ensureMetadata` to pull the DocType meta doc from that response via a new pure `extractDocTypeMeta`. Downstream field-type parsing and `_mapToModel` are unchanged.

**Tech Stack:** Flutter, GetX, Dio (via `ApiProvider`), Frappe `frappe.desk.form.load.getdoctype`, `flutter_test`.

## Global Constraints

- Use `frappe.desk.form.load.getdoctype` (reachable for operators) — NOT `/api/resource/DocType/<name>` (403 for non-System-Manager users).
- On any failure / unexpected shape, `meta` stays null → the current `name`-only fallback is preserved; `_ensureMetadata` must never throw out of its try/catch.
- The getdoctype DocType doc exposes the same attributes the resource response did (`search_fields`, `title_field`, `image_field`, `fields[]` with `fieldname`/`fieldtype`), so `search`/`_mapToModel` stay unchanged.
- `extractDocTypeMeta` is a pure `static` (unit-tested, no DI), tolerating `{docs: […]}` and `{message: {docs: […]}}` (mirroring `ApiProvider.rolesWithPermission`).
- No new analyzer warnings/errors in touched files.

---

### Task 1: getdoctype-backed search metadata

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (add `getDocTypeMeta`)
- Modify: `lib/app/data/services/global_search_service.dart` (`_ensureMetadata` via getdoctype + `extractDocTypeMeta`)
- Test: `test/unit/global_search_metadata_test.dart` (create)

**Interfaces:**
- Consumes: `ApiProvider.callMethod(String method, {Map<String,dynamic>? params})` → `Future<Response>` (exists, `api_provider.dart:327`).
- Produces: `Future<Response> ApiProvider.getDocTypeMeta(String doctype)`; `static Map<String,dynamic>? GlobalSearchService.extractDocTypeMeta(dynamic data, String doctype)`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/global_search_metadata_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('extractDocTypeMeta', () {
    final itemDoc = {
      'doctype': 'DocType',
      'name': 'Item',
      'search_fields': 'item_name,item_group',
      'title_field': 'item_name',
      'fields': [
        {'fieldname': 'item_name', 'fieldtype': 'Data'},
      ],
    };

    test('finds the target doc in {docs: [...]}', () {
      final data = {
        'docs': [
          {'doctype': 'DocType', 'name': 'UOM'}, // a parent/other doc
          itemDoc,
        ],
      };
      final meta = GlobalSearchService.extractDocTypeMeta(data, 'Item');
      expect(meta, isNotNull);
      expect(meta!['search_fields'], 'item_name,item_group');
      expect(meta['title_field'], 'item_name');
      expect(meta['fields'], isA<List>());
    });

    test('tolerates the {message: {docs: [...]}} wrapper', () {
      final data = {
        'message': {'docs': [itemDoc]},
      };
      final meta = GlobalSearchService.extractDocTypeMeta(data, 'Item');
      expect(meta?['title_field'], 'item_name');
    });

    test('returns null when the target doc is absent', () {
      final data = {
        'docs': [
          {'doctype': 'DocType', 'name': 'UOM'},
        ],
      };
      expect(GlobalSearchService.extractDocTypeMeta(data, 'Item'), isNull);
    });

    test('returns null on non-Map data or a missing/!List docs', () {
      expect(GlobalSearchService.extractDocTypeMeta('nope', 'Item'), isNull);
      expect(GlobalSearchService.extractDocTypeMeta({'foo': 'bar'}, 'Item'),
          isNull);
      expect(
          GlobalSearchService.extractDocTypeMeta({'docs': 'notalist'}, 'Item'),
          isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/global_search_metadata_test.dart`
Expected: FAIL — `extractDocTypeMeta` not defined.

- [ ] **Step 3: Add `getDocTypeMeta` to the provider**

In `lib/app/data/providers/api_provider.dart`, add this method next to `fetchDocTypeRoles` (after it, ~line 429):

```dart
  /// DocType metadata via the desk `getdoctype` endpoint — reachable for
  /// ordinary operators, unlike `/api/resource/DocType/<name>` (which 403s
  /// without read access on the DocType doctype). Returns the raw method
  /// response; callers pull the target doc from `data['docs']`.
  Future<Response> getDocTypeMeta(String doctype) => callMethod(
        'frappe.desk.form.load.getdoctype',
        params: {'doctype': doctype, 'with_parent': 1},
      );
```

- [ ] **Step 4: Rewrite `_ensureMetadata` + add `extractDocTypeMeta`**

In `lib/app/data/services/global_search_service.dart`, replace the whole
`_ensureMetadata` method (currently lines 307–335) with:

```dart
  /// Fetches and caches DocType metadata to understand fields and types.
  ///
  /// Uses the desk `getdoctype` endpoint (reachable for operators) rather than
  /// `/api/resource/DocType/<name>`, which 403s for non-System-Manager users and
  /// would leave search matching only the document `name` (e.g. item_code), never
  /// descriptive fields like item_name.
  Future<void> _ensureMetadata(String doctype) async {
    if (_metadataCache.containsKey(doctype)) return;

    try {
      final response = await _apiProvider.getDocTypeMeta(doctype);
      final meta = extractDocTypeMeta(response.data, doctype);
      if (meta != null) {
        _metadataCache[doctype] = meta;

        // Parse Field Types
        final Map<String, String> types = {};
        final fields = meta['fields'];
        if (fields is List) {
          for (final field in fields) {
            if (field is Map) {
              final fname = field['fieldname'];
              final ftype = field['fieldtype'];
              if (fname != null && ftype != null) {
                types[fname.toString().toLowerCase()] = ftype.toString();
              }
            }
          }
        }
        _fieldTypesCache[doctype] = types;
      }
    } catch (e) {
      print('GlobalSearchService: Metadata fetch failed for $doctype: $e');
    }
  }

  /// The DocType meta doc for [doctype] from a `frappe.desk.form.load.getdoctype`
  /// response — the entry in `docs` with `doctype == 'DocType'` and matching
  /// `name`. Tolerates the `{docs: […]}` and `{message: {docs: […]}}` shapes.
  /// Returns null on any unexpected shape (fail-closed → name-only search). Pure.
  static Map<String, dynamic>? extractDocTypeMeta(
    dynamic data,
    String doctype,
  ) {
    if (data is! Map) return null;
    final docs = data['docs'] ??
        (data['message'] is Map ? data['message']['docs'] : null);
    if (docs is! List) return null;
    for (final doc in docs) {
      if (doc is Map &&
          doc['doctype'] == 'DocType' &&
          doc['name'] == doctype) {
        return doc.cast<String, dynamic>();
      }
    }
    return null;
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/unit/global_search_metadata_test.dart`
Expected: PASS (all cases).

- [ ] **Step 6: Confirm no analyzer regressions**

Run: `flutter analyze lib/app/data/providers/api_provider.dart lib/app/data/services/global_search_service.dart`
Expected: no NEW issues (pre-existing `avoid_print` infos remain; the retained `catch (e)` still uses `e` in the print, so no unused-catch warning is introduced).

- [ ] **Step 7: Commit**

```bash
git add lib/app/data/providers/api_provider.dart lib/app/data/services/global_search_service.dart test/unit/global_search_metadata_test.dart
git commit -m "fix(search): fetch DocType metadata via getdoctype so operators get full-field search

The DocType resource API 403s for non-System-Manager users, leaving search
matching only the document name (e.g. item_code). Use the operator-reachable
frappe.desk.form.load.getdoctype endpoint instead.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (full project)**

Run: `flutter analyze`
Expected: issue count ≤ the current 386 baseline; no new issues referencing `api_provider.dart` or `global_search_service.dart` beyond the pre-existing lint. Grep aid: `flutter analyze 2>&1 | grep -Ei "api_provider|global_search_service|issues found"`.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass (existing + the new metadata test). If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout before treating it as a regression (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual, operator account)**

On a non-System-Manager operator account (e.g. the ALI NX1 / adnan login):
- Search a descriptive multi-word term (e.g. `belts reversible`) → the matching item(s) now appear (item_name is searched, not just item_code); the Default-Warehouse balance still shows on the Item rows.
- The `GlobalSearchService: Metadata fetch failed … DocType … 403` log no longer appears for the searched doctypes.
- Confirm a System-Manager account still searches correctly (no regression).

---

## Notes / deviations from the spec

- `_ensureMetadata` keeps its `print` on failure (now a genuine fallback signal, not the routine 403); the pre-existing `avoid_print` lint is unchanged.
- The networked `getDocTypeMeta` / `_ensureMetadata` path is verified on-device; the pure `extractDocTypeMeta` seam carries the unit coverage — consistent with the suite's DI-free convention.

## Versioning

Bundled with the pending multi-word commit for the next release; the bump tool
classifies the field at release time (search bugfix → at least PATCH).
