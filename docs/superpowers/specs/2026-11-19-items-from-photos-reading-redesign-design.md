# Items from Photos: reading that shows its work (design)

Date: 19 November 2026. Size: a feature (MINOR bump). Status: approved by the user on 19 November 2026; plan in `docs/superpowers/plans/2026-11-19-items-from-photos-reading-redesign.md`.
Builds on the fix for one small label (`1b1c755f`, `d0dc77b4` on `claude/reverent-wozniak-04950e`, not yet
merged): the tile fallback, `logic/grey_plane.dart` and the decoder's injectable analyser are assumed.
Mock-up: `2026-11-19-items-from-photos-reading-redesign-prototype.html` beside this file (open it in a
browser; Play, or drag the slider). Feature context: `docs/items_from_photos.md`.

## Why

Today the screen shows one bar, "Reading photo n of N", then "Checking stock…", and only then the review
list. On the XCover7 ten wallet product cards took 44 s before a single row appeared, because five of them
needed the tiles (about 7 s each). Nothing says why the bar has stopped, nothing can be checked meanwhile, and
Back drops the run without asking.

The total time is set by ML Kit and cannot be parallelised (`mobile_scanner`'s Android side keeps one pending
result). What can change is the order of the work and what the screen shows while it happens.

## Goals

- The review list opens at once, with a row for every photo.
- Every photo gets the quick whole-photo pass before any photo is read in tiles.
- A row fills in as its photo is read: barcode first, then name and stock.
- The screen says what it is doing and what is left.
- Rows can be switched, reordered and removed while reading goes on.
- A row says only **In stock** or **Out of stock**; a tap opens it to the rack-wise balance and stock ageing.

Targets, same ten cards on the XCover7: first barcode on screen within 1 s (today 44 s); five rows with their
stock within 8 s; everything done no later than today.

## Non-goals

- Reading faster. Tile geometry, the copies and the codec rules are untouched.
- The file. Balance Qty, racks and ageing stay on screen only; columns and layout do not change.
- The finished screen, Download, sharing, the out-of-stock question.
- The Telegram bot (it takes the wording below in its own change).

## Decisions (the user's, 19 November 2026)

1. All photos have rows from the start, greyed until read, so the list never grows under the finger.
2. Rows may be switched off, reordered and swiped away while others are still being read.
3. The main list shows only **In stock** (or **Out of stock**); no quantity, no rack chips.
4. A tap on a row opens the card to **Rack-Wise Stock Balance** and **Stock Ageing**.
5. Stock Ageing is fetched the first time a card is opened, not with the stock check.
6. A photo removed while it is being read in tiles stops at once.
7. The wording for the tile pass is **Zooming in…**, in the app and in the Telegram bot.
8. A sheet of labels stays one row until it is zoomed in on, then becomes its item rows.
9. Zooming in follows the list from the top, so a row dragged up is read sooner.
10. The Stock Ageing section shows quantity columns only; the report's Value columns are left out.

## Design

### Row states and wording (exact copy)

| State | Row shows | When |
|---|---|---|
| Not read yet | photo, "Photo n", **Not read yet**; dashed outline, no fill | before its quick pass |
| Reading | the same, with a spinner and **Reading…** | during its quick pass |
| Waiting to zoom in | photo, "Photo n", **Waiting to zoom in** | quick pass found no item, or two or more (see below) |
| Zooming in | photo, "Photo n", orange pill with spinner **Zooming in…** | its tiles are being written and read |
| Checking stock | ERP image placeholder, barcode in mono, **Checking stock…** | read; Item and stock not back yet |
| Ready | item name, `barcode · Variant Of`, pill **In stock** or **Out of stock**, an arrow | Item and stock known |
| Unresolved | as today: "Unreadable photo", "No recognised code", "Not in ERP: <barcode>", **✎ Type or scan code** | nothing found after zooming in |

"Photo n" is the photo's number in the order it was given, and does not change when rows are dragged.
The switch is disabled until the row has an item. Pills follow the StatusPill convention (x500 at 13% fill, 35%
border, x700 ink in light and x300 in dark): green for In stock, red for Out of stock, orange for Zooming in.

Strip under the title (hidden when everything is settled), with a determinate bar of photos read:

- round one: **Reading photo n of N** · "k read"
- round two: **Zooming in on photo n of N…** · "k read · m to go"
- reading done, stock outstanding: **Checking stock…** · "k read"

Title **Review photos**; subtitle "N photos · M items so far" while anything is outstanding, then
"N photos · M items in the file" as today. **Generate file · M items** counts switched-on items that are
ready and stays disabled until every row is settled (as it is today "while the list is changing").
Screen readers hear the strip's line when it changes (a polite live region), not every row.

### Reading in two rounds

1. Duplicates by content and the 100-photo limit are settled first, as now; then the list opens with one
   row per photo.
2. **Round one:** each photo's whole-photo pass, in list order. One item → the row goes to Checking stock.
   No item, or two or more → Waiting to zoom in.
3. When round one ends, one Item call and one Stock Balance call cover every code read so far (chunks of 100,
   as now); ERP images load alongside.
4. **Round two:** the waiting photos, one at a time: tiles, then (small photo, still nothing) the 2x copy.
   The next photo to zoom in on is the **first waiting row in the list's current order**, so dragging a row
   up brings it forward (decision 9); the photo already being zoomed in on is finished first. A photo put
   back with Undo waits its turn again by its place in the list. When a photo is read, its codes that are not already known get their own Item and
   stock calls while the next photo is zoomed in on. Item and stock results are kept by item code for the
   life of the screen, so an item seen twice is asked for once.
5. **A sheet of labels** (two or more items in the quick pass) stays one row, "Photo n · k items so far",
   until its tiles are read, and is then replaced in place by its item rows in reading order. Reading order
   comes from the tiles' boxes, so the rows cannot be placed sooner. Until then the row has no switch; it
   can be dragged and removed like any other, and its item rows take its place in the list. *(Decision 8;
   the mock-up has no sheet photo.)*

**＋ Add photos** and a share that arrives during the review use the same path: the new photos appear as
"Not read yet" rows at the end and join the rounds. The "Add / Start again / Cancel" question is unchanged.

### Removing, Undo, reordering, switching

- Swipe and the screen reader's remove action work in every row state. A photo removed before its turn is
  not read. A photo being zoomed in on stops: no further tile is read, its tile files are deleted, and the
  next waiting photo starts. One ML Kit read cannot be interrupted, so "at once" means after the tile in
  hand (0.1–0.25 s), or after the tiles are written if that is still running (up to about 4 s; the result
  is thrown away).
- Snackbar "Photo removed." (no item yet) or "Item removed." with **Undo** for 5 seconds, as now. Undo puts
  the row back where it was; a photo that had not finished goes back to Waiting to zoom in and is read
  afresh.
- Reordering by the handle works in every state. Switching works once the row has an item.
- Still blocked, as today: removing while a code is being fixed, a file is being generated, or the
  out-of-stock question is open.
- **Back** asks "Discard these photos?" from the first frame, because the review is on screen from the
  first frame.

### The card

Collapsed, a ready row shows the ERP image (placeholder when none), item name, `barcode · Variant Of` and
one pill. A tap anywhere on the row except the handle and the switch opens it; the arrow at the right of
the pill line is the same control for keyboards and screen readers ("Rack-Wise Stock Balance and Stock
Ageing", expanded or collapsed). Several cards may be open at once. A swipe or a drag is not a tap.

**Rack-Wise Stock Balance** (from the stock check already made; shown at once): a two-column table,
**Rack** and **Balance Qty**, one line per rack, largest first; stock on no rack is the line **No rack**;
more than one line adds a total. Out of stock: "No stock in Finished Goods - KA." This replaces the rack
chips on the row and the "Stock by rack · <total>" sheet, which go.

**Stock Ageing** (fetched on the first opening, kept by item code afterwards):

- Run through the existing `ApiProvider.runStockAgeingCustom` (`Stock Ageing - Custom` via the standard
  `frappe.desk.query_report.run`, already checked on v15 and v16) with the report's saved filter values and
  `item_code` set: `company`, `to_date` today, `warehouse: Finished Goods - KA`, `range: "90, 180, 360, 720"`,
  `show_warehouse_wise_stock: 0`. Sending filters makes the app send `are_default_filters=false`, as the
  Stock Ageing screen does once a filter is changed.
- Parsed with `StockAgeingLogic`, so column titles are the report's own and the buckets are titled from the
  range in effect: **Available Qty**, **Average Age**, **Earliest**, **Latest**, **Age (0 - 90)** …
  **Age (721 - Above)**, each bucket with its quantity and a bar scaled to the largest bucket. The
  report's **Value (…)** columns are not shown (decision 10): Items from Photos shows quantities only.
- States: "Fetching Stock Ageing…" with a spinner; the figures; "Not in the Stock Ageing report." when the
  run returns no row; "Couldn't load Stock Ageing." with **Retry** when it fails. An out-of-stock item is
  not fetched: "Not in the Stock Ageing report: nothing in stock."
- On screen only; never in the file.

### Code

- **`PhotoDecoder`** (`logic/photo_decoder.dart`): `decode` splits into `readWhole(path)` (round one) and
  `zoomIn(path, {required whole, bool Function()? stopped})` (tiles, then the 2x copy; `stopped` is asked
  after the tiles are written and before each tile read; a stopped zoom returns null and deletes its
  files). The rule "one item needs no zoom" stays in one place.
- **`ReviewEntry`** (`model/review_models.dart`): a `stage` (not read, reading, waiting, zooming, checking
  stock, settled). A placeholder entry exists for each photo from the start and is replaced in place by its
  item rows; ids stay as documented (`<photo>:<item>`, `<photo>!<barcode>`, the photo's path).
- **`StockSheetController`**: `start` and `addPhotos` share one reading queue; phase `reviewing` is entered
  as soon as the photos are fingerprinted, and `decoding` / `checkingStock` go. `canRemove` no longer
  depends on reading. New: the item-and-stock cache by item code, `openCard` / per-item ageing state, and a
  `reading` flag for the footer. Failures keep today's messages: no access to stock levels and an
  unsupported device still end in the error state; a failed stock batch leaves its rows "Stock not checked"
  with **Retry check**.
- **`StockSheetProvider`**: `fetchStockAgeing(itemCode)` wrapping the report run.
- **`ReviewList`** (`widgets/review_list.dart`): the row states above, the strip, the expandable card; rows
  keyed so a row that changes state is updated in place, not re-inserted. `RackChips` and its sheet are
  removed.
- Contrast rules apply: no hard-coded surfaces or inks; the dark-mode widget tests cover every row state
  and the open card.

## Verification

- Unit: the controller with a staged fake decoder: round one before any zoom; zoom order follows the list;
  removing the photo being zoomed in on stops it and starts the next; Undo re-queues it; a removed photo is
  never read; stock is asked once per item code; a sheet photo becomes its item rows in reading order;
  adds join the queue; the footer count and its disabled state.
- Unit: `MlKitPhotoDecoder.zoomIn` stops between tiles and leaves no temporary file; `readWhole` plus
  `zoomIn` give what `decode` gave (the existing decoder tests, re-pointed).
- Unit: `fetchStockAgeing` builds the filters above; the card's ageing states.
- Widget: every row state in light and dark; tap opens and closes; swipe and drag do not open; the strip's
  three lines; `flutter analyze`.
- Device (XCover7, release `.dev` build, the ten wallet cards kept outside the repo): the three targets
  above; remove and Undo during a zoom; open a card during reading; the 30-label sheet still gives 30 rows
  in order.

## Left to the builder

- Time a `Stock Ageing - Custom` run filtered to one item, on v15 and v16, as an ordinary user (the
  mock-up assumes 1.5 s), and check that `show_warehouse_wise_stock: 0` with the group warehouse gives one
  row per item; if it gives one per warehouse, show them as the report does rather than adding them up.
- Whether the report run needs a permission the stock check does not; without it the section says
  "You don't have access to Stock Ageing." and the rest of the card works.
- Keep the review list's header rebuild guards in mind: the strip changes several times a second in round
  one; give it its own `Obx`.
- Update `docs/items_from_photos.md` (§3.2, §3.3, §4, §5, §7) and mirror the wording into the Telegram bot.

## As built

Written 19 November 2026, after the nine tasks. The design above stands except for the following rulings made while
building. Nothing of this has been seen on a device yet.

1. The `decoding` phase is kept, only for the moment photos are fingerprinted before the list opens;
   `checkingStock` is gone.
2. Photo numbers come from a counter that only goes up within one review, so a number is never reused; a row put
   back with Undo keeps its number.
3. The controller itself refuses to generate a file while any row is still being read or checked, not only the
   button.
4. A row removed during its quick first pass and put back with Undo is read once more; one removed while being
   zoomed in on returns to "Waiting to zoom in" and is read afresh.
5. On a device that cannot read barcodes, adding photos ends in the same error state as starting, instead of a
   message from the add.
6. Item and stock answers are kept by item code for the life of one review, not of the screen: each new run
   asks afresh (within one review an item is still asked for once), and a late answer from an earlier review is
   dropped. A fresh answer brings its ERP images before its rows settle; rows settled from answers already in
   hand load any image still missing (one that failed earlier in the review) without waiting for it.
7. Tapping a ready row opens its card with no ripple (the row's filled background would hide it); the arrow button
   is the labelled control.
8. `PhotoDecoder.decode` and the controller's `decoded` counter are removed; the decoder tests run both rounds
   through a small test helper.
9. Known and left as is: Undo does not check the 100-photo limit (remove one, add until full, Undo gives 101). The
   strip has no `Obx` of its own: the review body's `Obx` already rebuilds it with the list, from the same rows.
10. Row ids: a photo's placeholder, and a photo that gives one row, have the photo's path as id; the rows of a
    photo that gives several have `<path>#<k>` (k = 0, 1, … in reading order), not the `<photo>:<item>` /
    `<photo>!<barcode>` named under Code above.
11. **Retry check** on any "Stock not checked" row re-checks every such row at once: one Item call and one stock
    call for all their codes, through the same answers the reading uses; each becomes its item rows in place, and
    one spinner state covers them all. A failure leaves them all unchecked.
12. A row not read yet shows a placeholder tile; its photo appears once its quick pass is done (the table under
    Row states says "photo" for "Not read yet").
13. The four Stock Ageing figures (Available Qty, Average Age, Earliest, Latest) are labelled from the report's
    columns (`qty`, `average_age`, `earliest`, `latest`), with those titles when a column is missing; the
    buckets are titled from the range, as before.
14. A code typed to fix a row always lands on that row, even if the list changed while it was typed (the row is
    named by its id, not its place); only a settled row with no item can be fixed. Undo puts a row back after
    the row that was above it, else before the one below it, never inside another photo's rows.
15. In the strip, "of N" is the highest photo number given in the review, so after removals it can exceed the
    photos still listed. Besides the three lines above, the strip says **Zooming in…** (unnumbered) when the
    only photos left are waiting to be zoomed in on.
16. Back while the photos given are fingerprinted asks "Discard these photos?" as in the review; a late "no
    access to stock levels" for rows no longer listed is dropped rather than shown; `zoomIn` asks `stopped`
    once more before the 2x copy.

Left to the builder, answered in part: Stock Ageing for one item was probed on 19 November 2026 against the live
v16 server with an API user only (not on v15, not as an ordinary user): about 1.4 s, one row for the item and no
warehouse column with `show_warehouse_wise_stock: 0`. Whether the report needs a permission the stock check does
not is still open. The Telegram bot takes none of this yet.
