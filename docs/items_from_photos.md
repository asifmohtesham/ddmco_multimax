# Items from Photos — feature context (single file)

The one document to read before working on **Items from Photos**: what it does, every screen and message, the
rules behind it, how each platform gets photos in, where the code lives, and what is still open. Written on
18 November 2026, current as of **2.44.0+132**. The dated specs and plans in `docs/superpowers/` are the history;
this file is the summary. Where they disagree, the code and this file win.

Code identifiers keep the old name: module `lib/app/modules/stock_sheet/`, classes `StockSheet*`, route
`AppRoutes.STOCK_SHEET`. User-facing text always says **Items from Photos** (capital P).

## 1. The user story

Staff photograph the labels on items (each label carries an EAN-8 barcode and/or a batch QR code). They need a
list of those items with their stock, as an **Excel** and/or **PDF** titled **Items**, to send on (WhatsApp,
e-mail, Drive) or save.

- **On a phone (Android, iPhone):** select the photos in the gallery or Photos → Share → **Multimax**. The app
  reads every label, checks stock, lets the user review the list, then generates the file.
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
Reading photo n of N  →  Checking stock…        (one Item call + one Stock Balance call per 100 codes)
        ▼
REVIEW LIST ("Review photos")  ◄── ＋ add photos · swipe to remove · type/scan a code · reorder · switches
        ▼   Excel | PDF | Both  ·  Generate file · N photos
Any switched-on item out of stock? ── yes → out-of-stock question
        ▼
Generating the file…  →  system share sheet  →  FINISHED screen  (Share files · Download · Done)
```

### 3.1 Start state

Shown only when the screen was opened with no photos (never flashes in front of a share). Text:
"Choose photos of item labels to list their stock as Excel or PDF." Buttons: **Choose files…** (filled),
**Choose from gallery**, **Take a photo** (outlined; hidden on the Mac). On the Mac only:
"On a Mac you can also drag photos here or share them from Finder."

### 3.2 Reading and checking

Determinate progress "Reading photo n of N", then "Checking stock…". Over 100 photos: "Share up to 100 photos at a
time (you shared N)." and nothing is processed.

### 3.3 Review list

Title **Review photos**; subtitle "N photos · M in the file"; **＋** action (Take a photo / Choose from gallery /
Choose files…; a spinner replaces it while photos are being added).

- **One row per photo**, in order: thumbnail, then one block per item found in the photo: item name;
  `barcode · Variant Of` in mono type; a stock line with **Balance Qty in bold** (sum over Finished Goods) and one
  **rack chip** per rack with its full name and quantity (e.g. `KA-WH-DXB1-21A 300`), largest first, three shown
  then "+n" (tap or long-press for all, "Stock by rack · <total>"); stock on no rack shows **No rack**; out of stock
  shows the red pill **Out of stock · 0**. Balance Qty and racks are **on screen only, never in the file**.
- **Switches:** one per photo; a photo with several items also has one per item (row off → all off; all items off →
  row off; row on → items back on).
- **Unresolved photos** start off with a reason — "Unreadable photo", "No recognised code", "Not in ERP: <barcode>"
  — and **✎ Type or scan code**: a sheet with a text field ("Barcode or item code"), **Scan** (camera overlay) and
  **Use code**. Input → EAN-8 or batch QR via the codec, else exactly 7 digits as the item code, else
  "Not a barcode or item code"; unknown item → "Not in ERP". A resolved code shows a "Typed" marker. If the stock
  check failed, rows show "Stock not checked" with **Retry check**.
- **Reorder** with the ⋮⋮ handle on the left (no long-press drag on the row).
- **Swipe to remove:** swipe a row right-to-left (red `AppColors.red700` background, white bin icon) → the photo
  leaves the list; snackbar "Photo removed." with **Undo** for 5 seconds (it closes when the user leaves the review).
  Undo puts it back where it was (clamped to the list length) unless the same photo — same content — has been added
  again meanwhile. Disabled while photos are being added, a code is being fixed, stock is re-checked, a file is being
  generated, or the out-of-stock question is open. Screen readers get a "Remove photo" action on each row.
- **Footer:** segmented **Excel | PDF | Both**, preset to the last choice (first time: Excel; stored under
  `stock_sheet_last_format` in `StorageService`); **Generate file · N photos** (N = photos with at least one item
  on), disabled when N = 0 or while the list is changing.
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

- **Back** on the review list: "Discard these photos?" — **Keep reviewing** / **Discard**.
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
  two rows. Row order = review order; within a photo, the order the codes were found.
- **Stock** = the item's `bal_qty` in **Finished Goods - KA and its child warehouses** from the core **Stock Balance**
  report (`showDimensionWise` for racks), summed per item. ≤ 0 or no row = **out of stock**. Not in the Item list =
  **not in ERP**. Never Bin, never the `Stock Balance - Custom` report (frozen columns, no Country of Origin).
- **Limit:** 100 photos per run, across the whole list.
- **Duplicates:** by content (SHA-256 of the file bytes) as well as by path, across every route.
- **The file:** title **Items**; subtitle "dd/MM/yyyy HH:mm · N photos · M items · K out of stock"; file names
  `Items-<yyyyMMdd-HHmm>.xlsx` / `.pdf`; columns **#, Image, Barcode, Variant Of, Country of Origin, Item Name**, plus
  **Stock** ("In stock" / "Out of stock") when out-of-stock rows are included; no Item Code column. Excel is
  hand-written OOXML (`archive`): header fill `305496`, out-of-stock fill `FFC7CE` / text `9C0006`, frozen header,
  auto-filter, A4 fit to width, embedded thumbnails (~480 px, JPEG). PDF: A4 portrait, repeated header, same colours.
- **Server calls** (standard methods only, v15 and v16): `frappe.client.get_list` on Item (`name in [...]`, fields
  `name, item_name, variant_of, country_of_origin`) and `frappe.desk.query_report.run` for Stock Balance
  (`company`, today, `item_code` list, `warehouse: Finished Goods - KA`), in chunks of 100 codes, through
  `ApiProvider.getStockBalanceReport` (which handles v15 < 15.72 by filtering on the device). No access →
  "You don't have access to stock levels."; network → "Couldn't reach the ERP. Check the connection and try again."
- Nothing is saved to the ERP.

## 5. Messages (exact copy)

Progress: "Reading photo n of N", "Checking stock…", "Generating the file…".
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
| Controller (phases, review ops, duplicates, add, remove/restore, make, share, download, clean-up) | `lib/app/modules/stock_sheet/stock_sheet_controller.dart` |
| Screen (start state, review, footer, dialogs, snackbars) | `lib/app/modules/stock_sheet/stock_sheet_screen.dart` |
| Codes, decoding, fingerprints, review model building, stock sums, thumbnails | `lib/app/modules/stock_sheet/logic/` (`stock_sheet_codec`, `photo_decoder`, `photo_fingerprint`, `review_builder`, `stock_aggregator`, `thumbnail_maker`) |
| Writers | `lib/app/modules/stock_sheet/output/` (`xlsx_stock_sheet_writer`, `pdf_stock_sheet_writer`) |
| Widgets | `lib/app/modules/stock_sheet/widgets/` (`review_list`, `rack_chips`, `fix_code_sheet`, `out_of_stock_sheet`, `stock_sheet_choice_sheet`, `stock_sheet_result_list`, `stock_sheet_start_panel`, `items_from_photos_button`) |
| Entry points | `lib/app/modules/item/widgets/item_list_app_bar.dart`, `lib/app/modules/home/home_screen.dart` + `global_widgets/barcode_input_widget.dart` (`trailingActions`) |
| Android | `AndroidManifest.xml`, `MainActivity.kt`, `SharedStreamCopier.kt`, `android/build.gradle.kts` |
| iOS | `ios/ShareExtension/`, `ios/Runner/IntakeBridge.swift`, `AppDelegate.swift`, `Runner.entitlements`, `Info.plist` |

Phases: `idle → decoding → checkingStock → reviewing → (awaitingChoice) → building → done`, plus `error`.
Tests: `test/unit/` — `stock_sheet_controller`, `stock_sheet_codec`, `stock_sheet_photo_decoder`,
`stock_sheet_provider`, `photo_fingerprint`, `share_intake_service`, `native_intake`, `xlsx_stock_sheet_writer`,
`pdf_stock_sheet_writer`, `ios_share_extension_contract`; `test/widget/` — `stock_sheet_screen`,
`stock_sheet_review_list`, `items_from_photos_button`. CI runs no tests; run `flutter test` before merging.

## 8. Release history

| Version | Date | What | Where |
|---|---|---|---|
| 2.41.0+129 | 17–18/11/2026 | Share to the stock sheet with the review list (Android) | Play (`v2.41.0`); App Store upload, extension inert |
| 2.42.0+130 | 18/11/2026 | iOS Share Extension (plugin's controller); heading "Items from photos" | App Store only |
| 2.43.0+131 | 18/11/2026 | Mac: own share screen, drag and drop, Choose files…, start state, Item list / Dashboard icons, duplicates by content; renamed **Items from Photos**, "Generate file" | Play (`v2.43.0`) + App Store; TestFlight checks passed on Mac and iPhone |
| 2.44.0+132 | 18/11/2026 | Swipe to remove (Undo), Download | Play (`v2.44.0`) + App Store; Mac and iPhone checks passed |

## 9. Testing on devices

- **Android:** a Pixel or the Samsung XCover7 over USB (a side-by-side `.dev` debug install can sit beside the Play
  app). Share real photos from the gallery and from the Files app — `adb` SEND injection does not exercise the real
  paths.
- **iPhone and Mac:** only through TestFlight builds (each costs a build number); the release upload doubles as the
  test build. The Mac is reached over SSH (`ssh sys6.it.ka 'ssh -o BatchMode=yes mbp.it.ka zsh -s' < script.sh`) and
  sometimes drops off the network for minutes; the user drives its screen through RustDesk. Simulator (DeviceHub in
  Xcode 27) covers sharing from Photos, the start state and Choose files, but not reading.

## 10. Open items and known limits

- **Android Download** has not been seen on a device yet (the Pixel had only the Play app); check the "Save to"
  picker saves both files.
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
  `…/2026-11-18-items-from-photos-swipe-and-download-design.md` (swipe, Download).
- Plans: the same names under `docs/superpowers/plans/`.
- iOS set-up and Apple side: `docs/ios_share_extension_setup.md`.
