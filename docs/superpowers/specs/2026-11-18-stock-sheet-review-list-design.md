# Stock Sheet: Review List — Design Spec (addendum)

**Date:** 18 November 2026
**Extends:** `docs/superpowers/specs/2026-11-17-share-to-stock-sheet-design.md` (the "base spec"). Everything there still holds
unless this addendum says otherwise.
**Status:** approved by the user on 18/11/2026 (including the calls in §9).
**Mock-ups:** HTML, shown in the brainstorming companion on 18/11/2026 (`.superpowers/brainstorm/…/review-list-v2.html`,
git-ignored). The user picked the **list** layout over a grid.

## 1. Intent

Before the Excel/PDF is made, the user wants to curate the batch:
- **rearrange** the photos (and so the rows);
- **exclude** any photo;
- **fix** a photo whose code wasn't read;
- **add** a photo they forgot.

While doing so, they want each item's **Balance Qty and rack** visible for quick reference. Those figures are on the
screen only, never in the file.

## 2. The user's decisions (18/11/2026)

1. **Read first, then review.** Photos are read and stock is checked straight after the share. A review list follows,
   and the format choice comes last. This replaces the base spec's "format sheet first" (§6.1).
2. **List layout:**
   - one row per photo: thumbnail, item name, barcode and Variant Of, plus stock;
   - drag handle ⋮⋮ on the left;
   - on/off switch on the right.
3. **Suggestions taken:**
   - (1) fix an unreadable photo by typing or scanning its code;
   - (2) add photos from the review list;
   - (4) remember the last format choice.
   Not taken: the duplicate warning, and a quantity column in the file.
4. **Balance Qty and Rack on screen only**, not in the Excel or PDF. The file columns stay exactly as in the base spec.
5. **Rack names are shown in full**, e.g. `KA-WH-DXB1-21A`, never trimmed.

## 3. Server facts (checked live on 18/11/2026, v16, read-only)

- The **core** `Stock Balance` report with `show_dimension_wise_stock: 1`, `warehouse: Finished Goods - KA` and a list
  `item_code` returns one row per item × warehouse × **rack**, with columns
  `item_code, item_name, item_group, warehouse, rack, stock_uom, bal_qty, …`.
  - 1002312 → `KA-WH-DXB1-21A` 372
  - 1001579 → `KA-WH-DXB1-34B` 924
  - 1000550 → `KA-WH-DXB1-14D` 108
  - 1004390 → `KA-WH-DXB1-23C` 192
  - 1004021 → `KA-WH-DXB1-22C` 48
- `ApiProvider.getStockBalanceReport(…, showDimensionWise: true)` already sends that filter. The base spec's single
  stock call therefore gains the rack breakdown at no extra cost. Both v15 and v16 accept the filter (the app's Stock
  Balance screen already uses it). No new server call or method is needed.
- `rack` can be empty (`null` / `""`) for stock held in a warehouse but on no rack.

## 4. Goals, non-goals, anti-goals

**Goals**
- One screen to review, reorder, include or exclude, fix and add, then make the sheet.
- The sheet's row order is the review order; excluded photos and items are simply absent.
- Balance Qty and racks for every resolved item, from the one existing stock call.
- The last format choice is preset.

**Non-goals**
- Any change to the Excel/PDF columns, colours or file names (`Items-<yyyyMMdd-HHmm>`).
- Any change to the Telegram/n8n feature, which has no review step.
- Editing ERP data (stock, racks) from this screen.
- Reordering individual items within a photo.

**Anti-goals**
- Losing the user's review work through a slip (Back, a new share, rotation).
- A file that contains something the user switched off, or misses something they switched on.
- Rack or quantity data leaking into the file.
- More server calls per photo. Stock stays batched: a single report call per chunk of up to 100 codes.

## 5. Approaches

1. **A review phase inside the existing stock-sheet screen and controller**, with Flutter's built-in
   `ReorderableListView`. *Chosen.* One run's state (scans, thumbnails, stock, results) stays in one controller.
   Reordering uses the stock Flutter widget.
2. A separate review screen and controller. Rejected: it splits one run's state across two controllers and two routes,
   and a new share or Back would have to coordinate both.
3. A third-party drag-and-drop list package. Rejected: the built-in widget covers a single-column list, and the package
   would add a dependency.

## 6. Design

### 6.1 Flow (replaces base §6.1 after the share is received)

```
Share received (limit 100, sign-in rules unchanged)
  ▼
Reading photo n of N  →  Checking stock…        (one Item call + one Stock Balance call, showDimensionWise)
  ▼
REVIEW LIST  ◄──────────────┐
  · drag ⋮⋮ to reorder      │  ＋ Add photos (camera / gallery) → read + check new ones → appended
  · switch photo / item     │  ✎ Type or scan code → resolve → row switches on
  · Excel | PDF | Both      │  (preset to last choice)
  · Make sheet · N photos ──┘
  ▼
Any out-of-stock item switched on?  ── yes → out-of-stock question (unchanged)
  ▼
Building file…  →  system share sheet  →  result screen (unchanged)
```

### 6.2 Review list rows (mock-up `review-list-v2`)

**One row per photo**, in the current order:
- **Thumbnail:** the photo's own thumbnail.
- **Item block, one per resolved item in that photo:**
  - item name;
  - `barcode · Variant Of` in mono type;
  - a **stock line**: **Balance Qty in bold** (sum of `bal_qty` over Finished Goods), followed by one **rack chip**
    per rack showing the full rack name and the quantity on it (`KA-WH-DXB1-21A 300`). Chips are sorted by quantity,
    largest first. If there are more than three racks, three chips are shown, then "+n"; tapping "+n" or long-pressing
    the stock line lists them all.
  - Stock with an empty `rack` shows the chip **No rack**.
  - **Out of stock** (total ≤ 0 or no row) shows the red pill **Out of stock · 0** and no chips.
  - Chips wrap onto a second line rather than being cut off.
- **Switches:**
  - A photo with **one item** has one switch, on the row.
  - A photo with **two or more items** has a switch per item, plus the row switch:
    - row off → all its items off;
    - all items off → row off;
    - turning the row on restores the items to on.
- **Unresolved photos** (unreadable, no recognised code, or only not-in-ERP codes) start **off**, with:
  - the reason (`Unreadable photo`, `No recognised code`, `Not in ERP: <barcode>`);
  - the action **✎ Type or scan code**.
  Their switch is disabled until a code resolves.
- **Drag:** the ⋮⋮ handle on the left (`ReorderableListView` with drag handles; no long-press drag on the whole row).
- **Header:** title **Review photos**, subtitle `N photos · M on the sheet`, and a **＋** action.
- **Footer:**
  - segmented **Excel | PDF | Both**, preset to the last choice (first time: Excel);
  - `AsyncFilledButton` **Make sheet · N photos**, where N is the photos with at least one item switched on. It is
    disabled when N = 0.
- List conventions apply (`Scrollbar` with a shared controller, nav-bar padding, an "End of list" marker). Theme
  surfaces and the AppColors ramps are as in the base spec.

### 6.3 Type or scan code (suggestion 1)

A bottom sheet with:
- a text field;
- a **Scan** button that opens the existing `CameraScanOverlay.show(context)` and returns `String?`;
- **Use code**.

Input is resolved in this order:
1. Through `StockSheetCodec.classify` (an EAN-8 with a valid checksum, or the batch QR text) → item code.
2. Otherwise, exactly 7 digits → used as the item code directly.
3. Anything else → the inline error `Not a barcode or item code`.

The item code is then looked up through the same provider calls (Item + Stock Balance with racks):
- **Found:** the row's items are replaced by that item. The photo's own thumbnail stays as the row's image. The row
  switches on.
- **Unknown:** the inline error `Not in ERP` appears, and the sheet stays open.
- **403 or network error:** the existing messages appear inline.

The resolved code shows a small "typed" marker in the row, so it can be told apart from a read code.

### 6.4 Add photos (suggestion 2)

**＋** opens a small menu: **Take a photo** (`ImagePicker().pickImage(source: camera)`) and **Choose from gallery**
(`pickMultiImage`).
- The new photos are read and checked with the same pipeline, using only the new codes. Progress shows inline in the
  header, and the list stays usable.
- They are appended to the end of the list.
- The **100-photo limit** covers the whole list. If the user picks more than would fit, the app explains how many
  photos it can still accept and adds none.
- If the network fails during the check, the new photos are added as unresolved, with a **Retry check** action on each
  row.

### 6.5 Remember the format (suggestion 4)

The last **Make sheet** choice is saved through `StorageService` under the key `stock_sheet_last_format`
(`excel`/`pdf`/`both`), and read to preset the segmented control.

### 6.6 Guarding the user's work

- **Back** on the review list asks **Discard these photos?** with *Keep reviewing* / *Discard*.
- **A new share while reviewing** asks **Add these N photos to the list, or start again?** with *Add* / *Start again*.
  *Add* appends, subject to the 100 limit.
- **A new share while building** keeps today's busy snackbar.
- **Rotation and configuration changes** keep the state, which lives in the controller.

### 6.7 Building the file

- Rows are built in review order, from switched-on photos and items only.
- `#` is numbered 1…n in that order.
- The out-of-stock question is asked only if a switched-on item is out of stock. Its count refers to switched-on items
  only.
- **Balance Qty and rack are never passed to the writers.** `StockSheetRow` and `StockSheetDocument` stay unchanged.
  Quantity and rack live in a separate review-only model.
- The result screen is unchanged, except that excluded photos appear in none of its lists.

### 6.8 Controller and model changes (builder's guide)

- **Phases:** `decoding → checkingStock → reviewing → (awaitingChoice) → building → done`, plus `error`.
- **`start(paths)`** no longer takes a format. The format is passed to **`makeSheet(SheetFormat)`**.
- **Review model:** `ReviewEntry { photoIndex, path, decodeFailed, rawValues, items: [ReviewItem], included,
  typedCode? }` and `ReviewItem { itemCode, barcode, info?, stock: ItemStock?, included }`.
  - `ItemStock { total, racks: [RackQty(rack?, qty)] }` comes from the dimension-wise rows. It is grouped by
    `item_code`, then by `rack`, and summed across warehouses.
  - `reorder(old, new)`, `setIncluded(entry, bool)` and `setItemIncluded(entry, item, bool)` are plain list operations
    on an observable list.
- `StockAggregator.sumByItem` stays. A new pure `StockAggregator.racksByItem(rows) → Map<String, ItemStock>` is added
  and unit-tested.
- The existing `takeShare` / busy / `_closed` logic is kept and extended for the reviewing phase (6.6).

## 7. Testing

- **Unit:**
  - `racksByItem`: one rack, two racks sorted by quantity, an empty rack, a negative quantity, several warehouses
    summed.
  - Review operations: reorder, the row/item switch rules, and N for **Make sheet**.
  - Code resolution order in 6.3.
  - The 100 limit with added photos.
  - Format persistence.
  - The built document follows review order and excludes switched-off photos and items.
  - Neither writer receives rack or quantity data.
- **Widget:**
  - dragging a row reorders it;
  - switches;
  - dark-mode surfaces;
  - chips wrap and keep the full rack name;
  - Back asks for confirmation;
  - the fix sheet's errors.
- **Device** (APK built on sys6, per the user's 18/11/2026 instruction):
  - share 16 ERP photos;
  - reorder;
  - exclude;
  - fix one photo with a typed code and one by camera scan;
  - add from camera and from the gallery;
  - check that the Excel and PDF order and content match the review list, with no rack or quantity in the files.

## 8. Versioning

This adds new behaviour (MINOR). The branch already carries 2.41.0+129, which has not been released, so this ships
inside 2.41.0 if it lands before that release is tagged. If 2.41.0 ships first, this becomes 2.42.0. Decide with
`dart run tool/bump_version.dart` at release time.

## 9. Settled after the builder check (my calls, 18/11/2026; correct any)

1. **The Barcode column for a typed 7-digit item code** is the full EAN-8: the code plus the check digit from
   `Ean8`. This follows the base rule that the Item Code is the first 7 digits of the EAN-8. A typed item therefore
   looks exactly like a scanned one in the file. The "typed" marker appears on screen only.
2. **The result is built from the review model**, not from the original scans:
   - rows are the switched-on items in review order;
   - "Couldn't use these photos" lists photos still unresolved at **Make sheet**;
   - photos the user switched off appear in no list.
   
   A photo with one known item and one not-in-ERP code shows the known item as normal, plus a note line
   `Also read: <barcode> · not in ERP`. The note has no switch and its own **✎ Type or scan code** action.
   
   The file subtitle counts: N photos = photos with at least one switched-on item; M items = rows in the file;
   K out of stock = switched-on out-of-stock items (left out when the choice is *Leave them out*).
3. **Dismissing the out-of-stock question returns to the review list** with everything intact, not to idle. A
   failure while building or sharing also returns to the review list, with the message shown above **Make sheet**.
   Nothing the user curated is ever discarded except through *Discard* or *Start again*.
4. **A failed first stock check** keeps today's behaviour: the error screen with **Retry**, which re-runs the ERP
   calls without reading the photos again. A 403 still blocks with the access message. The per-row **Retry check**
   applies only to photos added from the review list.
5. **A new share while reviewing:** the controller exposes a pending share, and the screen shows the dialog.
   - If the new photos fit under 100, it offers *Add* / *Start again* / *Cancel*.
   - If they don't fit, it says how many can still be added and offers only *Start again* / *Cancel*.
   - Refusal while busy building is unchanged.
6. **A typed fix makes its own two calls**: Item, and Stock Balance with racks, for that one code. This is a deliberate
   exception to "no per-photo calls", because it is user-initiated and one at a time.

## 10. Left to the builder

- The exact layout of the multi-item row, and the "+n" overflow list sheet.
- The inline progress for added photos.
- The wording of the "typed" marker.
