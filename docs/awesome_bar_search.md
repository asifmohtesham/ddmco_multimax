# Awesome Bar search

A mirror of the Frappe Framework v15 **Awesome Bar** (the Desk search box). Opened
from the Dashboard header search icon and from the nav drawer's **Search** item.
Type a document type, a report, a page, `new <doctype>`, `<text> in <doctype>`, a
calculation, or any text to full-text search documents.

Reference sources (Frappe `version-15`): `frappe/public/js/frappe/ui/toolbar/awesome_bar.js`,
`search_utils.js`, `fuzzy_match.js`, and `frappe/utils/global_search.py`.

## Files

| Concern | File |
|---|---|
| Fuzzy matcher (port of `fuzzy_match.js`) | `lib/app/data/utils/fuzzy_match.dart` |
| Safe calculator (replaces Frappe's `eval`) | `lib/app/data/utils/safe_calculator.dart` |
| Route argument for "Find *x* in …" | `lib/app/data/utils/awesome_bar_query.dart` |
| Option model, global-search hit, recent entry | `lib/app/data/models/awesome_bar_option.dart` |
| Option builders, dedupe/sort, recents store | `lib/app/data/services/awesome_bar_service.dart` |
| Full-text endpoint client | `GlobalSearchService.globalSearch` |
| UI (`SearchDelegate`) | `lib/app/modules/global_widgets/awesome_bar_delegate.dart` |
| Help sheet | `lib/app/modules/global_widgets/awesome_bar_help_sheet.dart` |
| Fuzzy-match highlight | `MatchIndexHighlight` in `search_highlight.dart` |

## Option types and indices

Every row is an `AwesomeBarOption` with Frappe's `{type, label, value, index,
route, match, recent}` shape. `index` is the sort key (higher first); the flat
list `AwesomeBarService.assemble` returns is exactly Frappe's, and the delegate
groups it for display (top rows, then Recents, Create a new…, Lists, Reports,
Pages, Find "x" in…, Documents, then Help).

| Type (`typeName`) | Label | Index | Source |
|---|---|---|---|
| `search` (Search) | Search for *txt* | 100 | always (query > 1 char) |
| `current` (Current) | Find *txt* in *current list* | 90 | only when opened with `currentDoctype`, and the text has no ` in` |
| `calculator` (Calculator) | *expr* = *result* | 80 | text starts with a digit, `(` or `=` and evaluates |
| `newDoc` (New) | New *DocType* | `1 + score` (after `new`), `score + 0.015` (plain) | `kGlobalSearchTargets` entries with `newArgs`, gated on `create` |
| `inList` (In List) | Find *x* in *DocType* | `1 + score` | `x in y` syntax; readable list screens |
| `list` (List) | *DocType* List | `score + 0.05` | `kNavCatalog` DocType links + ToDo, gated on `read` |
| `report` (Report) | Report *name* | `score` | `kNavCatalog` Report links, gated on the guard doctype's `report` permission |
| `page` (Page) | Open *page* | `score` | `kAwesomeBarPages` (Profile, User Area, Theme, Session Defaults, Notification Settings, About) |
| `recent` (no type) | *DocType* *name* / *DocType* List / *name* Report / *page* | 80 | recents store, substring match |
| `document` (no type) | document name + matched fields | 0 | `frappe.utils.global_search.search` |
| `help` (Help) | Help on Search | −10 | always last |

`set_specifics`: with more than one word, the text before the last space is
built and narrowed to the type whose name starts with the last word —
`delivery note list` yields only the List option, `delivery note new` only the New
option.

An empty (or one-character) field lists **Recents** (newest first) then
**frequent links** (top five by visit count, index = count), as Frappe does on
focus.

## Scoring

`fuzzyMatch(pattern, str)` is a character-exact port of Frappe's
`fuzzy_match.js`: every pattern character must appear in order (case
insensitive). A full match starts at 100 and adds/subtracts:

| Rule | Points |
|---|---|
| leading letters before the first match | −5 each, capped at −15 |
| unmatched letters | −1 each |
| first character matched | +15 |
| adjacent matches | +25 |
| match right after a space or `_` | +30 |
| lower→upper camel boundary | +30 |

The recursion (limit 10) explores alternative alignments and keeps the best.
`fuzzySearch` returns score 0 for no match (Frappe tests the score for
truthiness). Matched indices are emphasised in the row title by
`MatchIndexHighlight` (bold, primary colour, 13 % primary tint — the StatusPill
tint convention).

## Dedupe and ordering

`AwesomeBarService.deduplicate` mirrors Frappe: one option per `dedupeKey`
(`list:<DocType>`, `new:<DocType>`, `report:<name>`, `page:<route>`,
`form:<DocType>/<name>`). A later duplicate replaces the earlier one only when
its index is higher **and** it is not a recent. Options without a key (search,
current, calculator, help) are always kept. Then a stable sort by index
descending.

## Permissions

Builders take a `bool? Function(doctype, permType)` lookup. An option is kept
unless the answer is explicitly `false` (`null` = cache not yet warm, treated
permissively) — the same rule as `GlobalSearchService.filterPermittedTargets`.
The live lookup is `PermissionService.hasAccess`.

## Registries each builder reads

- `kNavCatalog` (`workspace_menu.dart`): list screens (`linkType: 'DocType'`) and
  report screens (`linkType: 'Report'`) with routes and guards. ToDo is added
  explicitly (it is a top-level drawer item, not in the catalog).
- `kGlobalSearchTargets` (`global_search_targets.dart`): the form route +
  `argsFor(id)` used to open recents and global results, and the new `newArgs` /
  `newRoute` create contract. `newArgs` is traced per doctype from each list
  screen's own create affordance; `null` (Item, Job Card) means no "New" option
  is ever offered. Packing Slip creates through its list's picker dialog, so
  its `newRoute` is the list with `{'openCreate': true}`.
- `kAwesomeBarPages`: the settings pages.
- `_kListsWithoutSearch` (Attendance, Purchase Receipt): lists with no local
  search, which "Find *x* in …" opens without a query.

## "Find *x* in *DocType*"

The option navigates to the list route with `{'awesomeBarQuery': x}`. Every list
controller that exposes `onSearchChanged` reads it in `onReady` through
`awesomeBarQueryArg()` and applies it as if typed — fifteen lists: Batch, BOM,
Delivery Note, Item, Job Card, Material Request, Packing Slip, POS Upload,
Purchase Order, Stock Entry, ToDo, Work Order, Sales Order, Item Price, Pricing
Rule.

## Full-text results

`GlobalSearchService.globalSearch(text, {start, limit, doctype})` calls
`frappe.utils.global_search.search` and parses `{message: [{doctype, name,
content, rank, image}]}`. The endpoint only covers DocTypes enabled in **Global
Search Settings** on the instance and uses MariaDB `MATCH … AGAINST`, so partial
tokens may not hit; the bar therefore shows these inline under **Documents** and
keeps "Search for *txt*", which opens the existing Dashboard fan-out
(`GlobalDocumentSearchDelegate`, LIKE per doctype) with the query pre-filled.

`AwesomeBarService.makeDescription` ports Frappe's `make_description`: from the
`"Label : value ||| Label : value"` content it keeps the fields whose value
contains the keyword, trims each value to 120 chars around the first match, caps
the whole line at 300 chars, joins with `, `, and never repeats the document
name. Hits for doctypes the app cannot open are dropped. Any endpoint error
(403, 417, not enabled) simply yields no Documents group.

The call is debounced 100 ms after the last keystroke and cached per query; a
`LinearProgressIndicator` under the field (an `RxBool busy`, set/cleared in a
`finally`, wrapped in its own `Obx`) shows while it is in flight. Nav options
render synchronously.

## Recents store

`AwesomeBarRecentsStore` persists per user through `StorageService`:

| Key | Value |
|---|---|
| `awesome_bar_recent::<user>` | up to 20 `AwesomeBarRecent` JSON rows, newest first, deduplicated by `kind:name:docname` |
| `awesome_bar_visits::<user>` | `{key: count}` visit counter (frequent links), capped at 200 keys |

Entries are recorded from `GetMaterialApp.routingCallback` in `main.dart` on
every forward navigation (`isBack`, dialogs and sheets are skipped), resolved
through the registries: a form route with a `name` / `itemCode` argument (not
`mode: 'new'`) → `form`; a list, report or page route → `list` / `report` /
`page`. Both keys are cleared for the signing-out user in
`AuthenticationController._clearSessionAndLocalData`.

## Deliberately not ported

- Tag search (`#tag`) — the app has no tag UI.
- `get_marketplace_apps`, `get_executables` / `make_function_searchable`,
  `make_random` (random password) — no app equivalent.
- The "*DocType* Report" (report-builder view of a list) — the app has no report
  view of a list.
- Workspaces / dashboards as pages — the drawer groups are not navigable targets.
- Frappe's `eval` calculator — replaced with `safe_calculator.dart`
  (`+ - * / % ^`, parentheses, decimals, unary minus; identifiers never run).

## Tests

- `test/unit/fuzzy_match_test.dart` — hand-computed score parity.
- `test/unit/safe_calculator_test.dart`.
- `test/unit/awesome_bar_options_test.dart` — builders, `set_specifics`,
  permissions, dedupe, recents, global-result mapping.
- `test/unit/global_search_description_test.dart` — `make_description` and the
  endpoint response parser.
- `test/unit/awesome_bar_recents_test.dart` — store cap/dedupe/per-user/clear and
  route resolution.
- `test/widget/awesome_bar_delegate_test.dart` — sections, highlight, dark-mode
  inks, busy flag, "Search for" hand-off, navigation with arguments, Documents
  group, Escape, calculator dialog.
