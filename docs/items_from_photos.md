# Items from Photos — feature context (single file)

The one document to read before working on **Items from Photos**: what it does, every screen and message, the
rules behind it, how each platform gets photos in, where the code lives, and what is still open. Written on
18 November 2026, current as of **2.45.0+133** plus two unreleased changes of 19 November 2026: the fix for a
photo of one small label and the reading redesign (reading in two rounds, live rows, the card; see §3, §4 and
§8). The dated specs and plans in `docs/superpowers/` are the history; this file is the summary. Where they
disagree, the code and this file win.

Code identifiers keep the old name: module `lib/app/modules/stock_sheet/`, classes `StockSheet*`, route
`AppRoutes.STOCK_SHEET`. User-facing text always says **Items from Photos** (capital P).

## 1. The user story

Staff photograph the labels on items (each label carries an EAN-8 barcode and/or a batch QR code). They need a
list of those items with their stock, as an **Excel** and/or **PDF** titled **Items**, to send on (WhatsApp,
e-mail, Drive) or save.

- **On a phone (Android, iPhone):** select the photos in the gallery or Photos → Share → **Multimax**. The app
  shows the list at once, reads every label and checks stock while the user watches, lets the user review the list,
  then generates the file.
- **At a Mac (office staff):** the photos were taken on phones and synced into **OneDrive**. Staff work folder by
  folder: share or drag photos from one Finder folder, add more from another, then generate and **Download** the
  file. On the Mac, Multimax is the **iPad app** running on Apple silicon (from the App Store or TestFlight); there
  is no native macOS build.
- **Telegram twin:** the company bot has the same feature (**📋 Items from Photos**). The app is the reference;
  user-facing changes are mirrored there (see §11).

## 2. Ways in

| Route | Platforms | What happens |
|---|---|---|
| **Share** from the gallery / Photos | Android, iPhone | Photos arrive through `receive_sharing_intent`; the screen opens on them. |
| **Share** from Finder | Mac | Our own share screen copies the files into the App Group and opens Multimax. |
| **Drag and drop** onto the window | Mac (and iPad) | The Runner's drop handler copies the files and hands them over like a share. |
| **Item list** icon (photo-stack, tooltip "Items from Photos") | all | Opens the screen's start state. |
| **Dashboard** scan bar icon (same icon, beside the camera) | all | Opens the start state. No Dashboard card. |
| **Choose files…** / **Choose from gallery** / **Take a photo** | all (camera hidden on the Mac) | On the start state, and in the review list's **＋** menu. |

Both icons are shown only to users who can run the Stock Balance report (`DocTypeGuard(doctype: 'Stock Entry',
permType: 'report')`, the same guard as the side menu's Stock Balance entry).

A share or drop that arrives while signed out is held, and the screen opens after sign-in with the same photos.
A share that arrives on any screen opens Items from Photos on top; one that arrives while the list is open asks
first (§3.6).

## 3. The flow and every screen

```
Start state (opened without photos)   or   photos arrive (share / drop / pick)
        ▼
Reading photo 1 of N   (only while the photos are fingerprinted: duplicates, the 100-photo limit)
        ▼
REVIEW LIST ("Review photos") opens at once, one row per photo, with the reading strip
   round one: every photo's whole-photo pass, then one Item call + one Stock Balance call per 100 codes
   round two: the photos that need it are "zoomed in on", one at a time, in list order
   meanwhile: ＋ add photos · swipe to remove · type/scan a code · reorder · switches · open a card
        ▼   Excel | PDF | Both  ·  Generate file · M items  (enabled once every row is settled)
Any switched-on item out of stock? ── yes → out-of-stock question
        ▼
Generating the file…  →  system share sheet  →  FINISHED screen  (Share files · Download · Done)
```

### 3.1 Start state

Shown only when the screen was opened with no photos (never flashes in front of a share). Text:
"Choose photos of item labels to list their stock as Excel or PDF." Buttons: **Choose files…** (filled),
**Choose from gallery**, **Take a photo** (outlined; hidden on the Mac). On the Mac only:
"On a Mac you can also drag photos here or share them from Finder."

### 3.2 Reading: the strip

There are no separate reading and checking screens. Only the moment the photos are fingerprinted (duplicates by
content, the 100-photo limit) shows a progress view, "Reading photo 1 of N" with an indeterminate bar; then the
review list opens with a row for every photo. Over 100 photos: "Share up to 100 photos at a time (you shared N)."
and nothing is processed.

Under the title, a **reading strip** (hidden once every row is settled) shows a determinate bar of photos read and
one of four lines of text with a tally. It is a polite live region, so a screen reader hears the line and the tally
when they change, not every row. It is built from the same rows as the list and rebuilds with it (the review body's
`Obx`); it has no `Obx` of its own.

- Round one: **Reading photo n of N** · "k read"
- Round two: **Zooming in on photo n of N…** · "k read · m to go"
- Round two, between two zooms (the only photos left are waiting): **Zooming in…** (unnumbered) · "k read · m to go"
- Reading done, stock outstanding: **Checking stock…** · "k read"

N is the highest photo number given in the review, so after removals "of N" can exceed the photos still listed.

### 3.3 Review list

Title **Review photos**; subtitle "N photos · M items so far" while anything is outstanding, then
"N photos · M items in the file" (N counts each photo once, M the items switched on); **＋** action (Take a photo /
Choose from gallery / Choose files…; a spinner replaces it only while photos are being fingerprinted for adding).

**One row per photo from the first frame**, greyed until read. "Photo n" is the photo's number: a counter that only
goes up within one review, so a number is never reused; a row put back with Undo keeps its number; dragging does not
renumber.

| Stage | The row shows |
|---|---|
| Not read yet | placeholder tile, "Photo n", **Not read yet**; dashed outline, no fill |
| Reading | the same, with a spinner and **Reading…**; the photo appears once its quick pass is done |
| Waiting to zoom in | photo, "Photo n", **Waiting to zoom in** (the quick pass found no item, or two or more) |
| Zooming in | photo, "Photo n", orange pill with spinner **Zooming in…** |
| Checking stock | ERP image placeholder, barcode in mono, **Checking stock…** |
| Ready | item name, `barcode · Variant Of`, pill **In stock** (green) or **Out of stock** (red), an arrow |
| Unresolved | "Unreadable photo", "No recognised code", "Not in ERP: <barcode>", **✎ Type or scan code** |

- **Pills** use the `AppColors` ramp (x500 at 13% fill, 35% border, x700 ink in light, x300 in dark); a spinner on a
  pill takes the pill's ink colour. **Balance Qty and racks are no longer on the row** (the rack chips and their
  "Stock by rack" sheet are gone): they are on the card, on screen only, never in the file.
- **A sheet of labels** (two or more items in the quick pass) stays one row, "Photo n · k items so far", with no
  switch, until its tiles are read; it is then replaced in place by its item rows in the sheet's reading order, then
  one "Not in ERP: <barcode>" row per code ERP does not know. A photo of one label gives one row.
- **The switch** is disabled until the row has an item. **Generate file** stays disabled until every row is settled.
- **The card:** a tap on a ready row (not on the handle or the switch) opens it, with no ripple (the row's filled
  background would hide it); the arrow at the right of the pill line is the labelled control ("Rack-Wise Stock
  Balance and Stock Ageing", expanded or collapsed) for keyboards and screen readers. Several cards may be open at
  once; a swipe or a drag is not a tap. It has two sections:
  - **Rack-Wise Stock Balance**, from the stock check already made and shown at once: **Rack** and **Balance Qty**,
    one line per rack, largest first; stock on no rack is **No rack**; more than one line adds a total. Out of stock:
    "No stock in Finished Goods - KA."
  - **Stock Ageing**, fetched the first time the card is opened and kept by item code: "Fetching Stock Ageing…"
    with a spinner; then the four figures, labelled as the report's columns title them (`qty`, `average_age`,
    `earliest`, `latest`; today **Available Qty**, **Average Age**, **Earliest**, **Latest**, which are also the
    labels used when a column is missing), and the age buckets titled from the report's range (**Age (0 - 90)** … **Age (721 - Above)**), each with its quantity and a bar scaled to the
    largest bucket. The report's Value columns are not shown. Other states: "Not in the Stock Ageing report.",
    "Not in the Stock Ageing report: nothing in stock." (an out-of-stock item is not fetched), "Couldn't load Stock
    Ageing." with **Retry**, "You don't have access to Stock Ageing." (the rest of the card still works).
- **Unresolved photos** start off with a reason — "Unreadable photo", "No recognised code", "Not in ERP: <barcode>"
  — and **✎ Type or scan code**: a sheet with a text field ("Barcode or item code"), **Scan** (camera overlay) and
  **Use code**. Input → EAN-8 or batch QR via the codec, else exactly 7 digits as the item code, else
  "Not a barcode or item code"; unknown item → "Not in ERP". A resolved code shows a "Typed" marker. The code
  always lands on the row it was typed for, even if the list changed meanwhile (a photo above becoming several
  rows): the row is named by its id, not its place. Only a settled row with no item can be fixed. If a stock check
  failed, rows show "Stock not checked" with **Retry check**: a tap on any of them re-checks every such row at
  once (one Item call and one stock call for all their codes), each becoming its item rows in place; one spinner
  state covers them all, and a failure leaves them all unchecked and says why.
- **Reorder** with the ⋮⋮ handle on the left (no long-press drag on the row), in every stage. Dragging a row up
  brings it forward in round two (§4).
- **Swipe to remove:** swipe a row right-to-left (red `AppColors.red700` background, white bin icon) in any stage →
  the row leaves the list (the photo's other rows stay); snackbar "Item removed." ("Photo removed." for a row with no
  item) with **Undo** for 5 seconds (it closes when the user leaves the review). Undo puts it back after the row
  that was above it (else before the row that was below it; each found by its id, else by its photo; else at its
  old place, clamped to the list length), never in the middle of another photo's rows, unless the same photo —
  same content — has been added again meanwhile under another path. A photo removed before its turn is never read; one being zoomed in on stops (§4). Removing is disabled while
  a code is being fixed, stock is re-checked, a file is being generated, or the out-of-stock question is open; reading
  and adding do not disable it. Screen readers get a "Remove item" ("Remove photo") action on each row.
- **Footer:** segmented **Excel | PDF | Both**, preset to the last choice (first time: Excel; stored under
  `stock_sheet_last_format` in `StorageService`); **Generate file · M items** (M = items switched on and ready),
  disabled when M = 0, while any row is still being read or checked, or while the list is changing. The controller
  itself also refuses to generate while any row is being read or checked, not only the button.
- List conventions apply: `Scrollbar`, nav-bar padding, "End of list".

### 3.4 Out-of-stock question

Only when a switched-on item is out of stock: "1 item is out of stock" / "N items are out of stock" — "How should
the file show them?" → **Include, colour red** / **Include, no colour** / **Leave them out**. Dismissing it cancels
the run (never a silent default). If every photo in the file is out of stock and the user leaves them out:
"Every photo in the file is out of stock."

### 3.5 Generating, sharing and the finished screen

"Generating the file…", then the system share sheet opens with the file(s). The finished screen shows the summary
("N photos · M items · K out of stock") and only what needs attention: **Out of stock** and **Couldn't use these
photos** (with reasons and thumbnails). With no problems the list is just "End of list". Footer:
**Share file(s)** · **Download** · **Done**.

- **Download** saves each file to a place the user picks: Mac — the standard Save dialog (Downloads, OneDrive, …);
  iPhone — Files' save sheet; Android — the system "Save to" picker. Excel + PDF means two dialogs in turn.
  Messages: "Saved Items-….xlsx." / "Saved 2 files."; cancelling stops quietly (files already saved stay saved);
  a failure says "Couldn't save the file. Try again." Below 400 dp the button shows its icon only. Share and
  Download never run at the same time.

### 3.6 Guarding the user's work

- **Back** on the review list, or while the photos given are fingerprinted ("Reading photo 1 of N"): "Discard
  these photos?" — **Keep reviewing** / **Discard**. From the start state (no photos) Back leaves at once.
- **New photos while reviewing** (share, drop, stranded share): "Add these N photos to the list, or start again?"
  (or "Add this photo …") — **Add** / **Start again** / **Cancel**. Add appends within the limit:
  "Only n more photos fit (limit 100)." / "No more photos fit (limit 100)."
- **Photos already in the list** (judged by content, whatever folder or route): "Those photos are already in the
  list." and nothing is added.
- **New photos while a file is being generated:** "Items from Photos is already generating a file."
- Rotation keeps the state (it lives in the controller).

## 4. Rules

- **Codes:** an EAN-8 with a valid checksum → **Item Code = its first 7 digits**. A batch QR holds only the Batch No,
  `^(\d{8})-[A-Za-z0-9]+$` (e.g. `30003330-4CPIWR`); its 8-digit prefix must pass the EAN-8 checksum and gives the
  item. Invalid checksums and other codes (EAN-13, stray Code 128) are ignored for rows.
- **One row per (photo, item):** several labels of one item in a photo give one row; the same item in two photos gives
  two rows; a photo of several items gives one review row per item (each switched, reordered and removed on its own).
  Row order = review order; within a photo, reading order (rows of labels top to bottom, each left to right).
- **Two rounds:** round one is every photo's whole-photo pass, in list order, before any photo is read in tiles.
  When it ends, one Item call and one Stock Balance call (chunks of 100 codes) cover every code read so far; ERP
  images load alongside. Round two takes the photos that need it one at a time; the next is the **first waiting row
  in the list's current order**, so a row dragged up is read sooner (the one in hand is finished first). When a photo
  is read, its codes not already known get their own Item and stock calls while the next photo is zoomed in on. Item
  and stock answers are kept by item code for the life of one review, so an item seen twice in it is asked for once;
  each new run (a new share, Start again) asks afresh, and a late answer from an earlier review is dropped. A fresh
  answer brings its ERP images before its rows settle; rows settled from answers already in hand load any image
  still missing (one that failed earlier in the review) without waiting for it.
- **Removing and Undo:** a photo removed before its turn is not read. One removed while being zoomed in on stops: no
  further tile is read, its tile files are deleted and the next photo starts; one ML Kit read cannot be
  interrupted, so this happens after the tile in hand (0.1–0.25 s) or, if the tiles are still being written, after
  they are (up to about 4 s; the result is thrown away). A row removed during its quick first pass and put back with
  Undo is read once more; one removed while being zoomed in on returns to "Waiting to zoom in" and is read afresh.
  Known and left as is: Undo does not check the 100-photo limit (remove one, add until full, Undo gives 101).
- **Adding:** ＋ and a share during the review use the same path: the new photos appear as "Not read yet" rows at the
  end and join the rounds. On a device that cannot read barcodes, adding photos ends in the same error state as
  starting ("Reading barcodes from photos isn't supported on this device."), not a message from the add.
- **Reading a photo again in tiles ("Zooming in…"):** the whole photo is read first. **One item** found (an EAN-8 and its batch QR
  count as one item) is the answer and nothing is read again. **Two or more items** (a sheet of labels) or **no
  item at all** (most often one label too small to be found in the whole photo, such as a 1,280 px product card
  whose EAN-8 has bars about 2 px wide) send the photo to nine overlapping tiles (each 60% of the photo's width and
  height, 20% apart, greyscale, enlarged up to 4x towards a 1,200 px side; `logic/sheet_reading.dart`), so codes
  too small to be found whole are added; any label up to 40% of the photo lies whole in some tile. An enlarged
  tile is read twice, smoothed (cubic) and sharp (each pixel repeated): on a small sharp image such as a WhatsApp
  copy of a printed sheet (484 px wide, bars ~1.7 px) smoothing blurred one label of 30 away, the sharp copy reads
  it. A full-size camera photo's tiles are not enlarged (9 reads instead of 18). Every tile is read, even after one
  gives a code: a photo may hold more. Codes come once each, ordered by the boxes the platform reports; codes
  without a box follow in the order found.
- **Last resort for a small photo:** when the first pass and the tiles find no item and the photo's sides are both
  under 2,000 px, a 2x smoothed copy of the whole photo is read (one label larger than a tile that only reads
  enlarged). It runs after the tiles, never before: on the ten wallet cards it read one of the five photos the
  first pass missed, the tiles all five.
- **How the copies are made:** `logic/grey_plane.dart` cuts, enlarges and writes the tiles and the 2x copy (in a
  background isolate). It replaces the `image` package's resize, which takes seconds for each enlarged megapixel
  (one 1,280 px card's 18 tiles: 43 s on a desktop, now 1.6 s there and about 4.2 s on the XCover7), and gives **exactly the package's pixels** (`test/unit/grey_plane_test.dart` compares them), so what ML Kit is
  given did not change. Do not swap in another resize or PNG layout without re-checking both sheets and cards on a
  device. Tiles are read one at a time: `mobile_scanner`'s Android side keeps a single pending result, so two
  `analyzeImage` calls at once would lose one.
- **Timings (XCover7, release build, 19/11/2026), measured before the reading redesign**, when the review list
  opened only after every photo had been read: a photo the first pass reads takes 0.2–0.5 s. A 1,280 px photo
  it misses takes about 7 s more: 4.2 s to write the 18 tiles and 2–4 s to read them. Ten wallet cards, five of them
  missed by the first pass: 39 s of reading, 44 s from choosing the photos to the review list (2.45.0: 4 min 12 s,
  with four of the ten unread). Not measured: a full-size camera photo with no readable code, which now costs nine
  tile reads where it used to cost none (writing its tiles takes about 2.6 s on a desktop, most of it decoding the
  JPEG), and the 30-label sheet, which took about 1½ minutes before the faster copies.
- **Images:** every row's Image (review list, finished screen, Excel and PDF) is the **Item's `image` from ERP**,
  downloaded through the signed-in session (four at a time, alongside the stock check, once per item) and shrunk to a
  ~480 px JPEG. No ERP image (or one that cannot be fetched) → the cell is **blank**. The shared photo is never the
  row's image; it is shown only for rows with no item.
- **Stock** = the item's `bal_qty` in **Finished Goods - KA and its child warehouses** from the core **Stock Balance**
  report (`showDimensionWise` for racks), summed per item. ≤ 0 or no row = **out of stock**. Not in the Item list =
  **not in ERP**. Never Bin, never the `Stock Balance - Custom` report (frozen columns, no Country of Origin).
- **Limit:** 100 photos per run, across the whole list (a photo of several items counts once).
- **Duplicates:** by content (SHA-256 of the file bytes) as well as by path, across every route.
- **The file:** title **Items**; subtitle "dd/MM/yyyy HH:mm · N photos · M items · K out of stock" (N = the photos
  the file's rows came from); file names
  `Items-<yyyyMMdd-HHmm>.xlsx` / `.pdf`; columns **#, Image, Barcode, Variant Of, Country of Origin, Item Name**, plus
  **Stock** ("In stock" / "Out of stock") when out-of-stock rows are included; no Item Code column. Excel is
  hand-written OOXML (`archive`): header fill `305496`, out-of-stock fill `FFC7CE` / text `9C0006`, frozen header,
  auto-filter, A4 fit to width, embedded ERP images (~480 px, JPEG; blank when none). PDF: A4 portrait, repeated header, same colours.
- **Server calls** (standard methods only, v15 and v16): `frappe.client.get_list` on Item (`name in [...]`, fields
  `name, item_name, variant_of, country_of_origin, image`), a plain GET of each Item image's file URL
  (`ApiProvider.getFileBytes`, private files through the session cookie) and `frappe.desk.query_report.run` for Stock Balance
  (`company`, today, `item_code` list, `warehouse: Finished Goods - KA`), in chunks of 100 codes, through
  `ApiProvider.getStockBalanceReport` (which handles v15 < 15.72 by filtering on the device). **Stock Ageing** for
  the card goes through the existing `ApiProvider.runStockAgeingCustom` (`Stock Ageing - Custom` via
  `frappe.desk.query_report.run`) with `company`, `to_date` today, `warehouse: Finished Goods - KA`,
  `range: "90, 180, 360, 720"`, `item_code` and `show_warehouse_wise_stock: 0`; sending filters makes the app send
  `are_default_filters=false`, as the Stock Ageing screen does; one item took about 1.4 s (v16, probed 19/11/2026,
  §10). The card's figure labels and bucket titles come from the run's `message.columns`. No access →
  "You don't have access to stock levels." (from a batch no listed row waits for any more, it is dropped); network
  → "Couldn't reach the ERP. Check the connection and try again."
- Nothing is saved to the ERP.

## 5. Messages (exact copy)

Progress: "Reading photo 1 of N" (fingerprinting), "Generating the file…".
Strip: "Reading photo n of N", "Zooming in on photo n of N…", "Zooming in…", "Checking stock…", "k read",
"k read · m to go".
Subtitle: "N photos · M items so far", "N photos · M items in the file". Footer: "Generate file · M items".
Row stages: "Not read yet", "Reading…", "Waiting to zoom in", "Zooming in…", "Checking stock…", "In stock",
"Out of stock", "Photo n", "Photo n · k items so far", "Stock not checked".
Card: "Rack-Wise Stock Balance", "Rack", "Balance Qty", "No rack", "No stock in Finished Goods - KA.", "Stock Ageing",
"Fetching Stock Ageing…", "Not in the Stock Ageing report.", "Not in the Stock Ageing report: nothing in stock.",
"Couldn't load Stock Ageing.", "Retry", "You don't have access to Stock Ageing.".
Undo snackbar: "Item removed." / "Photo removed.".
Errors and notices: "Share up to 100 photos at a time (you shared N).", "Only 1 more photo fits (limit 100).",
"Only n more photos fit (limit 100).", "No more photos fit (limit 100).", "Those photos are already in the list.",
"Items from Photos is already generating a file.", "Every photo in the file is out of stock.", "Nothing to put in a
file.", "Couldn't build the sheet. Try again.", "Couldn't open the share sheet. Try again.", "Couldn't save the file.
Try again.", "Couldn't open the camera.", "Couldn't open the gallery.", "Couldn't open the file dialog.",
"Couldn't read these photos." (a drop or Mac share where nothing could be copied), "You don't have access to stock
levels.", "Couldn't reach the ERP. Check the connection and try again.", "Reading barcodes from photos isn't
supported on this device." (iOS Simulator), "Something went wrong.".
iOS/Mac share card: "Sending 1 photo to Multimax…" / "Sending N photos to Multimax…", "Opening Multimax…",
"Switch to Multimax to continue.", "Couldn't read these photos.", "Multimax couldn't get these photos in time. Try
fewer, or download them first."

## 6. Platforms

### Android
- `AndroidManifest.xml`: `SEND` and `SEND_MULTIPLE` intent filters for `image/*`; MainActivity is **`singleTask`**
  (with `singleTop` each share started a new activity and engine).
- `android/.../SharedStreamCopier.kt` copies document URIs (Files app, MediaStore) to `cacheDir/shared` as `file://`
  before `super.onCreate` / `onNewIntent`, drops ones it can't copy, and drops a stale share on restore — the plugin
  alone returned unreadable `/storage/...` paths or threw. Found only by real shares, never by `adb` SEND injection.
- `android/build.gradle.kts` has `subprojects { project.evaluationDependsOn(":app") }` — **required** by
  `android_file_picker` (Download); without it the build fails with "Extension with name 'flutter' does not exist".

### iPhone / iPad
- **Share extension** `ios/ShareExtension/` (bundle id `com.ddmco.multimax.ShareExtension`): our own
  `ShareViewController` — no plugin code. It loads each image as a file (retried once as `public.image`), copies it
  into the App Group `group.com.ddmco.multimax`, writes the plugin's hand-over record and opens
  `ShareMedia-com.ddmco.multimax:share`; the plugin's app half (`receive_sharing_intent`, **pinned to exactly 1.9.0**
  for this contract) hands the paths to `ShareIntakeService`. Visible card, 120-second time-out, never hangs, cannot
  be swiped away. Activation: images only, at most 100.
- **Hand-over contract:** group `UserDefaults` key `ShareKey` = JSON array of `{path: file URL string, percent-decoded,
  mimeType, type: "image"}`, plus `MultimaxShareId` (UUID). Pinned by `test/unit/ios_share_extension_contract_test.dart`.
- **`ios/Runner/IntakeBridge.swift`** (channel `com.ddmco.multimax/intake`; Dart side
  `lib/app/data/services/native_intake.dart`): `isRunningOnMac`, `sharedFolders` (App Group root and
  `NSTemporaryDirectory()`), `takeStrandedShare` / `markShareHandled` (a share whose URL never brought the app forward
  is picked up on start or resume; older than 24 h is dropped), drag and drop (`UIDropInteraction` → `tmp/dropped/`
  → `dropped`, or `dropFailed`), and a start-up sweep of image copies older than 24 h.
- Plugins resolve through **Swift Package Manager only** (`receive_sharing_intent`, `file_selector`, `file_picker`
  all ship `Package.swift`). The Mac builds iOS with pre-release **Flutter 3.45**, which resolves older plugin
  versions than CI's 3.50 — check any new plugin there.
- The iOS **Simulator cannot read barcodes from photos** (`mobile_scanner.analyzeImage` needs the GPU), so it never
  reaches the review list. Test reading, review, swipe and Download on a real iPhone or the Mac (TestFlight).
- Full set-up, Apple objects, provisioning profiles (expire 14/11/2027) and the two-target headless signing:
  `docs/ios_share_extension_setup.md`.

### Mac
- The iPad app: Finder **Share → Multimax**, **drag and drop** onto the window, **Choose files…** (OneDrive
  placeholders are downloaded by the system dialog / share), **Download** via the Save dialog. "Take a photo" is
  hidden. Barcode reading works on the Mac.

## 7. Code map

| Piece | File |
|---|---|
| Intake (shares, drops, stranded shares, sign-in hold) | `lib/app/data/services/share_intake_service.dart` (permanent, registered in `main.dart`) |
| Native channel (Dart) | `lib/app/data/services/native_intake.dart` |
| ERP calls | `lib/app/data/providers/stock_sheet_provider.dart` |
| Controller (phases, the reading queue with its two rounds, item and stock cache, review ops, duplicates, add, remove/restore, card and ageing state, make, share, download, clean-up) | `lib/app/modules/stock_sheet/stock_sheet_controller.dart` |
| Screen (start state, review, footer, dialogs, snackbars) | `lib/app/modules/stock_sheet/stock_sheet_screen.dart` |
| Codes, decoding, fingerprints, review model building, stock sums, thumbnails | `lib/app/modules/stock_sheet/logic/` (`stock_sheet_codec`, `photo_decoder`, `sheet_reading`, `grey_plane`, `photo_fingerprint`, `review_builder`, `stock_aggregator`,
`thumbnail_maker`, `reading_status`: the strip's text) |
| Models | `lib/app/modules/stock_sheet/model/` (`stock_sheet_models`, `review_models`: `ReviewEntry`, `ReadStage`; `ageing_models`: `ItemAgeing`, `AgeingState`) |
| Writers | `lib/app/modules/stock_sheet/output/` (`xlsx_stock_sheet_writer`, `pdf_stock_sheet_writer`) |
| Widgets | `lib/app/modules/stock_sheet/widgets/` (`review_list`, `reading_strip`, `stock_card_details`, `fix_code_sheet`, `out_of_stock_sheet`, `stock_sheet_choice_sheet`, `stock_sheet_result_list`, `stock_sheet_start_panel`, `items_from_photos_button`) |
| Entry points | `lib/app/modules/item/widgets/item_list_app_bar.dart`, `lib/app/modules/home/home_screen.dart` + `global_widgets/barcode_input_widget.dart` (`trailingActions`) |
| Android | `AndroidManifest.xml`, `MainActivity.kt`, `SharedStreamCopier.kt`, `android/build.gradle.kts` |
| iOS | `ios/ShareExtension/`, `ios/Runner/IntakeBridge.swift`, `AppDelegate.swift`, `Runner.entitlements`, `Info.plist` |

Phases: `idle → decoding → reviewing → (awaitingChoice) → building → done`, plus `error`. `decoding` lasts only
while the photos are fingerprinted before the list opens; `checkingStock` is gone (a row's stage says it, and the
controller's `reading` flag says that some row is unsettled). `rack_chips.dart` and its sheet were removed. The
decoder has `readWhole` (round one) and `zoomIn` (round two); the single `decode` is gone.
Tests: `test/unit/` — `stock_sheet_controller`, `stock_sheet_codec`, `stock_sheet_photo_decoder`,
`stock_sheet_provider`, `reading_status`, `sheet_reading`, `grey_plane`, `review_builder`, `photo_fingerprint`, `share_intake_service`, `native_intake`, `xlsx_stock_sheet_writer`,
`pdf_stock_sheet_writer`, `ios_share_extension_contract`; `test/widget/` — `stock_sheet_screen`,
`stock_sheet_review_list`, `items_from_photos_button`. CI runs no tests; run `flutter test` before merging.

## 8. Release history

| Version | Date | What | Where |
|---|---|---|---|
| 2.41.0+129 | 17–18/11/2026 | Share to the stock sheet with the review list (Android) | Play (`v2.41.0`); App Store upload, extension inert |
| 2.42.0+130 | 18/11/2026 | iOS Share Extension (plugin's controller); heading "Items from photos" | App Store only |
| 2.43.0+131 | 18/11/2026 | Mac: own share screen, drag and drop, Choose files…, start state, Item list / Dashboard icons, duplicates by content; renamed **Items from Photos**, "Generate file" | Play (`v2.43.0`) + App Store; TestFlight checks passed on Mac and iPhone |
| 2.44.0+132 | 18/11/2026 | Swipe to remove (Undo), Download | Play (`v2.44.0`) + App Store; Mac and iPhone checks passed |
| 2.45.0+133 | 18/11/2026 | A photo of several items: one row per item, tiled reading in sheet order (smooth and sharp copies), ERP images everywhere (blank when none); "Also read" notes and per-item switches gone | Play (`v2.45.0`) + App Store |
| unreleased | 19/11/2026 | **Reading redesign** (will be a MINOR bump): the review list opens at once with a row per photo and the reading strip; photos read in two rounds (quick pass for all, then "Zooming in…" in list order); rows stay usable while reading (switch, reorder, remove with Undo, add); a ready row shows only In stock / Out of stock and opens to Rack-Wise Stock Balance and Stock Ageing; rack chips gone | on `claude/reverent-wozniak-04950e`, not merged, bumped or tagged |
| unreleased | 19/11/2026 | A photo of one small label is read in tiles when the first pass finds nothing (it gave "No recognised code"); tiles and the 2x copy made by `GreyPlane` (same pixels, far faster) | on `claude/reverent-wozniak-04950e`, not merged |

## 9. Testing on devices

- **Android:** a Pixel or the Samsung XCover7 over USB (a side-by-side `.dev` debug install can sit beside the Play
  app). Share real photos from the gallery and from the Files app — `adb` SEND injection does not exercise the real
  paths.
- **iPhone and Mac:** only through TestFlight builds (each costs a build number); the release upload doubles as the
  test build. The Mac is reached over SSH (`ssh sys6.it.ka 'ssh -o BatchMode=yes mbp.it.ka zsh -s' < script.sh`) and
  sometimes drops off the network for minutes; the user drives its screen through RustDesk. Simulator (DeviceHub in
  Xcode 27) covers sharing from Photos, the start state and Choose files, but not reading.

## 10. Open items and known limits

- **The reading redesign on a device (Pixel 7, release build with a side-by-side package name, 19/11/2026).**
  Ten 1,280 px wallet cards through Choose files…: the review was on screen about half a second after the photos
  were confirmed, the first barcode within 1 s, five rows with their stock in about 5 s, and all ten rows complete
  in about 21 s (round one 3.8 s; the five photos the quick pass missed took 3.1–3.6 s each to zoom in on). The
  targets were set for the XCover7, which is slower (44 s before the redesign); **the XCover7, the iPhone and the
  Mac have not been checked.** Also seen on the Pixel:
  - a photo swiped away while "Zooming in…" stopped 1.7 s into its zoom, the next photo started at once, and
    after Undo it was read afresh in its place in the list;
  - a card opened to the rack table at once and Stock Ageing after its fetch (about 3 to 5 s on the phone,
    against 1.4 s for the bare call), two cards open together;
  - a sheet of ten labels (a 900 x 1,360 px test image made from the cards) stayed one row, "Photo n · 8 items
    so far", then became ten rows in sheet order;
  - a code typed for an unreadable file below that sheet, with the fix sheet opened before the sheet's rows
    appeared and submitted after, landed on the unreadable row;
  - Back asked "Discard these photos?"; photos added with ＋ joined the list;
  - Excel: eleven rows in list order, columns #, Image, Barcode, Variant Of, Country of Origin, Item Name,
    Stock; no rack, quantity or ageing column;
  - dark mode: every row state, the strip and an open card.
  Not tried on a device: Retry check after a failed stock check, a drag during a sheet's expansion, Scan in the
  fix sheet while zooming, a share of many photos, a full-size camera photo.
- **Stock Ageing for one item, probed 19/11/2026** against the live v16 server with an API user only (not on v15, not
  as an ordinary user, so a permission the report needs but the stock check does not is unconfirmed; the card then
  says "You don't have access to Stock Ageing."): `Stock Ageing - Custom` through `frappe.desk.query_report.run` with
  `company`, `to_date` today, `warehouse: Finished Goods - KA`, `range: "90, 180, 360, 720"`, `item_code`,
  `show_warehouse_wise_stock: 0` and `are_default_filters=false` took about 1.4 s and returned one row for the item,
  with no warehouse column. Columns: Available Qty, Average Age, Age (0 - 90) … Age (721 - Above) each with a Value
  column (not shown in the app), Earliest, Latest.
- **Sheet photos on a device:** on Android (XCover7, 18/11/2026) the 30-label sheet gave all 30 items in sheet
  order, the right ERP images and blanks in the review, Excel and PDF. Not yet seen on the iPhone/Mac (Vision's
  corner boxes order the rows there).
- **A photo of one small label (19/11/2026):** ten 1,280 px wallet product cards, one EAN-8 each (about 140 x 60 px),
  gave 6 of 10 on 2.45.0 and **10 of 10, ten rows, in 44 s** with the tile fallback (XCover7, release build; the
  photos are kept outside the repo). Not yet seen on the iPhone or the Mac.
- **A second, smaller label beside a readable one is still missed:** a first pass that finds exactly one item is
  never tiled, so a photo of two labels of which only one reads whole gives one row and no warning.
- **Telegram twin** has the sheet-photo changes of 2.45.0 (deployed 18/11/2026) but neither the tile fallback nor the
  redesign. Its sidecar has the tile fallback in its repository but it is not deployed, so the same wallet cards will
  fail there; the bot does not have the wording "Zooming in…" or anything else of the redesign (§11).
- **Known and left as is:** Undo does not check the 100-photo limit (§4); the reading strip rebuilds with the
  list (§3.2).

- **Android Download** was seen on the Pixel 7 on 19/11/2026 for one file (Excel, the system "Save to" picker);
  saving both files in turn has not been seen.
- After the Undo snackbar expires, a later close could dismiss a different snackbar (parked, low impact).
- Swiped rows disappear without the collapse animation (removal happens in `confirmDismiss`).
- A share whose files were swept (older than 24 h) is dropped; a removed photo's copy is deleted only when the screen
  closes (so Undo works until then).
- Copies in `tmp/` from the gallery picker are deleted when the screen closes; after a crash only the 24-hour sweep of
  the App Group, `tmp/dropped/` and `tmp/<bundle id>-Inbox/` catches leftovers.
- `receive_sharing_intent` must stay at exactly 1.9.0 until the extension's hand-over code is re-checked against a new
  version.
- iOS release notes in App Store Connect must cover everything since the last *released* iOS version; "Add for
  Review" is done by hand.

## 11. The Telegram twin

The bot's **📋 Items from Photos** (n8n workflows + a `stocksheet` sidecar + a Mini App review page) gives the same
result: the same decode rules, columns, colours, file names and title, a review step, the Excel / PDF / Both choice
and "Generate file". The old button text and `/sheet` still work. Its source of truth is a git repo on sys6
(`telegram-stock-sheet`); deployment needs the user's go-ahead and backups first. **Rule:** treat the app as the
reference and mirror user-facing changes into the bot.

## 12. Documents

- Specs: `docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md` (base),
  `…/2026-11-18-stock-sheet-review-list-design.md` (review list),
  `…/2026-11-18-items-from-photos-on-mac-design.md` (Mac routes),
  `…/2026-11-18-items-from-photos-swipe-and-download-design.md` (swipe, Download),
  `…/2026-11-19-items-from-photos-reading-redesign-design.md` (reading in two rounds, live rows, the card with
  rack-wise balance and stock ageing; built, unreleased, with an "As built" section; its HTML mock-up sits beside it).
- Plans: the same names under `docs/superpowers/plans/`.
- iOS set-up and Apple side: `docs/ios_share_extension_setup.md`.
