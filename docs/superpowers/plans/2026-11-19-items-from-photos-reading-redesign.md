# Items from Photos Reading Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The review list opens at once with a row per photo, photos are read in two rounds while rows stay usable, and a ready row opens into a card with the rack-wise balance and stock ageing.

**Architecture:** The decoder's single `decode` becomes two steps (`readWhole`, `zoomIn`) that the controller drives from one reading loop over the review list itself: each photo is one placeholder entry with a `stage` until it settles, when it is replaced in place by today's item rows. Item and stock answers are cached by item code; Stock Ageing is fetched per item when a card is first opened. The list widget renders stages; a pure `ReadingStatus` gives the strip's text.

**Tech Stack:** Flutter 3.50, GetX (`.obs`, `Obx`), `mobile_scanner` 7.4 (ML Kit), `image` 4.3, Dio via `ApiProvider`; tests with `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-19-items-from-photos-reading-redesign-design.md` (read it first; its mock-up is the `…-prototype.html` beside it). Feature context: `docs/items_from_photos.md`. Project rules: `CLAUDE.md`.

## Global Constraints

- Start from `claude/reverent-wozniak-04950e` (it holds the tile fallback, `logic/grey_plane.dart` and the injectable analyser this plan builds on). Do not merge into `release/play-store`, bump, tag, push or deploy.
- British English in code comments, docs, commit messages and UI copy.
- UI copy is exact, including the ellipsis character `…`: "Not read yet", "Reading…", "Waiting to zoom in", "Zooming in…", "Checking stock…", "In stock", "Out of stock", "Reading photo n of N", "Zooming in on photo n of N…", "k read", "k read · m to go", "N photos · M items so far", "N photos · M items in the file", "Generate file · M items", "Photo n", "Photo n · k items so far", "Rack-Wise Stock Balance", "Rack", "Balance Qty", "No rack", "No stock in Finished Goods - KA.", "Stock Ageing", "Fetching Stock Ageing…", "Not in the Stock Ageing report.", "Not in the Stock Ageing report: nothing in stock.", "Couldn't load Stock Ageing.", "Retry", "You don't have access to Stock Ageing.". Unchanged copy stays as in `docs/items_from_photos.md` §5.
- ML Kit reads are strictly one at a time (`mobile_scanner`'s Android side keeps one pending result).
- Tile geometry, `GreyPlane`, the codec and the file writers are not touched. Balance Qty, racks and ageing never reach the file.
- Colours: no hard-coded surfaces or inks. Pills use the `AppColors` ramp: fill x500 at alpha 0.13, border x500 at alpha 0.35, text x700 in light and x300 in dark (green for In stock, red for Out of stock, orange for Zooming in). Spinners on the pill take the pill's text colour.
- Server: standard methods only; never branch on the server version; v15 and v16 both. Stock Ageing uses the existing `ApiProvider.runStockAgeingCustom`.
- List conventions hold: `Scrollbar` sharing the list's `ScrollController`, bottom nav-bar padding, "End of list".
- CI runs no tests: run `flutter analyze` and the named tests locally in every task; run the full suite on sys6 at the end (three Windows-only failures are known: two in `stock_ageing_controller_test.dart`, one in `items_from_photos_controller_test.dart` "empty, relative and root folders are not clean-up roots").
- On this machine call Flutter as `flutter` (snap); if the sandbox blocks it, use `~/snap/flutter/common/flutter/bin/flutter`. `flutter` runs may rewrite `linux/ macos/ windows/` generated plugin files: `git checkout --` them before committing.

## Review Focus

Conditions the spec implies and a person will meet; each has its test in the task named.

1. A row removed while its stock answer is in flight, then put back with Undo, must settle from the cache and not stay on "Checking stock…" (Task 4).
2. "Start again", `reset()` or closing the screen in the middle of a zoom: the loop stops, the tile files are gone, and nothing is written into the new review (Task 4).
3. The same item in two photos is asked for once and both rows settle (Task 3).
4. Every photo removed while reading: the strip goes, "Generate file · 0 items" is disabled, and the loop ends rather than spinning (Task 4).
5. The ERP unreachable for one stock batch while zooming goes on: those rows read "Stock not checked" with **Retry check**, reading continues, and the footer follows the rows that are ready (Task 3).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/app/modules/stock_sheet/logic/photo_decoder.dart` (modify) | `readWhole`, `zoomIn` with `stopped`; `decode` kept as a helper until Task 9 |
| `lib/app/modules/stock_sheet/model/review_models.dart` (modify) | `ReadStage`; `ReviewEntry.stage`, `.number`, `.codes` |
| `lib/app/modules/stock_sheet/model/ageing_models.dart` (create) | `ItemAgeing`, `AgeingState` |
| `lib/app/modules/stock_sheet/logic/reading_status.dart` (create) | The strip's label, tally and progress from the list (pure) |
| `lib/app/data/providers/items_from_photos_provider.dart` (modify) | `fetchStockAgeing` |
| `lib/app/modules/stock_sheet/items_from_photos_controller.dart` (modify) | The reading loop, the item and stock cache, removal while reading, card and ageing state |
| `lib/app/modules/stock_sheet/widgets/review_list.dart` (modify) | Row stages, pills, the tap that opens a card |
| `lib/app/modules/stock_sheet/widgets/reading_strip.dart` (create) | The strip under the title |
| `lib/app/modules/stock_sheet/widgets/stock_card_details.dart` (create) | Rack-Wise Stock Balance and Stock Ageing inside an open card |
| `lib/app/modules/stock_sheet/widgets/rack_chips.dart` (delete in Task 7) | Replaced by the card |
| `lib/app/modules/stock_sheet/items_from_photos_screen.dart` (modify) | Phases, title, strip, footer |
| `docs/items_from_photos.md` (modify) | The as-built description |

---

### Task 1: Decoder in two steps

**Files:**
- Modify: `lib/app/modules/stock_sheet/logic/photo_decoder.dart`
- Test: `test/unit/items_from_photos_photo_decoder_test.dart`
- Modify (compile only): `test/unit/items_from_photos_controller_test.dart` (`_FakeDecoder`), `test/widget/items_from_photos_screen_test.dart` (its fake decoder, if it has one)

**Interfaces:**
- Produces:
  ```dart
  abstract class PhotoDecoder {
    /// Round one: the whole photo. Null when the photo cannot be read.
    Future<List<String>?> readWhole(String path);
    /// Round two: tiles, then the 2x copy for a small photo that still has no item.
    /// [whole] is what readWhole gave. Null when [stopped] said so.
    Future<List<String>?> zoomIn(String path, {required List<String> whole, bool Function()? stopped});
    /// True unless [whole] holds exactly one item.
    static bool needsZoom(List<String> whole);
    /// readWhole, then zoomIn when needed. Removed in Task 9.
    Future<List<String>?> decode(String path);
    Future<void> dispose();
  }
  ```
  `PhotoDecoder` becomes a class to extend (it has a concrete `decode`); fakes change `implements` to `extends`.

- [ ] **Step 1: Write the failing tests** in the `decode` group's set-up of `items_from_photos_photo_decoder_test.dart` (reuse `_FakeAnalyser`, `photo()`, `_tile`, `_at`, `_a`, `_b`):

```dart
test('readWhole reads the photo once and nothing else', () async {
  analyser.holds.add((_named('photo.png'), [_plain(_a)]));
  expect(await decoder.readWhole(photo()), [_a]);
  expect(analyser.calls, hasLength(1));
});

test('needsZoom: no item or several, never exactly one', () {
  expect(PhotoDecoder.needsZoom(const []), isTrue);
  expect(PhotoDecoder.needsZoom(const [_ean13]), isTrue);
  expect(PhotoDecoder.needsZoom(const [_a, _aBatch]), isFalse);
  expect(PhotoDecoder.needsZoom(const [_a, _b]), isTrue);
});

test('zoomIn gives what decode gave for the same photo', () async {
  analyser.holds.add((_tile(8, 'n'), [_at(_a, 150, 85, 80, 40)]));
  final path = photo();
  expect(await decoder.zoomIn(path, whole: const []), [_a]);
  expect(analyser.tiles, hasLength(18));
});

test('zoomIn stops before the next tile, gives null and leaves no file', () async {
  var reads = 0;
  final result = await decoder.zoomIn(
    photo(),
    whole: const [],
    stopped: () => ++reads > 3, // asked once after writing, then before each read
  );
  expect(result, isNull);
  expect(analyser.tiles.length, lessThan(18));
  expect(analyser.retries, isEmpty);
  expect(temp.listSync(), isEmpty);
});

test('zoomIn stopped while the tiles were being written reads none', () async {
  expect(await decoder.zoomIn(photo(), whole: const [], stopped: () => true), isNull);
  expect(analyser.tiles, isEmpty);
  expect(temp.listSync(), isEmpty);
});
```

- [ ] **Step 2: Run** `flutter test test/unit/items_from_photos_photo_decoder_test.dart` — the new tests fail to compile (`readWhole`, `zoomIn`, `needsZoom` undefined).

- [ ] **Step 3: Implement.** Move today's `decode` body into `readWhole` (the first `_analyse`, with the same `UnsupportedError` rethrow and null on other failures) and `zoomIn` (everything after `if (items == 1) return first;`, with `first` now `whole`). `_readTiles` takes `stopped` and asks it once after `Isolate.run` returns and before each `_analyseFound`; when it says stop, `_readTiles` signals it (distinct from "no tiles") so `zoomIn` returns null without the 2x copy. The existing `finally` already deletes the tile files. `decode` in the base class is `readWhole`, then `zoomIn` when `needsZoom`, falling back to `whole` when `zoomIn` gives null.

- [ ] **Step 4: Make the fakes compile.** In `test/unit/items_from_photos_controller_test.dart` change `_FakeDecoder implements PhotoDecoder` to `extends PhotoDecoder`, keep its `decode` override as it is, and add `readWhole` (same body as its `decode`) and `zoomIn` (returns `whole`). Do the same for any other `PhotoDecoder` fake (`grep -rn "PhotoDecoder" test`).

- [ ] **Step 5: Run** `flutter test test/unit/items_from_photos_photo_decoder_test.dart test/unit/items_from_photos_controller_test.dart test/widget/items_from_photos_screen_test.dart` — all pass (the existing `decode` tests prove `readWhole` + `zoomIn` give what `decode` gave). `flutter analyze lib/app/modules/stock_sheet` shows nothing new.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/stock_sheet/logic/photo_decoder.dart test/unit/items_from_photos_photo_decoder_test.dart test/unit/items_from_photos_controller_test.dart test/widget/items_from_photos_screen_test.dart
git commit -m "refactor(items-from-photos): read a photo in two steps that can be stopped"
```

---

### Task 2: Row stages and the strip's text

**Files:**
- Modify: `lib/app/modules/stock_sheet/model/review_models.dart`
- Create: `lib/app/modules/stock_sheet/logic/reading_status.dart`
- Test: `test/unit/reading_status_test.dart` (create), `test/unit/review_builder_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum ReadStage { notRead, reading, waiting, zooming, checkingStock, settled }

  // ReviewEntry gains (all kept by copyWith, which also takes them):
  final ReadStage stage;            // default ReadStage.settled
  final int number;                 // 1-based place in the order given; 0 when unknown
  final List<ClassifiedCode> codes; // items read so far, before Item and stock are known
  bool get settled => stage == ReadStage.settled;

  class ReadingStatus {
    const ReadingStatus({required this.label, required this.tally, required this.progress});
    final String label; final String tally; final double progress; // 0..1
    /// Null when every row is settled (the strip is hidden).
    static ReadingStatus? of(List<ReviewEntry> entries);
  }
  ```
  `ReadingStatus.of` counts photos (distinct `path`s), not rows. N in the labels is the highest `number` in the list. A photo counts as read once none of its rows is `notRead`, `reading`, `waiting` or `zooming`. The label is chosen in this order: a `reading` row → "Reading photo n of N"; else a `zooming` row → "Zooming in on photo n of N…"; else a `notRead` row → "Reading photo n of N" for the first of them; else a `waiting` row → "Zooming in…"; else "Checking stock…".

- [ ] **Step 1: Write the failing tests** in `test/unit/reading_status_test.dart`, with a helper `ReviewEntry e(int n, ReadStage s) => ReviewEntry(path: 'p$n', number: n, stage: s)`:

```dart
test('round one names the photo being read', () {
  final s = ReadingStatus.of([e(1, ReadStage.checkingStock), e(2, ReadStage.reading), e(3, ReadStage.notRead)])!;
  expect(s.label, 'Reading photo 2 of 3');
  expect(s.tally, '1 read');
  expect(s.progress, closeTo(1 / 3, 1e-9));
});

test('round two names the photo being zoomed in on and what is left', () {
  final s = ReadingStatus.of([e(1, ReadStage.settled), e(2, ReadStage.zooming), e(3, ReadStage.waiting)])!;
  expect(s.label, 'Zooming in on photo 2 of 3…');
  expect(s.tally, '1 read · 2 to go');
});

test('between photos in round two the label has no number', () {
  final s = ReadingStatus.of([e(1, ReadStage.settled), e(2, ReadStage.waiting)])!;
  expect(s.label, 'Zooming in…');
});

test('reading done, stock outstanding', () {
  final s = ReadingStatus.of([e(1, ReadStage.settled), e(2, ReadStage.checkingStock)])!;
  expect(s.label, 'Checking stock…');
  expect(s.tally, '2 read');
  expect(s.progress, 1);
});

test('nothing outstanding, or an empty list, gives no strip', () {
  expect(ReadingStatus.of([e(1, ReadStage.settled)]), isNull);
  expect(ReadingStatus.of(const []), isNull);
});

test('a photo removed leaves the numbers of the others alone', () {
  final s = ReadingStatus.of([e(1, ReadStage.settled), e(3, ReadStage.zooming)])!;
  expect(s.label, 'Zooming in on photo 3 of 3…');
  expect(s.tally, '1 read · 1 to go');
});
```

  And in `review_builder_test.dart`: `copyWith` keeps `stage`, `number` and `codes`; a default `ReviewEntry` is `settled`.

- [ ] **Step 2: Run** `flutter test test/unit/reading_status_test.dart test/unit/review_builder_test.dart` — fails to compile.

- [ ] **Step 3: Implement** the enum, the three fields (constructor defaults `ReadStage.settled`, `0`, `const []`; `codes` unmodifiable like `items`), `copyWith`, and `ReadingStatus.of`.

- [ ] **Step 4: Run** the same tests — pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/stock_sheet/model/review_models.dart lib/app/modules/stock_sheet/logic/reading_status.dart test/unit/reading_status_test.dart test/unit/review_builder_test.dart
git commit -m "feat(items-from-photos): row stages and the reading strip's text"
```

---

### Task 3: The reading loop (list opens at once, two rounds, stock by item)

**Files:**
- Modify: `lib/app/modules/stock_sheet/items_from_photos_controller.dart`
- Test: `test/unit/items_from_photos_controller_test.dart`

**Interfaces:**
- Consumes: `PhotoDecoder.readWhole` / `zoomIn` / `needsZoom` (Task 1); `ReadStage`, `ReviewEntry.stage/number/codes` (Task 2); `ReviewBuilder.entriesFor(scan, items, stock)`; `ItemsFromPhotosProvider.fetchItems`, `fetchFinishedGoodsStock`; `StockAggregator.racksByItem`.
- Produces (used by Tasks 4, 5, 8):
  ```dart
  final reading = false.obs;      // true while any row is not settled
  // start(paths): fingerprints (phase decoding), then phase reviewing with one placeholder per photo, then reads.
  // ItemsFromPhotosPhase.checkingStock is removed; decoding lasts only while photos are fingerprinted.
  ```
  Private, named here so later tasks agree: `_pump(int generation)` (the single reading loop), `_requestStock()` (asks for what is not yet known and settles rows whose codes are known), `_knownCodes`, `_itemsByCode`, `_stockByCode`, and the one long-lived `_decoder` (made on first use from `_decoderFactory`, disposed in `onClose`).

**Rules the loop follows** (the spec's "Reading in two rounds"):
1. A placeholder is `ReviewEntry(path: p, number: n, stage: ReadStage.notRead)`; `number` continues from the highest in the list (adds in Task 4).
2. `_pump` is the only reading loop and never runs twice at once (a flag). Each turn it notes the current `_generation`, takes the first `notRead` row in list order, else the first `waiting` row in list order, else ends. It sets `reading` / `zooming`, awaits the decoder, and then, if the generation has moved, drops the answer and carries on with the list as it now is; otherwise it writes the row found by path (it may have moved or gone). So a new `start` during a read waits for that one read to come back, and no two reads overlap.
3. After `readWhole`: null → settled with `decodeFailed: true`; one item → `checkingStock` with `codes`; otherwise → `waiting` with `rawValues` and `codes` so far. The photo's thumbnail is made after its quick pass, as today.
4. After `zoomIn`: no item → the unresolved row `ReviewBuilder.entriesFor` gives (settled); items → `checkingStock` with `codes`.
5. `_requestStock()` is called when no `notRead` row is left, and after every zoom. It is not awaited by the loop. It asks (one `fetchItems`, one `fetchFinishedGoodsStock`, images alongside) only for codes not in `_knownCodes`, then replaces every `checkingStock` row whose codes are all known with `ReviewBuilder.entriesFor(scan, _itemsByCode, _stockByCode)` at the row's place.
6. Failures: `UnsupportedError` from the decoder → `_fail(unsupportedMessage)`; `StockAccessDenied` → `_fail(noAccessMessage)`; any other stock failure → the rows of that batch become `ReviewEntry(path:, rawValues:, unchecked: true)` (settled), as added photos do today, and reading goes on. `retryCheck` keeps working on them and writes its answers into the cache.
7. `reading.value` is recomputed whenever the list changes: any row not settled.
8. `busy` is true only while fingerprinting. Every write checks `_stale(generation)` first.

- [ ] **Step 1: Give the fake decoder two steps.** In `_FakeDecoder`: `readWhole(path)` returns `codes[path]` (as `decode` does, honouring `gate`, `unsupported`, `throwFor`); new `final Map<String, List<String>?> zoomed = {}` and `zoomIn` returns `zoomed[path] ?? whole`, records the path in `final zooms = <String>[]`, honours a `Completer<void>? zoomGate`, and returns null if `stopped?.call() == true` after the gate. Record every call, in order, in `final log = <String>[]` as `'whole:<path>'` / `'zoom:<path>'`.

- [ ] **Step 2: Write the failing tests** (new group `reading in two rounds`; `_a`, `_b` are the file's item fixtures, `ean(_a)` their barcodes; use the file's existing `make`, `untilReviewing`-style helpers or add `Future<void> settled(c)` that pumps the event queue until `!c.reading.value`):

```dart
test('the list opens with a row per photo before anything is read', () async {
  final decoder = _FakeDecoder({'p1': [eanA], 'p2': [eanB]})..gate = Completer<void>();
  final c = make(decoder, _FakeProvider());
  unawaited(c.start(['p1', 'p2']));
  await pumpEventQueue();
  expect(c.phase.value, ItemsFromPhotosPhase.reviewing);
  expect(c.review.map((e) => e.number), [1, 2]);
  expect(c.review.map((e) => e.stage), [ReadStage.reading, ReadStage.notRead]);
  expect(c.reading.value, isTrue);
  decoder.gate!.complete();
});

test('every photo gets the quick pass before any is zoomed in on', () async {
  final decoder = _FakeDecoder({'p1': const [], 'p2': [eanA], 'p3': const []})
    ..zoomed.addAll({'p1': [eanB], 'p3': const []});
  final c = make(decoder, _FakeProvider());
  await c.start(['p1', 'p2', 'p3']);
  await settled(c);
  expect(decoder.log, ['whole:p1', 'whole:p2', 'whole:p3', 'zoom:p1', 'zoom:p3']);
  expect(c.review.map((e) => e.resolved), [true, true, false]);   // p3: "No recognised code"
  expect(c.review.every((e) => e.settled), isTrue);
  expect(c.reading.value, isFalse);
});

test('round one\'s items are asked for in one batch, a zoomed photo\'s on its own', () async {
  final provider = _FakeProvider();
  final decoder = _FakeDecoder({'p1': [eanA], 'p2': const []})..zoomed['p2'] = [eanB];
  final c = make(decoder, provider);
  await c.start(['p1', 'p2']);
  await settled(c);
  expect(provider.itemRequests, [[_a], [_b]]);
  expect(provider.stockRequests, [[_a], [_b]]);
});

test('the same item in two photos is asked for once and both rows settle', () async {   // Review Focus 3
  final provider = _FakeProvider();
  final c = make(_FakeDecoder({'p1': [eanA], 'p2': const []})..zoomed['p2'] = [eanA], provider);
  await c.start(['p1', 'p2']);
  await settled(c);
  expect(provider.itemRequests, [[_a]]);
  expect(c.review.map((e) => e.items.single.info.itemCode), [_a, _a]);
});

test('a sheet of labels stays one row until zoomed in on, then becomes its rows in place', () async {
  final decoder = _FakeDecoder({'p1': [eanA, eanB], 'p2': [eanA]})
    ..zoomGate = Completer<void>()
    ..zoomed['p1'] = [eanB, eanA];
  final c = make(decoder, _FakeProvider());
  await c.start(['p1', 'p2']);
  await pumpEventQueue();
  expect(c.review, hasLength(2));
  expect(c.review.first.stage, ReadStage.zooming);
  expect(c.review.first.codes, hasLength(2));           // "Photo 1 · 2 items so far"
  decoder.zoomGate!.complete();
  await settled(c);
  expect(c.review.map((e) => e.items.single.info.itemCode), [_b, _a, _a]);   // p1's rows first, in reading order
  expect(c.review.take(2).every((e) => e.path == 'p1'), isTrue);
});

test('an unreadable photo is settled without a zoom', () async {
  final decoder = _FakeDecoder({'p1': null});
  final c = make(decoder, _FakeProvider());
  await c.start(['p1']);
  await settled(c);
  expect(c.review.single.decodeFailed, isTrue);
  expect(decoder.zooms, isEmpty);
});

test('a stock batch that cannot reach the ERP leaves its rows unchecked and reading goes on', () async {   // Review Focus 5
  final provider = _FakeProvider()..stockError = Exception('offline');
  final decoder = _FakeDecoder({'p1': [eanA], 'p2': const []})..zoomed['p2'] = const [];
  final c = make(decoder, provider);
  await c.start(['p1', 'p2']);
  await settled(c);
  expect(c.phase.value, ItemsFromPhotosPhase.reviewing);
  expect(c.review.first.unchecked, isTrue);
  expect(decoder.zooms, ['p2']);
  provider.stockError = null;
  expect(await c.retryCheck(0), isNull);
  expect(c.review.first.resolved, isTrue);
});

test('no access to stock levels still ends in the error state', () async {
  final provider = _FakeProvider()..stockError = const StockAccessDenied();
  final c = make(_FakeDecoder({'p1': [eanA]}), provider);
  await c.start(['p1']);
  await settled(c);
  expect(c.phase.value, ItemsFromPhotosPhase.error);
  expect(c.errorMessage.value, ItemsFromPhotosController.noAccessMessage);
});
```

  (Adapt fixture names to the file's own: check how `_FakeProvider.stockError` and `StockAccessDenied` are spelt there.)

- [ ] **Step 3: Run** `flutter test test/unit/items_from_photos_controller_test.dart` — the new tests fail; note which existing tests fail too.

- [ ] **Step 4: Implement** the rules above in `start`, replacing `_decode`, `_checkStock` and the `decoding → checkingStock → reviewing` sequence. `retry()` (from the error state) asks `_requestStock()` again for rows not yet settled. Remove `ItemsFromPhotosPhase.checkingStock`.

- [ ] **Step 5: Bring the existing tests along.** Tests that asserted `ItemsFromPhotosPhase.checkingStock`, or `decoding` for the whole read, or `decoded`/`total` counting up, now assert the stages or `reading`; tests that awaited `start(...)` for a finished review add `await settled(c)`. Do not weaken what a test proves about the final review, the file, sharing, duplicates, limits or clean-up. `addPhotos` still uses its own path until Task 4; keep its tests green.

- [ ] **Step 6: Run** `flutter test test/unit/items_from_photos_controller_test.dart` and `flutter analyze lib/app/modules/stock_sheet` — all pass, nothing new.

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/stock_sheet/items_from_photos_controller.dart test/unit/items_from_photos_controller_test.dart
git commit -m "feat(items-from-photos): open the review at once and read in two rounds"
```

---

### Task 4: Rows stay live (remove, Undo, reorder, add while reading)

**Files:**
- Modify: `lib/app/modules/stock_sheet/items_from_photos_controller.dart`
- Test: `test/unit/items_from_photos_controller_test.dart`

**Interfaces:**
- Consumes: `_pump`, `_requestStock`, `reading` (Task 3).
- Produces: `canRemove` no longer depends on reading or adding (`_reviewing && !(rechecking.value || fixing.value || busy.value)`); `removeAt`, `restore`, `reorder`, `setIncluded` work in every stage; `addPhotos` appends placeholders and wakes `_pump`; `adding` is true only while the new photos are fingerprinted.

**Rules:**
- Removing the row being zoomed in on stops that zoom: `stopped` is true for that attempt from then on, and also once the generation moves. The stop belongs to the attempt, not the path: putting the row back does not revive it, and the photo is read afresh. The loop then takes the next row. A removed photo's late answers are dropped (the row is found by path and is not there).
- `restore` puts the row back at its index. A row that had not finished reading returns as `notRead` (never read) or `waiting` (had its quick pass); a `checkingStock` row returns as it was. `restore` then wakes `_pump` and calls `_requestStock()`.
- Zoom order is the list's order at the moment the loop picks: nothing to store, but a reorder must wake nothing and break nothing.
- `reset()` / `_clear()` / `onClose()` bump the generation: the loop ends at its next step, a zoom in hand is stopped, and the long-lived decoder is disposed in `onClose` only.

- [ ] **Step 1: Write the failing tests** (group `rows stay live while reading`):

```dart
test('removing the photo being zoomed in on stops it and starts the next', () async {
  final decoder = _FakeDecoder({'p1': const [], 'p2': const []})
    ..zoomGate = Completer<void>()
    ..zoomed.addAll({'p1': [eanA], 'p2': [eanB]});
  final c = make(decoder, _FakeProvider());
  await c.start(['p1', 'p2']);
  await pumpEventQueue();
  expect(c.review.first.stage, ReadStage.zooming);
  final removed = c.removeAt(0)!;
  decoder.zoomGate!.complete();
  await settled(c);
  expect(decoder.zooms, ['p1', 'p2']);
  expect(c.review.single.path, 'p2');
  expect(removed.path, 'p1');
});

test('Undo puts the photo back to wait its turn by its place in the list', () async {
  final decoder = _FakeDecoder({'p1': const [], 'p2': const []})..zoomGate = Completer<void>();
  final c = make(decoder, _FakeProvider());
  await c.start(['p1', 'p2']);
  await pumpEventQueue();
  final removed = c.removeAt(0)!;
  c.restore(removed, 0);
  expect(c.review.first.stage, ReadStage.waiting);
  decoder.zoomGate!.complete();
  await settled(c);
  expect(decoder.zooms, ['p1', 'p1', 'p2']);   // stopped, then read afresh before p2: it is first in the list
});

test('a photo removed before its turn is never read', () async {
  final decoder = _FakeDecoder({'p1': const [], 'p2': const []})..zoomGate = Completer<void>();
  final c = make(decoder, _FakeProvider());
  await c.start(['p1', 'p2']);
  await pumpEventQueue();
  c.removeAt(1);
  decoder.zoomGate!.complete();
  await settled(c);
  expect(decoder.zooms, ['p1']);
});

test('a row dragged up is zoomed in on sooner; the photo in hand finishes first', () async {
  final decoder = _FakeDecoder({'p1': const [], 'p2': const [], 'p3': const []})..zoomGate = Completer<void>();
  final c = make(decoder, _FakeProvider());
  await c.start(['p1', 'p2', 'p3']);
  await pumpEventQueue();
  c.reorder(2, 0);                       // p3 to the top while p1 is being zoomed in on
  decoder.zoomGate!.complete();
  await settled(c);
  expect(decoder.zooms, ['p1', 'p3', 'p2']);
});

test('a row removed while its stock is being checked settles when put back', () async {   // Review Focus 1
  final provider = _FakeProvider()..stockGate = Completer<void>();
  final c = make(_FakeDecoder({'p1': [eanA]}), provider);
  await c.start(['p1']);
  await pumpEventQueue();
  expect(c.review.single.stage, ReadStage.checkingStock);
  final removed = c.removeAt(0)!;
  provider.stockGate!.complete();
  await pumpEventQueue();
  c.restore(removed, 0);
  await settled(c);
  expect(c.review.single.resolved, isTrue);
  expect(provider.itemRequests, hasLength(1));
});

test('starting again in the middle of a zoom writes nothing into the new review', () async {   // Review Focus 2
  final decoder = _FakeDecoder({'p1': const [], 'q1': [eanB]})
    ..zoomGate = Completer<void>()
    ..zoomed['p1'] = [eanA];
  final c = make(decoder, _FakeProvider());
  await c.start(['p1']);
  await pumpEventQueue();
  unawaited(c.start(['q1']));
  decoder.zoomGate!.complete();
  await settled(c);
  expect(c.review.map((e) => e.path), ['q1']);
});

test('every photo removed while reading ends the reading', () async {   // Review Focus 4
  final decoder = _FakeDecoder({'p1': const []})..zoomGate = Completer<void>();
  final c = make(decoder, _FakeProvider());
  await c.start(['p1']);
  await pumpEventQueue();
  c.removeAt(0);
  decoder.zoomGate!.complete();
  await settled(c);
  expect(c.review, isEmpty);
  expect(c.reading.value, isFalse);
  expect(c.sheetItemCount, 0);
});

test('photos added during reading join the list and get their quick pass before the next zoom', () async {
  final decoder = _FakeDecoder({'p1': const [], 'p2': const [], 'n1': [eanA]})..zoomGate = Completer<void>();
  final c = make(decoder, _FakeProvider());
  await c.start(['p1', 'p2']);
  await pumpEventQueue();
  expect(await c.addPhotos(['n1']), isNull);
  expect(c.review.last.number, 3);
  decoder.zoomGate!.complete();
  await settled(c);
  expect(decoder.log, ['whole:p1', 'whole:p2', 'zoom:p1', 'whole:n1', 'zoom:p2']);
});
```

- [ ] **Step 2: Run** `flutter test test/unit/items_from_photos_controller_test.dart` — the new tests fail.

- [ ] **Step 3: Implement** the rules. `addPhotos` keeps its guards, duplicate and room checks and messages; after fingerprinting it appends placeholders and returns null without waiting for the reading. The clean-up test for temporary tile files is in Task 1; here the fake cannot leave files.

- [ ] **Step 4: Bring the existing `addPhotos`, `removeAt` and `restore` tests along** (those that expected removal to be refused while adding now expect it to work; those that awaited `addPhotos` for checked rows add `await settled(c)`).

- [ ] **Step 5: Run** the controller tests and `flutter analyze lib/app/modules/stock_sheet` — pass.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/stock_sheet/items_from_photos_controller.dart test/unit/items_from_photos_controller_test.dart
git commit -m "feat(items-from-photos): remove, undo, reorder and add while photos are read"
```

---

### Task 5: Stock Ageing for one item

**Files:**
- Create: `lib/app/modules/stock_sheet/model/ageing_models.dart`
- Modify: `lib/app/data/providers/items_from_photos_provider.dart`
- Test: `test/unit/items_from_photos_provider_test.dart`

**Interfaces:**
- Consumes: `ApiProvider.runStockAgeingCustom({Map<String, dynamic>? filters})`; `StockAgeingLogic.applyRange`, `parseBuckets`, `parseRows`, `num_` (`lib/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart`).
- Produces:
  ```dart
  class ItemAgeing {
    const ItemAgeing({this.warehouse, required this.availableQty, required this.averageAge,
        required this.earliest, required this.latest, required this.buckets});
    final String? warehouse;                              // set only when the run gives one row per warehouse
    final double availableQty, averageAge;
    final int earliest, latest;
    final List<({String label, double qty})> buckets;     // label as the report titles it, e.g. "0 - 90"
  }
  enum AgeingStatus { loading, ready, missing, failed, denied }
  class AgeingState {
    const AgeingState(this.status, [this.rows = const []]);
    final AgeingStatus status; final List<ItemAgeing> rows;
  }

  // ItemsFromPhotosProvider
  static const String ageingRange = '90, 180, 360, 720';
  /// The item's rows in Stock Ageing as of today, Finished Goods; empty when the report has none.
  /// Throws StockAccessDenied on 403 and whatever else the call throws.
  Future<List<ItemAgeing>> fetchStockAgeing(String itemCode);
  ```
  `ItemsFromPhotosProvider` takes a new optional `String Function()? company` (default `Get.find<StorageService>().getCompany()`, as the Stock Ageing controller does).

- [ ] **Step 1: Probe the server (read-only), before writing code.** With the dev credentials in memory `erp-dev-api-credentials.md`, run `frappe.desk.query_report.run` for `Stock Ageing - Custom` with the filters of Step 3 and an item known to be in stock (EAN `10039991` → item `1003999`). Record in the task's commit message: seconds taken, and whether one row or one row per warehouse comes back. The code below handles both; the number goes into the docs in Task 9. If the credentials are gone, ask the user; do not guess.

- [ ] **Step 2: Write the failing tests** in `items_from_photos_provider_test.dart` (follow the file's fake `ApiProvider` pattern; add a `runStockAgeingCustom` override that records `filters` and returns a canned `Response`):

```dart
test('fetchStockAgeing asks for one item with the report\'s saved filter values', () async {
  await provider.fetchStockAgeing('1003999');
  expect(api.ageingFilters.single, {
    'company': 'KA',
    'to_date': '2026-11-17',
    'warehouse': 'Finished Goods - KA',
    'range': '90, 180, 360, 720',
    'item_code': '1003999',
    'show_warehouse_wise_stock': 0,
  });
});

test('quantity columns only, buckets titled from the range', () async {
  api.ageingMessage = {
    'columns': [
      {'fieldname': 'item_code', 'label': 'Item Code'},
      {'fieldname': 'qty', 'label': 'Available Qty', 'fieldtype': 'Float'},
      {'fieldname': 'average_age', 'label': 'Average Age', 'fieldtype': 'Float'},
      {'fieldname': 'range1', 'label': 'Age (0 - 30)', 'fieldtype': 'Float'},        // frozen title, wrong range
      {'fieldname': 'range1value', 'label': 'Value (0 - 30)', 'fieldtype': 'Float'},
      {'fieldname': 'range2', 'label': 'Age (31 - 60)', 'fieldtype': 'Float'},
      {'fieldname': 'earliest', 'label': 'Earliest', 'fieldtype': 'Int'},
      {'fieldname': 'latest', 'label': 'Latest', 'fieldtype': 'Int'},
    ],
    'result': [
      {'item_code': '1003999', 'qty': 384, 'average_age': 212.4, 'range1': 96, 'range1value': 960,
       'range2': 288, 'earliest': 298, 'latest': 41},
    ],
  };
  final rows = await provider.fetchStockAgeing('1003999');
  expect(rows.single.availableQty, 384);
  expect(rows.single.averageAge, 212.4);
  expect((rows.single.earliest, rows.single.latest), (298, 41));
  expect(rows.single.buckets.map((b) => (b.label, b.qty)).take(2), [('0 - 90', 96.0), ('91 - 180', 288.0)]);
  expect(rows.single.warehouse, isNull);
});

test('rows for other items are dropped; none left is an empty list', () async {
  api.ageingMessage = {'columns': const [], 'result': [{'item_code': '9999999', 'qty': 5}]};
  expect(await provider.fetchStockAgeing('1003999'), isEmpty);
});

test('one row per warehouse keeps each warehouse', () async {
  api.ageingMessage = {'columns': const [], 'result': [
    {'item_code': '1003999', 'warehouse': 'WH-DXB1 - KA', 'qty': 300},
    {'item_code': '1003999', 'warehouse': 'WH-DXB2 - KA', 'qty': 84},
  ]};
  final rows = await provider.fetchStockAgeing('1003999');
  expect(rows.map((r) => (r.warehouse, r.availableQty)), [('WH-DXB1 - KA', 300.0), ('WH-DXB2 - KA', 84.0)]);
});

test('a 403 is StockAccessDenied', () async {
  api.ageingError = DioException(requestOptions: RequestOptions(), response: Response(requestOptions: RequestOptions(), statusCode: 403));
  expect(provider.fetchStockAgeing('1003999'), throwsA(isA<StockAccessDenied>()));
});
```

- [ ] **Step 3: Implement** `fetchStockAgeing` through the provider's existing `_guard`. Filters exactly as the first test (date `yyyy-MM-dd` from `_now()`). Columns go through `StockAgeingLogic.applyRange(columns, ageingRange)` then `parseBuckets`; rows through `parseRows`; keep rows whose `item_code` is the one asked for; `warehouse` is set only when more than one row is kept.

- [ ] **Step 4: Run** `flutter test test/unit/items_from_photos_provider_test.dart` — pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/stock_sheet/model/ageing_models.dart lib/app/data/providers/items_from_photos_provider.dart test/unit/items_from_photos_provider_test.dart
git commit -m "feat(items-from-photos): fetch one item's Stock Ageing"
```

---

### Task 6: Row stages and the strip on screen

**Files:**
- Modify: `lib/app/modules/stock_sheet/widgets/review_list.dart`
- Create: `lib/app/modules/stock_sheet/widgets/reading_strip.dart`
- Test: `test/widget/items_from_photos_review_list_test.dart`

**Interfaces:**
- Consumes: `ReadStage`, `ReviewEntry.stage/number/codes`, `ReadingStatus.of` (Task 2).
- Produces: `ReadingStrip({required List<ReviewEntry> entries})` (renders nothing when `ReadingStatus.of` is null; otherwise the label, the tally and a determinate `LinearProgressIndicator`; the label is in a polite live region). `ReviewList` renders every stage per the spec's table; nothing in its constructor changes in this task.

**What each stage shows** (spec, "Row states and wording"): `notRead` and `reading` rows have a dashed `borderStrong` outline and no fill, the name in `textMuted`; `reading` and the Zooming in pill carry a small spinner; `waiting` and `zooming` show the photo thumbnail and "Photo n" (or "Photo n · k items so far" when `codes.length >= 2`); `checkingStock` shows the barcode of `codes.single` in mono and "Checking stock…" (or "Photo n · k items" and "Checking stock…" for several codes); settled rows show the name, `barcode · Variant Of` and one pill, **In stock** or **Out of stock**, in place of `RackChips`. The switch is enabled only for settled rows with an item. Swipe, the screen reader's remove action and the drag handle are present in every stage.

- [ ] **Step 1: Write the failing widget tests** (use the file's `_app` wrapper and its light/dark helpers):

```dart
testWidgets('each stage shows its line', (tester) async {
  await tester.pumpWidget(_app(ReviewList(entries: [
    ReviewEntry(path: 'p1', number: 1, stage: ReadStage.notRead),
    ReviewEntry(path: 'p2', number: 2, stage: ReadStage.reading),
    ReviewEntry(path: 'p3', number: 3, stage: ReadStage.waiting),
    ReviewEntry(path: 'p4', number: 4, stage: ReadStage.zooming),
    ReviewEntry(path: 'p5', number: 5, stage: ReadStage.checkingStock, codes: const [_codeA]),
    ReviewEntry(path: 'p6', number: 6, stage: ReadStage.waiting, codes: const [_codeA, _codeB]),
  ], /* the file's usual callbacks */)));
  expect(find.text('Not read yet'), findsOneWidget);
  expect(find.text('Reading…'), findsOneWidget);
  expect(find.text('Waiting to zoom in'), findsNWidgets(2));
  expect(find.text('Zooming in…'), findsOneWidget);
  expect(find.text('Checking stock…'), findsOneWidget);
  expect(find.text(_codeA.barcode), findsOneWidget);
  expect(find.text('Photo 6 · 2 items so far'), findsOneWidget);
  expect(tester.widgetList<Switch>(find.byType(Switch)).every((s) => s.onChanged == null), isTrue);
});

testWidgets('a ready row shows one pill and no quantity or rack', (tester) async {
  await tester.pumpWidget(_app(ReviewList(entries: [_inStockEntry, _outOfStockEntry], /* callbacks */)));
  expect(find.text('In stock'), findsOneWidget);
  expect(find.text('Out of stock'), findsOneWidget);
  expect(find.textContaining('KA-WH-'), findsNothing);
  expect(find.textContaining('Out of stock · 0'), findsNothing);
});

testWidgets('a row that is not read yet can be swiped away', (tester) async {
  var removed = -1;
  await tester.pumpWidget(_app(ReviewList(
    entries: [ReviewEntry(path: 'p1', number: 1, stage: ReadStage.notRead)],
    onRemove: (i) { removed = i; return true; }, /* other callbacks */)));
  await tester.drag(find.text('Not read yet'), const Offset(-500, 0));
  await tester.pumpAndSettle();
  expect(removed, 0);
});

testWidgets('the strip follows the list and goes when all is settled', (tester) async {
  await tester.pumpWidget(_app(ReadingStrip(entries: [
    ReviewEntry(path: 'p1', number: 1), ReviewEntry(path: 'p2', number: 2, stage: ReadStage.zooming)])));
  expect(find.text('Zooming in on photo 2 of 2…'), findsOneWidget);
  expect(find.text('1 read · 1 to go'), findsOneWidget);
  await tester.pumpWidget(_app(ReadingStrip(entries: [ReviewEntry(path: 'p1', number: 1)])));
  expect(find.byType(LinearProgressIndicator), findsNothing);
});
```

  Plus, in the file's existing dark-mode contrast group, the six stage rows and both pills (same assertions the group already makes for text on its surface: at least 4.5:1).

- [ ] **Step 2: Run** `flutter test test/widget/items_from_photos_review_list_test.dart` — the new tests fail.

- [ ] **Step 3: Implement** the stages in `_ReviewRow`, the pills (one private `_StatusPill` with a colour ramp argument, per Global Constraints) and `ReadingStrip`. Leave `RackChips` in place but unused by the row (it goes in Task 7); move its "Out of stock" pill colours to the new pill.

- [ ] **Step 4: Update the existing row tests** that expected quantities or rack chips on a row to expect the pill. Keep the `RackChips` widget tests until Task 7.

- [ ] **Step 5: Run** the list tests and `flutter analyze lib/app/modules/stock_sheet` — pass.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/stock_sheet/widgets/review_list.dart lib/app/modules/stock_sheet/widgets/reading_strip.dart test/widget/items_from_photos_review_list_test.dart
git commit -m "feat(items-from-photos): show each row's reading stage and the reading strip"
```

---

### Task 7: The card (rack-wise balance and stock ageing)

**Files:**
- Modify: `lib/app/modules/stock_sheet/items_from_photos_controller.dart`, `lib/app/modules/stock_sheet/widgets/review_list.dart`
- Create: `lib/app/modules/stock_sheet/widgets/stock_card_details.dart`
- Delete: `lib/app/modules/stock_sheet/widgets/rack_chips.dart` (and its tests in `items_from_photos_review_list_test.dart`)
- Test: `test/unit/items_from_photos_controller_test.dart`, `test/widget/items_from_photos_review_list_test.dart`

**Interfaces:**
- Consumes: `ItemsFromPhotosProvider.fetchStockAgeing`, `ItemAgeing`, `AgeingState`, `AgeingStatus` (Task 5); `ItemStock`, `RackQty`.
- Produces:
  ```dart
  // ItemsFromPhotosController
  final openCards = <String>{}.obs;                 // ReviewEntry.id of open cards
  final ageing = <String, AgeingState>{}.obs;       // by item code
  void toggleCard(String entryId);                  // opens or closes; first opening of an in-stock item fetches its ageing
  Future<void> retryAgeing(String itemCode);        // from failed

  // ReviewList gains
  required Set<String> openCards, required Map<String, AgeingState> ageing,
  required void Function(String entryId) onToggleCard, required void Function(String itemCode) onRetryAgeing

  // StockCardDetails({required ItemStock? stock, required AgeingState? ageing, required VoidCallback onRetry})
  ```
  Opening is offered only on settled rows with an item. An out-of-stock item (`stock == null || stock.outOfStock`) is never fetched. `_clear()` empties both maps.

- [ ] **Step 1: Write the failing controller tests:**

```dart
test('the first opening of an in-stock card fetches its Stock Ageing once', () async {
  final provider = _FakeProvider(stock: {_a: 384})..ageing[_a] = [_ageingA];
  final c = make(_FakeDecoder({'p1': [eanA]}), provider);
  await c.start(['p1']); await settled(c);
  final id = c.review.single.id;
  c.toggleCard(id);
  expect(c.openCards, {id});
  expect(c.ageing[_a]!.status, AgeingStatus.loading);
  await pumpEventQueue();
  expect(c.ageing[_a]!.status, AgeingStatus.ready);
  c.toggleCard(id); c.toggleCard(id);
  await pumpEventQueue();
  expect(provider.ageingRequests, [_a]);
});

test('an out-of-stock card opens without a fetch', () async {
  final provider = _FakeProvider();                     // no stock rows: out of stock
  final c = make(_FakeDecoder({'p1': [eanA]}), provider);
  await c.start(['p1']); await settled(c);
  c.toggleCard(c.review.single.id);
  await pumpEventQueue();
  expect(c.ageing, isEmpty);
  expect(provider.ageingRequests, isEmpty);
});

test('no row, a failure and no access each have their state; Retry asks again', () async {
  final provider = _FakeProvider(stock: {_a: 5});
  final c = make(_FakeDecoder({'p1': [eanA]}), provider);
  await c.start(['p1']); await settled(c);
  c.toggleCard(c.review.single.id); await pumpEventQueue();
  expect(c.ageing[_a]!.status, AgeingStatus.missing);
  provider.ageingError = Exception('offline');
  await c.retryAgeing(_a);
  expect(c.ageing[_a]!.status, AgeingStatus.failed);
  provider.ageingError = const StockAccessDenied();
  await c.retryAgeing(_a);
  expect(c.ageing[_a]!.status, AgeingStatus.denied);
});

test('a card that is not ready does not open', () async {
  final decoder = _FakeDecoder({'p1': [eanA]})..gate = Completer<void>();
  final c = make(decoder, _FakeProvider());
  unawaited(c.start(['p1'])); await pumpEventQueue();
  c.toggleCard(c.review.single.id);
  expect(c.openCards, isEmpty);
  decoder.gate!.complete();
});
```

  (Give `_FakeProvider` `final ageing = <String, List<ItemAgeing>>{}`, `final ageingRequests = <String>[]`, `Object? ageingError`, and a `fetchStockAgeing` override.)

- [ ] **Step 2: Write the failing widget tests:**

```dart
testWidgets('a tap opens the card to the rack table at once and the ageing when it arrives', (tester) async {
  // _twoRackEntry: item with racks KA-WH-DXB1-20D 300 and null (no rack) 84, total 384
  String? toggled;
  Widget list(Set<String> open, Map<String, AgeingState> ageing) => _app(ReviewList(
    entries: [_twoRackEntry], openCards: open, ageing: ageing,
    onToggleCard: (id) => toggled = id, onRetryAgeing: (_) {}, /* other callbacks */));
  await tester.pumpWidget(list(const {}, const {}));
  await tester.tap(find.text('In stock'));
  expect(toggled, _twoRackEntry.id);

  await tester.pumpWidget(list({_twoRackEntry.id}, {_a: const AgeingState(AgeingStatus.loading)}));
  expect(find.text('Rack-Wise Stock Balance'), findsOneWidget);
  expect(find.text('Rack'), findsOneWidget);
  expect(find.text('Balance Qty'), findsOneWidget);
  expect(find.text('KA-WH-DXB1-20D'), findsOneWidget);
  expect(find.text('No rack'), findsOneWidget);
  expect(find.text('384'), findsOneWidget);                 // the total line: more than one rack
  expect(find.text('Fetching Stock Ageing…'), findsOneWidget);

  await tester.pumpWidget(list({_twoRackEntry.id}, {_a: AgeingState(AgeingStatus.ready, [_ageingA])}));
  for (final label in ['Stock Ageing', 'Available Qty', 'Average Age', 'Earliest', 'Latest',
      'Age (0 - 90)', 'Age (721 - Above)']) {
    expect(find.text(label), findsOneWidget, reason: label);
  }
  expect(find.textContaining('Value'), findsNothing);
});

testWidgets('the other ageing states say what they are', (tester) async {
  for (final (state, text) in [
    (const AgeingState(AgeingStatus.missing), 'Not in the Stock Ageing report.'),
    (const AgeingState(AgeingStatus.failed), "Couldn't load Stock Ageing."),
    (const AgeingState(AgeingStatus.denied), "You don't have access to Stock Ageing."),
  ]) {
    await tester.pumpWidget(_app(StockCardDetails(stock: _inStock, ageing: state, onRetry: () {})));
    expect(find.text(text), findsOneWidget);
  }
  expect(find.text('Retry'), findsNothing);                 // last pumped is denied: no retry
  await tester.pumpWidget(_app(StockCardDetails(stock: null, ageing: null, onRetry: () {})));
  expect(find.text('No stock in Finished Goods - KA.'), findsOneWidget);
  expect(find.text('Not in the Stock Ageing report: nothing in stock.'), findsOneWidget);
});

testWidgets('a swipe or a drag by the handle does not open the card', (tester) async {
  var toggles = 0;
  await tester.pumpWidget(_app(ReviewList(entries: [_inStockEntry], openCards: const {}, ageing: const {},
    onToggleCard: (_) => toggles++, onRetryAgeing: (_) {}, onRemove: (_) => false, /* other callbacks */)));
  await tester.drag(find.text('In stock'), const Offset(-300, 0));
  await tester.pumpAndSettle();
  expect(toggles, 0);
});
```

  Plus the open card in the dark-mode contrast group, and a semantics check that the arrow is a button labelled "Rack-Wise Stock Balance and Stock Ageing" with its expanded state.

- [ ] **Step 3: Run** both test files — the new tests fail.

- [ ] **Step 4: Implement.** Controller: `toggleCard`, `retryAgeing`, the maps (`StockAccessDenied` → `denied`; an empty list → `missing`; any other error → `failed`; results ignored when `_stale`). `StockCardDetails`: the rack table (largest first, as `ItemStock.racks` already is; `rack == null` is "No rack"; a total line only when there is more than one line), then Stock Ageing (when several `ItemAgeing` rows come back, each under its warehouse name); bucket bars scaled to the largest bucket in the row, in `scheme.primary`. `ReviewList`: `InkWell`/tap on the row body and the arrow button call `onToggleCard`; `Obx`-free (the screen passes plain values). Delete `rack_chips.dart` and its tests.

- [ ] **Step 5: Run** `flutter test test/unit/items_from_photos_controller_test.dart test/widget/items_from_photos_review_list_test.dart` and `flutter analyze` — pass, nothing new, no reference to `RackChips` left (`grep -rn RackChips lib test`).

- [ ] **Step 6: Commit**

```bash
git add -A lib/app/modules/stock_sheet test/unit/items_from_photos_controller_test.dart test/widget/items_from_photos_review_list_test.dart
git commit -m "feat(items-from-photos): open a row to rack-wise balance and stock ageing"
```

---

### Task 8: The screen

**Files:**
- Modify: `lib/app/modules/stock_sheet/items_from_photos_screen.dart`
- Test: `test/widget/items_from_photos_screen_test.dart`

**Interfaces:**
- Consumes: `controller.reading`, `openCards`, `ageing`, `toggleCard`, `retryAgeing`, `canRemove` (Tasks 3, 4, 7); `ReadingStrip` (Task 6).

**What changes:** the review (app bar "Review photos", list, footer) shows as soon as the phase is `reviewing`; `ReadingStrip` sits between the app bar and the list inside its own `Obx` (it changes several times a second in round one; do not rebuild the app bar with it). Subtitle: "N photos · M items so far" while `reading`, else "… in the file". Footer: **Generate file · M items** disabled while `reading.value` (as well as today's conditions). The `checkingStock` progress view goes; the `decoding` view (the fingerprinting moment) keeps "Reading photo 1 of N". The ＋ action shows its spinner only while `adding` (fingerprinting). Snackbar text for a removed row: "Item removed." when the entry is resolved, else "Photo removed." (unchanged rule). Back asks "Discard these photos?" from the first frame (already true once the phase is `reviewing`).

- [ ] **Step 1: Write the failing tests** (follow the file's pump helpers and fakes; its fake decoder gets the two steps as in Task 3):

```dart
testWidgets('the review is on screen while photos are still being read', (tester) async {
  // decoder gated on its first quick pass
  await openWith(tester, ['p1', 'p2']);
  expect(find.text('Review photos'), findsOneWidget);
  expect(find.text('2 photos · 0 items so far'), findsOneWidget);
  expect(find.text('Reading photo 1 of 2'), findsOneWidget);
  expect(find.text('Not read yet'), findsOneWidget);
  final generate = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate file · 0 items'));
  expect(generate.onPressed, isNull);
});

testWidgets('when everything is settled the strip goes and the file can be generated', (tester) async {
  await openWith(tester, ['p1', 'p2']); releaseDecoder(); await tester.pumpAndSettle();
  expect(find.byType(ReadingStrip), findsOneWidget);          // present, renders nothing
  expect(find.textContaining('Reading photo'), findsNothing);
  expect(find.text('2 photos · 2 items in the file'), findsOneWidget);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate file · 2 items')).onPressed, isNotNull);
});

testWidgets('Back during reading asks before discarding', (tester) async {
  await openWith(tester, ['p1']);
  await tester.pageBack(); await tester.pumpAndSettle();
  expect(find.text('Discard these photos?'), findsOneWidget);
});

testWidgets('a row swiped away during reading shows Undo', (tester) async {
  await openWith(tester, ['p1', 'p2']);
  await tester.drag(find.text('Not read yet'), const Offset(-500, 0)); await tester.pumpAndSettle();
  expect(find.text('Photo removed.'), findsOneWidget);
  expect(find.text('Undo'), findsOneWidget);
});
```

- [ ] **Step 2: Run** `flutter test test/widget/items_from_photos_screen_test.dart` — the new tests fail; note the existing ones that fail.

- [ ] **Step 3: Implement** the changes above and pass the card state and callbacks to `ReviewList`.

- [ ] **Step 4: Bring the existing screen tests along** (those that expected "Checking stock…" as a full-screen step, or the bar until the list, now expect the list; nothing about the start state, the dialogs, the footer formats, Download or the finished screen changes).

- [ ] **Step 5: Run** `flutter test test/widget/items_from_photos_screen_test.dart test/widget/items_from_photos_review_list_test.dart test/unit/items_from_photos_controller_test.dart` and `flutter analyze` — pass.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/stock_sheet/items_from_photos_screen.dart test/widget/items_from_photos_screen_test.dart
git commit -m "feat(items-from-photos): the review opens at once, with the reading strip"
```

---

### Task 9: Tidy, document, verify

**Files:**
- Modify: `lib/app/modules/stock_sheet/logic/photo_decoder.dart` (remove `decode`), `test/unit/items_from_photos_photo_decoder_test.dart`, the test fakes
- Modify: `docs/items_from_photos.md`, `docs/superpowers/specs/2026-11-19-items-from-photos-reading-redesign-design.md` (an "As built" section)

- [ ] **Step 1: Remove `PhotoDecoder.decode`.** Re-point the decoder tests that call `decoder.decode(path)` at a small test helper that does `readWhole` then `zoomIn` when `needsZoom` (they keep proving the same results); remove `decode` from the fakes. `grep -rn "\.decode(" lib/app/modules/stock_sheet test | grep -i decoder` is empty.

- [ ] **Step 2: Update `docs/items_from_photos.md`:** the flow diagram and §3.2 (no separate reading and checking screens; the strip and its three lines), §3.3 (row stages, pills, the card and its two sections, what can be done while reading, the sheet-of-labels row), §4 (two rounds, zoom order follows the list, removal stops a zoom, stock asked once per item, Stock Ageing on first opening with its filters and the time measured in Task 5), §5 (the new copy), §7 (new files, removed `rack_chips`, phases without `checkingStock`), §8 (an unreleased row), §10 (what the device check showed; iPhone and Mac unchecked; the Telegram bot still to take the wording). Add "As built" to the spec with anything that differs from it.

- [ ] **Step 3: Run everything locally that this change touches:** `flutter analyze` (nothing new against the branch's start), then
  `flutter test test/unit/items_from_photos_controller_test.dart test/unit/items_from_photos_photo_decoder_test.dart test/unit/items_from_photos_provider_test.dart test/unit/reading_status_test.dart test/unit/review_builder_test.dart test/unit/sheet_reading_test.dart test/unit/grey_plane_test.dart test/widget/items_from_photos_review_list_test.dart test/widget/items_from_photos_screen_test.dart test/widget/items_from_photos_button_test.dart` — all pass.

- [ ] **Step 4: Full suite on sys6** (memory `sys6-windows-build-host.md`: bundle the branch, detached worktree, `flutter test`; wait if the host is busy). Expected: only the three known Windows-only failures.

- [ ] **Step 5: Commit**

```bash
git add -A lib/app/modules/stock_sheet test docs
git commit -m "docs(items-from-photos): the reading redesign as built; drop decode"
```

- [ ] **Step 6: Device check, with the user's go-ahead** (memory `device-smoke-test-recipe.md`; XCover7 `R5CXB2JBDYY`; a release `.dev` build from sys6; the user signs in; check `mCurrentFocus` before every tap). Photos: the ten wallet cards in `~/.config/Claude/side-session-notes/local_36ee42fb-21e9-452e-ab64-6681e56cfa3c/wallet-cards/`, fed through Choose files…. Done when: first barcode on screen within 1 s of choosing; five rows with stock within 8 s; all ten read, ten rows, no later than 44 s; a row removed during "Zooming in…" stops and Undo brings it back to be read; a card opened during reading shows the rack table at once and Stock Ageing after its fetch; a photo of a sheet of labels (ask the user for one; the 30-label sheet used for 2.45.0 was deleted from the phone) stays one row, then gives its rows in sheet order; Excel generated at the end has ten rows and no rack, quantity or ageing columns. Note the times in `docs/items_from_photos.md`, clean the phone, and stop: merging, the version bump (MINOR), tagging and the Telegram wording are the user's call.
