# POS & DN Item Rate — Smoke-Test Enhancements (Design)

**Date:** 2026-07-03 · **Status:** Design pending user review

Follow-up round after the first on-device smoke test of the shipped
[POS & DN Item Rate report](2026-07-03-pos-dn-item-rate-flutter-design.md).
Six punch-list items plus codifying three of them as standing conventions.

## Decisions (defaults taken while user was away — confirm on review)

| Fork | Decision |
|---|---|
| Image source | **Client-side enrichment** via existing `ApiProvider.getItemImages` — no change to the deployed Desk report. |
| End-of-list summary | **Qty sums + row count**; no rate total (summing/averaging rates across items is meaningless). Honors active filters. |
| Image thumbnail + zoom widget | **Extract to shared** `global_widgets/item_image.dart`; re-point Stock Balance (behaviour-preserving). |
| Convention scope | **Codify in CLAUDE.md + apply to this screen**; retrofit other screens as a separate follow-up. |

## Punch list

### 1. Discard the server Total card
The deployed report has `add_total_row` on, so `query_report.run` appends a
row whose `status` is `Total` (rendered as a stray card). Fix in `parseRows`:
keep only rows whose `status` is one of the four known values
(`New`, `Already mapped`, `No delivery line`, `No code`). This drops the total
row robustly regardless of its label, and any future stray/blank-status rows.

### 2. Item image with tap-to-zoom
- **Enrichment:** in `runReport`, after `parseRows`, collect distinct non-empty
  `item_code`s, call `ApiProvider.getItemImages(codes)` (returns `code → relative
  path`), then a pure static `attachImages(rows, imgMap, baseUrl)` writes an
  absolute URL onto each row's `item_image` (trim trailing `/` off base; keep
  `http…` as-is; rows without an image are left untouched). Mirrors
  `stock_balance_controller.attachItemImages`.
- **Widget:** extract `ItemThumbnail` (46px, `CachedNetworkImage`, 2-letter
  initials fallback) and `showItemImagePreview(context, url, itemCode, itemName)`
  (full-bleed `Dialog` + `InteractiveViewer`, minScale 1 / maxScale 5) from
  `stock_balance_screen.dart` into `global_widgets/item_image.dart`. Re-point
  Stock Balance to the shared widget — no behaviour change.
- **Tile:** a leading `ItemThumbnail` on the hero row. Item-less rows
  (No code / No delivery line) have no `item_code`/image → show the neutral
  initials/glyph placeholder, no zoom.

### 3. Tap card → Item detail
Wrap the tile body in an `InkWell`; `onTap` →
`Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': itemCode})` (the Item
form is a read-only detail view; opens modal over the report). **Only when
`item_code` is non-empty** — item-less rows get no card tap. The image thumbnail
(zoom) and the DN/POS voucher chips remain inner `InkWell`s and take precedence
in their own hit-areas (same inner-over-outer model as `_BalanceTile`).

### 4. Scrollbar on scrollable lists  *(also a convention)*
Wrap the screen's `CustomScrollView` in a `Scrollbar` sharing a single
`ScrollController` with the scroll view. No screen in the app does this today;
this becomes the standing pattern.

### 5. Last card must clear the system nav bar  *(also a convention)*
Read `MediaQuery.of(context).padding.bottom` once and feed it into the trailing
footer's bottom padding (the `delivery_note_screen` pattern), so the final card
is never hidden behind the Android gesture/nav bar.

### 6. End-of-list marker with totals  *(also a convention)*
A footer after the last card: an "End of list" marker plus a totals summary —
row count, summed POS Qty, summed DN Qty — computed from the **filtered** rows
via `sumTotals`. Rate is not summed. Carries the item 5 bottom inset. Also add a
top `ResultCountPill` ("N rows") for parity with the standardised list screens.

## Conventions added to CLAUDE.md

New subsection "List / report screen conventions":
1. Every vertically-scrollable result list is wrapped in a `Scrollbar` with a
   shared `ScrollController`.
2. The last item must clear the system nav bar — apply
   `MediaQuery.padding.bottom` to the trailing padding/footer.
3. Scrollable result lists end with an "End of list" marker; **report** lists
   put a totals summary there (sum quantity columns, never rate columns).

Applied to the POS & DN report now; retrofitting existing screens
(Stock Balance, BOM Stock, list screens) is a separate opt-in follow-up.

## Extra suggestions
1. **Long-press customer code → copy to clipboard.** — **APPROVED, in scope.**
   The report exists to help transcribe "New" codes into Desk by hand; one-tap
   copy speeds that. Long-press the `ref_code` hero text → `Clipboard.setData` +
   a brief confirmation snackbar. Item-less rows (no `ref_code`) have nothing to
   copy → no-op.
2. **Sort / New-first grouping** — deferred; the status chips already cover the
   main need and v1 was intentionally sort-free.

## Module layout (touched)
- `pos_dn_item_rate_controller.dart` — total-row drop, `attachImages`,
  `sumTotals`, image enrichment in `runReport`.
- `widgets/pos_dn_item_rate_tile.dart` — thumbnail, card-tap, (optional) copy.
- `pos_dn_item_rate_screen.dart` — scrollbar, bottom inset, end footer,
  result-count pill.
- `global_widgets/item_image.dart` — **new** shared `ItemThumbnail` +
  `showItemImagePreview` (extracted from Stock Balance).
- `stock_balance_screen.dart` — re-point to the shared widget.
- `CLAUDE.md` — new conventions subsection.

## Testing
- **Unit:** `parseRows` drops a `status:'Total'` row and keeps the four known
  statuses; `attachImages` (relative→absolute, `http…` passthrough, missing code
  left unchanged, trailing-slash base); `sumTotals` over filtered rows
  (count / posQty / dnQty, rate ignored, `null`/`—` handled).
- **Widget:** tile renders a thumbnail when `item_image` set and initials when
  not; card tap navigates to `ITEM_FORM` only when `item_code` present (no-op for
  No code); tapping the thumbnail opens the zoom dialog; end footer shows the
  totals; bottom padding applied. Long-press-copy if adopted.
- **Regression:** Stock Balance's existing thumbnail/zoom tests still pass after
  the extraction.

## Sequencing
1. Extract shared `item_image.dart` + re-point Stock Balance (green regression).
2. Controller: total-row drop + `sumTotals` + `attachImages` + enrichment.
3. Tile: thumbnail + card-tap (+ copy).
4. Screen: scrollbar + bottom inset + end footer + result pill.
5. CLAUDE.md conventions.
6. Full suite + analyze + on-device re-smoke.
