# Stock Sheet Review List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** after a share, read the photos and check stock first, then show a reorderable review list. The list has include switches, the Balance Qty and full rack names, type-or-scan fixes and added photos. The file is made from what the user leaves switched on, in their order.

**Architecture:** a new `reviewing` phase inside the existing `StockSheetController`. A pure review model (`ReviewEntry` / `ReviewItem`) and a pure builder turn the scans, Item info and dimension-wise Stock Balance rows into the list. The same builder turns the list back into `StockSheetRow`s and a `StockSheetResult`, so the writers and the result screen are reused unchanged. The UI is a `ReorderableListView` with drag handles.

**Tech Stack:** Flutter 3.50, GetX, the existing `ApiProvider.getStockBalanceReport(showDimensionWise:)`, `image_picker` 1.2, the existing `CameraScanOverlay`, and `StorageService` (GetStorage).

**Spec:** `docs/superpowers/specs/2026-11-18-stock-sheet-review-list-design.md` (the addendum, including §9 "settled" calls), over the base spec `docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md`.

## Global Constraints

- **Files unchanged.** Excel/PDF columns, colours, names (`Items-<yyyyMMdd-HHmm>`) and the title `Items` stay as they are. `StockSheetRow` and `StockSheetDocument` get **no new fields**. Balance Qty and rack must never reach the writers.
- **Racks in full.** Rack names are shown in full (e.g. `KA-WH-DXB1-21A`), never trimmed. Chips wrap onto a second line and are sorted by quantity, largest first. Three are shown, then `+n`. An empty rack shows `No rack`. Out of stock shows the pill `Out of stock · 0` and no chips.
- **One stock call for the batch.** Stock comes from `getStockBalanceReport(..., showDimensionWise: true)` with `warehouses: ['Finished Goods - KA']`, today's date, and chunks of 100. Only a typed fix makes its own two calls (Item plus stock for one code).
- **100-photo limit** across the whole list, including added photos.
- **Phases:** `idle → decoding → checkingStock → reviewing → (awaitingChoice) → building → done`, plus `error`. Dismissing the out-of-stock question, or a build or share failure, returns to `reviewing` with everything intact.
- **Remembered format:** `StorageService` key `stock_sheet_last_format` (`excel` / `pdf` / `both`). The first time, it is `excel`.
- **Exact copy (British English):**
  - Headings and counts: `Review photos`, `N photos · M on the sheet`, `Make sheet · N photo(s)`.
  - Fixing a code: `✎ Type or scan code`, `Use code`, `Scan`, `Not a barcode or item code`, `Not in ERP`.
  - Add photos and other notes: `Take a photo`, `Choose from gallery`, `Also read: <barcode> · not in ERP`, `Retry check`.
  - Back: `Discard these photos?` with `Keep reviewing` / `Discard`.
  - New share mid-review: `Add these N photos to the list, or start again?` with `Add` / `Start again` / `Cancel`.
  - When the new share won't fit, the dialog body reads `Only K more photos fit (limit 100).`
- **Repo rules** (`CLAUDE.md`):
  - theme surfaces only, and `AppColors` x700/x300 by brightness;
  - `AsyncFilledButton` with an `RxBool` busy flag;
  - lists use `Scrollbar` with a shared controller, nav-bar padding and an "End of list" marker;
  - workers are stored and disposed;
  - British English.
- **Version:** stays **2.41.0+129**, which is unreleased, so there is no bump in this plan.
- **APK builds run on `sys6.it.ka`**, never on the Linux machine (user, 18/11/2026).

## Review Focus

1. **A two-item photo with one item switched off.** The file holds only the switched-on item, and `#` stays 1…n with no gap. Test in Task 2.
2. **Order survives later edits.** A fix keeps the row's position. Added photos append at the end. A reorder made before a fix or an add is kept. Test in Task 4.
3. **A share arriving while the out-of-stock sheet is open over the review list.** The review state is not lost. The pending-share dialog appears after the sheet closes, or replaces it. Test in Task 4.
4. **Rack rows that need merging.** The same rack in two report rows is merged by rack name. A null rack and an empty rack both count as "No rack". A negative total is out of stock. Test in Task 1.
5. **A typed code for an item already in another photo** is allowed and gives two rows (base rule). It must not merge into the other photo. Test in Task 2.

---

## File structure

```
lib/app/modules/stock_sheet/
  model/items_from_photos_models.dart      + RackQty, ItemStock (Task 1)
  model/review_models.dart           NEW ReviewItem, ReviewEntry (Task 2)
  logic/stock_aggregator.dart        + racksByItem (Task 1)
  logic/review_builder.dart          NEW build list / rows / result (Task 2)
  logic/items_from_photos_codec.dart       + resolveTyped (Task 3)
  items_from_photos_controller.dart        reviewing phase, makeSheet, fix, add, pending share, format store (Tasks 4–5)
  widgets/review_list.dart           NEW rows, switches, stock line, footer (Task 6)
  widgets/fix_code_sheet.dart        NEW (Task 6)
  widgets/rack_chips.dart            NEW (Task 6)
  items_from_photos_screen.dart            wiring, PopScope, dialogs, add menu (Task 7)
lib/app/shared/barcode/ean8.dart     + withCheckDigit (Task 3)
lib/app/data/providers/items_from_photos_provider.dart   showDimensionWise: true (Task 1)
lib/app/data/services/share_intake_service.dart    offerShare (Task 5)
```

`widgets/format_sheet.dart` is no longer used to start a run. Task 7 deletes it if nothing else imports it. `StockSheetChoiceSheet` (in that file) is still used by the out-of-stock sheet, so it moves to `widgets/items_from_photos_choice_sheet.dart`.

---

### Task 1: Rack-aware stock

**Files:** modify `items_from_photos_provider.dart`, `items_from_photos_models.dart` and `stock_aggregator.dart`. Tests in `test/unit/stock_aggregator_test.dart` and `test/unit/items_from_photos_provider_test.dart`.

**Interfaces:**
- Produces:
  - `class RackQty { final String? rack; final double qty; }` (const, value equality; `rack` is null for "No rack").
  - `class ItemStock { final double total; final List<RackQty> racks; bool get outOfStock => total <= 0; }`. `racks` is sorted by qty descending and includes only racks with qty > 0.
  - `static Map<String, ItemStock> StockAggregator.racksByItem(List<Map<String, dynamic>> rows)`:
    - groups by `item_code`, then by `rack` (null and blank both become null);
    - sums `bal_qty` (int, double or numeric string; anything unparsable is skipped);
    - `total` is the sum over all rows for the item.
- `fetchFinishedGoodsStock` now passes `showDimensionWise: true`. `sumByItem` keeps working on those rows.

- [ ] **Step 1: write the failing tests.**
  - `racksByItem` on rows `[{item_code:'1002312',rack:'KA-WH-DXB1-21A',bal_qty:300},{item_code:'1002312',rack:'KA-WH-DXB1-14D',bal_qty:72},{item_code:'1002312',rack:'KA-WH-DXB1-21A',bal_qty:'5'},{item_code:'1001579',rack:null,bal_qty:10},{item_code:'1001579',rack:'',bal_qty:4},{item_code:'1004765',rack:'X',bal_qty:-2}]`:
    - 1002312 → total 377, racks `[21A 305, 14D 72]`;
    - 1001579 → total 14, racks `[RackQty(null,14)]`;
    - 1004765 → total −2, `outOfStock` true, racks empty.
  - The provider test asserts the report is called with `showDimensionWise: true`, the existing arguments unchanged.
- [ ] **Step 2:** run `flutter test test/unit/stock_aggregator_test.dart test/unit/items_from_photos_provider_test.dart`. Expect it to fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run the same command. Expect it to pass.
- [ ] **Step 5:** commit `feat(stock-sheet): rack-wise stock from the Stock Balance report`.

### Task 2: Review model and builder (pure)

**Files:** create `model/review_models.dart` and `logic/review_builder.dart`. Test in `test/unit/review_builder_test.dart`.

**Interfaces:**
- Consumes: `PhotoScan`, `ClassifiedCode`, `ItemInfo`, `StockSheetRow`, `StockSheetResult`, `UnresolvedEntry` / `UnresolvedReason` (base), and `ItemStock` (Task 1).
- Produces:
  - `class ReviewItem { final ClassifiedCode code; final ItemInfo info; final ItemStock? stock; final bool included; ReviewItem copyWith({bool? included}); }`. It is resolved, so `info` is non-null.
  - `class ReviewEntry`:
    - fields: `final String path; final bool decodeFailed; final List<String> rawValues; final List<ReviewItem> items; final List<String> notInErp; final bool typed; final bool unchecked;`
    - `bool get resolved => items.isNotEmpty;`
    - `bool get included => items.any((i) => i.included);`
    - `ReviewEntry copyWith(...)`
    - `unchecked` means an added photo whose stock check failed (Retry check).
  - `class ReviewBuilder`:
    - `static ReviewEntry entryFor(PhotoScan scan, Map<String, ItemInfo> items, Map<String, ItemStock> stock)`:
      - items found in `items` become `ReviewItem(included: true)`;
      - codes not found go to `notInErp` as barcodes;
      - an entry with no resolved items has none included.
    - `static List<ReviewEntry> setIncluded(List<ReviewEntry> list, int index, bool on)`: row switch. On sets all its items on; off sets all off. A no-op for an unresolved entry.
    - `static List<ReviewEntry> setItemIncluded(List<ReviewEntry> list, int index, int itemIndex, bool on)`
    - `static List<ReviewEntry> reorder(List<ReviewEntry> list, int oldIndex, int newIndex)`: Flutter `ReorderableListView` semantics (when newIndex > oldIndex, decrement it).
    - `static int sheetPhotoCount(List<ReviewEntry> list)`: entries with ≥ 1 included item.
    - `static StockSheetResult toResult(List<ReviewEntry> list)`:
      - **rows:** one `StockSheetRow` per included item, in list order. `photoIndex` is the entry's position in the list. `outOfStock` is `stock == null || stock.outOfStock`.
      - **unresolved:** for each **unresolved** entry still in the list, an `UnresolvedEntry` with reason `unreadable` (decodeFailed), `notInErp` (with the first barcode) or `noRecognisedCode`. A resolved entry's leftover `notInErp` codes and switched-off entries add nothing.

- [ ] **Step 1: write the failing tests.**
  - `entryFor`:
    - two codes, one known and one unknown → 1 item and `notInErp:['99999995']`;
    - all unknown → unresolved, with `included` false;
    - decodeFailed → unresolved.
  - Switch rules:
    - row off on a two-item entry → both off, entry not included;
    - item off then the other off → entry not included;
    - row on → both on;
    - `setIncluded` on an unresolved entry changes nothing.
  - `reorder(list, 0, 3)` on `[a,b,c,d]` → `[b,c,a,d]`; `reorder(list, 3, 0)` → `[d,a,b,c]`.
  - **Review focus 1:** `toResult` on `[twoItemEntry(itemA on, itemB off), entryC]` → rows `[A, C]` with photoIndex `[0, 1]`.
  - **Review focus 5:** two entries both holding item 1002312 → two rows.
  - Switched-off entries produce neither rows nor unresolved; unresolved entries produce one unresolved each, with the right reason.
- [ ] **Step 2:** run `flutter test test/unit/review_builder_test.dart`. Expect it to fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run the same command. Expect it to pass.
- [ ] **Step 5:** commit `feat(stock-sheet): review list model and builder`.

### Task 3: Typed-code resolution

**Files:** modify `lib/app/shared/barcode/ean8.dart` and `logic/items_from_photos_codec.dart`. Tests in `test/unit/items_from_photos_codec_test.dart`.

**Interfaces:**
- `static String Ean8.withCheckDigit(String code7)` throws `ArgumentError` unless it gets exactly 7 digits.
- `static ClassifiedCode? StockSheetCodec.resolveTyped(String input)`:
  - trims the input, then tries `classify`;
  - otherwise exactly 7 digits → `ClassifiedCode(itemCode: input, barcode: Ean8.withCheckDigit(input), batchNo: null)`;
  - anything else → null.

- [ ] **Step 1: tests.**
  - `withCheckDigit('2001136')` → `'20011369'`, and `'1004765'` → `'10047651'`.
  - `resolveTyped(' 2001136 ')` gives barcode `20011369`.
  - `resolveTyped('30003330-4CPIWR')` gives itemCode `3000333` and the batch kept.
  - `resolveTyped('20011362')` → null (bad checksum, and 8 digits so not an item code).
  - `resolveTyped('ABC')` → null.
  - `resolveTyped('200113')` → null.
- [ ] **Step 2:** run, expecting a failure.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, expecting a pass.
- [ ] **Step 5:** commit `feat(stock-sheet): resolve typed item codes and barcodes`.

### Task 4: Controller core: read, check, review, make sheet

**Files:** modify `items_from_photos_controller.dart`. Test in `test/unit/items_from_photos_controller_test.dart`, updating the existing tests to the new API.

**Interfaces:**
- Consumes Tasks 1–3.
- Produces (all on `StockSheetController`):
  - `enum StockSheetPhase` gains `reviewing`, placed after `checkingStock`.
  - `abstract class SheetFormatStore { SheetFormat read(); void write(SheetFormat f); }`. The default implementation is backed by `StorageService` with key `stock_sheet_last_format`. Add a constructor parameter `SheetFormatStore? formatStore`.
  - `final review = <ReviewEntry>[].obs;`
  - `final format = SheetFormat.excel.obs;`, initialised from the store in `onInit`.
  - `int get sheetPhotoCount`
  - `Future<void> start(List<String> paths)`:
    - the format parameter is removed;
    - it decodes, then checks stock (Items, and stock with racks via `racksByItem` and `sumByItem`), then fills `review` via `ReviewBuilder.entryFor`, then `phase = reviewing`;
    - the over-100 message and the error and 403 handling are unchanged;
    - `retry()` from `error` re-checks without decoding again.
  - `void reorder(int o, int n)`, `void setIncluded(int i, bool on)` and `void setItemIncluded(int i, int j, bool on)` delegate to `ReviewBuilder`. They are ignored unless the phase is `reviewing`.
  - `Future<void> makeSheet(SheetFormat f)`:
    - ignored unless `reviewing` and `sheetPhotoCount > 0`;
    - stores `f`, then computes `result = ReviewBuilder.toResult(review)`;
    - if it has out-of-stock rows → `awaitingChoice`, otherwise it builds.
  - `chooseOutOfStock(null)` → back to `reviewing`. The result is cleared and the review is kept.
  - A build or share failure → `reviewing` with `errorMessage` set. The message is cleared on the next `makeSheet`.
  - File subtitle (spec §9.2):
    - N photos = `sheetPhotoCount`;
    - M items = rows in the file;
    - "K out of stock" counts included out-of-stock items, and is left out for `leaveOut`.
- `takeShare(paths)` keeps today's behaviour for now: it refuses while busy, otherwise resets and stores `sharedPaths`. The screen now calls `start(sharedPaths)` directly, with no format sheet. Task 5 replaces it.

- [ ] **Step 1: tests** (fakes as now, plus a fake `SheetFormatStore`).
  - `start` with 3 photos (known, out of stock, unreadable) ends in `reviewing`, with review entries in share order and `included` = `[true, true, false]`.
  - `makeSheet(pdf)` with nothing out of stock builds a PDF only, stores `pdf`, and `onInit` of a new controller presets `pdf`.
  - Reorder then `makeSheet` → the document's row order follows the review.
  - Switching off the out-of-stock entry means no out-of-stock question.
  - `chooseOutOfStock(null)` → `reviewing`, with `review` unchanged.
  - Build failure → `reviewing` with the message.
  - The subtitle reads `… · 1 photo · 1 item` when one of two photos is switched off.
  - **Review focus 2** (the order part): reorder, then `setIncluded`, keeps the order.
- [ ] **Step 2:** run, expecting a failure.
- [ ] **Step 3:** implement. Then update the screen minimally so the app still compiles: call `start(paths)` and show a plain placeholder for `reviewing` (Task 7 replaces it).
- [ ] **Step 4:** run `flutter test test/unit/ test/widget/items_from_photos_screen_test.dart`. Expect it to pass. Adjust the existing screen tests that assumed the format sheet comes first.
- [ ] **Step 5:** commit `feat(stock-sheet): review phase and make-sheet in the controller`.

### Task 5: Controller: fix, add, pending share

**Files:** modify `items_from_photos_controller.dart` and `share_intake_service.dart`. Tests in `test/unit/items_from_photos_controller_test.dart` and `test/unit/share_intake_service_test.dart`.

**Interfaces:**
- `Future<String?> fixCode(int index, String input, {String? noteBarcode})`:
  - `resolveTyped`; null → returns `'Not a barcode or item code'`.
  - Otherwise `fetchItems([code])` and `fetchFinishedGoodsStock([code])`:
    - unknown → `'Not in ERP'`;
    - found, `noteBarcode` null (an unresolved row) → replace the entry's items with that one item (included), clear `notInErp`, set `typed: true`, keep the position and path, and return null;
    - found, `noteBarcode` set (fixing an `Also read` note on a resolved row) → **append** the item (included), remove only that barcode from `notInErp`, set `typed: true`, and return null.
  - 403 or network errors return the base messages.
  - A per-call busy flag `fixing` (`RxBool`).
- `Future<String?> addPhotos(List<String> paths)`:
  - if `review.length + paths.length > 100` → returns `'Only K more photos fit (limit 100).'` and adds nothing;
  - otherwise it decodes and thumbnails them, then checks stock for the new codes only, and appends entries;
  - if the check fails, it appends them with `unchecked: true` and returns null;
  - `adding` (`RxBool`) plus progress through `decoded` / `total` for the new batch.
- `Future<void> retryCheck(int index)` re-checks one unchecked entry.
- **Pending share:**
  - `enum ShareOffer { started, pending, refusedBusy }`
  - `ShareOffer offerShare(List<String> paths)`:
    - busy (building or decoding) → `refusedBusy`;
    - `reviewing` or `awaitingChoice` → stores `pendingShare` (`RxList<String>`) and returns `pending`;
    - otherwise it resets, starts and returns `started`.
  - `Future<void> resolvePendingShare(PendingShareChoice c)` with `enum PendingShareChoice { add, startAgain, cancel }`:
    - `add` → `addPhotos`, only offered when the photos fit;
    - `startAgain` → reset, then `start(pending)`;
    - `cancel` → clears the pending share.
  - `bool get pendingShareFits`
- `ShareIntakeService` calls `offerShare` instead of `takeShare`, and shows the busy snackbar only on `refusedBusy`. `takeShare` is removed.

- [ ] **Step 1: tests.**
  - `fixCode`:
    - `'2001136'` on an unresolved entry at index 2 of 4 → the entry resolves with barcode `20011369`, `typed`, and the same index;
  - fixing the note `99999995` on a resolved one-item entry with `'1004765'` → the entry holds 2 items and `notInErp` is empty;
    - `'ABC'` → the error text;
    - an unknown code → `'Not in ERP'`;
    - **Review focus 5**: a code already present in entry 0 still resolves entry 2.
  - `addPhotos`:
    - 98 + 3 → the limit message, nothing added;
    - 2 new photos are appended after a reorder (**Review focus 2**);
    - a failed check leaves them unchecked; `retryCheck` resolves one.
  - `offerShare`:
    - while `reviewing` → `pending`, with the review untouched;
    - while `awaitingChoice` → `pending` (**Review focus 3**);
    - `resolvePendingShare(add)` appends; `(startAgain)` replaces; `(cancel)` keeps the review.
  - The ShareIntakeService tests are updated to `offerShare`.
- [ ] **Step 2:** run, expecting a failure.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, expecting a pass.
- [ ] **Step 5:** commit `feat(stock-sheet): fix codes, add photos and pending shares`.

### Task 6: Review list widgets

**Files:** create `widgets/review_list.dart`, `widgets/rack_chips.dart` and `widgets/fix_code_sheet.dart`. Test in `test/widget/items_from_photos_review_list_test.dart`.

**Interfaces:**
- `ReviewList({required List<ReviewEntry> entries, required Map<String, Uint8List> thumbnails, required void Function(int, int) onReorder, required void Function(int, bool) onToggle, required void Function(int, int, bool) onToggleItem, required void Function(int index, String? noteBarcode) onFix, required void Function(int) onRetryCheck})`:
  - a `ReorderableListView.builder` with `buildDefaultDragHandles: false` and a `ReorderableDragStartListener` on the ⋮⋮ icon;
  - wrapped in a `Scrollbar` with a shared `ScrollController`;
  - the footer spacer covers nav-bar padding, and the list ends with an "End of list" marker.
- **Row content:**
  - Resolved items: name, `barcode · variantOf` (mono), and the stock line.
  - Unresolved rows: the reason text and the `✎ Type or scan code` action. Their switch is disabled.
  - `typed` → a small "Typed" tag. `unchecked` → `Retry check`. Leftover `notInErp` → `Also read: <barcode> · not in ERP` with its own fix action.
- `RackChips({required ItemStock? stock})`:
  - a bold total, then `Wrap` chips `"<rack> <qty>"` with the **full rack name**;
  - `No rack` for a null rack;
  - at most 3 chips, then `+n`, which opens a bottom sheet listing all racks;
  - a long-press on the stock line opens the same sheet;
  - out of stock → the red pill `Out of stock · 0` (`AppColors.red700` / `red300` by brightness) and no chips;
  - quantities are formatted without `.0`.
- `Future<void> showFixCodeSheet(BuildContext, {required Future<String?> Function(String) onSubmit, required Future<String?> Function(BuildContext) scan})`:
  - a text field, `Scan` (default `CameraScanOverlay.show`) and `Use code` (`AsyncFilledButton`);
  - shows the returned error inline;
  - closes when the result is null.

- [ ] **Step 1: widget tests.**
  - Rack chips: a total of `377` with chips `KA-WH-DXB1-21A 305` and `KA-WH-DXB1-14D 72`, the full text present; 5 racks → 3 chips plus `+2`.
  - Out of stock → `Out of stock · 0` and no chips.
  - Dragging a row's handle down one place calls `onReorder(0, 2)`.
  - The switch on an unresolved row is disabled.
  - Dark mode: the surfaces equal `context.scheme.fg` and nothing is `Colors.white`.
  - The fix sheet shows `Not in ERP` when `onSubmit` returns it, and closes on null.
  - "End of list" is present.
- [ ] **Step 2:** run, expecting a failure.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run, expecting a pass.
- [ ] **Step 5:** commit `feat(stock-sheet): review list, rack chips and fix-code sheet`.

### Task 7: Screen wiring

**Files:** modify `items_from_photos_screen.dart`; move `StockSheetChoiceSheet` to `widgets/items_from_photos_choice_sheet.dart`; delete `widgets/format_sheet.dart` if it is unused. Test in `test/widget/items_from_photos_screen_test.dart`.

**Interfaces:**
- Constructor injection for tests: `pickCamera` and `pickGallery`, each a `Future<List<String>> Function()`. The defaults are `ImagePicker().pickImage(source: ImageSource.camera)` and `pickMultiImage()`, mapped to paths.
- **On open:** `controller.start(paths)`. There is no format sheet first.
- **`reviewing`:**
  - AppBar title `Review photos` with the subtitle `N photos · M on the sheet`, and a **＋** action → menu `Take a photo` / `Choose from gallery` → `addPhotos`; its error shows as a snackbar.
  - Body: `ReviewList`.
  - Footer: a `SegmentedButton` (Excel / PDF / Both) bound to `controller.format`, `errorMessage` when set, and `AsyncFilledButton` `Make sheet · N photo(s)`, disabled at 0.
- **Other phases:** the AppBar stays `Stock sheet`, as now.
- **`PopScope`:** while `reviewing`, Back shows `Discard these photos?` with `Keep reviewing` / `Discard`. Discard pops the screen, and the controller's `onClose` cleans up.
- **Pending share:** an `ever(pendingShare, …)` worker shows the dialog. It appears once any open sheet has closed, or after `_closeSheetsAbove()`. It offers `Add` only when `pendingShareFits`, otherwise the body is `Only K more photos fit (limit 100).`
- The out-of-stock sheet is wired as now. Its dismissal returns to the list, because the controller handles it.

- [ ] **Step 1: widget tests.**
  - The share opens straight into reading, then the review list, with no format sheet.
  - The segmented control shows the stored format.
  - `Make sheet · 2 photos` is disabled after switching both off.
  - Back while reviewing shows the dialog; `Keep reviewing` stays.
  - A pending share while reviewing shows the dialog with `Add` / `Start again` / `Cancel`; 99 + 3 shows only `Start again` / `Cancel` with the limit text.
  - The ＋ menu → the gallery fake → `addPhotos` is called with its paths.
- [ ] **Step 2:** run, expecting a failure.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run `flutter test test/widget/items_from_photos_screen_test.dart`, then the full `flutter test`, then `flutter analyze` on the changed files. Expect no new issues.
- [ ] **Step 5:** commit `feat(stock-sheet): review screen wiring, add photos and guards`.

### Task 8: Device check (APK built on sys6)

- [ ] **Step 1:** build a debug `.dev` APK **on sys6**. Follow memory `sys6-windows-build-host`: bundle the branch, fetch it into a detached worktree, add `applicationIdSuffix = ".dev"` locally there, run `flutter build apk --debug`, then `scp` the APK back.
  - sys6's debug key differs from Linux's, so uninstall the current `.dev` first (the user signs in again), or use the suffix `.review` so the old app stays. Ask the user which.
- [ ] **Step 2:** on the XCover7, the user shares the 16 `StockSheetTest` photos. Check:
  - review rows in share order, each with Balance Qty and **full** rack chips;
  - 1004765 shows `Out of stock · 0`;
  - 3000299 and 3000302 start switched off.
- [ ] **Step 3:** run through the list:
  - reorder two rows;
  - switch one photo off;
  - fix 3000299 by typing `1002312`, which should show "Typed" and racks;
  - ＋ → Choose from gallery → add 1 photo;
  - Make sheet with Both → out-of-stock question → Leave them out.
- [ ] **Step 4:** pull the files (a debug build, so `run-as`). Check:
  - the row order equals the review order;
  - switched-off photos are absent;
  - no rack or quantity text appears anywhere in `sheet1.xml` or the PDF text (`pdftotext`).
- [ ] **Step 5:**
  - press Back on the review list → the dialog appears;
  - send a share (`am start … SEND`) while reviewing → the Add / Start again dialog appears.
- [ ] **Step 6:** update the addendum's status line to say it is implemented and what was verified, then commit. No version bump, no push.
