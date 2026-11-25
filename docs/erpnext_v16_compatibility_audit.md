# ERPNext / Frappe v16 Compatibility Audit

**Date:** 15 November 2026
**App:** audited at 2.34.1+112; amended on the same day for 2.35.1+115 (finding N4,
which the audit missed)
**Server audited:** the production instance, migrated to v16 on 14 November 2026

| App | Version on the server | Upstream tag read |
|---|---|---|
| Frappe | 16.56.0 | `v16.56.0` |
| ERPNext | 16.55.0 | `v16.55.0` |
| HRMS | 16.53.2 | `v16.53.2` |

This replaces the static audit of 27 September 2026 (app 2.25.7, upstream as of
16.26). That version is in the git history of this file. It could not be relied
on any longer: the app had gained about 7,900 lines since, the server was 30
minor releases further on, and nothing in it had been run against a server.

## Method

1. Read the server's versions from `frappe.utils.change_log.get_versions` and
   check out upstream at exactly those tags, plus `version-15` as a baseline.
2. Inventory every server call in `lib/` (providers, services, and the
   controllers that call `ApiProvider` directly).
3. Fetch live field metadata (`frappe.desk.form.load.getdoctype`) for every
   DocType the app touches (96) and cross-check every field key the app reads
   or writes.
4. Replay every list, picker, report and read-only method call against the
   live server with the app's exact fields, filters, sort and argument shapes.
5. Diff v15 against v16 for each report, method and DocType the app depends on.
6. Smoke-test the fixes on a device against the live server.

Two shortcuts in how steps 2 and 4 were first carried out let finding N4 through;
do not repeat them:

- **Look at every row of a report result, not the first.** The shape of each
  result was judged from its first row. A report with a total row returns keyed
  rows followed by one positional row.
- **Follow each provider method to all of its callers.** Calls were traced from
  `ApiProvider` outwards. The rack scan reaches the server through
  `ItemProvider.getWarehouseStock` and parses the reply in `HomeController`,
  which was never read.

Everything in steps 1–5 was read-only. No document was created or changed on
the server.

## Summary

| # | Severity | Area | Finding | Status |
|---|---|---|---|---|
| N1 | Degraded | Navigation | Both workspace endpoints refuse on 16.56; the drawer kept its cached or default layout | Fixed in 2.34.1 |
| N2 | Functional | Roles | Users who are not System Managers have no readable roles on v16; role-dependent features switched off | Fixed in 2.34.1 |
| N3 | Cosmetic | Item Variant Details | 16.55 adds a template subtotal row, shown as if it were a variant | Fixed in 2.34.1 |
| B1–B6 | Breaking | Job Card, pickers, permissions, Sales Order, navigation | Found in the September audit | Fixed in 2.26.0 |
| — | Breaking | Writes | v16 enforces CSRF on cookie-session writes | Fixed in 2.29.0 |
| — | Breaking | Stock Balance | `item_code` must be a list on every v16 | Fixed in 2.30.0 |
| N4 | Functional | Dashboard rack scan | The Stock Balance result ends with a positional total row; the scan read it as a keyed row and always failed | Fixed in 2.35.1; missed by the audit |
| N5 | Cosmetic | Item Variant Details | Empty attribute chips take up space in variant cards | Fixed in working tree; 16.60 checked live |
| P1 | Pre-existing | Lists | Child-table lists without a parent are refused on v15 and v16 | Open |
| P3 | Pre-existing | Search | `SearchProvider.getBootData` calls `frappe.boot`, a module, not a method | Open |

**Minimum app version for a v16 server: 2.30.0.** Below 2.26.0 Job Card timers
and Sales Order pricing fail; below 2.29.0 writes are rejected; below 2.30.0 the
rack picker returns nothing. 2.34.1 is needed for N1–N3 and 2.35.1 for N4.

## Findings fixed in 2.34.1

### N1 — Workspace endpoints refuse on Frappe 16.56

`frappe.desk.desktop.get_workspace_sidebar_items` does not exist on v16 (HTTP
417). `frappe.desk.desktop.get_workspaces`, which the September fix fell back
to, is **no longer whitelisted** in 16.56 (HTTP 403). With no pages, the drawer
kept the last cached layout, or the default grouping on a fresh install, and
retried both calls every time it opened.

The same `{pages: [...]}` is in the boot object Desk embeds in its page, as
`frappe.boot.workspaces`. 16.56 also dropped the boot keys
`workspace_sidebar_item` and `module_wise_workspaces`; their replacement,
`module_sidebars`, is keyed by module name and carries the same
`{label, app, items}` plus each module's `workspaces`.

**Fix:** `AppNavDrawerController` tries the v15 endpoint, then the v16 one, then
takes the pages from the boot data. A server whose endpoints answered "no" is
remembered so later loads skip them; a timeout rules nothing out.
The 25 November drawer update uses those pages for group order and reads
the exact-name Report allowlist from Desk boot.

### N2 — Roles are unreadable for users who are not System Managers

v16 removed `frappe.core.doctype.user.user.get_roles`, and the User document's
`roles` table is permlevel 1. The September fix (B4) made create and edit
permissions ask the server when roles are unknown, but everything that reads
`user.roles` directly still saw an empty list:

- the POS Upload **Status** control (the field is permlevel 1 on this site),
- the digest notification entry and scheduler (`User.isManager`),
- the role list on the profile screen,
- the home dashboard's tasks-first ordering.

On the audited site this affected 26 of 29 enabled users.

**Fix:** when the User document carries no roles and `get_roles` is not
available, `UserProvider.getRolesFromDesk` reads `frappe.boot.user.roles`, and
only when `frappe.boot.user.name` is the signed-in user. If no source answers,
the roles already known for that same user are kept, so a refresh while offline
does not switch features off. This closes limitation L1 of the September audit.

The Desk page is about half a megabyte. `ApiProvider.getDeskHtml` shares one
download between the drawer and the role lookup, reuses it for two minutes, and
drops it on sign-in, sign-out and server change.

Only standard endpoints are used. The site has an API Server Script that
returns the session user's roles, but relying on it would tie the app to one
site's customisation.

### N3 — Item Variant Details template row

ERPNext 16.55 rewrote this report. Each template's variants are now listed
under a subtotal row for the template (`indent: 0`; variants are `indent: 1`),
and `item_group` and `stock_uom` became columns. On v15 every row is a variant
and no row has `indent`.

**Fix:** a row with `indent` equal to 0 is rendered as a heading — template
code, Item Group, and the totals the report gives it under the report's own
column labels. A figure the server leaves empty (variants with different stock
UOMs) is omitted. The image gallery and the item-detail lookup skip template
rows. `item_group` and `stock_uom` are shown as chips like any other report
column.

## Finding fixed in 2.35.1

### N4 — Dashboard rack scan and the Stock Balance total row

Scanning a rack on the Dashboard always ended in "Invalid Rack QR or Network
Error" on the audited server.

The Stock Balance report has `add_total_row` set, so `message.result` is the
keyed rows followed by one positional list:

```
[{"item_code": "…", "rack": "…", "bal_qty": 36, …}, …, ["Total", "", "", …]]
```

`HomeController` read `row['rack']` on every entry. On the list that throws,
and a catch-all turned the error into the generic message.

Whether this is new in v16 is **not established**. Upstream declares
`add_total_row` for Stock Balance on `version-15` as well as on 16.55, and
`frappe.desk.query_report.run` appends the row on both. The v15 site could not
be examined after the migration, so it is unknown whether the scan worked there.
The fix does not depend on the answer.

**Fix** (`lib/app/modules/home/rack_scan_logic.dart`, commit `56239975`):

- `rackRowsFromStockBalance` keeps only keyed rows, so the total row and any
  other non-map entry are skipped. The rack match is still applied on the
  client.
- The request now passes the rack as the `rack` inventory-dimension filter
  (`ItemProvider.getWarehouseStock(warehouse, rack: …)`), a list on v15 and
  v16, so the reply is the one rack and not the whole warehouse.
- Rack look-up distinguishes invalid codes, report refusals, connection
  failures and unrecognised replies.

**Tablet smoke follow-up.** Reports share one error message mapper. HTTP 403
and Frappe `PermissionError` replies name the report and direct the user to
their administrator. Connection failures give a retry hint. Server failures
use plain text. For validation feedback the app reads the actual message
field and removes HTML. Frappe metadata and exception IDs remain in debug
logs. The same API v1 error fields are available on v15 and v16.
[Frappe v15 response source](https://github.com/frappe/frappe/blob/version-15/frappe/utils/response.py#L31-L64),
[Frappe v16 response source](https://github.com/frappe/frappe/blob/v16.60.0/frappe/utils/response.py#L36-L60).

The fix was checked against live replies from the audited server by the session
that wrote it. It has not been confirmed on a device as part of this audit.

**Was anything else exposed?** After N4 was found, every place that reads a
report's `message.result` was re-read (18 other sites, in `ApiProvider`, the
Item screens and the report controllers). All of them keep only keyed rows, or handle
positional rows explicitly. The Dashboard rack scan was the only one that did
not.

## Follow-up on ERPNext 16.60.0 (21 November 2026)

### N5 — Item Variant Details filters and empty attributes

The tagged report JavaScript, Python and metadata are identical in 16.55.0
and 16.60.0. Both expose three `MultiSelectList` filters in Desk:
`item` (Items), `item_group` (Item Groups) and `warehouse` (Warehouses).
The Python report accepts a string or list for `item`. The app sends a
scalar for one template and a list for several. Item Groups and Warehouses
are sent as lists. Empty selections are omitted.

Both v16 tags return keyed template subtotal rows at `indent: 0` and variant
rows at `indent: 1` with a `template` parent. The report adds no grand-total
row. Columns include Item, Item Group, dynamic attributes, stock UOM,
quantities, order count and prices. Brand can come from the dynamic attributes.
On production (16.60.0) every attribute column is present on each variant row
and an unset attribute comes back as the literal string `-`. Rows also carry
`template` and `currency` keys that are not report columns, so they never
become chips. Template rows carry `stock_uom` and the three totals.

**Fix:** build chips only for populated values, so missing values, blanks
and dash placeholders occupy no space. Template headings and variant-only
item lookups follow N3. The new test covers headings, variants, blank and
dash values. Its fixture follows the production response.

**Live read-only checks (21 November 2026, Frappe/ERPNext 16.60.0).**
All report calls set `ignore_prepared_report=true`. Captures are under
`build/smoke/ivd/multiselect/`. Times are elapsed HTTP time from one request
per case.

| Capture | Filters | HTTP | Result |
|---|---|---:|---|
| `item.json` | ACP-25 | 200 | 3 rows, one template, Current Stock 936 |
| `items.json` | ACP-25 and ACP-MIX | 200 | 5 rows, two contiguous template blocks |
| `groups.json` | Belts only | 200 | 1,991 rows including 939 headings in 1.11 s (532 KB) |
| `multiple_groups.json` | Belts and Wallets | 200 | 7,496 rows including 2,892 headings in 2.28 s (2.01 MB) |
| `warehouse.json` | POS-DXB2 - KA only | 200 | 0 rows |
| `item_warehouse.json` | ACP-25 and POS-DXB2 - KA | 200 | Same 3 rows, Current Stock 936 to 72 |
| `groups_warehouse.json` | Belts and POS-DXB2 - KA | 200 | Same 1,991 rows in the same order, variant Current Stock 224,963 to 23,292 |
| `multiple_warehouses.json` | ACP-25 and POS-DXB2 - KA / WH-DXB1 - KA | 200 | Same 3 rows, Current Stock 936 |
| `empty.json` | Empty object | 200 | 0 rows |
| `non_template.json` | Variant 2002506 in Items | 200 | 0 rows |
| `item_and_group.json` | ACP-25 and Belts together | 417 | ValidationError requiring either Items or Item Groups |

Group selection includes descendants and enabled templates. The upstream
queries have no report-level row cap or pagination. Warehouse selection
includes descendant warehouses and scopes Current Stock, In Production and
Open Sales Orders by source. Current Stock was the only field that changed in
the captures. The app requires Items or Item Groups, enforces their mutual
exclusion, and lets Warehouses qualify either. The variant tile's separate
Stock Balance lookup is labelled as across warehouses when a warehouse
filter is active.

**v15 compatibility.** Desk declares a required single Item Link. Python
passes it to `get_doc("Item", item)` to build the columns and compares
`variant_of` with a scalar equality filter. Current v15 Frappe source can
use the list to pick one matching document for the columns. The variant
query still compares the Link against the stringified list and ordinarily
returns zero rows. A lookup rejection can also occur. For matching Frappe
rejections or a successful legacy-shaped reply to a multi-item request,
the app retries one scalar per template and merges the variant blocks in
selection order, with the union of dynamic columns. Scalar retries keep any selected
warehouses. The report Python
doesn't read `item_group` or `warehouse`. A group-only request lacks the
required Item, and a legacy result returned with extra filters is discarded
with an explanation. This prevents showing unfiltered quantities as
warehouse-filtered values. The fallback uses server responses without a
version check.

The live checks used the privileged API account. Ordinary-user permissions,
the new device UI and a live v15 server remain unverified.

## Drawer report visibility (23 November 2026)

Desk sends a map of report names allowed for the signed-in user. Frappe v15
and early v16 put it in `frappe.boot.user.all_reports`. Later v16 releases
such as 16.56 and 16.60 publish the same map at `frappe.boot.allowed_reports`.
Frappe uses the map to show Report links in Desk, with the Report's roles,
custom role overrides, disabled status, and Report list permissions taken
into account. The `user.can_get_report` list contains DocType names and
cannot identify which named reports the user may open.
[Frappe v15 user boot](https://github.com/frappe/frappe/blob/version-15/frappe/utils/user.py#L225-L253),
[Frappe v15 report map](https://github.com/frappe/frappe/blob/version-15/frappe/boot.py#L177-L285),
[Frappe v16 Desk boot](https://github.com/frappe/frappe/blob/v16.60.0/frappe/desk/desk_views.py#L24-L36),
[Frappe v16 report map](https://github.com/frappe/frappe/blob/v16.60.0/frappe/desk/desk_views.py#L152-L279).

The mobile drawer reads either shape from the existing Desk request and
matches exact report names once the boot user matches the signed-in Frappe
User. Missing or malformed data keeps the default visibility. A valid empty
map hides all report links. The cached workspace layout stays available
offline. Report permissions stay in memory until sign-out. The existing
DocType checks also apply. Frappe still checks access when the report runs,
including permissions for the chosen filters, so a visible link can still
lead to a permission message.
[Frappe v15 report execution](https://github.com/frappe/frappe/blob/version-15/frappe/desk/query_report.py#L248-L268),
[Frappe v16 report execution](https://github.com/frappe/frappe/blob/v16.60.0/frappe/desk/query_report.py#L262-L283).

### Drawer DocType and Report placement (25 November 2026)

Each visible DocType and Report appears once under its own server module on
v15 and v16. DocTypes use `frappe.desk.form.load.getdoctype` metadata. Reports
use the `module` field from `frappe.client.get_list` on Report, which the
standard Desk User role can read. The catalog supplies the group when the
module is unknown and supplies every subheading. When restoring a layout,
the drawer uses any saved server Report module and the catalog fallback for
legacy layouts. A refresh picks up module changes on the server.

The catalog assigns Purchase Receipt and Item Price to Stock, Pricing Rule
to Accounts, and ToDo to Desk. Item appears at the top level of Stock for
users with Item read access, including users whose Desk blocks Stock. The
Report catalog now assigns BOM Search and POS & DN Item Rate to Stock.
Shift Attendance appears under HR → Reports for users who can see it.
To put POS & DN Item Rate under Selling, an administrator can set that custom
Report's `module` to `Selling` in Desk. The app follows that value on refresh.
Report visibility still uses the exact-name Desk allowlist and permission
guards.

## How both versions are served

No fix depends on knowing the server version. Each one either uses a form both
servers accept or detects the capability from what the server answers.

| Change | Why it works on v15 and v16 |
|---|---|
| `JobCardProvider.timeLogParams` | Payload sent under `args` and `kwargs`; each server keeps the key it declares |
| `JobCardProvider.setJobCardPaused` | Pause writes `status` (v15) and `is_paused` (v16) together |
| `DocTypePickerProvider.queryDocType` | Sort is the unquoted `modified desc` |
| `PermissionService` | Known roles are intersected with DocPerm rows; unknown roles ask `frappe.client.has_permission` |
| `SalesOrderProvider.itemDetailsParams` | Payload sent under `args` and `ctx` |
| `CsrfInterceptor` | Token fetched only after the first CSRF rejection, then retried once |
| `ApiProvider.stockBalanceUsesListFilters` | Compares major, then minor; the only version check in the app |
| `AppNavDrawerController._fetchPages` | Endpoints first, boot data when they refuse |
| `AuthenticationController._rolesOf` | User document, then `get_roles`, then boot data, then the roles already known |
| `isTemplateRow` | A v15 row has no `indent` and is always a variant |
| `rackRowsFromStockBalance` | Keeps keyed rows only; a total row is skipped wherever it appears |

## Verified on the live server

- **List and picker queries:** 134 of 136 succeed with the app's exact fields,
  filters, sort options and child-table joins. The two refusals are P1.
- **Reports:** Stock Balance (seven filter shapes), Batch-Wise Balance History,
  Stock Ledger, Item Variant Details, BOM Search, Job Card Summary, Stock
  Ageing - Custom (default and filtered), BOM Stock with Customer Code, POS and
  Delivery Note Item Rate, and Monthly Attendance Sheet all run and return the
  columns the app reads. This check looked at columns and at the first row of
  each result; it did not catch that a result with a total row ends in a
  positional row (N4).
- **Read-only methods:** `get_item_details` (with `args` and `ctx`),
  `get_party_details`, `get_stock_reservation_status`, `has_permission` with and
  without a document name, `get_count` with dict and tuple filters,
  `global_search.search`, `get_data_for_custom_field`, `get_desktop_page`,
  `getdoctype`, and `hrms.api.get_attendance_calendar_events`.
- **Paging and errors:** `limit_page_length=0` returns every row; a missing
  document answers 404 with `DoesNotExistError`.
- **On a device:** the drawer (admin and non-admin), roles for a non-admin
  user, the POS Upload Status control, and the Item Variant Details heading.

## Field-level comparison

v16 removed no field the app depends on, apart from Company
`expenses_included_in_valuation`, which `LandedCostVoucherProvider` already
replaces with an Account lookup. No DocType the app writes gained a mandatory
field, and no Select option the app sends was removed.

New Select values the app may now see: Purchase Order and Sales Order status
`To Pay` (only with an advance payment request), Work Order status
`Stock Reserved` and `Stock Partially Reserved`, Job Card status
`To Manufacture`, Material Request type `Subcontracting`, and four Stock Entry
purposes for subcontracting. `StatusPill` handles `To Pay`.

## Behaviour changes worth knowing

- Dashboard Work Order, Job Card and BOM counts use the standard
  GET method `frappe.client.get_count`. Both versions build the count through
  the permission-checked list query. The standard Job Card grants are for
  System Manager, Manufacturing User and Manufacturing Manager. Stock User
  has read access to Work Order and BOM in upstream metadata. A refused count
  hides its card quietly. Successful counts (including zero), tasks, actionable
  drafts and attendance still load. The Dashboard skips the optional Job Card
  resume lookup when the Job Card count is unavailable.
  [Frappe v15 query](https://github.com/frappe/frappe/blob/version-15/frappe/model/db_query.py#L835-L854)
  · [Frappe v16 query](https://github.com/frappe/frappe/blob/v16.60.0/frappe/model/db_query.py#L578-L597)
  · [ERPNext v15 Job Card](https://github.com/frappe/erpnext/blob/version-15/erpnext/manufacturing/doctype/job_card/job_card.json#L522-L568)
  · [ERPNext v16 Job Card](https://github.com/frappe/erpnext/blob/v16.60.0/erpnext/manufacturing/doctype/job_card/job_card.json#L692-L738)
- `get_item_details` now authorises the pricing context: `doctype` must be a
  transaction DocType, the customer needs `select` permission, the price list
  must be a selling one, and the resolved warehouse must be within the user's
  User Permissions. A refusal falls back to manual rate entry.
- `make_time_log` accepts POST only (the app posts). 16.55 adds
  `JobCard.validate_on_hold`, which clears the pause on a Job Card that has no
  time logs or nothing left to make.
- REST create and update responses omit fields the user cannot read at their
  permlevel.
- The timestamp-conflict message now names the document. The app detects the
  conflict by `TimestampMismatchError`, not by the text.
- `upload_file` gained chunked uploads; a single-part upload is unchanged.
- The realtime socket still requires the site name as namespace and a matching
  Origin; subscription events are unchanged.

## Pre-existing, not v16 regressions

- **P1** — `ItemProvider.getItemVariantsByAttribute` (`Item Variant Attribute`)
  and `PurchaseOrderProvider.getOpenDraftReceiptsForPo` (`Purchase Receipt
  Item`) list a child table without a parent. Both versions refuse. The Item
  attribute filter falls back, and the Purchase Order "resume draft receipt"
  sheet never appears.
- **P3** — `/api/method/frappe.boot` names a module and answers 500.
- `ApiProvider.getStockBalance` sends `batch_no`, which the Stock Balance report
  ignores on both versions.
- `ApiProvider.getRackBatchStock` has no callers.

## Not verified

- **Saving and submitting documents on the production server.** The REST
  handlers, unknown-field handling and `use_serial_batch_fields` behaviour are
  unchanged from v15 by source, and Stock Settings has `use_serial_batch_fields`
  on. None of it was executed during the audit.
- **Sales Orders, Work Orders, Job Cards and Landed Cost Vouchers.** The audited
  site has none, so these were checked against source only.
- **Server Scripts.** The site runs 13 DocType-event scripts on Stock Entry,
  Delivery Note, Purchase Receipt and Material Request saves and submits. They
  use only APIs the v16 sandbox still provides, and attribute access behaves as
  on v15, but they were read, not run.

## Site requirements

Required by the app and not part of upstream:

- DocTypes: `Rack`, `POS Upload`, `Attendance Sync Status`
- Reports: `BOM Stock with Customer Code`, `POS and Delivery Note Item Rate`,
  `Stock Ageing - Custom`
- Inventory Dimension `rack` (and `to_rack`)
- Custom fields: `custom_po_no`, `custom_reference_no`, `custom_purchase_order`,
  `custom_supplier_name`, `custom_total_qty`, `custom_invoice_serial_number`,
  `custom_variant_of`, `custom_packaging_qty`, `custom_item_barcode`,
  `custom_country_of_origin`
- Server Scripts must stay enabled (`server_script_enabled`); the POS Upload
  status updates and the rack and packing checks depend on them.

## Smoke test before relying on a new server version

Sign in as a user who is **not** a System Manager; an administrator's roles come
from the User document and bypass the fallbacks.

1. Open the drawer and verify that DocTypes and Reports are grouped by their
   server modules. Reports appear under the Reports subheading.
2. Open the profile: the role list is filled in.
3. Open a POS Upload: the Status field is enabled for a user with level-1 write.
4. Run Item Variant Details for a template: one heading on v16, then its
   variants. On v15 expect only variants. Check that empty attributes take up
   no space and that item names and images load where available.
   On v16 run multiple Items, then multiple Item Groups, each with multiple
   Warehouses. Check removable selections, quantity totals and tree blocks.
5. Scan a rack on the Dashboard: the rack's contents open.
6. Stock Entry, Delivery Note, Packing Slip and Purchase Receipt: save and
   submit one of each.
7. Job Card: start, pause with a quantity, resume, complete, submit.
8. Sales Order: add an item and confirm the rate and UOM are filled in.

### Item Variant Details navigation on large reports

Keep the scrollbar passive above 500 report rows while the visible list
contains expanded cards. The report shows "Collapse groups to drag the
scrollbar" beside Collapse All and Expand All. Fully collapsed groups use
a 52 logical-pixel extent and support direct thumb seeking. Large flat
replies use touch scrolling and show their own hint.

The Pixel 7 profile freeze baseline measured 1,501.2 ms for Belts and
4,755.1 ms with one ANR for Belts + Wallets. The combined frame spent
4,747 ms in Flutter's UI phase. Released v2.51.0 reached 19.59 ms and
34.94 ms on the respective collapsed thumb runs, with zero ANRs.
Its separate combined Expand All action peaked at 112.99 ms.

Flutter's variable-height SliverList measures intervening children on
a distant pixel jump. Fixed placeholder rows could seek quickly during
a drag, but resolving the landing point requires changing scroll
geometry and preserving the visible row and offset. Group-index seeking,
auto-collapse, and expansion caps all change the meaning of Expand All
or the thumb. The existing collapsed mode already provides group-index
seeking on demand. The package option, super_sliver_list 0.4.1, estimates
unmeasured extents and supports index jumps. It is the closest fit for
keeping expanded cards and thumb navigation together. Adoption would
need to preserve the report's pinned heading and pass the same
Pixel 7 profile gesture measurements. No package was added.

Name search loads the missing variant names via the standard
`frappe.client.get_list` Item method. The request body contains only
the exact report codes, two field names and a row limit. Both v15 and
v16 accept the same arguments and enforce normal Item list permissions.
The cache lasts for one report. The screen reports an incomplete search
if the server refuses the call or omits requested names. Group headings
display the server's subtotal and suppress it when the server leaves
it empty for mixed UOMs. Flat replies have no template subtotal.
The follow-up Pixel 7 profile run used 1,994 Belts rows and 7,500 combined
rows. Five Belts down/up pairs peaked at 15.42 ms. One combined down/up
pair peaked at 10.35 ms. The combined Expand All action peaked at
40.95 ms. Android logged zero ANRs. The passive runs used long edge
swipes on already-expanded content, so these results verify normal
scrolling under the guard. They give no timing for an interactive
variable-height thumb.
