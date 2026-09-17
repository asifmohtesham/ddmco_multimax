# Claude Design prompt — Item Price + Pricing Rule (mockups)

Paste the fenced block into Claude Design. Facts come from `README.md` in this folder
(ERPNext v15 source + live `erp.multimax.cloud` data, 2026-09-17); component names come
from `docs/doctype_list_view_conventions.md`, `docs/doctype_form_view_conventions.md` and
`docs/app_bar_conventions.md`.

---

```
Design the mobile UI for two new ERPNext DocTypes in Multimax, an existing
warehouse ERP app (Flutter, Material 3, Android-first, phone 390x844):
"Item Price" (what an item sells or is bought for, per price list) and
"Pricing Rule" (automatic discounts / special rates applied on Delivery
Notes). Produce mockups only; no code. Match the existing app, do not
restyle it.

BRAND / TOKENS (existing, reuse exactly)
- Primary maroon #870E18 (form header bar, FAB, avatars, active chips).
  On-primary white.
- Grey ramp: 50 #F9FAFA, 100 #F4F5F6, 200 #EBEEF0, 300 #D8DEE3, 400 #BCC4CB,
  500 #98A1A9, 600 #74808B, 700 #525C66, 800 #323A45, 900 #1F272E.
- Status colours, as TEXT/ICON only: light mode uses the 700 shade, dark mode
  the 300 shade. green 700 #1F5E34 / 300 #8FD3A8; red 700 #9A2222 / 300
  #F09494; orange 700 #9E5409 / 300 #F7B67A; blue 700 #18599A / 300 #7CC0F7.
  Pills: tinted fill (500 colour at ~13%) + 700/300 text. Every text/background
  pair must pass 4.5:1.
- Corners 12-14px on cards, full radius on pills/chips. 14px card padding.
- Both light and dark themes are required.

WHO USES IT
About eight managers (sales/purchase master managers, sales/purchase
managers). They open these screens a few times a week to check or correct
a price, or to set up a customer/group deal. Operators never see these
screens (the entries are hidden for them). Priorities: find an item's
price fast, change it without mistakes, and understand at a glance what a
pricing rule does and to whom.

DATA (real constraints, design for them)
- One company "Multimax", currency AED everywhere. Show "AED" with amounts;
  never ask for company or currency.
- Three price lists: "Standard Selling" (selling, 1,654 prices),
  "Credit Selling" (selling, 0 prices), "Standard Buying" (buying, 7 prices).
- 1,661 item prices, almost all on Standard Selling, all per unit "Nos",
  rates 0-220 AED (typical 15-40). Items are fashion accessories with
  numeric codes and upper-case names, e.g. 1000001 "WALLETS COW" 25.00,
  2001490 "BELTS COTTON AUTO" 40.00. Only variant items can have a price
  (templates cannot); roughly 80% of items have no price yet — that is
  normal, not an error.
- An Item Price can optionally be limited to one customer (selling lists)
  or one supplier (buying lists), one batch, a validity window (valid from
  / valid upto), a packing unit and a lead time. Today none of the rows use
  these, so they are secondary ("More options"), but they must be
  representable, including on list rows (e.g. a small "Customer: Al Noor"
  or "until 31 Dec" tag).
- Derived validity state for both DocTypes: Active (in window), Upcoming
  (valid from is in the future), Expired (valid upto is past); Pricing
  Rules can also be Disabled.
- Two prices for the same item + list + unit + customer/supplier + batch +
  dates are rejected by the server; show that as an inline error on save.
- Pricing Rules: ZERO exist today. The empty state is the first screen
  every manager sees, so it must explain in one line what a rule does and
  offer "New pricing rule".
- A Pricing Rule has:
  * Title (required), enabled/disabled.
  * Applies on: Item Code | Item Group | Brand | Whole transaction, with a
    list of targets (items, groups or brands; each optionally with a unit).
    23 item groups exist; 0 brands (brand picker may be empty).
  * Selling and/or Buying, then "For": everyone, or one Customer, Customer
    Group, Territory, Sales Partner, Campaign (selling) / Supplier,
    Supplier Group (buying). 6 customer groups, 2,376 customers.
  * What it gives. Price rules: a fixed Rate, a Discount %, or a Discount
    Amount, optionally only for one price list. Product rules: a free item
    and quantity (v1 shows these read-only with "Edit on desktop").
  * When: valid from / valid upto, min/max qty, min/max amount (0 = no
    limit).
  * Priority 1-20 (optional) and "Apply multiple rules". Important: if two
    rules match the same Delivery Note line at the same priority, the
    Delivery Note fails to save. The form should make priority
    understandable and warn softly when priority is blank.
  * Rarely used, read-only in the app when set: dynamic Python condition,
    coupon-code based, recursion, margin, "created by Promotional Scheme"
    (edits there get overwritten, so show a locked notice).
- Every rule should be summarised as one plain sentence, generated from
  its fields, e.g. "10% off Standard Selling for customer group Retail on
  3 items, min 12 pcs, 1 Oct - 31 Dec 2026". Use this sentence on list rows
  and at the top of the form.

SCREENS

A. Item Price list (follow the app's list-screen convention)
1. Large collapsing app bar titled "Item Price" (singular), hamburger left,
   search + filter + refresh right. Search is by item code or item name.
2. Price-list segmented chips under the bar: All / Standard Selling /
   Credit Selling / Standard Buying (with counts); plus removable filter
   chips (validity, customer/supplier) and a "+ Filter" chip.
3. Result count pill ("1,654 prices").
4. Rows: item code (monospace-ish tabular) + item name, price list, rate
   right-aligned large in tabular figures "AED 25.00" with "/ Nos", a
   validity pill only when not plainly Active (Upcoming/Expired), optional
   scope tags (customer, supplier, batch, until-date). Zero rate shows
   "AED 0.00" with a muted "zero" hint, not red. Tap opens the form.
5. End-of-list footer ("End of results"); never a sum of rates.
6. FAB "New price" (hidden without create permission).

B. Item Price form (create / view / edit)
- Solid maroon form header: back, "Item Price" label, item name as title,
  StatusPill (Active/Upcoming/Expired), reload + save actions, overflow
  with Delete.
- Main card: Item (picker; after creation shown locked with code + name +
  thumbnail), Price list (short sheet of 3, shows Selling/Buying tag),
  Rate (big numeric input, "AED" prefix, "/ Nos" suffix), Unit (picker
  limited to the item's units, defaults to its stock unit).
- Validity card: Valid from (defaults to today), Valid upto (optional,
  "No end date").
- "More options" collapsed card: Customer (only for selling lists) or
  Supplier (only for buying lists), Batch (limited to the item), Packing
  unit, Lead time (days), Note. Brand + reference shown read-only.
- Unsaved-changes state (save icon active), saving state, server duplicate
  error as an inline banner quoting the server message, delete confirm.
- View mode for users with read-only access (no save/delete, fields flat).

C. Pricing Rule list
1. App bar "Pricing Rule"; status chips All / Active / Upcoming / Expired /
   Disabled with counts; Selling / Buying filter.
2. Rows: title, the generated summary sentence (2 lines max), leading icon
   by kind (percent / tag / gift), StatusPill, small "P5" priority badge
   when set, validity dates. Disabled rows visually muted.
3. Empty state (zero rules): icon, "No pricing rules yet", one line
   explaining "Rules apply special rates or discounts automatically on
   Delivery Notes", primary button "New pricing rule".

D. Pricing Rule form (explicit Save; tabs in the maroon header)
Suggested tabs: Rule | Discount | Conditions (designer may merge if
clearer).
- Top of every tab: the live summary sentence card, updating as fields
  change.
- Rule tab: Title, Enabled switch, Selling / Buying toggles, "For" picker
  (Everyone + the party types valid for the chosen side) + the one party
  link, Applies on segmented (Item / Group / Brand / Transaction), target
  list as removable rows or chips with "+ Add item" (item picker with
  barcode scan), optional unit per target.
- Discount tab: Price vs Product segmented; for Price: Rate | Discount % |
  Discount amount segmented + one value field (%, AED) + "Only for price
  list" optional picker (hidden for Rate). For Product: read-only card with
  "Edit on desktop" notice.
- Conditions tab: Valid from / upto, Min / Max qty, Min / Max amount,
  Priority stepper or picker 1-20 with an explainer line, "Apply multiple
  rules" switch, "Mixed conditions" switch (items only), warehouse
  (optional). Read-only "Advanced" block when condition/coupon/margin/
  recursion are set.
- Validation states: inline field errors for missing title, no targets,
  missing party, min > max, valid upto before valid from, rate/discount
  missing; plus a server error banner.
- Locked state: rule created by a Promotional Scheme (whole form read-only,
  banner with the scheme name).

E. Item form: new "Prices" tab (the Item screen already has tabs Overview,
Stock Levels, Attributes, Attachments, Re-order; this is a sixth)
- Section "Item prices": compact rows per price list (rate, unit, validity
  pill, scope tags), tap opens the Item Price form; "+ Add price" button
  pre-filled with this item (hidden without permission).
- Section "Pricing rules": rules that name this item (or its template)
  directly, using the Pricing Rule row; one muted line "Rules on item
  groups are not listed here".
- Empty states: "No price set" with "+ Add price"; template item:
  "Prices are set on variants" (no add button).

F. Pickers and sheets
- Filter sheet for Item Price (price list, validity, has customer/supplier)
  with "Apply" and "Clear".
- Generic link picker sheet (search + list), shown once for Customer Group.
- Priority picker (1-20) with the explanation "Higher number wins when
  several rules match".

ARTBOARDS TO PRODUCE (one each, phone frame)
1. Item Price list, light, Standard Selling selected, mixed rows (one
   Upcoming, one with a customer tag, one zero rate).
2. Same list, dark theme.
3. Item Price form, view mode, light.
4. Item Price form, editing with unsaved changes + "More options" open,
   dark.
5. New Item Price, duplicate-price server error banner.
6. Pricing Rule list, empty (zero rules), light and dark (two frames).
7. Pricing Rule list with 4 sample rules across Active/Upcoming/Expired/
   Disabled.
8. Pricing Rule form, Rule tab: selling, for Customer Group "Retail",
   applies on 3 items.
9. Pricing Rule form, Discount tab: 10% off, only Standard Selling.
10. Pricing Rule form, Conditions tab with validation errors (min > max,
    missing priority warning).
11. Promotional-scheme locked rule, and a Product (free item) rule shown
    read-only (two frames).
12. Item form Prices tab: item with prices + one rule; and template-item
    empty state (two frames).
13. Filter sheet and priority picker (two frames).
14. Component sheet: validity pills (Active/Upcoming/Expired/Disabled) in
    light and dark with hex values; price row anatomy with spacing;
    rule row anatomy; summary-sentence card; money input field.

CONSTRAINTS
- Reuse these existing app components conceptually and name them in the
  notes so the developer maps them: DocTypeListHeader, ResultCountPill,
  FilterChipWidget, AddFilterChip, GenericDocumentCard, ListEmptyState,
  ListEndFooter, DocTypeFormHeader (solid maroon, tabs inside), StatusPill,
  DocSectionCard, DocDetailRow, DocPickerField, SettingsSwitchRow,
  SettingsSegmented, InlineBanner, FormEmptyState, DocType picker bottom
  sheet, AsyncFilledButton. Call out anything genuinely new (validity pill
  "Upcoming", money input, target list editor, summary-sentence card,
  priority picker).
- Money: tabular figures, right-aligned, 2 decimals, "AED" prefix. Never
  total rates.
- No red for "no price" or zero rate; red only for Expired and errors.
  Upcoming uses orange.
- Dates as "d MMM yyyy". Touch targets >= 48px. Text >= 12px.
- Explicit Save on forms (no auto-save); unsaved-changes guard on back.

DELIVERABLE
Artboards plus a short notes page: pill colour mapping for both themes,
new vs reused components, the summary-sentence grammar you used (with 4
examples covering Rate, Discount %, Discount Amount, Transaction), and any
assumptions you made.
```
