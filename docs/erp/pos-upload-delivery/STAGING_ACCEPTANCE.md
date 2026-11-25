# POS Upload delivery staging acceptance

**25 November 2026 · erp-testing.multimax.cloud · 53 passed, 0 failed, 2 blocked**

Staging reported Server Scripts enabled. The before-images hold the original six voucher scripts, POS Upload metadata overrides, Desk scripts, permissions and existing insert webhook. There was no existing POS Upload Workflow or Custom Field. The staged workflow has six transition rows for Delivery Dispatcher and Stock Manager. It has no Workflow email alerts. The new delivery webhook stays disabled. The existing staging insert webhook was paused during the six fixture inserts and restored afterward.

Native Workflow save seeded all 97 previously blank draft statuses to Pending without changing their revisions. All 2,017 historical Completed records kept their status and revision. No Driver or mapping records were edited. All three staging Driver records were linked through Employees to existing users. The test accounts had no Driver mapping and recorded actions for two distinct existing drivers. The UI picker’s direct and Employee mappings and ambiguous mapping handling were also checked with local fixtures.

## Requests and results

The ERP cases used real staging documents and native HTTP routes. The Tally case exercised the installed Desk script locally with mocked form APIs. The n8n imports were checked offline. Trigger, signing transport and Telegram acceptance require a separate staging notification target.

| Case | Request | Expected | Actual | Result |
|---|---|---|---|---|
| Existing insert webhook restored | GET Webhook/POS Upload | enabled=1 | True | PASS |
| New POS starts Pending | POST POS Upload without status (first run) | All six Pending on insert | Six POS Uploads created in Pending. A later attempt reused them. | PASS |
| DN draft starts warehouse prep | POST Delivery Note | In Progress | In Progress | PASS |
| DN submission enters To Deliver with explicit Version | POST frappe.client.submit | To Deliver + status-changing Version with DN, saved modified and Comment | To Deliver; Version 1q47fpa7jc | PASS |
| Required driver on dispatch | POST apply_workflow Out for Delivery | validation error / To Deliver; Select an active Driver | HTTP 417 / To Deliver; Select an active Driver. | PASS |
| Invalid driver on dispatch | POST apply_workflow Out for Delivery | validation error / To Deliver; Select an active Driver | HTTP 417 / To Deliver; Select an active Driver. | PASS |
| Stale modified rejected | POST apply_workflow Out for Delivery | validation error / To Deliver; This POS Upload changed | HTTP 417 / To Deliver; This POS Upload changed. Reload it and use Actions again. | PASS |
| Non-dispatcher unauthorized | POST apply_workflow Out for Delivery | workflow error / To Deliver; Not a valid Workflow Action | HTTP 417 / To Deliver; Not a valid Workflow Action | PASS |
| Raw REST status write rejected | PUT POS Upload status=Out for Delivery | rejected; To Deliver | HTTP 417; Delivery status and Return Reason are managed by the workflow. Reload the POS Upload and use Actions. | PASS |
| Client-supplied workflow flag rejected | PUT POS Upload with flags and protected fields | rejected; To Deliver | HTTP 417; Delivery status and Return Reason are managed by the workflow. Reload the POS Upload and use Actions. | PASS |
| Two DNs block dispatch | POST apply_workflow Out for Delivery | validation error / To Deliver; Multiple submitted outbound Delivery Notes | HTTP 417 / To Deliver; Multiple submitted outbound Delivery Notes are linked. Ask Stock Manager to reconcile them. | PASS |
| Removing duplicate keeps original ready entry | Cancel duplicate Delivery Note | To Deliver; unchanged ready Version | To Deliver; 1q47fpa7jc | PASS |
| Dispatcher picks a separate Driver | POST apply_workflow Out for Delivery | 200 / Out for Delivery | HTTP 200 / Out for Delivery | PASS |
| Dispatch audit captures driver and recorder | GET POS docinfo | Version + linked Workflow comment with both actor identities | Version 1vokljjooq; Comment 1vndjemfni | PASS |
| Unmapped Stock Manager gets current dispatch Driver as default | GET pos_upload_delivery_drivers | Three active choices; default is dispatched driver | 3 choices; current driver default True | PASS |
| Return requires reason | POST apply_workflow Delivery Return | validation error / Out for Delivery; Select a Return Reason | HTTP 417 / Out for Delivery; Select a Return Reason (Late, Rejected or Other). | PASS |
| Return requires driver | POST apply_workflow Delivery Return | validation error / Out for Delivery; Select an active Driver | HTTP 417 / Out for Delivery; Select an active Driver. | PASS |
| Cancel DN while out preserves state with review | Cancel originally dispatched DN | Out for Delivery + cancellation review | Out for Delivery; matching review count 1 | PASS |
| Zero DNs block Delivered | POST apply_workflow Delivered | validation error / Out for Delivery; No submitted outbound Delivery Note | HTTP 417 / Out for Delivery; No submitted outbound Delivery Note found for this POS Upload. | PASS |
| Replacement DN blocks handover until next dispatch | POST apply_workflow Delivered | validation error / Out for Delivery; changed since dispatch | HTTP 417 / Out for Delivery; The Delivery Note has changed since dispatch. Record a Delivery Return and dispatch the replacement before marking Delivered. | PASS |
| Return with no current DN allowed | POST apply_workflow Delivery Return | 200 / To Deliver | HTTP 200 / To Deliver | PASS |
| Return records new stage, reason, driver and recorder | GET POS + docinfo | To Deliver/Late; manager and second Driver; no DN | ('To Deliver', 'Late'); audit action Delivery Return | PASS |
| Zero DNs block dispatch | POST apply_workflow Out for Delivery | validation error / To Deliver; No submitted outbound Delivery Note | HTTP 417 / To Deliver; No submitted outbound Delivery Note found for this POS Upload. | PASS |
| Redispatch clears last reason | POST apply_workflow Out for Delivery | 200 / Out for Delivery | HTTP 200 / Out for Delivery | PASS |
| Prior reason cleared | GET POS Upload | Blank Return Reason | '' | PASS |
| Delivered by different Driver and user | POST apply_workflow Delivered | 200 / Delivered | HTTP 200 / Delivered | PASS |
| Handover audit preserves distinct actor and Driver | GET POS docinfo | Delivered; manager and second Driver | Delivered; Version 26eigsh502 | PASS |
| Voucher cancellation after Delivered | Cancel final DN | Delivered and review comment | Delivered | PASS |
| Cancel last To Deliver DN restores In Progress | Cancel the only submitted outbound DN | In Progress | In Progress | PASS |
| Customer mismatch preserves stage | Submit DN with customer different from POS | Pending + review | Pending | PASS |
| Concurrent dispatch applies once | Two same-revision POSTs | One success and one rejection; one dispatch Version | HTTP 200 and HTTP 500 (QueryDeadlockError); exactly one dispatch Version. | PASS |
| MX Material Issue draft | POST Stock Entry | In Progress | In Progress | PASS |
| MX Material Issue submit | Submit Stock Entry | Completed | Completed | PASS |
| Driver Link can search active choices | GET native Link search as dual-role dispatcher | 3 active options | HTTP 200; 3 choices | PASS |
| Delivery permissions do not grant managed business edits | PUT POS total_amount with dual delivery roles | Managed record refuses edit | HTTP 417; This POS Upload cannot be edited here. Use Actions for delivery changes. | PASS |
| MX Material Issue cancel | Cancel the only submitted MX Stock Entry during cleanup, then GET POS | Cancelled | Cancelled | PASS |
| KX Material Issue draft | POST Stock Entry | In Progress | In Progress | PASS |
| KX Material Issue submit | Submit Stock Entry | Completed | Completed | PASS |
| KX Material Issue cancel | Cancel last Stock Entry | Cancelled | Cancelled | PASS |
| Conflict before ready leaves preparation stage | Submit valid DN second to a mismatched DN | In Progress + conflict review | In Progress | PASS |
| Cancellation resolves recorded conflict | Cancel the wrong-customer DN | To Deliver + new conflict-resolved Version | To Deliver; Delivery Note Conflict Resolved | PASS |
| Dual-role action discovery | GET native get_transitions with doc identity | Two rows for one distinct Out for Delivery action | ['Out for Delivery', 'Out for Delivery'] | PASS |
| Submitted stock return preserves ready status with review | Submit mapped return DN against current outbound | To Deliver and a stock return review | To Deliver | PASS |
| Submitted stock return blocks dispatch | POST apply_workflow Out for Delivery | validation error / To Deliver; submitted stock return | HTTP 417 / To Deliver; The submitted Delivery Note has a submitted stock return. Ask Stock Manager to reconcile it. | PASS |
| Cancelling stock return keeps stage entry | Cancel mapped return DN | To Deliver with same stage Version | To Deliver; 3a3l1h29b5 | PASS |
| Cancelling stock return restores dispatch eligibility | POST apply_workflow Out for Delivery | 200 / Out for Delivery | HTTP 200 / Out for Delivery | PASS |
| Cancellation racing dispatch | Cancel current DN while submitting same-revision dispatch | Cancellation wins and POS returns to In Progress, or dispatch wins and cancellation leaves a review | Dispatch HTTP 500 (QueryDeadlockError); cancel HTTP 200; final In Progress; DN cancelled | PASS |
| Historical Completed preserved | Compare paged GET snapshots before/after rollout | All historical Completed rows same status and revision | 2017/2017 unchanged | PASS |
| Native Workflow blank status seed | Compare draft blanks before Workflow save to current records | All before-image blanks become Pending without changed modified | 97/97 | PASS |
| Direct Desk save cannot write status | POST frappe.desk.form.save.savedocs action=Save; set status=Delivered | Rejected by workflow guard; Out for Delivery remains | HTTP 417; Delivery status and Return Reason are managed by the workflow. Reload the POS Upload and use Actions.; Out for Delivery | PASS |
| Workflow and notification switches match staging rollout | GET Workflow, Webhook and POS Custom Field records | Workflow active, six role edges, email alerts off, webhook disabled, one Custom Field | Active with six transitions; email alerts off; delivery webhook disabled; only custom_return_reason added. | PASS |
| No Driver assignment persists on POS Upload | GET current Out for Delivery POS Upload | No transient driver/reason request fields in POS document | HTTP 200; both transient fields absent | PASS |
| MX Material Issue sibling cancellation | POST a second submitted-eligible Stock Entry with the same MX reference | With two submitted siblings, cancelling the first keeps Completed | HTTP 417 UniqueValidationError on insert. MariaDB error 1062 names the unique custom_reference_no index. | BLOCKED |
| MX Material Issue amendment | POST a draft amended from cancelled MAT-STE-2026-08340 with the same MX reference | Cancelled → In Progress on amended draft, then Completed on submit | HTTP 417 UniqueValidationError. Stock Entry-custom_reference_no has unique=1 and the cancelled document still owns the reference. | BLOCKED |
| Tally Pending-only gate | Run the staged Desk Client Script against mocked Frappe form APIs in Node | Allow new Pending and persisted Pending or blank; hide In Progress; block changed status or revision before edit/save | Both persisted eligible statuses saved one fixture item, new Pending saved, In Progress hid Update, and both changed cases made no edits or saves. | PASS |

The two blocked Stock Entry cases could not reach the voucher hooks. Staging enforces one Stock Entry per nonblank Reference No, including cancelled stock entries. The existing unique constraint was retained. A testing site that permits repeated references is needed to exercise those branches through voucher insert and submit.

## Remaining test data

Test users were created with `send_welcome_email=0` and disabled after the checks. All submitted test vouchers were cancelled. The unused draft from the initial test setup was deleted. POS test rows and their audit history remain for inspection.

| Doctype | Name | Final state |
|---|---|---|
| Delivery Note | `MAT-DN-2026-01180` | Cancelled |
| Delivery Note | `MAT-DN-2026-01181` | Cancelled |
| Delivery Note | `MAT-DN-2026-01182` | Cancelled |
| Delivery Note | `MAT-DN-2026-01183` | Cancelled |
| Delivery Note | `MAT-DN-2026-01184` | Cancelled |
| Delivery Note | `MAT-DN-2026-01185` | Cancelled |
| Delivery Note | `MAT-DN-2026-01186` | Cancelled |
| Delivery Note | `MAT-DN-2026-01187` | Cancelled |
| Delivery Note | `MAT-DN-2026-01188` | Cancelled |
| Delivery Note | `MAT-DN-2026-01189` | Cancelled |
| Delivery Note | `MAT-DN-2026-01190` | Cancelled |
| POS Upload | `KA-ZZTEST-P1A-261125-B` | In Progress |
| POS Upload | `KX-ZZTEST-P1A-261125-SE` | Cancelled |
| POS Upload | `ML-ZZTEST-P1A-261125-A` | Delivered |
| POS Upload | `ML-ZZTEST-P1A-261125-C` | Out for Delivery |
| POS Upload | `ML-ZZTEST-P1A-261125-D` | Out for Delivery |
| POS Upload | `MX-ZZTEST-P1A-261125-SE` | Cancelled |
| Stock Entry | `MAT-STE-2026-08340` | Cancelled |
| Stock Entry | `MAT-STE-2026-08341` | Cancelled |
| User | `zztest-p1a-dispatcher@example.invalid` | disabled |
| User | `zztest-p1a-manager@example.invalid` | disabled |
| User | `zztest-p1a-sales@example.invalid` | disabled |

## Flutter Phase 1 contract

Post to `/api/method/frappe.model.workflow.apply_workflow` with an object-valued `doc`. Frappe also accepts its JSON string representation, which Desk uses. Capture `modified` from the server when loading the form and send the exact string, including fractional seconds. The picker accepts the Driver document name, such as `HR-DRI-2026-00003`, and returns the user's uniquely mapped active Driver first, then the current dispatch Driver for Return or Delivered when available. The picker is `GET /api/method/pos_upload_delivery_drivers?name=<POS>&action=<action>` and returns `message.drivers` as `[{name, full_name}]` plus `message.default_driver` as a Driver name or null.

```json
{
  "action": "Delivery Return",
  "doc": {
    "doctype": "POS Upload",
    "name": "ML-ZZTEST-P1A-261125-A",
    "modified": "2026-11-25 19:20:11.123456",
    "pos_delivery_driver": "HR-DRI-2026-00003",
    "pos_delivery_reason": "Late"
  }
}
```

For Out for Delivery and Delivered, include `pos_delivery_driver` and omit `pos_delivery_reason`. Discover actions with `GET /api/method/frappe.model.workflow.get_transitions` and the `doc` query parameter set to JSON `{"doctype":"POS Upload","name":"<POS>"}`. Read `message` and deduplicate by `action`. The apply result is the saved POS under `message`.

| Situation | Server message |
|---|---|
| Missing, unknown or inactive Driver | Select an active Driver. |
| Missing or invalid Return Reason | Select a Return Reason (Late, Rejected or Other). |
| Reason on dispatch or delivery | Return Reason is only accepted for Delivery Return. |
| Changed revision | This POS Upload changed. Reload it and use Actions again. |
| Missing action or role | Not a valid Workflow Action |
| Zero submitted outbound DNs | No submitted outbound Delivery Note found for this POS Upload. |
| Multiple submitted outbound DNs | Multiple submitted outbound Delivery Notes are linked. Ask Stock Manager to reconcile them. |
| Ineligible outbound DN | The submitted Delivery Note must be for Multimax, match the POS customer and have positive quantity. |
| Submitted stock return | The submitted Delivery Note has a submitted stock return. Ask Stock Manager to reconcile it. |
| Handover against a replacement DN | The Delivery Note has changed since dispatch. Record a Delivery Return and dispatch the replacement before marking Delivered. |
| Direct protected write | Delivery status and Return Reason are managed by the workflow. Reload the POS Upload and use Actions. |
| Ordinary edit outside authorized preparation | This POS Upload cannot be edited here. Use Actions for delivery changes. |

Frappe returned HTTP 417 for the validation messages exercised and can return HTTP 500 with `QueryDeadlockError` when concurrent transactions race. Reload POS, voucher resolution, actions and docinfo before a retry.

`GET /api/method/frappe.desk.form.load.get_docinfo` with `doctype=POS Upload` and `name` exposes `docinfo.workflow_logs` and the latest ten `docinfo.versions`. Parse each Version's `data` JSON. Use `changed` to identify the status edge and `updater_reference.pos_delivery` for the selected driver and recorder.

```json
{
  "doctype": "POS Upload",
  "docname": "ML-ZZTEST-P1A-261125-A",
  "label": "Delivery Return",
  "pos_delivery": {
    "action": "Delivery Return",
    "driver": "HR-DRI-2026-00003",
    "driver_name": "Tanveer",
    "recorded_by": "zztest-p1a-manager@example.invalid",
    "recorded_by_name": "ZZTEST-P1A-261125 manager",
    "dn": null,
    "reason": "Late",
    "comment_id": "<Workflow Comment name>",
    "modified": "<saved POS modified>"
  }
}
```

The linked Workflow comment reads `POS delivery · Delivery Return · Driver: Tanveer · recorded by ZZTEST-P1A-261125 manager · Reason: Late` and appends ` · Delivery Note: <DN>` when resolved. Use the audit `comment_id` to pair the records. Older summaries preserve their driver and recorder text after Versions leave the docinfo window. The core also adds a destination-state Workflow comment. Voucher-edge Versions carry the voucher as `updater_reference.doctype` and `docname`, with null driver fields.
