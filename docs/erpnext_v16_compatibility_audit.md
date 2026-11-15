# ERPNext / Frappe v16 Compatibility Audit

**Date:** 15 November 2026
**App:** `release/play-store` at 2.34.1+112
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
| P1 | Pre-existing | Lists | Child-table lists without a parent are refused on v15 and v16 | Open |
| P3 | Pre-existing | Search | `SearchProvider.getBootData` calls `frappe.boot`, a module, not a method | Open |

**Minimum app version for a v16 server: 2.30.0.** Below 2.26.0 Job Card timers
and Sales Order pricing fail; below 2.29.0 writes are rejected; below 2.30.0 the
rack picker returns nothing. 2.34.1 is needed for N1–N3.

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
`deskBootFromHtml` reads the older boot keys where present and `module_sidebars`
otherwise, so `resolveDeskSidebar` and `sidebarSpot` are unchanged.

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

## Verified on the live server

- **List and picker queries:** 134 of 136 succeed with the app's exact fields,
  filters, sort options and child-table joins. The two refusals are P1.
- **Reports:** Stock Balance (seven filter shapes), Batch-Wise Balance History,
  Stock Ledger, Item Variant Details, BOM Search, Job Card Summary, Stock
  Ageing - Custom (default and filtered), BOM Stock with Customer Code, POS and
  Delivery Note Item Rate, and Monthly Attendance Sheet all run and return the
  columns the app reads.
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

1. Open the drawer: screens are grouped under the server's workspaces.
2. Open the profile: the role list is filled in.
3. Open a POS Upload: the Status field is enabled for a user with level-1 write.
4. Run Item Variant Details for a template: one heading, then its variants.
5. Stock Entry, Delivery Note, Packing Slip and Purchase Receipt: save and
   submit one of each.
6. Job Card: start, pause with a quantity, resume, complete, submit.
7. Sales Order: add an item and confirm the rate and UOM are filled in.
