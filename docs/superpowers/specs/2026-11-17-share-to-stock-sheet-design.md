# Share Photos → Items from Photos — Design Spec

**Date:** 17 November 2026
**Feature:** share label photos from the phone's gallery into Multimax and get back an Excel or PDF stock sheet
**Status:** approved by the user on 17/11/2026: the answers in §10 and the recommended approaches in §5
(on-device decode and render, `receive_sharing_intent`, a hand-written `.xlsx` via `archive`).
Revised the same day at the user's direction: stock comes from the `Stock Balance` report, not Bin (§5.4).
**Implemented** on 18/11/2026 in v2.41.0+129. Later user decisions: files are named `Items-<yyyyMMdd-HHmm>` and titled **Items** (the worksheet tab too); the screen keeps the heading "Stock sheet". **Renamed** on 18/11/2026: the feature is called **Items from Photos** everywhere (the screen heading, the busy notice, and the Telegram bot). Code identifiers now use `ItemsFromPhotos*` and `ITEMS_FROM_PHOTOS`. The `stock_sheet` folder and `/stock/stock-sheet` route path are still in use. Android was verified on a Samsung XCover7 (debug and release builds): a signed-out share, a cold start, a warm share via `onNewIntent`, the out-of-stock question, the Excel and PDF contents, and the unreadable / no-code lists. **Not verified:** iOS (never built; the Runner App Group is held back until the profile carries it, see `docs/ios_share_extension_setup.md`), and a warm share started from the gallery's own task (`singleTop`).
**Reference behaviour:** the Telegram **📋 Stock sheet** feature (now **📋 Items from Photos**), built and confirmed working on 17/11/2026
(n8n workflow `Telegram - Stock Sheet` plus the `stocksheet` sidecar: FastAPI, zxing-cpp, openpyxl, reportlab).

## 1. Intent

Staff photograph product labels. Today they get a stock sheet by sending the photos to the Telegram bot, one
list at a time, with albums capped at 10. The app version lets them select every photo in the Photos app, share
it to Multimax, pick a format, and pass the file on (WhatsApp, e-mail, Drive) without leaving the phone.

### User story

1. The user opens the iOS or Android Photos app.
2. The user selects the photos.
3. The user shares them to **Multimax**.
4. Multimax opens with a bottom sheet asking **Excel** or **PDF**.
5. The user picks one.
6. The app decodes the labels, looks up stock and builds the file.
7. The system share sheet offers the file to other apps.

## 2. Rules carried over from Telegram (confirmed by the user on 17/11/2026)

- A photo shows one or more labels. Each label has an **EAN-8 barcode** and/or a **Batch No QR code**.
- **Item Code** is the first 7 digits of a checksum-valid EAN-8. Invalid checksums are ignored.
- A batch QR holds only the Batch No: `^(\d{8})-[A-Za-z0-9]+$`, e.g. `30003330-4CPIWR`. Its 8-digit prefix
  must pass the EAN-8 checksum. The item comes from that prefix, so no Batch lookup is needed.
- **Stock** is the item's balance in **Finished Goods - KA** and the warehouses under it (WH-DXB1 + WH-DXB3
  today), per item, not per batch. Telegram reads it from `Bin.actual_qty`. **The app reads it from the
  `Stock Balance` report** (`bal_qty`, summed per item), as the user decided on 17/11/2026, see §5.4. A total
  ≤ 0, or no row at all, counts as **out of stock**.
- **One row per (photo, item).** Several labels of the same item in one photo give one row. The same item in two
  photos gives two rows.
- Columns: **#, Image, Barcode, Variant Of, Country of Origin, Item Name**, plus **Stock** ("In stock" /
  "Out of stock") when out-of-stock rows are included. **No Item Code column.** Barcode is the 8-digit EAN-8.
- "Not found in ERP / unreadable" is reported separately from "out of stock".

## 3. Server facts (checked on 17/11/2026 against `erp.domain.com`, v16, read-only, API key)

- **Stock Balance report** (`frappe.desk.query_report.run`, `report_name=Stock Balance`) with
  `company=Multimax`, `from_date = to_date = today`, `item_code=[…7 codes…]` (a list) and
  `warehouse="Finished Goods - KA"` returned one row per item × warehouse with stock: 2001136 → WH-DXB1 60,
  2001141 → WH-DXB1 65, 2002349 → WH-DXB1 295. It also returned a trailing `["Total", …]` list row.
  - The group warehouse **includes its child warehouses** (the report filters on `lft/rgt`).
  - Items with no stock (1004954, 1004963, 3000333) **and** the unknown code 9999999 are simply **absent**. There
    is no error, so the report alone can't tell "out of stock" from "not in ERP". The Item call below decides
    that.
  - Its columns (`item_code, item_name, item_group, warehouse, stock_uom, bal_qty, …`) have **no `variant_of` or
    `country_of_origin`**, so the Item call is needed either way.
  - The app already calls the report through `ApiProvider.getStockBalanceReport(itemCodes:, warehouses:, …)`. That
    method sends `item_code` as a list on ERPNext ≥ 15.72, including every v16. On older v15 it omits the item
    filter so the caller narrows the rows on the device (the existing `stockBalanceUsesListFilters` check, the one
    version check `CLAUDE.md` allows). `ApiProvider.parseStockBalanceResponse` keeps only Map rows, so the `Total`
    row is dropped.
- For comparison, `GET /api/resource/Bin` with `["warehouse","descendants of (inclusive)","Finished Goods - KA"]`
  gave the same quantities. v16 rejects `sum(actual_qty)` in `fields` (`SQL functions are not allowed as strings
  in SELECT`), so either source is summed on the device.
- `GET /api/resource/Item` with `filters=[["name","in",[…]]]`,
  `fields=["name","item_name","variant_of","country_of_origin"]` returns the known items. Unknown codes are
  absent, which means "not found".
- The test labels: 2001136 (60), 2002349 (295), 2001141 (65) are in stock. 1004954, 1004963 and 3000333 have no
  Finished Goods stock, so they are out of stock.
- Both calls are standard (`frappe.desk.query_report.run`, `frappe.client.get_list`). There is no Server Script
  and no new version branch.

## 4. Goals, non-goals, anti-goals

**Goals**
- Share → format → file in one flow, from a cold start or with the app already open.
- The same decode rules, rows, columns and colours as Telegram, so the two outputs look alike.
- Two ERP calls per run (Item list + Stock Balance report), chunked if needed, never one call per photo.
- Runs under the user's own session and ERP permissions.

**Non-goals**
- Changing the Telegram feature or the n8n sidecar.
- Per-batch stock, stock per warehouse, or any warehouse other than Finished Goods - KA.
- Saving the sheet to the ERP (no File/Doc is created).
- Picking photos from inside the app. Gallery share is the only entry point. An in-app "Pick photos" button is an
  easy follow-up if wanted.

**Anti-goals** (failure even if it technically works)
- A row for a code the user can't see in the photo: guessing an item from a partial or invalid code.
- Silently dropping a photo. Every shared photo ends up as a row or in the "not found / unreadable" list.
- Losing the shared photos because the user had to sign in first.
- A file too big to send on WhatsApp because full-resolution photos were embedded.

## 5. Approaches considered

### 5.1 Where decoding and rendering happen

1. **On the device: ML Kit / Vision via `mobile_scanner.analyzeImage`, files built in Dart.** *Recommended.*
   No new server surface. Works with the user's own session. Photos never leave the phone. `mobile_scanner` 7,
   `pdf` and `share_plus` are already dependencies, and `analyzeImage` is already used by the search-by-image
   flow (`lib/app/shared/image_scan/`).
2. **Reuse the n8n `stocksheet` sidecar** (`/decode`, `/render`). Its decoding and output are proven. However,
   it is internal-only (`http://stocksheet:8000` on the n8n Docker network). Using it means a new public webhook
   with its own authentication outside Frappe, uploading every full-size photo over mobile data, and a second
   backend the app depends on. Rejected for now. It stays the fallback if on-device decoding proves weaker than
   zxing-cpp on real labels (see §9 risk 1).
3. **A new Frappe whitelisted method** that decodes and renders. This breaks the "standard methods only" rule in
   `CLAUDE.md`. Rejected.

### 5.2 Receiving the share

1. **`receive_sharing_intent` 1.9.0** (published 24/06/2026, Flutter ≥ 3.38, 810 likes, 150/160 pub points).
   *Recommended.* It is maintained, gives `getInitialMedia()` for a cold start and `getMediaStream()` for a warm
   app, copies Android `content://` URIs to cache files, and ships an `RSIShareViewController` base class for the
   iOS Share Extension.
2. `share_handler` 0.0.25 has had no release since 29/07/2025 and has fewer users. Rejected.
3. Hand-written platform channels. More code for no gain. Rejected.

### 5.3 Excel with embedded thumbnails

The `excel` 4.0.6 package already in the app **cannot embed images** (it has no drawing or picture API, and its
last release was in August 2024).

1. **Write the `.xlsx` ourselves with `archive`**, which is already a dependency. *Recommended.* An xlsx is a zip
   of fixed XML parts: workbook, one sheet, styles, one drawing with a `twoCellAnchor` picture per row, and the
   JPEG media. That is about 300 lines of pure Dart. It is unit-testable by unzipping and checking the XML, it has
   no licence question, and it reproduces the Telegram layout exactly (header fill `305496`, red fill `FFC7CE` /
   text `9C0006`, frozen header, auto-filter, A4 fit to width, print title row).
2. `syncfusion_flutter_xlsio` supports images and page setup, but it needs a Syncfusion licence (the free
   community licence has revenue and headcount limits) and a licence key registered at start-up. It also adds a
   large dependency. Rejected unless the user prefers it.
3. Use `excel` without images and put "(no image)" in the column. This fails the agreed column set. Rejected.

### 5.4 Where stock comes from (decided by the user, 17/11/2026)

1. **The `Stock Balance` report**, through the existing `ApiProvider.getStockBalanceReport`. *Chosen.* It reuses
   the call, filter-version handling and parser that the app's Stock Balance screen already uses and tests. It
   expands the group warehouse on the server. It needs the report permission the same users already have for that
   screen, not raw read access to the `Bin` doctype.
2. A `Bin` list with `descendants of (inclusive)`. This was the first draft. It returns the same numbers, but it is
   a second way of reading stock in the app and needs Bin read permission.
3. **`Stock Balance - Custom`** (a Desk Custom Report over Stock Balance). Rejected by the user on 17/11/2026, after
   a live check that day with `are_default_filters=false` and `ignore_prepared_report=true`:
   - Its 18 saved columns include **Variant Of** (TRENZA / GRABIN / ALCE were correct) and Image, but **not
     Country of Origin**.
   - Like the core report, it leaves out items with no stock and unknown codes, even with
     `include_zero_stock_items=1`. Out-of-stock rows would still lack their Variant Of, Country of Origin and Item
     Name, and only the Item call can tell "out of stock" from "not in ERP". So it would not save the Item call.
   - It has `prepared_report = 1`, and its saved filters are fixed to 24/12/2025–24/01/2026. Those replace the
     caller's filters unless `are_default_filters=false` is sent, and they change whenever someone re-saves the
     report on the Desk.

   Stock therefore comes from the **core** report, and item details from the **Item** list.

## 6. Design

### 6.1 Flow

```
Photos app ──share──► Multimax
   │ ShareIntakeService (permanent, main.dart) receives file paths
   │   cold start: getInitialMedia()  ·  warm: getMediaStream()
   ▼
Signed in? ── no ──► Login (photos kept in the service) ── success ──┐
   │ yes                                                            │
   ▼                                                                ▼
More than 100 photos? ── yes ──► message "Share up to 100 photos at a time (you shared N)", nothing processed
   │ no
   ▼
ITEMS_FROM_PHOTOS route  ──► bottom sheet 1: Excel / PDF / Both
   ▼
Progress: "Reading photo 7 of 23…" → "Checking stock…"
   ▼
Any item out of stock? ── yes ──► bottom sheet 2 (as Telegram): Include, colour red /
   │ no                              Include, no colour / Leave them out
   ▼                                 ▼
"Generating the file…" ◄───────────────────┘
   ▼
Result screen: summary counts · out-of-stock list · not-found/unreadable list (with thumbnails)
               [Share file(s)] [Done]
   ▼
share_plus → system share sheet (one file, or both files together for "Both")
```

The format question comes first, as in the user story. The out-of-stock question can only come once stock is
known, which is also where Telegram asks it. Dismissing sheet 2 cancels the run; it never defaults silently.

### 6.2 Pieces

| Piece | Where | Notes |
|---|---|---|
| `ShareIntakeService` (GetxService, permanent) | `lib/app/data/services/share_intake_service.dart` | Registered in `main.dart` next to `ScanService`. Holds `pendingPhotos` (paths). Listens to both streams and stores its `StreamSubscription`, cancelled in `onClose`. When signed in it calls `Get.toNamed(ITEMS_FROM_PHOTOS)`. Otherwise it waits for `isAuthenticated` (an `ever` worker kept in a field) and opens the route after `processSuccessfulLogin` has landed on HOME. It calls `ReceiveSharingIntent.reset()` once consumed, so a rotation or relaunch doesn't replay the share. |
| `ItemsFromPhotosCodec` (pure) | `lib/app/modules/stock_sheet/items_from_photos_codec.dart` | `ean8IsValid`, `classify(String raw) → ClassifiedCode?` (`itemCode`, `barcode`, `batchNo`), `rowsFor(photo, rawCodes)` with de-dupe per item within a photo. `ScanService._isValidEan8` moves here or to a shared util so there is one checksum. |
| `ItemsFromPhotosProvider` | `lib/app/data/providers/items_from_photos_provider.dart` | `fetchItems(codes)` through `ApiProvider.getDocumentList` (filter tuples, `limit: 0`). `fetchFinishedGoodsStock(codes)` through `ApiProvider.getStockBalanceReport(fromDate: today, toDate: today, itemCodes: chunk, warehouses: ['Finished Goods - KA'])`, keeping only rows whose `item_code` is in the chunk (this covers v15 < 15.72, where the item filter is omitted and the whole warehouse comes back). Chunks of 100 codes keep the URL short. |
| `StockAggregator` (pure) | same module | Sums the report's `bal_qty` per `item_code`, ignoring rows without an `item_code`. A missing code gives 0. Builds the final row list with `outOfStock` and `notFound`. |
| `ItemsFromPhotosController` / `Binding` / `Screen` | `lib/app/modules/stock_sheet/` | A GetX module. The controller holds `busy` (`RxBool`, re-entrancy guard, cleared in `finally`), a `phase` and `progress`, and the results. |
| `ThumbnailMaker` | same module | Decodes with `ui.instantiateImageCodec(targetWidth/Height ≈ 480 px long side)`, which honours EXIF orientation natively and is fast. It re-encodes to JPEG q≈82 (`image` package, run in an isolate) so each thumbnail is about 30–60 KB. |
| `XlsxItemsFromPhotosWriter` | same module | Hand-written OOXML via `archive` (§5.3 option 1). |
| `PdfItemsFromPhotosWriter` | same module | `pdf` package. A4 portrait with 12 mm margins, a `MultiPage` table with a repeated header row, the same column widths as reportlab, image max 26 mm, a footer with the title and "Page n", and a red row background when highlighting. |
| Route `ITEMS_FROM_PHOTOS` | `app_routes.dart` / `app_pages.dart` | `rightToLeftWithFade`, like other flow screens. |

### 6.3 Decoding

- `MobileScannerController.analyzeImage(path, formats: [ean8, ean13, qrCode, code128, dataMatrix])` returns a
  `BarcodeCapture` with **all** barcodes ML Kit finds in the image. The flow processes photos one at a time to
  keep memory flat. One controller is created for the run and disposed at the end.
- Each `rawValue` goes through `ItemsFromPhotosCodec.classify`. Codes that don't classify (EAN-13, a stray Code 128)
  are ignored for rows, but they are kept so an "unreadable" photo can say "codes found, none recognised".
- **Fallback for missed codes** (builder's call, matching the sidecar's retries): if a photo yields no recognised
  code, retry once on a 2× upscaled greyscale copy written to the temp dir. Add more retries only if testing on
  real labels shows a need.
- On the iOS Simulator `analyzeImage` is unsupported. The flow shows a clear error rather than "unreadable".

### 6.4 Output

- **File name:** `Items-YYYYMMDD-HHMM.xlsx` / `.pdf`, written to the temp dir and shared with
  `SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: …)]))`.
- **Title / subtitle:** "Items" / "17/11/2026 14:05 · 23 photos · 21 items · 3 out of stock"
  (en-GB date).
- **Row order:** the photo order as shared, and within a photo the order the codes were found.
- **Row colours and Stock column:** per the answer to §10 Q1.

### 6.5 UI conventions (repo rules)

- The format sheet and the result screen use `context.scheme.fg` / `surface` / `subtle`. Inks are
  `scheme.text` / `textMuted`. Out-of-stock text uses `AppColors.red700` / `red300` by theme. Pills use x500 at
  0.13 alpha.
- Async feedback: the buttons are `AsyncFilledButton`, and a determinate progress indicator shows while decoding
  ("Reading photo n of N"), then indeterminate for the ERP calls and building the file.
- The result list follows the list conventions: `Scrollbar` with a shared controller, bottom padding for the nav
  bar, and an "End of list" marker.

### 6.6 Platform setup

**Android** (`AndroidManifest.xml`, `.MainActivity` already `singleTop`):

```xml
<intent-filter>
  <action android:name="android.intent.action.SEND"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <data android:mimeType="image/*"/>
</intent-filter>
<intent-filter>
  <action android:name="android.intent.action.SEND_MULTIPLE"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <data android:mimeType="image/*"/>
</intent-filter>
```

**iOS (written, NOT built or tested here).** CI (`release.yml`) builds Android only, and this machine has no
Xcode. These are the steps on the Mac:

1. In Xcode, add a **Share Extension** target `ShareExtension` with bundle id
   `$(PRODUCT_BUNDLE_IDENTIFIER).ShareExtension`. Set its deployment target to match Runner.
2. Make `ShareViewController` subclass `RSIShareViewController` (from `receive_sharing_intent`). Add the pod to
   the extension target in the `Podfile`.
3. In the extension's `Info.plist`, set `NSExtensionActivationRule` to support images (up to the §10 Q5 limit).
4. **App Group** `group.<bundle id>` on both Runner and ShareExtension (entitlements plus the Apple Developer
   portal). Set `AppGroupId` in both `Info.plist` files.
5. Add a URL scheme `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` to Runner's `CFBundleURLTypes`.
6. Create a provisioning profile for the extension's bundle id. The headless release script on the Mac
   (`~/multimax-ios-release/release-headless.sh`) must sign and export **two** targets. Check its
   `ExportOptions.plist` lists the extension profile.

## 7. Testing

- **Unit:** `ItemsFromPhotosCodec`: valid/invalid EAN-8 checksums, batch QR with good and bad prefixes, EAN-13 and
  junk ignored, de-dupe within a photo, two photos giving two rows. `StockAggregator`: sum across warehouses, a
  an item missing from the report gives out of stock, a negative total gives out of stock, an unknown item gives not found.
  `XlsxItemsFromPhotosWriter`: unzip and check the parts exist, the header row, `t="s"`/text format on Barcode, the red
  style on out-of-stock rows, one picture anchor per row. `ShareIntakeService`: pending photos survive the
  sign-in redirect (with fake streams).
- **Widget:** the format sheet in dark mode (surface tokens), and the busy flag toggling the progress UI.
- **On Android** (Pixel_7 emulator on KA-IT-SYS6 or the USB Pixel): push real label photos to the gallery and
  share them to a debug build. Labels: 2001136, 2002349 (QR only), 2001141 + 1004954 on one label, and
  1004963 / 3000333 (out of stock). Open the Excel and PDF and check the rows, images, colours and the
  not-found list. Test a cold start, a warm app, and a share while signed out.
- `flutter analyze` and `flutter test` pass.

## 8. Versioning

A new module and flow: **MINOR** → 2.41.0, build +1, per `docs/versioning_conventions.md` (check with
`dart run tool/bump_version.dart`). Commit on the feature branch only. No push, PR or Play release without the
user's OK.

## 9. Risks

1. **ML Kit vs zxing-cpp on real labels.** The sidecar retries with greyscale, upscale and autocontrast. ML Kit
   is usually strong on QR and EAN, but small EAN-8s in wide shots may be missed. The on-device tests with the
   five labels decide whether the §6.3 fallback is enough. If it isn't, fall back to approach §5.1-2.
2. **Stock Balance report permission.** Users without the report's roles get a 403 (`PermissionError`). That must
   show "You don't have access to stock levels". It must not mark
   everything out of stock.
3. **Large shares.** Hundreds of 12 MP photos: process them sequentially, keep only the thumbnails in memory, and
   apply the §10 Q5 limit.
4. **iOS** is unverified until built on the Mac (§6.6).

## 10. The user's answers (17/11/2026)

1. **Out-of-stock handling: ask each time.** Sheet 2 offers *Include, colour red* / *Include, no colour* /
   *Leave them out*, and only when at least one item is out of stock. If they are included, the **Stock** column
   is added (as in Telegram).
2. **Unreadable / not-in-ERP photos: on screen only.** The result screen lists them with thumbnails. The file
   holds only found items.
3. **Formats: Excel, PDF or Both.** "Both" shares the two files together in one share sheet.
4. **Signed out: sign in, then continue.** `ShareIntakeService` keeps the photos through the login redirect.
5. **Limit: 100 photos per share.** *(My call on enforcement:* a larger share is refused with a message and
   nothing is processed, rather than silently taking the first 100. The iOS `NSExtensionActivationRule` uses
   `NSExtensionActivationSupportsImageWithMaxCount = 100`.)
6. **Access: any signed-in user.** There is no pre-check. A 403 on Item or the Stock Balance report shows
   "You don't have access to stock levels" (§9 risk 2).

## 11. Left to the builder

- The exact progress wording and the result-screen layout, within the §6.5 conventions.
- Whether the EAN-8 checksum moves to a shared util or stays in `ItemsFromPhotosCodec`, with `ScanService` delegating.
- The thumbnail size and quality, within "about 30–60 KB each".
- How the temp files are cleaned up (delete the shared copies and thumbnails when the result screen closes).
