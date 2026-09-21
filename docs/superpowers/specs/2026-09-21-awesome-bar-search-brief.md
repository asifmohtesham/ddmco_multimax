# Awesome Bar search — implementation prompt

Date: 2026-09-21 · Branch: `claude/awesome-bar-search-mirror-0le634` · Release: MINOR (`feat:`; do **not** bump `pubspec.yaml` — releases are separate `chore(release)` commits)

The text below is a self-contained prompt. Paste it verbatim into a fresh Claude Code session on this repository.

---

## Prompt

Implement a Flutter mirror of the Frappe Framework **Awesome Bar** (the desk search box, Frappe v15) in this Multimax app. Read `CLAUDE.md` first and follow every convention in it: GetX patterns, async feedback, list/report screen rules, and the contrast rules. Work on the current branch, commit in small conventional-commit steps (`feat(search): …`, `test(search): …`), and push when done. Do not bump the version.

### What the Awesome Bar does (reference behaviour)

Reference sources, Frappe `version-15`:

- `frappe/public/js/frappe/ui/toolbar/awesome_bar.js` — input handling, option assembly, dedupe, ordering.
- `frappe/public/js/frappe/ui/toolbar/search_utils.js` — the option builders (`get_creatables`, `get_search_in_list`, `get_doctypes`, `get_reports`, `get_pages`, `get_recent_pages`, `get_frequent_links`, `get_global_results`, `fuzzy_search`).
- `frappe/public/js/frappe/ui/toolbar/fuzzy_match.js` — the scoring algorithm (a port of Forrest Smith's `fts_fuzzy_match`).
- `frappe/utils/global_search.py` — the whitelisted `search(text, start=0, limit=20, doctype="")` endpoint.

Fetch and read these before writing code. The behaviour to mirror, precisely:

1. **Input.** Debounce 100 ms. Trim, collapse runs of whitespace to one space. If the text is longer than one character, build options; otherwise show **Recents** (recently opened documents and screens) followed by **Frequent links** (most-visited screens). The list is shown as soon as the field gains focus.
2. **Every option** is `{type, label, value, index (score), route or onclick, match, recent}`. Options are deduplicated by route (a later option replaces an earlier one only if its index is higher **and** the earlier one is not a recent) and then sorted by `index` descending. The same route with a `List` prefix is normalised to `List/<DocType>` before comparison.
3. **Default options** added for every query (`add_defaults`):
   - "Search for *txt*" — index 100. Opens the full document search.
   - "Find *txt* in *current list*" — index 90, only when the bar was opened from a list screen.
   - Calculator — index 80, when the text starts with a digit, `(` or `=`. Frappe uses `eval`; you must **not**. Write a small safe arithmetic evaluator (`+ - * / % ^`, parentheses, decimals, unary minus). Show "*expr* = *result*"; tapping it shows the result in a dialog.
   - "Help on Search" — index −10, always last. Opens a help sheet with the same table Frappe shows (create a new record, list a document type, search in a document type, open a module or tool, calculate).
4. **Built options** (`build_options`), each scored with the fuzzy matcher (score 0 = no match, omitted):
   - `get_creatables`: when the first word is `new`, fuzzy-match the rest against every DocType the user can **create** → "New *DocType*", index `1 + score`, opens a blank form.
   - `get_search_in_list`: when the text contains ` in ` (and does not end with `in`), split on ` in `; fuzzy-match the right part against readable DocTypes → "Find *left* in *DocType*", index `1 + score`, opens that list with the search pre-filled.
   - `get_doctypes`: fuzzy-match the whole text against every **readable** DocType. For each hit emit "*DocType* List" (index `score + 0.05`) and, if the user can create it, "New *DocType*" (index `score + 0.015`). Frappe also emits a "Report" view; this app has no report view of a list, so omit it. Frappe skips the word "List" when the DocType name already ends in "List".
   - `get_reports`: fuzzy-match against the app's report screens → "Report *name*", index `score`.
   - `get_pages` / `get_workspaces`: fuzzy-match against the app's non-DocType screens (Profile, Theme, Session Defaults, Notification Settings, About) → "Open *name*", index `score`. Skip Hub / Calendar / Email Inbox.
   - `get_recent_pages`: filter recents by substring, index 80, `recent: true`.
   - Tag search (`#`) and `get_marketplace_apps` / `get_executables` / `make_random`: **out of scope**, do not port.
   - `set_specifics`: if the text has more than one word, build options for everything before the last space and keep only those whose `type` starts with the last word (case-insensitive). So `delivery note list` yields only the List option and `delivery note new` only the New option.
5. **Global (full-text) results.** Frappe appends results from `frappe.utils.global_search.search` under the nav options. The response is a list of `{doctype, name, content, rank, image?}` where `content` is `"Label : value ||| Label : value …"`. Port `make_description`: keep only the fields whose value contains the keyword, trim each value to 120 chars around the first match, cap the whole description at 300 chars, join with `", "`, and never repeat the document name as a field. Group by `doctype`, in the order the server returns.
6. **Selection.** Navigate, then clear the input and dismiss the bar. Keyboard: Escape closes.
7. **Fuzzy matcher.** Port `fuzzy_match.js` exactly (constants: sequential +25, separator +30, camel +30, first letter +15, leading letter −5 capped at −15, unmatched −1; recursion limit 10; base 100 on a full match). Return `(score, matchIndices)`. Render matched characters emphasised, the way Frappe wraps them in `<mark>`.

### Where it lives in this app

Existing code you must build on, not duplicate:

- `lib/app/modules/global_widgets/global_document_search_delegate.dart` — the Dashboard "Search documents" overlay (a `SearchDelegate` that fans out `GlobalSearchService.searchAll` over `kDiscoverableSearchTargets`). Keep it. It becomes the target of "Search for *txt*" — open it with `showSearch(context: …, delegate: GlobalDocumentSearchDelegate(), query: txt)` so the query is pre-filled.
- `lib/app/data/services/global_search_service.dart` — per-DocType `get_list` LIKE search with cached `getdoctype` metadata. Add a `globalSearch(text, {start, limit, doctype})` method here that calls `frappe.utils.global_search.search` through `ApiProvider.callMethod` and maps the response (see point 5). If the endpoint errors (403, 417, not enabled in Global Search Settings) or returns an empty list, the bar simply shows no "Documents" group. Do not fall back to the fan-out inside the bar; the fan-out is what "Search for *txt*" opens.
- `lib/app/data/constants/global_search_targets.dart` — `kGlobalSearchTargets` is the canonical "open this document" registry: DocType → form route + `argsFor(id)`. Use it to open global results and recents. Add a nullable `newArgs` (the argument map that opens the form in create mode) per target, but **only after tracing each form controller's create contract** — it is not uniform (`{'mode': 'new'}` for Purchase Receipt, Packing Slip, Stock Entry, Delivery Note; others differ or have no create path from a bare route). A target with `newArgs == null` never produces a "New *DocType*" option.
- `lib/app/modules/global_widgets/workspace_menu.dart` — `kNavCatalog` lists every list screen (`linkType: 'DocType'`) and report screen (`linkType: 'Report'`) with its route and `PermEntry` guard. This is the source for "*DocType* List", "Report *name*", and "Find *x* in *DocType*".
- `lib/app/data/services/permission_service.dart` — `hasAccess(doctype, permType: 'read' | 'create' | 'report')` returns `null` while loading. Follow `GlobalSearchService.filterPermittedTargets`: keep an option unless the answer is explicitly `false`. Frappe's `can_read` / `can_create` / `can_search` lists map onto these checks.
- `lib/app/data/services/storage_service.dart` — add a per-user recents store (key `awesome_bar_recent:<user>`), capped at 20 entries, newest first, deduplicated by route+arguments, and a per-user visit counter for frequent links. Record entries from `GetMaterialApp.routingCallback` in `lib/main.dart` (it already forwards the current route to `HomeController`), resolving route + `Get.arguments` back to a DocType/document through the registries above. Clear both on logout wherever `PermissionService.clearCache()` is called.
- `lib/app/modules/global_widgets/search_highlight.dart` — reuse `SearchHighlight` (or extend it with an index-based variant) to emphasise matched characters.
- `lib/app/data/routes/app_routes.dart` — settings/page routes for the "Open *name*" options: `PROFILE`, `THEME`, `SESSION_DEFAULTS`, `NOTIFICATION_SETTINGS`, `ABOUT`.

Entry points:

- Replace the Dashboard header search action in `lib/app/modules/home/home_screen.dart` (currently `showSearch(delegate: GlobalDocumentSearchDelegate())`) with the Awesome Bar. The hint text is "Search or type a command…".
- Add the same action to `lib/app/modules/global_widgets/app_nav_drawer.dart` so it is reachable from every screen.
- Accept an optional `currentDoctype` so a list screen can later offer "Find *txt* in *this list*". Do not wire it into `DocTypeListHeader` in this task; that header owns its own in-list search.

"Find *x* in *DocType*" needs the list screen to accept an initial query. Check whether the list controllers read anything like `Get.arguments['search']`. If not, define one argument key (`'awesomeBarQuery'`) and consume it in the controllers that already expose a search `RxString` (see the nine lists in commit `094ddc1`). For lists without local search, open the list without a query.

### Files to create

```
lib/app/data/utils/fuzzy_match.dart                       # port of fuzzy_match.js, pure
lib/app/data/utils/safe_calculator.dart                   # arithmetic evaluator, pure
lib/app/data/models/awesome_bar_option.dart               # option model + type enum
lib/app/data/services/awesome_bar_service.dart            # option builders, dedupe, sort, recents; injectable registries
lib/app/modules/global_widgets/awesome_bar_delegate.dart  # SearchDelegate UI
lib/app/modules/global_widgets/awesome_bar_help_sheet.dart
test/unit/fuzzy_match_test.dart
test/unit/safe_calculator_test.dart
test/unit/awesome_bar_options_test.dart
test/unit/awesome_bar_recents_test.dart
test/unit/global_search_description_test.dart
test/widget/awesome_bar_delegate_test.dart
```

Keep every builder in `AwesomeBarService` a **pure static function** that takes the registries, the permission lookup, and the recents as parameters (the pattern `GlobalSearchService.runSearchAll` already uses), so the unit tests need no GetX.

### UI rules that apply

- The suggestions list is a vertically scrollable result list: `Scrollbar` sharing one `ScrollController`, bottom padding from `MediaQuery.padding.bottom`, and an end-of-list marker (`ListEndFooter`).
- Section headers in Frappe's order: Recents, Create a new…, Lists, Reports, Pages, Find "x" in…, Documents (the global results), then the calculator and help rows. Empty sections are dropped.
- Colours only through `context.scheme` / `colorScheme` and the `AppColors` ramp; status tints at alpha 0.13 / borders at 0.35. Never `Colors.white`, `grey.shadeX`, or `black87`. Run `test/unit/theme_contrast_test.dart` and the dark-mode widget tests.
- The global results call is async: show a linear progress indicator under the field while it is in flight, keyed on an `RxBool` set and cleared in a `finally`, with a re-entrancy guard. Nav options render immediately; the Documents group appends when the call returns. Cancel any `ever` worker in `onClose`.
- Follow the build-phase safety note at the top of `global_search_delegate.dart`: never write an Rx value synchronously inside `buildSuggestions`; defer with `addPostFrameCallback`.

### Tests (write these; a clean `flutter analyze` proves nothing)

- Fuzzy matcher: exact score parity with Frappe for a fixture table you compute by hand from the constants (e.g. `dn` vs `Delivery Note` scores the camel/separator bonuses; `xyz` vs `Item` returns 0; leading-letter penalty caps at −15).
- Calculator: `(55 + 434) / 4` = 122.25, `=2^10` = 1024, `1/0` yields no option, `12abc` yields no option, `1 + ` yields no option.
- Option assembly: `new deliv` → only creatable DocTypes; `stock in item` → "Find stock in Item"; `item list` keeps only the List option; a DocType with `hasAccess == false` is absent while `null` is kept; a recent is never displaced by a higher-scoring duplicate; ordering is by index descending with "Search for" first and "Help on Search" last.
- Description builder: the `" ||| "` / `" : "` / `" &&& "` separators, the 120/300 caps, and that the document name never appears as a field.
- Recents store: cap 20, dedupe, newest first, per-user isolation, cleared on logout.
- Widget: dark-mode surfaces, progress indicator toggles with the busy flag, tapping "Search for x" opens `GlobalDocumentSearchDelegate` with the query pre-filled (inject a `voicePrompt`/service stub as the existing widget test does), tapping a List option navigates with the right route.

### Documentation

- Add `docs/awesome_bar_search.md` describing the option types, the scoring, the registries each builder reads, the recents store keys, and what was deliberately not ported (tags, marketplace, executables, random password, report view).
- Add a `docs/` bullet for it in `CLAUDE.md` under "Codebase Docs", and mention the bar in the `Key Shared Widgets` list.

### Definition of done

- `flutter analyze` clean; `flutter test` green, including every new test above.
- The bar works on a device against `erp.domain.com`: typing `new stock` offers "New Stock Entry"; `item list` opens the Item list; `dn 0012` shows Delivery Note documents from the global search endpoint (if Global Search Settings on the instance include Delivery Note; otherwise the Documents group is absent and nothing errors); a previously opened Delivery Note appears under Recents when the field is empty.
- Commits pushed to the current branch. Do not open a pull request unless asked.

---

## Notes for the person running the prompt

- The full-text endpoint only covers DocTypes listed in **Global Search Settings** on the ERPNext instance and uses MariaDB `MATCH … AGAINST`, so it will not find partial tokens the way the app's LIKE fan-out does. That is why the prompt keeps both: inline global results in the bar, and "Search for *txt*" opening the existing fan-out.
- The `newArgs` tracing step is the riskiest part; a wrong argument map throws in the form controller's `onInit`. Insist on the trace being documented in the registry comments, as `argsFor` already is.
