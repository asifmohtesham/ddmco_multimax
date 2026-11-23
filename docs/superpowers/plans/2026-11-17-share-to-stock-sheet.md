# Share Photos → Stock Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users share label photos from the gallery into Multimax and get back an Excel and/or PDF stock sheet. They can pass it on through the system share sheet.

**Architecture:** A permanent `ShareIntakeService` receives shared image paths through `receive_sharing_intent`. It keeps them through sign-in, then opens a new `stock_sheet` GetX module. The module decodes each photo on the device with `mobile_scanner.analyzeImage` and classifies the codes with the Telegram rules. It then makes two batched ERP calls (an Item list and the `Stock Balance` report) and builds the file on the device: a hand-written OOXML `.xlsx` through `archive`, and a PDF through `pdf`. Pure units (codec, aggregator, writers) carry most of the tests. Platform pieces are thin.

**Tech Stack:** Flutter 3.50 / Dart, GetX, Dio (`ApiProvider`), `mobile_scanner` 7, `receive_sharing_intent` ^1.9.0 (new), `archive` ^3.6.1, `image` ^4.3.0 (promoted from transitive), `pdf`, `share_plus` ^13.

**Spec:** `docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md`. Read §2, §3, §6 and §10 before any task.

## Global Constraints

- The server must be v15 + v16 compatible. Items come from `ApiProvider.getDocumentList('Item', …)`. Stock comes from the existing `ApiProvider.getStockBalanceReport`, whose built-in `stockBalanceUsesListFilters` check is the only version handling allowed; add no other. No Bin queries, no new server methods.
- Item Code = first 7 digits of a **checksum-valid** EAN-8. Batch QR regex: `^(\d{8})-[A-Za-z0-9]+$`, and the prefix must pass the checksum.
- Stock = the `Stock Balance` report's `bal_qty` summed per `item_code`, with `warehouses: ['Finished Goods - KA']` and `fromDate = toDate = today` (`yyyy-MM-dd`). The report includes the child warehouses. A total ≤ 0 or no row means out of stock.
- One row per (photo, item). Columns: `#, Image, Barcode, Variant Of, Country of Origin, Item Name`, plus `Stock` only when out-of-stock rows are included. **No Item Code column.**
- Colours: header fill `305496` with white bold text, out-of-stock fill `FFC7CE` and text `9C0006`, grid `BFBFBF`.
- The limit is **100 photos** per share. A larger share is refused with `Share up to 100 photos at a time (you shared N).` and nothing is processed.
- Formats are **Excel / PDF / Both**. The out-of-stock question (`Include, colour red` / `Include, no colour` / `Leave them out`) is asked **only when ≥ 1 item is out of stock**, after the stock check. Dismissing it cancels the run.
- Unreadable and not-in-ERP photos are listed **on screen only**, never in the file.
- A 403 on Item or the Stock Balance report shows `You don't have access to stock levels.` It must never mark everything out of stock.
- File names are `Items-YYYYMMDD-HHMM.xlsx` / `.pdf`. Subtitle date is en-GB, `dd/MM/yyyy HH:mm`.
- Repo UI rules (`CLAUDE.md`): theme surfaces only (`context.scheme.*`), and `AppColors.red700` / `red300` by brightness for out-of-stock text. `AsyncFilledButton` with an `RxBool busy` guarded and cleared in `finally`. Result lists use `Scrollbar` + a shared controller + nav-bar padding + an "End of list" marker. Workers and subscriptions are stored and cancelled in `onClose`.
- British English in all copy, comments and commits. Docs use `erp.domain.com`, never the real host.

## Review Focus

1. **Item text with `&`, `<`, `>` or quotes** (e.g. `STRAPS & BELTS <35mm>`) must appear unchanged in the Excel cell and not corrupt the workbook. The test is in Task 4.
2. **One photo with a found item and an unknown one** (2001141 + an EAN-8 not in the ERP) gives one row *and* one not-in-ERP entry for the same photo. The test is in Task 2.
3. **A second share arriving while a run is busy** must not start a parallel run. Show `A stock sheet is already being made.` If the screen is idle (result showing), the new share replaces it. The test is in Task 7.
4. **A network failure after decoding** (the Stock Balance call times out) shows an error with **Retry**, which reruns the ERP calls without decoding again. The test is in Task 6.
5. **A file that isn't a decodable image** (corrupt, or a format the platform can't read) becomes an `unreadable` entry with no thumbnail. It must not crash and must not abort the run. The tests are in Tasks 3 and 6.

---

## File structure

```
lib/app/shared/barcode/ean8.dart                         # shared checksum (ScanService delegates)
lib/app/modules/stock_sheet/
  model/items_from_photos_models.dart                          # value types + enums
  logic/items_from_photos_codec.dart                           # classify / de-dupe (pure)
  logic/stock_aggregator.dart                            # sum report rows, build rows (pure)
  logic/thumbnail_maker.dart                             # downscale → JPEG bytes
  logic/photo_decoder.dart                               # PhotoDecoder + MlKitPhotoDecoder
  output/xlsx_items_from_photos_writer.dart                    # OOXML via archive
  output/pdf_items_from_photos_writer.dart                     # pdf package
  items_from_photos_controller.dart
  items_from_photos_binding.dart
  items_from_photos_screen.dart
  widgets/format_sheet.dart
  widgets/out_of_stock_sheet.dart
  widgets/items_from_photos_result_list.dart
lib/app/data/providers/items_from_photos_provider.dart
lib/app/data/services/share_intake_service.dart
ios/ShareExtension/{ShareViewController.swift,Info.plist,ShareExtension.entitlements}
docs/ios_share_extension_setup.md
```

---

### Task 1: Shared EAN-8 checksum and code classifier

**Files:**
- Create: `lib/app/shared/barcode/ean8.dart`, `lib/app/modules/stock_sheet/model/items_from_photos_models.dart`, `lib/app/modules/stock_sheet/logic/items_from_photos_codec.dart`
- Modify: `lib/app/data/services/scan_service.dart` (`_isValidEan8` delegates to `Ean8.isValid`)
- Test: `test/unit/items_from_photos_codec_test.dart`

**Interfaces:**
- Produces:
  - `class Ean8 { static bool isValid(String code); }`: 8 digits, and the weights 3,1,3,1,3,1,3 give the check digit (as `ean8_ok` in the sidecar).
  - `class ClassifiedCode { final String itemCode; final String barcode; final String? batchNo; }` (const constructor, value equality).
  - `class ItemsFromPhotosCodec { static ClassifiedCode? classify(String raw); static List<ClassifiedCode> itemsInPhoto(List<String> rawValues); }`. `itemsInPhoto` de-dupes by `itemCode` in first-seen order. If any code for that item was a batch QR, `batchNo` keeps it.

- [ ] **Step 1: Write the failing tests**

```dart
test('valid EAN-8 → item code is first 7 digits', () {
  expect(ItemsFromPhotosCodec.classify('30003330'),
      const ClassifiedCode(itemCode: '3000333', barcode: '30003330', batchNo: null));
});
test('bad checksum is ignored', () => expect(ItemsFromPhotosCodec.classify('30003331'), isNull));
test('batch QR → item from prefix, batch kept', () {
  expect(ItemsFromPhotosCodec.classify(' 30003330-4CPIWR '),
      const ClassifiedCode(itemCode: '3000333', barcode: '30003330', batchNo: '30003330-4CPIWR'));
});
test('batch QR with bad prefix checksum is ignored',
    () => expect(ItemsFromPhotosCodec.classify('30003331-4CPIWR'), isNull));
test('EAN-13, Code 128 text and junk are ignored', () {
  for (final s in ['4006381333931', 'SHIPMENT-12', '', 'ABCDEFGH']) {
    expect(ItemsFromPhotosCodec.classify(s), isNull, reason: s);
  }
});
test('same item twice in one photo (EAN + its batch QR) → one entry with batch', () {
  final items = ItemsFromPhotosCodec.itemsInPhoto(['30003330', '30003330-4CPIWR', '20011369']);
  expect(items.map((e) => e.itemCode), ['3000333', '2001136']);
  expect(items.first.batchNo, '30003330-4CPIWR');
});
test('Ean8.isValid agrees with ScanService examples', () {
  expect(Ean8.isValid('20011369'), isTrue);
  expect(Ean8.isValid('20011362'), isFalse);
  expect(Ean8.isValid('2001136'), isFalse);
});
```

These are the EAN-8s for the test items, for this and later fixtures: 2001136 → `20011369`, 2002349 → `20023492`, 2001141 → `20011413`, 1004954 → `10049549`, 1004963 → `10049631`, 3000333 → `30003330`.

- [ ] **Step 2: Run `flutter test test/unit/items_from_photos_codec_test.dart`.** Expected: FAIL (undefined names).
- [ ] **Step 3: Implement the three files.** Point `ScanService._isValidEan8` at `Ean8.isValid`, keeping its behaviour.
- [ ] **Step 4: Run `flutter test test/unit/items_from_photos_codec_test.dart test/unit/` (scan service tests included).** Expected: PASS.
- [ ] **Step 5: Commit** `feat(stock-sheet): EAN-8 checksum and label code classifier`

---

### Task 2: ERP lookups and stock aggregation

**Files:**
- Create: `lib/app/data/providers/items_from_photos_provider.dart`, `lib/app/modules/stock_sheet/logic/stock_aggregator.dart`
- Modify: `items_from_photos_models.dart` (add the types below)
- Test: `test/unit/stock_aggregator_test.dart`, `test/unit/items_from_photos_provider_test.dart`

**Interfaces:**
- Consumes: `ClassifiedCode` (Task 1).
- Produces (models):
  - `class PhotoScan { final int index; final String path; final List<String> rawValues; final List<ClassifiedCode> items; final bool decodeFailed; }`
  - `class ItemInfo { final String itemCode; final String? itemName; final String? variantOf; final String? countryOfOrigin; }`
  - `class ItemsFromPhotosRow { final int photoIndex; final String photoPath; final String barcode; final String? itemName; final String? variantOf; final String? countryOfOrigin; final bool outOfStock; }`
  - `enum UnresolvedReason { unreadable, noRecognisedCode, notInErp }`
  - `class UnresolvedEntry { final int photoIndex; final String photoPath; final UnresolvedReason reason; final String? barcode; }` (`barcode` is set for `notInErp`)
  - `class ItemsFromPhotosResult { final List<ItemsFromPhotosRow> rows; final List<UnresolvedEntry> unresolved; int get outOfStockCount; }`
  - `class StockAccessDenied implements Exception {}`
- Produces (provider):
  - `ItemsFromPhotosProvider({ApiProvider? api})`
  - `Future<Map<String, ItemInfo>> fetchItems(List<String> itemCodes)`: `getDocumentList('Item', fields: ['name','item_name','variant_of','country_of_origin'], filterTuples: [['Item','name','in', chunk]], limit: 0)`.
  - `Future<List<Map<String, dynamic>>> fetchFinishedGoodsStock(List<String> itemCodes)`: per chunk, `getStockBalanceReport(fromDate: today, toDate: today, itemCodes: chunk, warehouses: const ['Finished Goods - KA'])`. Keep `.rows` whose `item_code` is in the chunk; on v15 < 15.72 the report ignores the item filter and returns the whole warehouse. `today` comes from an injected `DateTime Function() now`.
  - Both use chunks of 100 distinct codes (the 100-photo limit allows several items per photo), merge the results, and map a `DioException` with status 403 to `StockAccessDenied`. Other errors are rethrown.
- Produces (aggregator):
  - `static Map<String, double> StockAggregator.sumByItem(List<Map<String, dynamic>> reportRows)`: sums `bal_qty` per `item_code`. `bal_qty` may arrive as int, double or numeric string. Rows without an `item_code` are skipped.
  - `static ItemsFromPhotosResult StockAggregator.build(List<PhotoScan> scans, Map<String, ItemInfo> items, Map<String, double> stock)`: rows in photo order, then code order. A `decodeFailed` scan gives `unreadable`. No classified items gives `noRecognisedCode`. An item missing from `items` gives `notInErp`. Out of stock = `(stock[code] ?? 0) <= 0`.

- [ ] **Step 1: Write the failing aggregator tests**
  - `sumByItem` over `[{item_code:'2001136',warehouse:'WH-DXB1 - KA',bal_qty:60.0},{item_code:'2001136',warehouse:'WH-DXB3 - KA',bal_qty:-5},{item_code:'2002349',bal_qty:'295'},{item_code:'',bal_qty:420}]` → `{'2001136':55.0,'2002349':295.0}`.
  - The **Review focus 2** test: one scan with items 2001141 and an unknown valid EAN-8 → `rows.length == 1`, `unresolved.single.reason == notInErp`, and `unresolved.single.barcode` is the unknown EAN-8.
  - Item absent from the report → `outOfStock` true. Negative total (−2) → true. 0.5 → false.
  - The same item in two scans → two rows, with `photoIndex` 0 and 1.
  - A `decodeFailed` scan → `unreadable`. A scan with `rawValues:['4006381333931']` and no items → `noRecognisedCode`.
- [ ] **Step 2: Write the failing provider tests** with a fake `ApiProvider` (pattern: `test/unit/bom_stock_customer_code_api_test.dart`). Assert:
  - the exact Item `filterTuples` sent;
  - the exact `getStockBalanceReport` arguments (`warehouses == ['Finished Goods - KA']`, today's date from the injected clock);
  - that 150 codes give 2 Item calls and 2 report calls;
  - that report rows for codes outside the chunk are dropped (the v15 < 15.72 case);
  - that a 403 `DioException` from either call throws `StockAccessDenied`.
- [ ] **Step 3: Run `flutter test test/unit/stock_aggregator_test.dart test/unit/items_from_photos_provider_test.dart`.** Expected: FAIL.
- [ ] **Step 4: Implement the provider, the aggregator and the model additions.**
- [ ] **Step 5: Run the same command.** Expected: PASS.
- [ ] **Step 6: Commit** `feat(stock-sheet): batched Item lookup and Stock Balance aggregation`

---

### Task 3: Thumbnails and photo decoding

**Files:**
- Modify: `pubspec.yaml` (add `image: ^4.3.0` as a direct dependency)
- Create: `lib/app/modules/stock_sheet/logic/thumbnail_maker.dart`, `lib/app/modules/stock_sheet/logic/photo_decoder.dart`
- Test: `test/widget/thumbnail_maker_test.dart` (needs the engine codec, so use `testWidgets` + `tester.runAsync`)

**Interfaces:**
- Produces:
  - `class ThumbnailMaker { static Future<Uint8List?> make(String path, {int longSide = 480, int quality = 82}); }`
    - It decodes with `ui.instantiateImageCodec` at a target size so the long side is at most `longSide`, keeping the aspect ratio. The engine applies EXIF orientation.
    - It converts to RGBA bytes, then encodes JPEG with `package:image` inside `Isolate.run`.
    - It returns `null` if the file can't be decoded.
  - `abstract class PhotoDecoder { Future<List<String>?> decode(String path); Future<void> dispose(); }`. It returns `null` when the image can't be read, and an empty list when no barcode is found.
  - `class MlKitPhotoDecoder implements PhotoDecoder`
    - It owns one `MobileScannerController(autoStart: false)`.
    - It calls `analyzeImage(path, formats: [BarcodeFormat.ean8, BarcodeFormat.ean13, BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.dataMatrix])` and returns the non-empty `rawValue`s.
    - If none of the values classify, it retries **once** on a 2× upscaled greyscale copy written to `getTemporaryDirectory()`, deleted afterwards. Skip the upscale if the long side is already ≥ 2000 px, as in the sidecar.
    - A `MobileScannerBarcodeException` or a decode error → `null`. An `UnsupportedError` (iOS Simulator) is rethrown so the controller can show a clear message.

- [ ] **Step 1: Write the failing thumbnail tests.** Using an image generated in the test with `package:image` (3000×1500 PNG written to a temp file):
  - the result decodes as JPEG with width 480 and height 240;
  - for **Review focus 5**, a file holding random bytes → `null`.
- [ ] **Step 2: Run `flutter test test/widget/thumbnail_maker_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement both files.** `MlKitPhotoDecoder` has no unit test; ML Kit needs a device. It is covered by Task 9's on-device check.
- [ ] **Step 4: Run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(stock-sheet): thumbnails and on-device barcode decoding`

---

### Task 4: Excel writer (hand-written OOXML)

**Files:**
- Create: `lib/app/modules/stock_sheet/output/xlsx_items_from_photos_writer.dart`
- Modify: `items_from_photos_models.dart`
- Test: `test/unit/xlsx_items_from_photos_writer_test.dart`

**Interfaces:**
- Consumes: `ItemsFromPhotosRow` (Task 2).
- Produces:
  - `class ItemsFromPhotosDocument { final String title; final String subtitle; final List<ItemsFromPhotosRow> rows; final Map<String, Uint8List> thumbnails /* by photoPath */; final bool highlightOutOfStock; final bool showStatus; }`
  - `class XlsxItemsFromPhotosWriter { static Uint8List write(ItemsFromPhotosDocument doc); }`

**What the file must contain** (copy the sidecar's `render_xlsx` layout):
- **Zip parts:** `[Content_Types].xml`, `_rels/.rels`, `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/styles.xml`, `xl/worksheets/sheet1.xml`, `xl/worksheets/_rels/sheet1.xml.rels`, `xl/drawings/drawing1.xml`, `xl/drawings/_rels/drawing1.xml.rels`, and `xl/media/imageN.jpeg`.
- **Cell text:** use inline strings (`t="inlineStr"`), so no sharedStrings part is needed. XML-escape `& < > " '`.
- **Rows:**
  - Row 1 is the title (bold, 14). Row 2 is the subtitle (italic, grey `666666`). Row 3 is empty.
  - Row 4 is the header row (fill `305496`, white bold, centred, wrapped, thin `BFBFBF` borders).
  - Data starts at row 5. Each data row is about 88.5 pt high (`110 px × 0.75 + 6`).
- **Columns:** widths A5, B17, C12, D22, E20, F48, G14.
- **Barcode:** the Barcode cell is text (`numFmtId 49`), so leading zeros survive.
- **Images:** one `xdr:oneCellAnchor` per row at column B, scaled to a 110 px long side. If there's no thumbnail, write the text `(no image)`.
- **Out-of-stock rows:** when `highlightOutOfStock`, every cell in the row uses a style with fill `FFC7CE` and font colour `9C0006`.
- **Stock column:** when `showStatus`, column G is headed `Stock` and holds `In stock` or `Out of stock`.
- **Sheet set-up:** freeze the pane below row 4, set an `autoFilter` over the header and data, repeat row 4 on every printed page (print titles), and print A4 portrait fitted to 1 page wide (`fitToHeight="0"`).

- [ ] **Step 1: Write the failing tests.** Decode the bytes with `ZipDecoder` and assert:
  - all the parts listed above exist;
  - `sheet1.xml` holds the 6 header texts in order and no `Item Code`;
  - with `showStatus` it holds `Stock` and `Out of stock`;
  - there is one `<xdr:pic>` per row that has a thumbnail, and `(no image)` for a row without one;
  - an out-of-stock row's cells reference the style index whose `<fill>` is `FFC7CE`, and an in-stock row's cells don't;
  - for **Review focus 1**, an item name `STRAPS & BELTS <35mm> "x"` round-trips: parse `sheet1.xml` with `package:xml` (already a transitive dependency via `excel`; add it as a dev_dependency if analyze complains), and the cell text equals the input;
  - the Barcode `01234565` keeps its leading zero.
- [ ] **Step 2: Run `flutter test test/unit/xlsx_items_from_photos_writer_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement the writer.**
- [ ] **Step 4: Run the same command.** Expected: PASS. Then write one sample file to the scratch directory and open it in LibreOffice (`soffice --headless --convert-to pdf`) to check it isn't flagged as corrupt.
- [ ] **Step 5: Commit** `feat(stock-sheet): Excel writer with embedded thumbnails`

---

### Task 5: PDF writer

**Files:**
- Create: `lib/app/modules/stock_sheet/output/pdf_items_from_photos_writer.dart`
- Test: `test/unit/pdf_items_from_photos_writer_test.dart`

**Interfaces:**
- Consumes: `ItemsFromPhotosDocument` (Task 4).
- Produces: `class PdfItemsFromPhotosWriter { static Future<Uint8List> write(ItemsFromPhotosDocument doc); }`

**Layout** (copy the sidecar's `render_pdf`):
- **Page:** A4 portrait, 12 mm side margins, 12 mm top and 14 mm bottom.
- **Table:** a `pw.MultiPage` with a `pw.Table`, the header repeated on each page, header background `305496` and white text, a grid `BFBFBF` 0.4.
- **Column widths:** `[8,30,22,34,26,66]` mm, or `[8,30,20,30,24,52,22]` mm with `showStatus`.
- **Text:** body font size 8.5.
- **Images:** at most 26 mm on the long side. If there's no thumbnail, print `(no image)`.
- **Out-of-stock rows:** when highlighting, the row background is `FFC7CE`.
- **Footer:** the title on the left and `Page n` on the right, 7.5 pt grey.
- **Fonts:** use the bundled `Inter` TTF (`lib/assets/fonts/Inter-Regular.ttf`, `Inter-Medium.ttf`) so non-Latin-1 characters don't break the default Helvetica.

- [ ] **Step 1: Write the failing tests:**
  - the bytes start with `%PDF`;
  - 40 rows give more than one page (count `/Type /Page` objects, or check the length grows against a 5-row document);
  - `showStatus` doesn't throw with 7 columns.
- [ ] **Step 2: Run `flutter test test/unit/pdf_items_from_photos_writer_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement the writer.**
- [ ] **Step 4: Run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(stock-sheet): PDF writer`

---

### Task 6: Stock sheet controller (the run)

**Files:**
- Create: `lib/app/modules/stock_sheet/items_from_photos_controller.dart`
- Test: `test/unit/items_from_photos_controller_test.dart`

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces:
  - `enum SheetFormat { excel, pdf, both }`
  - `enum OutOfStockChoice { includeRed, includePlain, leaveOut }`
  - `enum ItemsFromPhotosPhase { idle, decoding, checkingStock, awaitingChoice, building, done, error }`
  - `ItemsFromPhotosController({PhotoDecoder Function()? decoderFactory, ItemsFromPhotosProvider? provider, Future<void> Function(List<XFile>)? shareFiles, DateTime Function()? now})`. The defaults are the real implementations; `shareFiles` wraps `SharePlus.instance.share(ShareParams(files: …))`.
  - Observables: `busy` (RxBool), `phase`, `decoded` (RxInt), `total` (RxInt), `errorMessage` (RxnString), `result` (Rxn<ItemsFromPhotosResult>), `files` (RxList<XFile>), and `thumbnails` (RxMap<String, Uint8List>, keyed by photo path; the screen uses it for the not-found list).
  - `static const int maxPhotos = 100;`
  - `Future<void> start(List<String> paths, SheetFormat format)`:
    - if busy, it returns (the guard);
    - more than `maxPhotos` → `errorMessage` set to the Global Constraints text, `phase = error`, nothing decoded;
    - otherwise it decodes in sequence, updating `decoded`, and makes the thumbnails;
    - it then fetches the items and the Stock Balance rows for the distinct item codes and builds the `ItemsFromPhotosResult`;
    - if `outOfStockCount > 0`, it sets `phase = awaitingChoice` and returns; otherwise it builds the files at once.
  - `Future<void> chooseOutOfStock(OutOfStockChoice? choice)`: `null` (sheet dismissed) → `phase = idle` and the run is cancelled. Otherwise it filters the rows (`leaveOut` drops out-of-stock rows), sets `highlightOutOfStock = choice == includeRed` and `showStatus = choice != leaveOut`, and builds.
  - `Future<void> retry()`: reruns from the ERP step using the kept `PhotoScan`s and does **not** decode again.
  - `Future<void> shareAgain()`: calls `shareFiles(files)`.
  - Building writes `Items-<yyyyMMdd-HHmm>.xlsx` / `.pdf` (per format) to the temp directory and then calls `shareFiles` once with all the files.
  - Title `Items`. Subtitle `dd/MM/yyyy HH:mm · N photos · M items · K out of stock`.
  - `UnsupportedError` from the decoder (iOS Simulator) → `Reading barcodes from photos isn't supported on this device.`
  - `StockAccessDenied` → `You don't have access to stock levels.` Any other exception → `Couldn't reach the ERP. Check the connection and try again.` In both cases `phase = error` and the kept scans stay.
  - `busy` is set at the start and cleared in `finally`. In `onClose` it deletes the temp files it created.

- [ ] **Step 1: Write the failing tests** with a fake decoder (a map of path to codes, or `null`), a fake provider and a recording `shareFiles`:
  - 101 paths → error text `Share up to 100 photos at a time (you shared 101).`, and the decoder is never called;
  - all in stock → no `awaitingChoice`, and `shareFiles` gets one `.xlsx` for `excel` and two files for `both`;
  - one out of stock → `awaitingChoice`; `chooseOutOfStock(null)` → `idle` and `shareFiles` is never called; `leaveOut` → the built document has no out-of-stock rows and `showStatus == false`;
  - **Review focus 4:** the provider throws once on the stock call, then succeeds → after `retry()` the decode count is unchanged and the phase reaches `done`;
  - **Review focus 5:** the decoder returns `null` for one path → `unresolved` holds `unreadable` and the run still completes;
  - a 403 → the exact access-denied text;
  - calling `start` while `busy` is a no-op.
- [ ] **Step 2: Run `flutter test test/unit/items_from_photos_controller_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement the controller.**
- [ ] **Step 4: Run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(stock-sheet): run controller with out-of-stock choice and retry`

---

### Task 7: Screen, sheets, route and share intake

**Files:**
- Create: `items_from_photos_binding.dart`, `items_from_photos_screen.dart`, `widgets/format_sheet.dart`, `widgets/out_of_stock_sheet.dart`, `widgets/items_from_photos_result_list.dart`, `lib/app/data/services/share_intake_service.dart`
- Modify:
  - `lib/app/data/routes/app_routes.dart`: `ITEMS_FROM_PHOTOS = '/stock/stock-sheet'`
  - `app_pages.dart`: `rightToLeftWithFade`
  - `lib/main.dart`: `Get.put<ShareIntakeService>(…, permanent: true)` after `AuthenticationController`
  - `pubspec.yaml`: `receive_sharing_intent: ^1.9.0`
  - `android/app/src/main/AndroidManifest.xml`: the `SEND` and `SEND_MULTIPLE` `image/*` filters from spec §6.6
- Test: `test/widget/items_from_photos_screen_test.dart`, `test/unit/share_intake_service_test.dart`

**Interfaces:**
- Consumes: `ItemsFromPhotosController` (Task 6), `AuthenticationController.isAuthenticated`.
- Produces:
  - `ShareIntakeService({Stream<List<String>>? warmShares, Future<List<String>> Function()? initialShare, void Function()? resetShare})`. The defaults wrap `ReceiveSharingIntent.instance.getMediaStream()`, `getInitialMedia()` and `reset()`, filtered to `SharedMediaType.image` paths.
  - `RxList<String> pendingPhotos`
  - `void deliver(List<String> paths)`. Not signed in → keep the photos; when `isAuthenticated` turns true (an `ever` worker kept in a field), wait for HOME, then open the route. Signed in → open the route, or hand off as below.
  - Route arguments: `List<String>` paths. On a warm share while `ITEMS_FROM_PHOTOS` is open: if the controller is `busy`, show the snackbar `A stock sheet is already being made.` and drop the share; otherwise restart the screen with the new paths (Review focus 3).
  - **Screen:**
    - On open, it shows `FormatSheet` (Excel / PDF / Both).
    - Dismissing it closes the screen.
    - While working, it shows a determinate `LinearProgressIndicator` with `Reading photo n of N`, then an indeterminate one with `Checking stock…` and `Building file…`.
    - On `awaitingChoice`, it shows `OutOfStockSheet`.
    - The result view shows counts, an out-of-stock list (`AppColors.red700` / `red300` text), and an unreadable/not-found list with thumbnails and the reason (`Unreadable photo`, `No recognised code`, `Not in ERP: <barcode>`).
    - Its buttons are `AsyncFilledButton` `Share file(s)` and `Done`, and the error view has `Retry`.

- [ ] **Step 1: Write the failing tests.**
  - **ShareIntakeService** (fake streams, a fake auth `RxBool`): a share while signed out keeps `pendingPhotos`, and nothing navigates until auth flips (inject a `navigate` callback to observe); `resetShare` is called once per consumed share.
  - **Review focus 3:** a warm share while `busy` → snackbar text, and `start` isn't called again.
  - **Widget** (fake controller states): in dark mode, the format sheet's background equals `context.scheme.fg` (or `surface`) and no `Colors.white`; toggling `busy` swaps the button for a spinner; the result list ends with `End of list`.
- [ ] **Step 2: Run `flutter test test/unit/share_intake_service_test.dart test/widget/items_from_photos_screen_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement the files and modifications.** Run `flutter pub get`.
- [ ] **Step 4: Run the same command.** Expected: PASS. Then run `flutter analyze` and expect no new issues against the baseline.
- [ ] **Step 5: Commit** `feat(stock-sheet): share intake, screen and Android share target`

---

### Task 8: iOS Share Extension (written, unverified)

**Files:**
- Create: `ios/ShareExtension/ShareViewController.swift` (`class ShareViewController: RSIShareViewController {}`), `ios/ShareExtension/Info.plist`, `ios/ShareExtension/ShareExtension.entitlements`, `docs/ios_share_extension_setup.md`
- Modify:
  - `ios/Runner/Info.plist`: `CFBundleURLTypes` → `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`, and `AppGroupId` → `$(CUSTOM_GROUP_ID)`
  - `ios/Runner/Runner.entitlements`: `com.apple.security.application-groups`
  - `ios/Podfile`: a `ShareExtension` target with `inherit! :search_paths`
- **Do not hand-edit `project.pbxproj`.** Adding the target is a step on the Mac in Xcode.

- [ ] **Step 1: Write the files.** Use the `receive_sharing_intent` 1.9.0 README for the exact keys. The extension's `NSExtensionActivationRule` dictionary sets `NSExtensionActivationSupportsImageWithMaxCount = 100`.
- [ ] **Step 2: Write `docs/ios_share_extension_setup.md`.** It covers spec §6.6 steps 1 to 6 as a checklist: the Xcode target, the App Group in the developer portal, the provisioning profile, the `ExportOptions.plist` for `~/multimax-ios-release/release-headless.sh`, and a smoke test. The first line states: **Unverified: not built or run.**
- [ ] **Step 3: Run `flutter analyze`.** Expected: unchanged. Also run `plutil -lint`-equivalent XML validation (`python3 -c "import plistlib,sys;plistlib.load(open(sys.argv[1],'rb'))"`) on each plist.
- [ ] **Step 4: Commit** `feat(stock-sheet): iOS share extension sources (unverified)`

---

### Task 9: On-device verification, version bump

- [ ] **Step 1: Run `flutter analyze` and `flutter test`.** Expected: no new analyzer issues against the baseline, and all tests pass. Run the full suite on sys6 if the local run is slow (memory `sys6-windows-build-host`).
- [ ] **Step 2: Build a debug APK and install it** on the USB Pixel or the Pixel_7 emulator on KA-IT-SYS6. Follow memory `device-smoke-test-recipe`: the `.dev` side-by-side install was removed on 16/11/2026, so confirm with the user before replacing the Play build on the Pixel.
- [ ] **Step 3: Push label photos to the gallery** (`adb push` + a media scan). Use these labels: 2001136; 2002349 (QR only); 2001141 + 1004954 on one label; 1004963; 3000333.
- [ ] **Step 4: Check the share paths:**
  - cold start, warm app, and signed out → sign in → sheet;
  - a 101-photo refusal (duplicate one photo);
  - share from Google Photos.
- [ ] **Step 5: Check the launch behaviour.** With `launchMode="singleTop"`, make sure sharing doesn't open a second app instance on top of Photos. If it does, switch to `singleTask`, then re-check the notification taps and the DataWedge scan flow.
- [ ] **Step 6: Open the shared Excel and PDF** (pull them with `adb`, open in LibreOffice and a PDF viewer). Check:
  - the rows and the order;
  - no Item Code column;
  - the thumbnails;
  - the red rows for *Include, colour red*;
  - the Stock column;
  - that 1004963 and 3000333 are out of stock;
  - that the not-found list is on screen only.
- [ ] **Step 7: Bump the version.** Run `dart run tool/bump_version.dart` and expect a MINOR proposal to `2.41.0+129`. Apply it with `--write`, then commit `chore(release): bump version to 2.41.0+129`.
- [ ] **Step 8: Update the spec status line** to say it's implemented, and list anything that wasn't verified (iOS). Commit. **No push, PR or Play release** without the user's OK.
