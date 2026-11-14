# Item Price + Pricing Rule — design spec (digest of the Claude Design mockups)

Source: Claude Design project `9746931c-4bcc-40e2-aa3e-53323678cd6f`, file
`Item Price & Pricing Rule - Multimax.html` (+ `pricing-shared.jsx`,
`pricing-item-price.jsx`, `pricing-rule.jsx`, `pricing-extras.jsx`, `pricing.css`),
read 2026-09-17. This digest is the build's visual contract; behaviour still follows
`README.md` (README wins on conflicts). Phone 390×844, both themes.

## Tokens (map to existing theme — never hardcode)
| Mock var | App token |
|---|---|
| `--bg` #F4F5F6 / #15191D | scaffold background |
| `--fg` #fff / #1F262C | `context.scheme.fg` / `colorScheme.surface` (cards, sheets, fields) |
| `--subtle` #F9FAFA / #262D34 | `scheme.subtle` (read-only field fill, tags, add-row) |
| `--text` / `--muted` / `--sub` | `scheme.text` / `scheme.textMuted` / `scheme.textSubtle` |
| `--border` / `--border2` | `scheme.border` / strong border (as `DocPickerField`) |
| `--primary` #870E18 | `colorScheme.primary` (form header, FAB, switch on, selected priority) |
| `--accent` #870E18 light / #D9707C dark | `colorScheme.primary` in the current theme (dark scheme primary) |
| accent-tint | primary @ 12 % over surface; accent-line = primary @ 40 % |
| status ink | `AppColors` x700 light / x300 dark; dot/fill base x500; fill = x500 @ 13 % (StatusPill convention) |

Radii: cards/fields/sections 12, tags/badges 6, pills/chips full, sheets 16 top. Card padding
14; list card margin 6 vertical / 16 horizontal; section gap 12.

## Pills (StatusPill)
Active → green · **Upcoming → orange (NEW mapping)** · Expired → red · Disabled → gray ·
Not Saved → orange (existing) · Selling → green · Buying → blue. Compact size used in list
meta rows. No accent stripe on cards (validity is a pill).

## A. Item Price list (`01`, `02`)
- `DocTypeListHeader` title **"Item Price"**; ☰ · search · filter (badge with active
  count) · refresh.
- Segment chip row (SelectableFilterChip style, count in bold muted): **All 1,661 ·
  Standard Selling 1,654 · Credit Selling 0 · Standard Buying 7** (all enabled price lists,
  counts from server). Selected = accent tint.
- Chip row: applied `FilterChipWidget`s + `AddFilterChip` "+ Filter".
- `ResultCountPill` "1,654 prices" (tag icon; small filter icon when filtered).
- Row (`GenericDocumentCard`, `navigatesOnTap: true`):
  - top-left: item code 11 mono muted; name 13/700 one line ellipsis.
  - top-right: rate 17/700 tabular with "AED" 11/600 muted prefix; under it "/ Nos"
    11 muted; zero rate → "zero · / Nos" in subtle ink (never red).
  - meta row (11, wrap, gap 6): price-list tag (20h r6; ink green for selling, blue for
    buying) · compact pill only when Upcoming/Expired · scope tags with icon:
    "Customer: X" (person), "Supplier: X" (truck), "Batch X" (hash), "from d MMM yyyy"
    / "until d MMM yyyy" (calendar) · trailing chevron.
- `ListEndFooter` "End of results". FAB (extended, maroon) **"New price"** (+ icon),
  hidden without create.

## B. Item Price form (`03` view, `04` edit dark, `05` duplicate, `05b` delete)
- `DocTypeFormHeader`: docType caption "ITEM PRICE", title = item name, pill = validity
  (or "Not Saved" + "Unsaved changes" dot when dirty); refresh · save (filled white when
  dirty, spinner while saving; hidden in view/read-only) · ⋯ overflow (Delete). No tabs.
- Duplicate (server error) → error `InlineBanner` at top: bold "Couldn't save" + message
  line (verbatim server text).
- Card **"Price"**:
  - Item `DocPickerField` with 32px thumbnail, value "code (mono muted 12) name",
    trailing search icon; **locked (lock icon, read-only fill) outside new mode**.
  - Price list field (tag icon) with compact Selling/Buying pill after the value.
  - **MoneyField (NEW)**: label "Rate", "AED" prefix 14/600 muted, value 28/700 tabular,
    suffix "/ <uom>" 13 muted, accent border + 3px ring @22 % when focused, read-only
    = subtle fill; numeric keypad; 2 decimals on blur.
  - Unit field (box icon); hint (new mode only) "Item's stock unit · only the item's units
    are offered".
- Card **"Validity"**: two-column Valid from (calendar) / Valid upto (placeholder
  "No end date").
- Card **"More options"** collapsible (chevron; subtitle "None set" in view, "Customer,
  batch, lead time…" collapsed, list kind when open):
  Customer (selling list only; hint "Only for selling price lists") or Supplier (buying
  only) · row: Valid upto? (edit frame moved it here — keep it in Validity) / Batch
  ("Any batch") · row: Lead time (days) ("0") / Brand read-only "—" · Note.
- View mode footer note (11 subtle, centered): "Read-only · you can view prices but not
  change them".
- Delete confirm dialog: title "Delete this price?" body "<ITEM NAME> · <Price list> ·
  AED 25.00 / Nos. Delivery Notes already saved keep their rate; new ones will find no
  price." actions Cancel / Delete (red ink, trash icon).

## C. Pricing Rule list (`06` empty light/dark, `07`)
- Header title **"Pricing Rule"**; status chips **All · Active · Upcoming · Expired ·
  Disabled** with counts.
- Under header: `ResultCountPill` "4 rules" (percent icon) + right-aligned side dropdown
  chip "Selling ▾" (All / Selling / Buying).
- Row: leading 36px r10 accent-tint icon box (percent for Discount %, tag for Rate /
  Discount Amount, gift for Product); title 13/700; summary sentence 12 muted max 2 lines;
  `StatusPill` top-right; meta: "P5" priority badge (20h r6 accent tint, 700) when set ·
  side tag (Selling green / Buying blue) · calendar + dates ("d MMM yyyy – d MMM yyyy",
  "from …", "until …", or "No end date") · chevron. **Disabled rows: all children 60 %
  opacity, icon box subtle/grey.**
- Empty (zero rules): `ListEmptyState`-style centred: 64px accent-tint circle with percent
  icon, "No pricing rules yet", "Rules apply special rates or discounts automatically on
  Delivery Notes.", primary button "+ New pricing rule" (behind create).
- FAB **"New rule"**.

## D. Pricing Rule form (`08`–`11b`, `13b`)
- Header: caption "PRICING RULE", title = rule title, pill; tabs **Rule · Discount ·
  Conditions** (3 fixed, equal width). A tab containing a validation error shows a small
  red dot after its label.
- **Summary card (NEW)** first child of every tab: accent @12 % fill, accent @40 % border,
  r12, quote icon, 13/500 text; on the Discount tab it shows a small caps "THIS RULE"
  label above the sentence, other tabs compact (no label).
- Locked (promotional scheme) → info banner with lock icon "Locked · Promotional Scheme
  “<name>” overwrites edits" + action "Open on desktop"; everything read-only, no save.
- **Rule tab**
  - Card "Rule", header action: "Enabled"/"Disabled" + small switch.
    Title field (error "Title is required"). Row (120px / 1fr): Side (store icon Selling /
    truck Buying) · "For · <party type or Everyone>" field (users icon, search trailing)
    value party or "Everyone".
  - Card "Applies on", action "<n> items|groups|brands": segmented Item · Group · Brand ·
    Transaction (Brand disabled when there are 0 brands) + **TargetListEditor (NEW)**:
    bordered r12 list; row = code (mono 11 muted) + name 13/600, unit chip (26h,
    "Nos" solid or dashed "Any unit" ▾), × remove; footer row (subtle fill, accent ink)
    "+ Add item" with barcode-scan icon button at the end.
- **Discount tab**: card "What it gives": segmented Price · Product; for Price:
  segmented Rate · Discount % · Discount amount; MoneyField (label Rate / Discount /
  Discount amount; prefix AED except %; suffix "/ Nos", "%", "per line"); when not Rate:
  "Only for price list" field (placeholder "Any price list"; hint "Lines priced from other
  lists are not discounted" when set, "Leave empty to apply on every list" when empty)
  with Selling pill. Product (read-only): locked free-item field ("Free item", hint
  "Qty N"), info banner "Product rules are read-only in the app / Free-item rules are set
  up and changed on desktop.", outlined full-width "Edit on desktop" button (no-op
  snackbar / not required).
- **Conditions tab**: card "When": Valid from / Valid upto ("No end date"); Min qty / Max
  qty (hint "0 = no limit"; error "Max must be at least min (50)"); Min amount / Max
  amount ("AED 0.00"). Card "Priority": Priority field (arrows icon, placeholder "Not
  set", hint "1–20. When several rules match one line, the higher number wins.");
  **orange warning line when unset**: "No priority set. If another rule matches the same
  Delivery Note line at the same priority, that note can't be saved."; switch row "Apply
  multiple rules" / "Let other matching rules stack on top of this one". Below the fold:
  Mixed conditions (items only), Warehouse, read-only "Advanced" `DocDetailRow` card when
  condition / coupon / margin / recursion set.
- **PriorityPickerSheet (NEW)** (`13b`): sheet title "Priority", explainer "Higher number
  wins when several rules match the same line. Two matching rules with the **same**
  priority block the Delivery Note from saving.", 5-column grid of 1–20 buttons (48h r12,
  selected = primary fill white text), note "In use: P3 Dubai wholesale 5% · …" (other
  rules' priorities), footer "No priority" (secondary) / "Done" (primary).

## E. Item form Prices tab (`12a`, `12b`, `12c`)
- Sixth tab "Prices" (tab bar scrollable).
- Card "Item prices", action "<n> lists": compact rows — price list 13/600, tags (Selling
  / Buying, scope, validity pill when not active, "from …"), rate 15/700 "AED" + "/ Nos",
  chevron; divider between rows; outlined small button "+ Add price".
- Card "Pricing rules", action "<n> rule(s)": `RuleRow`s edge-to-edge, note "Rules on item
  groups are not listed here."
- Empty: inline empty (44px circle) "No price set" / "Most items have no price yet —
  that's normal." + small primary "+ Add price"; rules: "No rules name this item" /
  "Rules on item groups are not listed here."
- Template: "Prices are set on variants" / "This is a template. Open a variant to see or
  add its price." (layers icon, no button); rules card "No rules name this template".

## F. Item Price filter sheet (`13a`)
Sheet "Filter prices": PRICE LIST segmented (All / each list) · VALIDITY checkboxes
Active ("Valid today"), Upcoming ("Valid from is in the future"), Expired ("Valid upto has
passed") · SCOPE checkboxes "Has customer or supplier" ("Price limited to one party"),
"Has batch", "Zero rate". Footer Clear / Apply.

## Summary-sentence grammar (designer's — supersedes the build prompt's)
`[give] [on <price list> | the whole transaction] for [everyone | <party type lower> <party>]
[on <item X | N items | item group X | N item groups | brand X | N brands>]
[, min N pcs][, max N pcs][, min AED X][, max AED X][, <from> – <upto> | from <from> | until <upto>]`
- give: Rate → "AED 22.00"; Discount % → "10% off"; Discount Amount → "AED 5.00 off";
  Product → "Buy any of N items, get Q × <free item> free" (Transaction: "Buy anything, …").
- Price list: Rate uses "on Standard Selling"; discounts use "Standard Selling" (no "on").
  Transaction → "the whole transaction" instead of the price list; no target clause.
- Amounts in min/max drop ".00"; dates `d MMM yyyy`; omitted parts vanish (no "0").
Examples:
- "AED 22.00 on Standard Selling for customer Al Noor Trading on item 1000001, 1 Nov 2026 – 31 Jan 2027"
- "10% off Standard Selling for customer group Retail on 3 items, min 12 pcs, 1 Oct 2026 – 31 Dec 2026"
- "AED 5.00 off for everyone on item group Belts, min AED 200, 1 Jun 2026 – 31 Aug 2026"
- "5% off the whole transaction for territory Dubai, min AED 1,000"
- "Buy any of 2 items, get 1 × 2001490 BELTS COTTON AUTO free for everyone, min 3 pcs"

## New components (designer's list)
MoneyField · RuleSummaryCard · TargetListEditor · PriorityPickerSheet · ScopeTag (+
price-list variant) · PriorityBadge · StatusPill 'Upcoming'.
