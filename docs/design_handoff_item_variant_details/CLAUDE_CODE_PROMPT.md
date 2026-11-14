# Claude Code prompt — Item Variant Details: image-first tile, prominent Balance Qty, revamped gallery, Cards/Compact toggle

Copy everything in the fenced block below into Claude Code, run from the Flutter
project root (`ddmco_multimax/`). The HTML reference and full spec are alongside
this file in `design_handoff_item_variant_details/`.

---

```
You are working in the ddmco_multimax Flutter app (GetX + Material 3).

GOAL
Rework the Item Variant Details report so each variant LEADS WITH ITS PHOTO,
shows BALANCE QTY + UOM as the headline, lists attributes in a clear hierarchy,
offers a Cards / Compact view toggle, and uses a REVAMPED image gallery. This is
a PRESENTATION + light-state change — do not touch networking, the report API,
or routing. Pixel reference: design_handoff_item_variant_details/Item Variant
Details — Redesign.html (left = current; middle = redesign, tap Cards/Compact and
tap a photo to open the gallery; right = the revamped gallery). The HTML is in
the Multimax blue language; in the app use Theme.of(context).colorScheme + the
status palette below. Do NOT re-theme the app (ignore any pink in screenshots —
that is an app theme override, not this design).

FILES
- Edit: lib/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart
        (_VariantTile, _ItemThumb, _AttrChip, _StockSection, _skipFields,
         _ImageGallery/_ImageGalleryState; add _ViewBar + a compact row widget)
        lib/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart
        (add a persisted viewMode flag only)
- Read for context (don't change behaviour):
        lib/app/modules/global_widgets/doctype_list_header.dart
        lib/app/modules/item/widgets/item_image.dart  (existing image widget idiom)
        docs/doctype_list_view_conventions.md  (§6 report archetype)

DATA ALREADY PRESENT
- controller.reportData: each row Map has variant_name (item code), the attribute
  columns, and hidden numerics current_stock, in_production, open_orders,
  avg_buying_price_list_rate, avg_selling_price_list_rate.
- controller.itemDetails[code] → {item_name, item_group, image?}.
- stock_uom: if not already on the row/details, read it from the report columns or
  default to "Pcs"; confirm the real fieldname against a live response.
- controller.stockBalances[code] → [{rack, qty}] after fetchStockBalance (a toggle:
  call once to load+expand, again to collapse); loadingStock[code] is the flag.
- columns = controller.reportColumns; attribute columns are those whose fieldname
  is NOT in _skipFields.

TWO THINGS TO FIX (mention in your summary)
1. _ItemThumb renders itemCode.substring(0,2) as the leading "initials" when a
   variant has no image — so it shows "10" for every 10xxxxx variant. The leading
   slot is meant to be the PHOTO. Replace _ItemThumb with a real image thumbnail
   + a proper "no photo" placeholder (Icons.image_not_supported_outlined on a
   surfaceVariant tile). Never show code initials.
2. current_stock sits in _skipFields and is never displayed. Surface it as the
   colour-coded Balance-Qty hero with its UOM. Keep it in _skipFields so it does
   not ALSO render as an attribute (you render it explicitly).

CONTROLLER CHANGE (minimal)
Add `final viewMode = 'cards'.obs;` ('cards' | 'compact') + setViewMode(m) that
persists via the app's existing pref storage (reuse StorageService/GetStorage —
do not invent one); read it back in onInit.

STATE / STATUS PALETTE (from current_stock `s`)
  s <= 0 → out  : gray   (outline / onSurfaceVariant)        caption "Out of stock"
  s  < 10 → low  : orange (orange.shade600 / .shade800)       caption "Low stock"
  else    → ok   : green  (green.shade600  / .shade700)       caption "In stock"
Helper enum→(accent, fg); tintBg = accent.withValues(alpha:.12) over surface.
Reuse the app whole-number formatter (no ".0").

SCREEN — VIEW BAR (new SliverToBoxAdapter, only when reportData non-empty)
Left: quiet summary "<b>N</b> variants" + ", <b>K</b> out" when any current_stock
== 0 (muted 12.5, tabular). Right: a segmented Cards/Compact toggle (pill,
surfaceVariant, 26px segments; selected = surface + primary fg + xs shadow;
icons Icons.view_agenda_outlined / Icons.view_list_outlined). onTap →
setViewMode. Wrap the list body in Obx(viewMode).

BALANCE-QTY PILL (shared)
Rounded box (radius 8, ~5x10 padding, tintBg + accent@26% border): a baseline
Row of current_stock (23, w700, stateFg, tabular) + stock_uom (11, w700, stateFg);
under it the state caption (8.5, w700, UPPERCASE, muted-state). This is the
report's headline number — keep it visually dominant on the card.

CARDS LAYOUT (A) — keep the Material card (radius 16, elev 1, antiAlias).
1. If the variant has an image, KEEP the existing full-width _ImageBanner (200px,
   tap → gallery). Otherwise no banner.
2. HEAD row (tap → ITEM_FORM): leading 54px rounded image thumbnail (the variant
   image; "no photo" placeholder if absent) with a small corner expand glyph;
   tapping the thumbnail opens the gallery at this variant. Then a column:
   item_name (titleSmall w600, ellipsis 1 line) over "item_code · item_group"
   (bodySmall, onSurfaceVariant, monospace code). Trailing: the Balance-Qty pill.
3. ATTRIBUTE GRID: 2-column grid in a quiet inset (surfaceVariant bg, 1px border,
   radius 8, 11x12 padding, 8x14 gaps). One cell per non-empty attribute column:
   micro-label (9.5, w700, UPPERCASE, subtle) over value (13, w600, ellipsis).
   Uses the column's own label. REPLACES the _AttrChip pills.
4. FOOTER row, spaceBetween: a quiet "Check stock" button (primary fg, primary@9%
   fill, 32px) → fetchStockBalance (toggles "Hide stock"); a muted "View ›". Below,
   when expanded, the EXISTING _StockSection unchanged.

COMPACT LAYOUT (B) — new private _VariantRow (no card), 1px dividers, ~64px:
3px left state accent bar; 40px image thumbnail (tap → gallery); main column line1
= item_name (14.5 w600 ellipsis) + item_code (11.5 subtle mono); line2 = attribute
values joined by " · " (12, onSurfaceVariant, ellipsis); right = current_stock (19,
w700, stateFg) over stock_uom (8.5, w700, muted-state); trailing chevron. Tapping
the row → ITEM_FORM (long-press → fetchStockBalance, mirroring list screens);
document the choice. Add a "VARIANT / ON HAND" column header (10, w700, UPPERCASE,
subtle, bottom divider).

REVAMP THE IMAGE GALLERY (_ImageGallery / _ImageGalleryState) — it is central to
this report. Keep the swipeable PageView + pinch zoom + cross-variant collection
of images, and ADD:
- A TOP BAR: close (left), centered title "Item <code> · N photos" with the
  "<i> of <N>" position, optional zoom hint (right).
- PREV/NEXT controls on the stage (in addition to swipe) for one-handed paging.
- A RICH CAPTION CARD (translucent dark, radius 14) above the filmstrip showing
  the current variant's code + name, a wrap of its ATTRIBUTE chips, and the
  BALANCE QTY + UOM in the state colour ("24 PCS · In stock"); plus an
  "Open item ›" button → ITEM_FORM for that variant.
- A THUMBNAIL FILMSTRIP (horizontal scroll) of every variant photo; the current
  one is outlined in primary and labelled with the last 4 of its code; tap a
  thumb to jump. (Replaces the bare dot indicator; keep dots only as a fallback
  when there are very few photos if you like.)
- Robust broken/missing image handling (existing errorBuilder is fine).
Match the reference gallery in the HTML (right phone / the overlay).

_skipFields
Keep current_stock (and the other hidden numerics) skipped from the attribute
grid; verify against a live response that no standard column leaks in.

CONSTRAINTS
- Private widgets in the same file; add small private sub-widgets (_ViewBar,
  _StockPill, _AttrGrid, _VariantRow, _GalleryFilmstrip, _GalleryCaption). Reuse
  _ImageBanner, _StockSection, _StockRow.
- No fixed white/black; everything theme-derived (dark mode must work). Min 44px
  tap targets. Reuse the app image widget (item_image.dart) for loading/error.
- Run `flutter analyze`, fix new warnings. Add/adjust a widget test under
  test/widget/ rendering a variant in BOTH modes and all three stock states
  (ok/low/out) without overflow, asserting the toggle swaps layouts and the
  gallery caption shows qty+uom+attributes.

DELIVERABLE
item_variant_details_screen.dart (+ a 2-line controller change) compiling
cleanly: image-led tiles, Balance Qty + UOM as the colour-coded hero, attributes
as a key/value grid (Cards) and dotted line (Compact), a persisted Cards/Compact
toggle, a revamped gallery (filmstrip + rich caption), inline Check Stock intact,
and a passing widget test.
```
