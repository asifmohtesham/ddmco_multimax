# Item Price + Pricing Rule — research record

Sources: ERPNext `version-15` source (paths below, relative to `erpnext/`), the live
site `erp.multimax.cloud` (read-only queries, 2026-09-17; Frappe 15.120.1 / ERPNext
15.121.1), and this repo at `origin/release/play-store` @ `273447f1` (2.20.0+63).

Prompts in this folder:
- `CLAUDE_DESIGN_PROMPT.md` — paste into Claude Design for mockups.
- `CLAUDE_CODE_PROMPT.md` — paste into Claude Code to build (after mockups land).

---

## 1. Live site facts (drive the design)

| Fact | Value | Consequence |
|---|---|---|
| Company / currency | one company `Multimax`, `AED` | Company + currency default silently; show, don't ask |
| Price Lists | `Standard Selling` (sell), `Credit Selling` (sell), `Standard Buying` (buy); all AED, all enabled | 3 options — picker can be a short sheet |
| Item Price rows | **1,661** — Standard Selling 1,654, Standard Buying 7, **Credit Selling 0** | 39 customers default to Credit Selling but it has no prices |
| Price scope | 0 with customer, 0 with supplier, 0 with batch, 0 with valid_upto, all UOM `Nos` | Advanced fields are real but empty today → collapse them |
| Rates | 0 – 220 AED, avg ≈ 15; 6 rows at 0 | Zero rate is legal; show it, flag softly |
| Items | 13,600 enabled sales items; 5,390 templates; 8,182 active variants | Prices live on **variants** (1,638 of 1,661); 0 on templates |
| Coverage | ≈ 20 % of active variants have a price | "no price" is the norm, not an error |
| Who created prices | 8 users incl. Sales-User-only operators (asrar 518, maqbool 212…) | Created via Stock Settings **auto_insert_price_list_rate_if_missing = 1** from Delivery Notes |
| Pricing Rules | **0**. Promotional Schemes **0** | Empty state is the first thing every manager sees |
| Brands | 0 | "Apply on Brand" is allowed but its picker will be empty |
| Customer groups / suppliers / item groups | 6 / 119 / 23 | Small pickers |
| Selling transactions since Jun | 419 Delivery Notes (418 Standard Selling), 0 SO, 0 SI | Rules will bite on **Delivery Notes** |
| Selling Settings | `selling_price_list = Standard Selling`, `editable_price_list_rate = 0` | Operators can't override list rate on a DN |
| Stock Settings | auto-insert = 1, update_existing = 0 | A DN only creates a missing price; it never overwrites |
| Custom fields / property setters on these DocTypes | none | Stock v15 schema is the contract |

### Permissions (live DocPerm = stock v15)

| DocType | Roles with read+write+create+delete | Live users holding them |
|---|---|---|
| Item Price | Sales Master Manager, Purchase Master Manager | SMM 4 (arif, sajid, abdulaziz, asif); PMM 6 (+adnan, asim) |
| Pricing Rule | Accounts Manager, Sales Manager, Purchase Manager, Website Manager, System Manager | Sales Mgr 5, Purchase Mgr 6, Accounts Mgr 1, SM 2 |
| Price List | read: Sales User, Purchase User, Manufacturing User; full: SMM, PMM | 21 Sales Users can read lists but **not Item Price** |

→ Both screens are **manager tools** (~8 people). Operators (Sales User / Stock User) get a
REST 403 on Item Price and must not see the entries. `PermissionService` has no real
`delete` check → gate Delete on `write` (delete roles == write roles for both DocTypes).

---

## 2. Item Price (v15, `stock/doctype/item_price/`)

- `autoname: hash` (names are random, e.g. `5dfs7bls6g` — never show the name as a title),
  `title_field: item_name`, not submittable, `track_changes: 1`, sort `modified`.
- Fields (editable ones in **bold**): **item_code** (reqd, Link Item), **uom** (reqd, fetch
  stock_uom), **packing_unit** (Int), item_name (ro), brand (ro), item_description (ro),
  **price_list** (reqd), **customer** (depends `selling==1`), **supplier** (depends
  `buying==1`), **batch_no**, buying (ro), selling (ro), currency (ro),
  **price_list_rate** (reqd, "Rate"), **valid_from** (default Today), **lead_time_days**,
  **valid_upto**, **note**, reference (set by server = customer/supplier).
- Server `validate()` order and verbatim errors:
  1. item exists (`Item {0} not found.`); **uom must be in the Item's UOMs table**
     (`UOM {0} not found in Item {1}`).
  2. `Valid Upto must be after Valid From` (equal dates allowed).
  3. overwrites buying/selling/currency from the **enabled** Price List
     (`The price list {link} does not exist or is disabled` — HTML in message, strip tags).
  4. overwrites item_name / item_description.
  5. duplicate = same item_code + price_list + uom + valid_from + valid_upto + customer +
     supplier + batch_no + packing_unit (**exact equality, not date overlap**):
     `Item Price appears multiple times based on Price List, Supplier/Customer, Currency, Item, Batch, UOM, Qty, and Dates.`
  6. template items rejected: `Item Price cannot be created for the template item {0}`.
- `before_save`: selling list clears supplier, buying list clears customer.
- Desk picker filters: item `has_variants = 0`; batch `item = item_code`.
- Lookup at transaction time (`stock/get_item_details.py`): party-specific price first,
  then general; uom match or stock uom × conversion; date window; newest `valid_from`
  wins; variant falls back to template price (moot here — templates can't hold prices).

## 3. Pricing Rule (v15, `accounts/doctype/pricing_rule/`)

- `naming_series: PRLE-.####`, `title` reqd, not submittable, sort `modified desc`.
- Key fields & visibility (`depends_on` verbatim in agent report, summarised):
  - **Rule**: title, disable, apply_on (`Item Code|Item Group|Brand|Transaction`, default
    Item Code), price_or_product_discount (`Price|Product`, reqd, no default), warehouse
    (not Transaction), coupon_code_based.
  - **Targets** (child tables, one shown per apply_on): items (item_code, uom),
    item_groups (item_group, uom), brands (brand, uom). UOM optional.
  - mixed_conditions, is_cumulative (not Transaction).
  - **Party**: selling, buying, applicable_for (`Customer|Customer Group|Territory|Sales
    Partner|Campaign` need selling; `Supplier|Supplier Group` need buying) + its one link.
  - **Quantity/amount**: min_qty, max_qty (stock UOM), min_amt, max_amt (0 = no limit).
  - **Price discount**: rate_or_discount (`Rate|Discount Percentage|Discount Amount`,
    default Discount Percentage) → rate | discount_percentage | discount_amount;
    for_price_list (hidden when Rate); apply_discount_on (Transaction only).
  - **Product discount**: same_item, free_item, free_qty, free_item_rate, free_item_uom,
    round_free_qty, is_recursive / recurse_for / apply_recursion_over.
  - **Period**: valid_from (default Today), valid_upto, company, currency (reqd).
  - margin_type / margin_rate_or_amount; condition (Python); apply_multiple_pricing_rules,
    apply_discount_on_rate, threshold_percentage, validate_applied_rule, has_priority,
    priority (Select string `"1".."20"`); promotional_scheme (ro).
- Server `validate()` errors worth mirroring client-side:
  `Priority is mandatory` · `{Item Code} is not added in the table` · `{Customer} is required` ·
  `Rate or Discount is required for the price discount.` · `Duplicate {0} found in the table` ·
  `Variant {0} and its template {1} cannot both be added to the same Pricing Rule` ·
  `Atleast one of the Selling or Buying must be selected` ·
  `Selling must be checked, if Applicable For is selected as {0}` ·
  `Min Qty can not be greater than Max Qty` · `Min Amt can not be greater than Max Amt` ·
  `Rate can not be negative` · `Max discount allowed for item: {0} is {1}%` ·
  `Currency should be same as Price List Currency: {0}` ·
  `Valid from and valid upto fields are mandatory for the cumulative` ·
  `Valid Upto must be after Valid From` · `Free item code is not selected`.
- Server **clears fields of unselected options on save** (other tables, other party links,
  other discount values) → the app can send them; no client clean-up needed.
- Rules from a Promotional Scheme are editable over REST but **overwritten** next time the
  scheme is saved → show read-only with a notice.
- Matching at transaction time: item code (or its template), item group tree, brand;
  selling rules only on Quotation/SO/**DN**/SI/POS; party + group trees; date window;
  for_price_list blank or equal; qty/amount window; highest priority wins; **two rules left
  at the same priority → the Delivery Note save fails** with
  `Multiple Price Rules exists with same criteria, please resolve conflict by assigning priority.`
  (Item Code › Group › Brand precedence is only described in help text — v15 never calls it.)

## 4. Codebase integration map (release/play-store @273447f1)

| Concern | Reuse |
|---|---|
| CRUD reference | `lib/app/modules/todo/**` + `todo_provider.dart` + `todo_model.dart` (mode `new/edit/view`, dirty guard, delete via `performDelete`, `OptimisticLockingMixin`) |
| API | `ApiProvider.getDocumentList / getDocument / createDocument / updateDocument / deleteDocument / getDocumentCount` (`filterTuples` supports child-table 4-tuples) |
| Link pickers | `showDocTypePickerBottomSheet` + `DocTypePickerConfig` (`lib/app/shared/doctype_picker/`), example `work_order_form_controller.dart` warehouse picker |
| Fields | `DocPickerField`, `DocSectionCard`, `DocDetailRow`, `SettingsSwitchRow`, `SettingsSegmented`, `InlineBanner`, `FormEmptyState`, `AsyncFilledButton` |
| Select sheet | private `_showOptionPicker` in `todo_form_screen.dart` (extract if reused) |
| Money | `FormattingHelper.getCurrencySymbol` + `formatAmount` |
| List | `DocTypeListHeader`, `ResultCountPill`, `ListEmptyState`, `ListEndFooter`, `FilterChipWidget`, `GenericDocumentCard` |
| Status | `StatusPill` has `Active` (green), `Expired` (red), `Disabled` (gray), `Enabled` (blue); **`Upcoming` missing**; `GenericDocumentCard._statusAccentColor` keeps its own map |
| Perms | `permission_entries.dart` `kSellingPermissions` (+ drawer `guardEntries`), `DocTypeGuard` |
| Nav | drawer Selling group (`app_nav_drawer.dart` ~411); `kGlobalSearchTargets`; routes in `app_routes.dart` / `app_pages.dart` |
| Item form | 5 tabs (`ItemTabController length: 5`), lazy `onTabChanged`; Re-order tab is the editable-tab precedent; **no price shown anywhere today** |
| Not applicable | dashboard actionable chip-slider (Draft-count based — these DocTypes have no drafts); realtime auto-save (money edits need an explicit Save) |

## 5. Scope decisions (defaults taken — challenge before building)

1. **v1 edits Price-discount rules fully; Product-discount (free item) rules are read-only**
   with "Edit on desktop". Zero rules exist; add free-item editing when someone asks.
2. **Promotional-scheme rules read-only** (server regenerates them).
3. Dynamic `condition`, recursion, `apply_discount_on_rate`, `validate_applied_rule`,
   `threshold_percentage`, `coupon_code_based`: shown read-only when set, not editable.
4. Item form gets a lazy **Prices** tab (item prices + rules that name this item or its template).
5. No "effective price preview" (would call `get_item_details`/`apply_price_list`; shape
   unverified live). No "items without a price" report (needs a server anti-join).
6. Not in Quick Create / chip slider. Pricing Rule in global search (it has a title);
   Item Price not (hash names — search it from its own list by item).
