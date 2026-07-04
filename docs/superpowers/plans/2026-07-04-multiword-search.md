# Multi-word Global Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Dashboard/voice search match multi-word queries as "all words, any order" instead of requiring the exact contiguous phrase.

**Architecture:** Tokenize the query; ≥2 tokens run one server request that ORs every (field × token) LIKE (a superset), then a pure client-side filter keeps only rows containing every token. A new opt-in `orFilterTuples` param on `getDocumentList` carries the per-token OR conditions (the existing `orFilters` Map can't hold two LIKEs on one field).

**Tech Stack:** Flutter, GetX, Dio (via `ApiProvider`), Frappe `/api/resource` list filters, `flutter_test`.

## Global Constraints

- **1-token (or empty) queries behave exactly as today** — single `LIKE %query%` across fields, `limit: 20`, no client filtering.
- Multi-token match = **all words, any order**, each a case-insensitive substring across the searchable fields. No plural/singular stemming.
- The new `getDocumentList` param `orFilterTuples` is additive and default-null; every existing caller (which passes only `orFilters`) is unchanged. Do NOT rename the existing local `orFilterList` inside the provider's OR block.
- Multi-token server `limit` is **50** (superset headroom before the client AND-filter).
- No new analyzer warnings/errors in touched files.

---

### Task 1: Tokenized multi-word matching

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (add `orFilterTuples` param + prefer it in the OR block)
- Modify: `lib/app/data/services/global_search_service.dart` (tokenize + multi-token request + client filter; add `searchTokens`/`rowMatchesAllTokens`)
- Test: `test/unit/global_search_tokens_test.dart` (create)

**Interfaces:**
- Consumes: `ApiProvider.getDocumentList(String doctype, {..., Map<String,dynamic>? orFilters, List<List<dynamic>>? orFilterTuples, int limit, List<String>? fields})` → `Future<Response>` with `response.data['data']` a `List`.
- Produces: `static List<String> GlobalSearchService.searchTokens(String query)`; `static bool GlobalSearchService.rowMatchesAllTokens(Map<String,dynamic> row, List<String> fields, List<String> tokens)`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/global_search_tokens_test.dart`:

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

  group('rowMatchesAllTokens', () {
    const fields = ['name', 'item_name'];

    test('matches all tokens in any order, case-insensitive', () {
      final row = {'name': 'FG-1', 'item_name': 'Reversible Belts 30mm'};
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['belts', 'reversible']),
          isTrue);
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['REVERSIBLE', 'BELTS']),
          isTrue);
    });

    test('fails when a token is absent', () {
      final row = {'name': 'FG-1', 'item_name': 'Reversible Belts 30mm'};
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['belts', 'strap']),
          isFalse);
    });

    test('matches a token found in the code (name) field', () {
      final row = {'name': 'BELT-RED-01', 'item_name': 'Reversible'};
      expect(
          GlobalSearchService.rowMatchesAllTokens(
              row, fields, ['belt', 'reversible']),
          isTrue);
    });

    test('empty tokens -> true (no constraint)', () {
      expect(GlobalSearchService.rowMatchesAllTokens({'name': 'x'}, fields, []),
          isTrue);
    });

    test('missing field is treated as empty', () {
      final row = {'name': 'FG-1'}; // no item_name key
      expect(GlobalSearchService.rowMatchesAllTokens(row, fields, ['fg-1']),
          isTrue);
      expect(GlobalSearchService.rowMatchesAllTokens(row, fields, ['belts']),
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/global_search_tokens_test.dart`
Expected: FAIL — `searchTokens` / `rowMatchesAllTokens` not defined.

- [ ] **Step 3: Add the `orFilterTuples` param to the provider**

In `lib/app/data/providers/api_provider.dart`, add the param to `getDocumentList`'s signature (after `Map<String, dynamic>? orFilters,`, line 207):

```dart
    Map<String, dynamic>? orFilters,
    List<List<dynamic>>? orFilterTuples,
```

Replace the OR-filter block (lines 245–258) with a version that prefers the explicit tuples (do NOT rename the existing `orFilterList` local — it stays in the else branch):

```dart
    // Process OR Filters. An explicit pre-built tuple list (each entry a complete
    // Frappe [doctype, field, op, value]) wins; otherwise expand the Map form.
    if (orFilterTuples != null && orFilterTuples.isNotEmpty) {
      queryParameters['or_filters'] = json.encode(orFilterTuples);
    } else if (orFilters != null && orFilters.isNotEmpty) {
      final List<List<dynamic>> orFilterList = orFilters.entries.map((entry) {
        final val = entry.value;
        if (val is List) {
          if (val.length == 4) return List<dynamic>.from(val);
          if (val.length == 3) return [entry.key, val[0], val[1], val[2]];
          if (val.length == 2) return [doctype, entry.key, val[0], val[1]];
        }
        return [doctype, entry.key, '=', val];
      }).toList();

      queryParameters['or_filters'] = json.encode(orFilterList);
    }
```

- [ ] **Step 4: Tokenize the search + add the helpers**

In `lib/app/data/services/global_search_service.dart`, replace the "3. Construct Query" → "5. Map to Model" section inside `search` (currently lines 59–82, from `// 3. Construct Query` through the `return data.map(...)` block) with:

```dart
      // 3. Tokenise the query. ≤1 token keeps the classic single-phrase LIKE;
      // ≥2 tokens match "all words, any order" (server OR superset + client AND).
      final fieldSet = searchTargets.toSet();
      final tokens = searchTokens(query);

      if (kDebugMode) {
        print('GlobalSearchService: Searching "$query" $tokens in $doctype '
            'on fields: $searchTargets');
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
              orFilterTuples: [
                for (final field in fieldSet)
                  for (final token in tokens)
                    [doctype, field, 'like', '%$token%'],
              ],
              limit: 50,
              fields: selectFields.toSet().toList(),
            );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List data = response.data['data'];
        // 5. For multi-token queries, keep only rows containing EVERY token.
        final searchFields = fieldSet.toList();
        final rows = tokens.length <= 1
            ? data
            : data
                .where((e) => rowMatchesAllTokens(
                    e as Map<String, dynamic>, searchFields, tokens))
                .toList();
        return rows.map((e) => _mapToModel(e, meta)).toList();
      }
```

Add the two pure statics inside the `GlobalSearchService` class (e.g. just after the `search` method):

```dart
  /// Whitespace-separated, non-empty search tokens from [query]. Pure.
  static List<String> searchTokens(String query) => query
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// True when EVERY token in [tokens] appears (case-insensitive substring) in
  /// the concatenation of [fields]' values on [row] — "all words, any order".
  /// Pure. Empty [tokens] → true (no constraint).
  static bool rowMatchesAllTokens(
    Map<String, dynamic> row,
    List<String> fields,
    List<String> tokens,
  ) {
    final hay =
        fields.map((f) => (row[f] ?? '').toString()).join(' ').toLowerCase();
    return tokens.every((t) => hay.contains(t.toLowerCase()));
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/unit/global_search_tokens_test.dart`
Expected: PASS (all cases).

- [ ] **Step 6: Confirm no analyzer regressions**

Run: `flutter analyze lib/app/data/providers/api_provider.dart lib/app/data/services/global_search_service.dart`
Expected: no NEW issues (the pre-existing `avoid_print` infos in the service remain; no unused-variable/`late` errors — `response` is a plain `final` conditional expression).

- [ ] **Step 7: Commit**

```bash
git add lib/app/data/providers/api_provider.dart lib/app/data/services/global_search_service.dart test/unit/global_search_tokens_test.dart
git commit -m "feat(search): match multi-word queries as all-words-any-order

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (full project)**

Run: `flutter analyze`
Expected: issue count ≤ the current 386 baseline; no new issues referencing `api_provider.dart` or `global_search_service.dart` beyond the pre-existing `avoid_print` infos. Grep aid: `flutter analyze 2>&1 | grep -Ei "api_provider|global_search_service|issues found"`.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass (existing + the new tokens test). If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout before treating it as a regression (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual)**

Verify on device:
- Search `belts reversible` (or the real two-word case that failed) → the matching item(s) now appear regardless of word order; the Default-Warehouse balance still shows on the Item rows.
- Reverse the word order (`reversible belts`) → same results.
- A single-word search still works exactly as before.
- A two-word query where only one word matches any item → no results (AND semantics), not a flood.

---

## Notes / deviations from the spec

- The multi-token client filter runs over `searchTargets` (the fields actually searched: `name` + validated `search_fields`), which are a subset of `selectFields`, so the values are present on each returned row.
- The networked `search` path (server OR + client AND end to end) is covered by the on-device smoke; the pure `searchTokens`/`rowMatchesAllTokens` seams carry the unit coverage — consistent with the suite's DI-free convention.

## Versioning

New search capability → **MINOR** at release time per `docs/versioning_conventions.md`. Not part of this plan.
