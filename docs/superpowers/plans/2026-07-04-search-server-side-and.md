# Server-side AND for multi-word search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ≥2-word search AND its tokens server-side on the doctype's primary field, so "belts reversible" returns all matching items (not one truncated by the OR-superset).

**Architecture:** Add an additive AND-list param `filterTuples` to `getDocumentList` (symmetric to `orFilterTuples`). In `GlobalSearchService.search`, the ≥2-token path ANDs each token on the primary field (`title_field` → first non-name search field → `name`) via `filterTuples`; the client-side `rowMatchesAllTokens` filter is removed (server is authoritative). Single-token search is unchanged.

**Tech Stack:** Flutter, GetX, Dio (via `ApiProvider`), Frappe `/api/resource` `filters`, `flutter_test`.

## Global Constraints

- 1-token/empty query unchanged (OR phrase across all `searchTargets`, `limit 20`).
- ≥2 tokens: server ANDs each token on the primary field via `filterTuples`, `limit 20`, NO client-side filtering.
- Primary field = `meta['title_field']` if a non-empty String; else the first `searchTargets` entry that isn't `'name'`; else `'name'`.
- `filterTuples` is additive/default-null on `getDocumentList`; when set it is the `filters` payload as-is; existing `filters`-Map callers unchanged.
- Remove the now-dead `rowMatchesAllTokens` (and its tests); keep `searchTokens`.
- No new analyzer warnings/errors in touched files.

---

### Task 1: Server-side AND matching

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (add `filterTuples`)
- Modify: `lib/app/data/services/global_search_service.dart` (≥2-token server AND; `resolvePrimarySearchField`; remove `rowMatchesAllTokens`)
- Test: `test/unit/global_search_tokens_test.dart` (drop `rowMatchesAllTokens` group; add `resolvePrimarySearchField`)

**Interfaces:**
- Consumes: `ApiProvider.getDocumentList(String doctype, {..., Map<String,dynamic>? filters, List<List<dynamic>>? filterTuples, Map<String,dynamic>? orFilters, int limit, List<String>? fields})` → `Future<Response>`.
- Produces: `static String GlobalSearchService.resolvePrimarySearchField(Map<String,dynamic>? meta, List<String> searchTargets)`.

- [ ] **Step 1: Rewrite the unit test**

Overwrite `test/unit/global_search_tokens_test.dart` with (keeps `searchTokens`, replaces the `rowMatchesAllTokens` group with `resolvePrimarySearchField`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('searchTokens', () {
    test('splits on whitespace, drops empties', () {
      expect(GlobalSearchService.searchTokens('belts reversible'),
          ['belts', 'reversible']);
      expect(GlobalSearchService.searchTokens('  a   b '), ['a', 'b']);
      expect(GlobalSearchService.searchTokens('single'), ['single']);
      expect(GlobalSearchService.searchTokens(''), isEmpty);
      expect(GlobalSearchService.searchTokens('   '), isEmpty);
    });
  });

  group('resolvePrimarySearchField', () {
    test('uses title_field when present', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {'title_field': 'item_name'}, ['name', 'item_name']),
          'item_name');
    });

    test('falls back to the first non-name search target', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {}, ['name', 'item_name', 'item_group']),
          'item_name');
    });

    test('falls back to name when only name is searchable', () {
      expect(GlobalSearchService.resolvePrimarySearchField({}, ['name']),
          'name');
    });

    test('null meta falls back to the searchTargets rule', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(null, ['name']), 'name');
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              null, ['name', 'customer_name']),
          'customer_name');
    });

    test('empty / non-String title_field is ignored', () {
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {'title_field': ''}, ['name', 'item_name']),
          'item_name');
      expect(
          GlobalSearchService.resolvePrimarySearchField(
              {'title_field': 1}, ['name', 'item_name']),
          'item_name');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/global_search_tokens_test.dart`
Expected: FAIL — `resolvePrimarySearchField` not defined (and the old `rowMatchesAllTokens` group is gone).

- [ ] **Step 3: Add the `filterTuples` param to the provider**

In `lib/app/data/providers/api_provider.dart`, add the param to `getDocumentList`'s signature (right after `Map<String, dynamic>? filters,`, line 206):

```dart
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
```

Replace the "Process Standard Filters (AND)" block (currently lines 224–243, the `if (filters != null && filters.isNotEmpty) { … }`) with a version that prefers the tuple list:

```dart
    // Process Standard Filters (AND). An explicit pre-built tuple list (each
    // entry a complete Frappe [doctype, field, op, value]) wins; otherwise
    // expand the Map form.
    if (filterTuples != null && filterTuples.isNotEmpty) {
      queryParameters['filters'] = json.encode(filterTuples);
    } else if (filters != null && filters.isNotEmpty) {
      final List<List<dynamic>> filterList = filters.entries.map((entry) {
        final val = entry.value;
        if (val is List) {
          if (val.length == 4) return List<dynamic>.from(val);
          if (val.length == 3) return [entry.key, val[0], val[1], val[2]];
          if (val.length == 2) return [doctype, entry.key, val[0], val[1]];
        }
        return [doctype, entry.key, '=', val];
      }).toList();

      queryParameters['filters'] = json.encode(filterList);
    }
```

(If the current Map-expansion lambda differs from the above, keep the file's existing lambda body verbatim — only wrap it in the `else if` and add the `filterTuples` branch above it.)

- [ ] **Step 4: Switch the ≥2-token path to server-side AND + add the resolver**

In `lib/app/data/services/global_search_service.dart`, replace the block from `// 3. Tokenise…` through the `if (response.statusCode == 200 …) { … }` (currently lines 59–101) with:

```dart
      // 3. Tokenise. ≤1 token → single-phrase LIKE across all fields (matches
      // code OR name). ≥2 tokens → AND each token on the PRIMARY field
      // server-side (all-words, any order) so genuine matches aren't diluted by
      // an OR-superset.
      final fieldSet = searchTargets.toSet();
      final tokens = searchTokens(query);
      final primaryField = resolvePrimarySearchField(meta, searchTargets);

      if (kDebugMode) {
        print('GlobalSearchService: Searching "$query" $tokens in $doctype '
            'on fields: $searchTargets (primary: $primaryField)');
      }

      // 4. API Call
      final response = tokens.length <= 1
          ? await _apiProvider.getDocumentList(
              doctype,
              orFilters: {
                for (final field in fieldSet) field: ['like', '%$query%'],
              },
              limit: 20,
              fields: selectFields.toSet().toList(),
            )
          : await _apiProvider.getDocumentList(
              doctype,
              filterTuples: [
                for (final token in tokens)
                  [doctype, primaryField, 'like', '%$token%'],
              ],
              limit: 20,
              fields: selectFields.toSet().toList(),
            );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List data = response.data['data'];
        // The AND ran server-side, so the result is authoritative — no filter.
        return data.map((e) => _mapToModel(e, meta)).toList();
      }
```

Then DELETE the now-unused `rowMatchesAllTokens` method (currently lines 115–126, the `/// True when EVERY token …` doc comment through its closing brace). Keep `searchTokens` immediately above it.

Add the resolver right after `searchTokens` (where `rowMatchesAllTokens` used to be):

```dart
  /// The field to AND multi-word tokens against server-side: the doctype's
  /// [title_field] when it is a non-empty String (e.g. `item_name` for Item),
  /// else the first search target that isn't `name`, else `name`. Pure.
  static String resolvePrimarySearchField(
    Map<String, dynamic>? meta,
    List<String> searchTargets,
  ) {
    final title = meta?['title_field'];
    if (title is String && title.isNotEmpty) return title;
    for (final f in searchTargets) {
      if (f != 'name') return f;
    }
    return 'name';
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/unit/global_search_tokens_test.dart`
Expected: PASS (`searchTokens` + `resolvePrimarySearchField`).

- [ ] **Step 6: Confirm no analyzer regressions**

Run: `flutter analyze lib/app/data/providers/api_provider.dart lib/app/data/services/global_search_service.dart`
Expected: no NEW issues; specifically no "unused element `rowMatchesAllTokens`" (it was deleted) and no unused-import from its removal. Pre-existing `avoid_print` infos remain.

- [ ] **Step 7: Commit**

```bash
git add lib/app/data/providers/api_provider.dart lib/app/data/services/global_search_service.dart test/unit/global_search_tokens_test.dart
git commit -m "fix(search): AND multi-word tokens server-side on the primary field

The OR-superset + client-AND truncated genuine all-word matches (e.g. 'belts
reversible' returned 1 of 51). AND the tokens server-side on the doctype's
primary text field instead so real matches aren't diluted.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (full project)**

Run: `flutter analyze`
Expected: issue count ≤ the current 386 baseline; no new issues referencing `api_provider.dart` or `global_search_service.dart`. Grep aid: `flutter analyze 2>&1 | grep -Ei "api_provider|global_search_service|issues found"`.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass. The `rowMatchesAllTokens` tests are gone; `resolvePrimarySearchField` + `searchTokens` pass. If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual, operator account)**

On a non-System-Manager operator account:
- Search `belts reversible` → returns the belt items (up to the display cap of 8 per group), not one.
- Reverse to `reversible belts` → same set (order-independent within the field).
- A single word (`belts`) still returns results (unchanged path).
- A pure item-code fragment still finds items by code (single-token OR path unaffected).

---

## Notes / deviations from the spec

- Multi-token `limit` stays 20 (pagination is Part 2). No client filter now that the AND is server-side.
- `resolvePrimarySearchField` picks one field to AND on — a deliberate trade-off (multi-word matches within the primary/title field, not across code+name). Single-token search is unchanged and still ORs across all fields.

## Versioning

Search behaviour fix → **PATCH** at release time (bundle with Part 2 if it lands first).
