# ERPNext / Frappe `version-16` Compatibility Audit

**Date:** 2026-09-27
**App base:** `release/play-store` at `a79c60a0` (2.25.6+84)
**Method:** static audit. Every Frappe / ERPNext / HRMS touchpoint in `lib/` was
inventoried and checked against the upstream source of both branches.

| Reference repo | Branch | Revision | Commit date |
|---|---|---|---|
| frappe/erpnext | `version-15` | `4aee12e` | 2026-09-23 |
| frappe/erpnext | `version-16` | `b30aa53` | 2026-09-23 |
| frappe/frappe | `version-15` | `8f801ad` | 2026-09-22 |
| frappe/frappe | `version-16` | `012667b` | 2026-09-22 |
| frappe/hrms | `version-15` | `2238ff6` | 2026-09-23 |
| frappe/hrms | `version-16` | `c0a04b8` | 2026-09-23 |

> **Not covered:** nothing here was exercised against a running v15 or v16 site.
> Findings are derived from reading server source. Site-level customisations
> (`Rack`, `POS Upload`, the `BOM Stock with Customer Code` and
> `POS and Delivery Note Item Rate` reports, `custom_*` fields, server scripts)
> are not in the upstream repos and could not be checked — see
> [Site migration checklist](#site-migration-checklist).

## Summary

| # | Severity | Area | Finding | Status |
|---|---|---|---|---|
| B1 | **Breaking** | Job Card | `make_time_log` parameter renamed `args` → `kwargs`; every timer call fails | Fixed |
| B2 | **Breaking** | Job Card | Pause no longer sticks: `status` is recomputed from the new `is_paused` field | Fixed |
| B3 | **Breaking** | Pickers | `` `modified` desc `` sort is rejected by the v16 query engine; every DocType picker fails to load | Fixed |
| B4 | **Breaking** | Permissions | `user.get_roles` was removed, so the user's roles are unknown and every create / edit button is hidden for users who are not System Managers | Fixed |
| B5 | **Breaking** | Sales Order | `get_item_details` parameter renamed `args` → `ctx`; adding an item to a Sales Order fails | Fixed |
| B6 | Degraded | Navigation | `get_workspace_sidebar_items` renamed `get_workspaces`; the drawer falls back to its default layout | Fixed |
| L1 | Limitation | POS Upload | Status field stays read-only on v16 for users who are not System Managers | Open |
| C1 | Behaviour change | Job Card | `make_time_log` ignores `status`; time-log rows are written with `db_set`/`db_update` | No action |
| C2 | Behaviour change | Work Order | `make_job_card` overrides payload `workstation` with the Work Order Operation row | No action |
| C3 | Behaviour change | Work Order | New statuses `Stock Reserved`, `Stock Partially Reserved` bypass app logic keyed on `Not Started` | Open |
| C4 | Behaviour change | Stock Entry | Four new `purpose` values; `is_scrap_item` removed from Stock Entry Detail | No action |
| C5 | Behaviour change | Sales Order | New status `To Pay` | Open |
| C6 | Behaviour change | Lists | `limit_start` / `limit_page_length` are deprecated (removal targeted for v17) | No action |
| P1 | Pre-existing | Item | Child-table list of `Item Variant Attribute` without `parent` is denied on v15 and v16 | Open |
| P2 | Pre-existing | Job Card | The running-Job-Card check filters on a field with no database column | Open |
| P3 | Pre-existing | Search | `SearchProvider.getBootData` calls `frappe.boot`, which is a module, not a method | Open |

Everything else that was checked is compatible — see [Verified compatible](#verified-compatible).

## How both versions are served

No fix depends on knowing the server version. Each one either uses a form both
servers accept, or detects the capability from data the app already has.

| # | Change | Why it works on both |
|---|---|---|
| B1 | `JobCardProvider.timeLogParams` | Payload is sent under `args` and `kwargs`; each server keeps the key it declares |
| B2 | `JobCardProvider.setJobCardPaused`, `JobCard.isPaused` | Pause writes `status` (v15) and `is_paused` (v16) together. Resume clears `is_paused` first, only when the document carries that field |
| B3 | `DocTypePickerProvider.queryDocType` | Sort is `modified desc`, valid on both |
| B4 | `PermissionService`, `ApiProvider.hasDocTypePermission` | Known roles are intersected with the DocPerm rows as before. When the roles are unknown, the server is asked through `frappe.client.has_permission` |
| B5 | `SalesOrderProvider.itemDetailsParams` | Payload is sent under `args` and `ctx` |
| B6 | `AppNavDrawerController._fetchWorkspaces` | The v15 name is tried first, then the v16 name |

---

## Breaking

### B1 — `make_time_log` parameter renamed

`erpnext/manufacturing/doctype/job_card/job_card.py`

```python
# version-15
def make_time_log(args):
# version-16
def make_time_log(kwargs):
```

Frappe's dispatcher (`frappe.get_newargs`) discards request keys that are not in
the function signature, so on v16 `args` is dropped and the call raises
`TypeError: make_time_log() missing 1 required positional argument: 'kwargs'`.

**Affected:** start, pause, complete and manual time-log entry.

### B2 — Pause cannot be set through `status`

v16 adds an `is_paused` Check field to Job Card and `set_status()` now ends with:

```python
if self.is_paused:
    self.status = "On Hold"
```

The v15 early return (`if self.status == "On Hold" and self.docstatus == 0: return`)
is gone, so a `status` written by the app is recomputed on the same save.

The fix does **not** use the v16 `pause_job` / `resume_job` document methods.
`pause_job` always records a completed quantity of `0` and takes its employees
from the Job Card's employee table. The app asks for the quantity completed at
pause and records it against the employees on the open time log, so calling
`pause_job` would have dropped that. `make_time_log` still exists on v16.

v16 also refuses to submit a Job Card while `is_paused` is set. The app only
offers Complete while the card is Work In Progress, so this is not reachable.

### B3 — Picker sort expression rejected

In v16 both `/api/resource/<doctype>` and `frappe.desk.reportview.get` run through
the query-builder engine (`frappe/model/qb_query.py` → `frappe/database/query.py`).
Its `ORDER BY` / `GROUP BY` validator accepts a backticked identifier only in the
fully qualified form:

```python
BACKTICK_FIELD_PARSE_REGEX = re.compile(r"^`tab([\w\s-]+)`\.(`?)(\w+)\2$")
```

`` `modified` desc `` raises `Order By has invalid backtick notation`.

Every other sort and group expression in the app is accepted by v16, including
`` `tabItem`.`modified` desc ``, `` `tabPricing Rule`.`modified` desc ``,
multi-column sorts, and ``group_by: `tab<DocType>`.`name` ``.

### B4 — The user's roles cannot be read

`frappe.core.doctype.user.user.get_roles` exists on v15 and is absent from v16.

It is the primary source of roles, not a fallback: the `roles` table on User is
`permlevel 1` in both versions, so `GET /api/resource/User/<email>` returns no
roles unless the user is a System Manager. No standard v16 endpoint returns the
session user's roles; `Has Role` cannot be listed either, because Desk Users hold
only `select` on User.

`PermissionService` resolves `create` and `write` by intersecting a DocType's
DocPerm rows with the user's roles. With no roles, every check fails closed.

**Affected:** every create and edit control gated through `DocTypeGuard` — Material
Request, Packing Slip, Stock Entry, Delivery Note, Purchase Order, Sales Order,
Item, Item Price, Pricing Rule and ToDo.

**Fix:** an empty role set is treated as "unknown" rather than "none", since
every Frappe user holds at least the automatic roles. In that case the server
evaluates the permission. Users whose roles are known — all users on v15, System
Managers on v16 — take exactly the path they took before.

Checks that look for `System Manager` directly (attendance alerts, notification
settings, the home dashboard) stay correct on v16: System Managers can read their
own roles, and for everyone else the answer is `false` either way.

### B5 — `get_item_details` parameter renamed

`erpnext/stock/get_item_details.py`

```python
# version-15
def get_item_details(args, doc=None, for_validate=False, overwrite_warehouse=True):
# version-16
def get_item_details(ctx: ItemDetailsCtx, doc=None, for_validate=False, overwrite_warehouse=True):
```

Same mechanism as B1.

### B6 — Workspace sidebar endpoint renamed

`frappe.desk.desktop.get_workspace_sidebar_items` became `get_workspaces` in v16.
The response keeps its `pages` list and every field the app reads, with a few
added. The drawer already tolerated the failure by keeping its cached or default
layout, so this was a loss of the workspace grouping rather than a crash.

---

## Limitation

### L1 — POS Upload status field on v16

The Status control on POS Upload is enabled only when the user holds a `write`
rule at the field's permlevel. That is decided from the user's roles
(`ApiProvider.fieldWriteGranted`), and Frappe has no endpoint that evaluates a
field-level permission for the caller. On v16 the control therefore stays
disabled for users who are not System Managers.

Closing this needs the roles. The smallest change is a whitelisted method in the
site's custom app that returns `frappe.get_roles()`, called when `get_roles`
fails.

The same missing roles leave the profile screen's role list empty and make the
home dashboard's tasks-first ordering fall back to its default.

---

## Behaviour changes

- **C1** — v16 removed `reset_timer_value()`. The `status` key the app sends to
  `make_time_log` is ignored and the status is derived by `set_status()`. Totals
  are refreshed by a later save, which the app's `touchJobCard` already does.
  The removed fields `current_time`, `started_time`, `job_started` and
  `scrap_items` are not referenced by the app.
- **C2** — `make_job_card` now merges each row with the Work Order Operation it
  names, so the `workstation` in the payload is overwritten by the stored value.
  The app sends the row `name`, which v16 requires.
- **C3** — Logic keyed on the Work Order status `Not Started` will not match a
  reserved Work Order. Applies only with stock reservation enabled.
- **C4** — New Stock Entry purposes: `Receive from Customer`,
  `Return Raw Material to Customer`, `Subcontracting Delivery`,
  `Subcontracting Return`. `batch_no`, `serial_no` and `use_serial_batch_fields`
  are unchanged.
- **C5** — Sales Order gains the status `To Pay`. `sales_order_logic.dart` should
  be checked for status lists that need it.
- **C6** — `limit_page_length: 0` still means "no limit".

---

## Pre-existing (not v16 regressions)

- **P1** — `ItemProvider.getItemVariantsByAttribute` lists the child table
  `Item Variant Attribute` without a `parent` argument. Both versions refuse
  child-table queries that do not name a parent DocType.
- **P2** — `_checkForRunningJobCard` filters Job Card on `employee`, a Table
  MultiSelect field with no database column. The query fails on both versions
  and the check is skipped by its own error handler.
- **P3** — `SearchProvider.getBootData` calls `/api/method/frappe.boot`. That path
  names a module, so the call fails on both versions.
- `LogInterceptor(responseBody: true, requestBody: true)` in `ApiProvider` logs
  request bodies, including the login password.

---

## Verified compatible

**Frappe endpoints** — signature and behaviour unchanged for the way the app calls
them: `login`, `logout`, `ping`, `upload_file` (now POST-only; the app uses POST),
`frappe.auth.get_logged_user`, `frappe.client.get_list`, `get_count`, `insert`,
`cancel`, `has_permission`, `frappe.desk.reportview.get`,
`frappe.desk.query_report.run`, `get_data_for_custom_field`,
`frappe.desk.form.load.getdoctype`, `frappe.desk.form.utils.add_comment`,
`frappe.desk.desktop.get_desktop_page`, `frappe.desk.search.awesomebar_search`,
`frappe.utils.global_search.search`, `frappe.utils.change_log.get_versions`,
`user.reset_password`, `user.update_password`.
The login response still carries `message: "Logged In"` and `full_name`.
CSRF validation still applies only when the session holds a token, which API
logins do not create. The realtime socket namespace is unchanged.

**REST resource API** — `GET/POST/PUT/DELETE /api/resource/...` handlers are
unchanged, including submit via `PUT {docstatus: 1}` and child-row updates.
Filters in 2-, 3- and 4-element form, child-table filters, `like`, `in`,
`between`, `!=` and `<` are all handled by the v16 engine.

**ERPNext methods** — `work_order.make_stock_entry`, `job_card.make_stock_entry`,
`sales_order.make_delivery_note`, `sales_order.get_stock_reservation_status`,
`sales_order.update_status` (now POST-only; the app uses POST),
`accounts.party.get_party_details`.

**HRMS** — `hrms.api.get_attendance_calendar_events` is unchanged. The Monthly
Attendance Sheet report gains optional filters.

**Reports** — Stock Balance, Batch-Wise Balance History, Stock Ledger, Item
Variant Details, BOM Search and Job Card Summary exist on v16 with the same
filter names and the columns the app reads.

**DocTypes and fields** — all standard DocTypes the app uses exist on v16, and
every standard field read by a model is present.

---

## Site migration checklist

These are required by the app and are not part of upstream, so they must exist on
the v16 site:

- DocTypes: `Rack`, `POS Upload`
- Reports: `BOM Stock with Customer Code`, `POS and Delivery Note Item Rate`
- Inventory Dimension `rack` (and `to_rack`)
- Custom fields: `custom_po_no`, `custom_reference_no`, `custom_purchase_order`,
  `custom_supplier_name`, `custom_total_qty`, `custom_invoice_serial_number`,
  `custom_variant_of`, `custom_packaging_qty`, `custom_item_barcode`,
  `custom_country_of_origin`
- Any server scripts or custom-app code need their own v16 review, in particular
  anything passing raw SQL field strings such as `sum(x) as y` to
  `frappe.get_list` / `frappe.get_all`. Upstream replaced these with dict syntax
  (`{"SUM": "x", "as": "y"}`) for v16.

## Before release

Test on a v15 site and a v16 site:

1. Job Card: start, pause with a quantity, resume, complete, submit.
2. Open a DocType picker (for example Workstation on a Work Order operation).
3. Sign in as a user who is not a System Manager. Confirm the create and edit
   buttons appear where that user has the permission, and are hidden where the
   user has read-only access.
4. Sales Order: add an item and confirm the rate and UOM are filled in.
5. Open the navigation drawer and confirm screens are grouped by workspace.

Step 3 matters most on v16. Permission checks fail closed, so if
`has_permission` misbehaves on a real server the buttons disappear.
