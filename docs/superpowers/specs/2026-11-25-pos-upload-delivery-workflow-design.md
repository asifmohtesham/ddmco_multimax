# POS Upload delivery workflow design

- **Date** 25 November 2026
- **Scope** Multimax ERP Desk, Multimax Flutter and Telegram Updates through n8n
- **Release** MINOR for the app feature
- **Status** Product decisions confirmed. Phase 0 is committed. Phase 1 starts with ERP staging acceptance, followed by Flutter and separately approved rollout.

## 1. Workflow and data

Use a native Frappe Workflow on `POS Upload.status`. Warehouse preparation moves the POS Upload from **Pending** to **In Progress**. A qualifying Delivery Note (DN) submission makes it **To Deliver**. An authorized recorder selects the driver when recording **Out for Delivery**, a **Delivery Return** to **To Deliver**, or **Delivered**. Delivered is terminal. **Completed** remains for historical rows and the MX/KX Material Issue path. **Cancelled** is a voucher-script outcome on that stock-entry path.

| From | Trigger | Next | Effect |
|---|---|---|---|
| Pending | Eligible DN or MX/KX draft saved | In Progress | Start warehouse preparation. |
| Pending / In Progress | Qualifying DN submitted, or cancellation resolves a recorded conflict | To Deliver | Start the 4-working-hour clock. |
| To Deliver | Out for Delivery | Out for Delivery | Record the driver and recorder. Clear the last return reason and start the 8-working-hour clock. |
| Out for Delivery | Delivery Return | To Deliver | Record the driver, recorder and required reason. Start a fresh 4-working-hour clock. |
| Out for Delivery | Delivered | Delivered | Record the driver and recorder. Stop the clock. |
| To Deliver | Last submitted outbound DN cancelled | In Progress | Stop the clock until another qualifying DN starts a new entry. |
| Pending / In Progress / Cancelled | Qualifying MX/KX Material Issue submitted | Completed | Record stock completion. |
| In Progress / Completed | Last qualifying MX/KX Material Issue cancelled | Cancelled | Record stock cancellation. |
| Cancelled | Valid replacement MX/KX draft saved | In Progress | Resume warehouse preparation. |

**Verified live, before rollout.** Frappe is 16.60.2 and ERPNext/HRMS are 16.60.0. POS Upload is non-submittable, tracks changes and has a permlevel-1 Status Select with default Pending. The pre-rollout site has no POS Upload Workflow. The full paged GET returned **2,168** rows (2,147 Completed, 10 Cancelled, 9 In Progress and 2 Pending). **Verified staging, before apply.** Frappe is 16.60.2 and ERPNext is 16.60.0. Server Scripts are enabled and there is no existing POS Upload Workflow.

Keep Track Changes enabled. Keep `status` at permlevel 1, make it read-only on forms and configure blank, Pending, In Progress, To Deliver, Out for Delivery, Delivered, Completed and Cancelled. Normalize blank to Pending for new records. Add exactly one POS Custom Field after Status, **Return Reason** (`custom_return_reason`). Use Select with a blank first option followed by Late, Rejected and Other. Set permlevel 1, read-only, optional, blank default and `no_copy=1`. Show it when populated. Delivery Return alone sets a nonblank reason. The next Out for Delivery clears it. Versions and Workflow comments preserve each Return and its reason.

### Delivery Note resolution

Use the same query in ERP scripts and guards, Flutter submitted-DN links and n8n ERP reads. Match `Delivery Note.po_no = POS Upload.name`, `docstatus = 1` and `is_return = 0`. Read up to two rows for cardinality.

| Matches | Behaviour |
|---|---|
| 0 | Show that no current outbound DN was found. Block Out for Delivery and Delivered. Allow Delivery Return from Out for Delivery. |
| 1 | Use that DN. Dispatch and Delivered additionally require Multimax company, matching customer, positive documented quantity and no submitted stock return against that DN. |
| 2 or more | Flag for Stock Manager reconciliation. Block Out for Delivery and Delivered. Allow Return, show the ambiguity in Flutter and omit the current DN from alerts. |

**Verified live.** Of 1,922 submitted outbound DNs with nonblank `po_no`, 1,877 matched a POS name exactly across 1,877 distinct POS records. The maximum was one per POS. All exact matches belong to Multimax, and 1,832 also match the POS customer. Count all exact matches before checking company or customer. **Verified repo.** Flutter already looks up DN by exact `po_no` in `_fetchDeliveryNote`, currently taking the first result. The dashboard also does this. [POS form lookup](../../../lib/app/modules/pos_upload/form/pos_upload_form_controller.dart#L686) · [Dashboard lookup](../../../lib/app/modules/home/home_controller.dart#L1326)

### Driver selection and recorder permissions

Outsourced drivers do not have ERP login accounts. A dispatcher records each action and selects an active Driver. A logged-in driver with a dispatcher role may record an action in the same way. All three actions require transient `pos_delivery_driver`, a Link to Driver. For each action, default to a unique, consistently mapped active Driver for the current ERP user, using `Driver.user` and falling back through `Driver.employee` to `Employee.user_id`. If both links exist, they must agree for the default. For Return or Delivered without a mapped Driver, default to the Driver from the latest Out for Delivery Version if it is still active. The recorder can change the driver on every action. The driver and the recorder can each differ across actions on the same POS. Store the driver in the audit trail only. The authenticated User is the recorder and appears in `modified_by` for the action save.

**Verified live, before rollout.** Three active Driver rows have `full_name`. One has both `Driver.user` and `employee`, and its active Employee's `user_id` agrees with `Driver.user`. The other two are outsourced drivers without login mappings. The mapped enabled System User has Stock Manager, Delivery User and Delivery Manager. No existing role has Driver in its name. Stock Manager and Delivery User have no effective POS Custom DocPerm rows in the pre-rollout snapshot.

Create **Delivery Dispatcher** for warehouse dispatch users and logged-in drivers who record deliveries. Grant it based on dispatch responsibilities. Actor-to-Driver mapping supplies the input default only. **Stock Manager** also has permission to record delivery actions. Add effective POS Custom DocPerm rows for Delivery Dispatcher and Stock Manager with Read and Write at permlevels 0 and 1, `if_owner=0`, and other rights off. Retain intake and warehouse access. Add Select-only Driver access at permlevel 0 for Delivery Dispatcher and retain Stock Manager's existing Driver Select access. Make active Driver choices and defaults available to eligible POS readers through `GET /api/method/pos_upload_delivery_drivers?name=<POS>&action=<action>`. The response is `message: {drivers: [{name, full_name}], default_driver: <name or null>}`. Ensure recorders can read their Multimax DN links using standard voucher roles and applicable User Permissions. The action task resolves both names, checks that the selected Driver is active and enforces the full DN guard regardless of client visibility.

## 2. ERP workflow, guard and audit

Create **POS Upload Delivery** for `document_type=POS Upload` with `workflow_state_field=status`. Put Pending first, use docstatus 0 for every state and leave state update field/value blank. Set `allow_edit` to All for Pending/In Progress and Stock Manager for the remaining states. Keep the POS list indicators via **Don't Override Status**. Disable Workflow email alerts and action confirmation. Mark To Deliver, Out for Delivery and Delivered optional to suppress native work items while preserving action discovery. Saving the Workflow can seed blank statuses even while inactive. [Workflow activation](https://github.com/frappe/frappe/blob/v16.60.2/frappe/workflow/doctype/workflow/workflow.py#L37-L109) · [Workflow Action filtering](https://github.com/frappe/frappe/blob/v16.60.2/frappe/workflow/doctype/workflow_action/workflow_action.py#L292-L309)

| Source | Workflow Action Master | Destination | `allowed` |
|---|---|---|---|
| To Deliver | Out for Delivery | Out for Delivery | Delivery Dispatcher and Stock Manager, one row per role |
| Out for Delivery | Delivery Return | To Deliver | Delivery Dispatcher and Stock Manager, one row per role |
| Out for Delivery | Delivered | Delivered | Delivery Dispatcher and Stock Manager, one row per role |

Each row uses `allow_self_approval=1`, `send_email_to_creator=0` and the same synchronous **POS Upload Delivery Action** task, linking Workflow Task Server Script **POS Upload Apply Delivery Action**. Leave transition conditions empty and validate eligibility under lock in the task. Desk deduplicates identical menu labels. Flutter deduplicates returned action names for dual-role users. [Workflow transition role checks](https://github.com/frappe/frappe/blob/v16.60.2/frappe/model/workflow.py#L40-L71) · [Desk action menu](https://github.com/frappe/frappe/blob/v16.60.2/frappe/public/js/frappe/ui/page.js#L477-L533)

### Action validation and audit

1. Use the native POST to `frappe.model.workflow.apply_workflow` with top-level `action` and `doc`. The task reads the original `frappe.form_dict.doc` (object or JSON string) with `doctype: "POS Upload"`, `name`, expected `modified`, required `pos_delivery_driver` (Driver document name), and `pos_delivery_reason` for Return. Core reloads the record, checks the transition role and sets the proposed status before the synchronous task.
2. Lock the persisted POS. Match the requested identity and revision to the locked row and core's loaded revision. Validate the persisted source, requested action and proposed destination against the transition table. Resolve the recorder from the authenticated session, the selected active Driver from the required link and the current DN. For dispatch and handover enforce §1. Delivered also requires the current unique DN to match the one recorded by the latest status-changing Out for Delivery Version. If the DN was cancelled and replaced, record a Return and dispatch the replacement before marking it Delivered. Allow Return with exactly Late, Rejected or Other even if the DN is missing or ambiguous. Set the reason for Return and clear it for dispatch.
3. Insert an HTML-escaped Workflow summary comment with the format `POS delivery · {action} · Driver: {driver_name} · recorded by {recorded_by_name}`, followed by reason and DN when available. For example, the displayed dispatch reads “Out for Delivery · Driver: Tanveer · recorded by Asif”. Set a server-only `doc.flags.pos_delivery_action` carrying the approved revision, action and protected values. Use `Version.data.updater_reference` with the standard `doctype`, `docname` and `label` keys and a `pos_delivery` object containing `action`, `driver` (Driver name), `driver_name` (Driver `full_name`), `recorded_by` (User), `recorded_by_name` (User `full_name`), `dn`, `reason`, `comment_id` and the saved `modified` from the guard. The summary preserves readable history after older Versions leave docinfo. The comment, Version and status update commit together. Core also adds a destination-state Workflow comment. Voucher status edges use the same audit convention with their source voucher and no selected driver. [Workflow execution](https://github.com/frappe/frappe/blob/v16.60.2/frappe/model/workflow.py#L109-L217) · [Workflow Task Server Script](https://github.com/frappe/frappe/blob/v16.60.2/frappe/core/doctype/server_script/server_script.py#L217-L227) · [Version diff](https://github.com/frappe/frappe/blob/v16.60.2/frappe/core/doctype/version/version.py#L111-L129)

Add **POS Upload Guard Delivery Fields**, a POS Upload **Before Save** Server Script. On insert allow blank/Pending with empty reason and normalize status to Pending. On update compare `status` and `custom_return_reason` against `doc.get_doc_before_save()` after field-permission filtering. Require the in-process task flag, exact approved values and matching pre-save revision for a change to either field. Check that a workflow save changes only approved fields and save metadata. Preserve authorized warehouse/intake edits in Pending/In Progress and the Pending-only Tally re-import gate. Reject ordinary business-field edits by delivery-only users and to managed delivery records. Reject stale actions and raw protected writes with a reload/use Actions error. Core's role-based validation can accept a raw save across a permitted edge. Document flags are reserved against client payloads. Voucher automation uses the trusted direct-write path below. [Workflow save validation](https://github.com/frappe/frappe/blob/v16.60.2/frappe/model/workflow.py#L232-L271) · [Reserved fields](https://github.com/frappe/frappe/blob/v16.60.2/frappe/model/base_document.py) · [Document save order](https://github.com/frappe/frappe/blob/v16.60.2/frappe/model/document.py#L756-L811)

### Existing voucher Server Scripts

**Verified live.** All six named scripts are enabled. The DN scripts use `po_no` and currently write In Progress, Completed and Cancelled respectively. Stock Entry (SE) Save/Submit use `custom_reference_no`. SE Cancel uses `po_no` today. Update all six in place.

Use exact references to an existing POS. Keep Multimax scope, ML-/KA- references for DNs and MX-/KX- references for non-return Material Issues. Compare the DN customer to POS customer and require positive document quantity for a qualifying outbound DN. Record missing or mismatched links for operational review. For a stock-return DN, resolve the original through `return_against` and confirm its outbound POS reference. Submitted stock reversals create a review on managed POS records and preserve the recorded state. Cancelling a stock return refreshes eligibility against current vouchers.

| Existing ERP Server Script | Event | Required behaviour |
|---|---|---|
| Delivery Note updates POS Upload In Progress | After Save | A qualifying outbound draft moves Pending/blank to In Progress. Other states are preserved. |
| Delivery Note updates POS Upload Completed | After Submit | A sole qualifying submitted outbound DN moves Pending/blank or In Progress to To Deliver. A competing or ineligible DN creates a review and preserves status. A submission in To Deliver keeps that entry active. Out for Delivery and Delivered stay as recorded. |
| Delivery Note updates POS Upload Cancelled | After Cancel | Re-resolve after outbound cancellation. To Deliver with no submitted outbound DN goes to In Progress. With one remaining, keep To Deliver and its clock, subject to eligibility for the next action. With multiple remaining, keep To Deliver blocked and record a review. Pending/In Progress may enter To Deliver if cancellation resolves a recorded conflict and leaves one qualifying DN. Out for Delivery or Delivered stays as recorded and gets a voucher-reversal review. Out for Delivery still permits Return. |
| Stock Entry updates POS Upload In Progress | After Save | A qualifying draft moves Pending/blank to In Progress. A qualifying draft explicitly amended from a cancelled issue with the same reference may also move Cancelled to In Progress. |
| Stock Entry updates POS Upload Completed | After Submit | A qualifying submitted Material Issue moves Pending/blank, In Progress or Cancelled to Completed. |
| Stock Entry updates POS Upload Cancelled | After Cancel | Use `custom_reference_no`. Move In Progress or Completed to Cancelled only when no qualifying submitted Material Issue sibling remains for that reference. |

Stock Manager reconciles an invalid DN and can create or amend a replacement through standard ERP Desk with the same `po_no` if a Return leaves a To Deliver POS without a current DN.

Take the POS row lock before deciding and use current voucher reads in the same transaction. Retry a deadlocked operation from fresh data. A voucher cancellation racing an action either prevents the guarded action or records a reversal against its committed result. For each status change, load the locked preimage with `pos.load_doc_before_save()`, set the status and save metadata on the in-memory POS and use `frappe.db.set_value` with matching values. Add the audit comment and explicitly call `pos.save_version()` and `pos.notify_update()` in the voucher transaction. For a same-state exception record one review comment per POS, source and event under the lock and refresh listeners. The stage entry itself remains intact.

**Verified source.** `frappe.db.set_value` creates neither a Version nor an `on_update` webhook. Write a Version explicitly when a DN starts To Deliver. Its `name` and `creation` give the stage entry ID and time, including for backdated vouchers and drafts created long before submission. Use the native status-changing Version for manual entries. [Database write](https://github.com/frappe/frappe/blob/v16.60.2/frappe/database/database.py#L889-L951) · [Document Version creation](https://github.com/frappe/frappe/blob/v16.60.2/frappe/model/document.py#L1719-L1741)

### Desk

Update **POS Upload** Client Script to open a required active Driver Link and, for Return, a required reason selector in `before_workflow_action`. Use the defaults in §1. Send transient `frm.doc.pos_delivery_driver` and, for Return, `frm.doc.pos_delivery_reason` with the current revision. Unfreeze for the dialog, restore the freeze on confirmation and reject the hook on dismissal. Clear both transient values and the selected action on success, cancellation and failure. Reload on a stale revision. Keep Tally re-import restricted to blank/Pending with a recheck immediately before save. Extend **POS Upload-List** with To Deliver (orange), Out for Delivery (blue) and Delivered (green). [Desk workflow handler](https://github.com/frappe/frappe/blob/v16.60.2/frappe/public/js/frappe/form/workflow.js#L122-L141)

## 3. ERPNext webhook and n8n

**Verified live and local.** n8n runs at `https://automation.milanoleather.ae`. The enabled ERP Webhook **POS Upload** already posts on `after_insert` there with security disabled. The local router export shows the Updates channel and the Telegram send node credential **Telegram account**. Reuse it for `@MilanoLeatherBot` and chat `-1002382434792` (Updates). Stock Managers receive alerts as channel members. Confirm intended membership and bot posting rights during rollout. [Channel configuration](<C:/Users/asifm/telegram-stock-sheet/n8n/router-live.json:553>) · [Telegram node pattern](<C:/Users/asifm/telegram-stock-sheet/n8n/router-live.json:770>)

### New ERP Webhook

Create **POS Upload Delivery** on POS Upload `on_update`. POST to the n8n production path `/webhook/pos-upload-delivery` using JSON Request Structure and an explicit `Content-Type: application/json` header. Configure this condition:

```python
(
    doc.status in ("Out for Delivery", "To Deliver", "Delivered")
    and doc.get_doc_before_save() is not None
    and doc.has_value_changed("status")
    and (
        doc.status != "To Deliver"
        or doc.get_doc_before_save().status == "Out for Delivery"
    )
)
```

**Verified source, Frappe v16.60.2.** The save loads the preimage before `on_update`. `Document.run_method` calls `run_webhooks`, which evaluates the condition synchronously on the live Document. Both methods are available and the preimage is still present. The queue calls `enqueue_webhook` after commit to send, with the condition already evaluated. The explicit preimage check excludes inserts. A cached-document preview lacks a save preimage, so verify this with a real staging transition. DN submit uses the direct write above and creates no ready action alert. [Document lifecycle](https://github.com/frappe/frappe/blob/v16.60.2/frappe/model/document.py#L1565-L1615) · [Webhook condition and queue](https://github.com/frappe/frappe/blob/v16.60.2/frappe/integrations/doctype/webhook/__init__.py#L31-L112) · [Safe evaluation](https://github.com/frappe/frappe/blob/v16.60.2/frappe/utils/safe_exec.py#L869-L884)

Map JSON keys `name`, `status`, `customer`, `reference_no`, `custom_return_reason`, `modified` and `modified_by` to their respective `doc` fields using Jinja `tojson` without surrounding quotes. The JSON template receives the date-string document dict and `utils` plus the sandboxed Jinja globals. Resolve the driver and recorder from the matching ERP Version and resolve the DN through ERP GETs. [Webhook context and HTTP request](https://github.com/frappe/frappe/blob/v16.60.2/frappe/integrations/doctype/webhook/webhook.py#L137-L159) · [Webhook JSON rendering](https://github.com/frappe/frappe/blob/v16.60.2/frappe/integrations/doctype/webhook/webhook.py#L206-L238) · [Jinja sandbox](https://github.com/frappe/frappe/blob/v16.60.2/frappe/utils/jinja.py#L8-L35)

The repo Webhook record is disabled and uses an HMAC secret placeholder. Leave it disabled on ERP staging until an n8n staging destination is available and separately approved. At rollout, configure **Webhook Secret** in ERP and the corresponding credential in n8n. Frappe sends the base64 HMAC-SHA256 of the exact request-body bytes in `X-Frappe-Webhook-Signature`. Coordinate any later signing change to the current after-insert webhook as a separate router change with its own secret and insert regression test. Restrict ERP Webhook Request Log access and keep raw requests, signed headers and credentials out of n8n diagnostics. [Webhook signing and request logging](https://github.com/frappe/frappe/blob/v16.60.2/frappe/integrations/doctype/webhook/webhook.py#L154-L224)

If a deployment change breaks the preimage condition, use `doc.status in ("Out for Delivery", "To Deliver", "Delivered")` only with an n8n check for a committed, authorized status-changing Version for the exact POS and saved `modified`. For To Deliver require the Out for Delivery → To Deliver Return edge. Skip unrelated edits and events whose Version cannot be verified. Use the same `name + status + modified` static-data map in both modes to suppress repeated deliveries of the same revision.

### n8n configuration

Use an existing authorized ERP integration identity with an HTTP Header Auth credential named **Multimax ERP GET** (proposed label). Check its GET access to POS Upload, POS docinfo, Delivery Note, Shift Type and the selected Holiday List. Use the standard ERP endpoints with filters and pagination. Flutter and n8n use `GET /api/method/frappe.desk.form.load.get_docinfo` with POS read permission. It returns top-level `docinfo.workflow_logs` and the latest ten `docinfo.versions`. Keep existing global Version/Comment permissions. [Docinfo permission and response](https://github.com/frappe/frappe/blob/v16.60.2/frappe/desk/form/load.py#L86-L163) · [Version window](https://github.com/frappe/frappe/blob/v16.60.2/frappe/desk/form/load.py#L227-L236)

Keep importable, inactive JSON for exactly two delivery workflows in the repo. Reference credentials by name only. Both workflows use Telegram **Send Message** with the existing **Telegram account** credential and the Updates chat for production rollout.

#### POS Upload Delivery Events

Use a POST Webhook with **Raw Body** and **Respond to Webhook** mode. Calculate an HMAC-SHA256 over the exact binary request body using the encrypted **ERPNext POS Upload Delivery HMAC** credential (proposed label). Use Crypto v2 Hmac with binary property `data` and Base64 output, then compare the decoded 32-byte result with the tag from `X-Frappe-Webhook-Signature` using `crypto.timingSafeEqual`. Return HTTP 403 for a missing, malformed or mismatched signature. Check raw-byte handling and Code runner crypto support in staging. Parse the signed JSON and validate required fields, statuses and Return reasons, returning 400 for malformed authenticated input. Respond **HTTP 200** immediately after these local checks. Then dedupe, run the ERP GETs, format the message and send it to Telegram. [Webhook options](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook#node-options) · [Crypto HMAC](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.crypto#hmac-parameters)

Use a small map in the workflow's `$getWorkflowStaticData('global')` keyed by `name + status + modified` to absorb Frappe webhook retries. Skip a key recorded after a successful Telegram send. Expire keys after one hour and cap the map at 512 keys, dropping the oldest first.

Read the latest `pos_delivery` Versions for the POS and find the status-changing action Version for the signed revision. Use its captured `driver_name` and `recorded_by_name` as the Driver and Recorded by values. Verify the action and state edge against the event, skipping an event whose Version cannot be verified. Resolve the DN with up to two matches for `po_no = POS Upload.name`, `docstatus = 1` and `is_return = 0`. Use the current unique DN when the POS still has the signed revision and the link agrees with the audit. For a delayed event, use the DN captured in the matching action Version. Omit the DN when its link to the event cannot be established.

#### POS Upload Delivery Overdue

Use a Schedule Trigger hourly within the approved delivery windows in **Asia/Dubai**. Page through POS Uploads in **To Deliver** and **Out for Delivery** and read each current stage-entry Version from docinfo. Use its `creation` as the start and its `name` as `entry_version`. If the entry Version is missing, flag a review and skip that record. Active entries normally remain within the latest ten Versions because business edits are blocked and same-stage reviews add only comments.

Calculate elapsed working time using the calendar below. For entries at or above their threshold, check the workflow's `$getWorkflowStaticData('global')` map keyed by `name + stage + entry_version`. Before sending an alert for an unseen key, re-read the POS and latest stage-entry Version and skip the candidate if its stage or entry ID changed. Use the current unique DN when available. For Out for Delivery, use the driver and recorder of the current dispatch from its stage-entry Version. For To Deliver after a Return, use the driver and recorder captured for that Return. Format and send directly to Telegram. Record the key after a successful send. Prune keys once a complete active-stage scan confirms their entries are no longer active. A Return or redispatch creates a new entry key.

#### Retries and failure visibility

Enable **Retry On Fail** on both workflows' Telegram and HTTP Request nodes, with up to three attempts and a wait between tries. Respect HTTP 429 `retry_after` where the node supports it. Configure both workflows to use the existing n8n operator error workflow with its **Error Trigger** for exhausted failures. Keep diagnostics limited to safe execution context. An alert can be lost if Telegram or n8n is down when it runs. Failures in a running workflow appear in n8n **Executions**. The **ERP Webhook Request Log** records Frappe's request outcome, including delivery failures before acknowledgement. Each event send is attempted within its webhook execution. [Node retries](https://docs.n8n.io/build/understand-workflows/workflow-components/work-with-nodes.md#node-settings) · [Error workflows](https://docs.n8n.io/build/flow-logic/handle-errors-gracefully.md)

Static data persists after successful production executions. Overlapping runs or a failure after a send can still result in a duplicate. Test dedupe through published staging workflows using their real triggers. [Workflow static data](https://docs.n8n.io/build/code-in-n8n/cookbook/built-in-methods-and-variables-examples/getworkflowstaticdata.md)

### Telegram alert templates

Use Telegram **HTML** to match the existing router. Bold titles and consistent labels make the messages easy to scan on a phone without emoji. Turn on **Disable WebPage Preview** and turn off **Append n8n Attribution**. Escape all interpolated ERP values for HTML, replacing `&`, `<`, `>`, `"` and `'` with `&amp;`, `&lt;`, `&gt;`, `&quot;` and `&#39;` respectively. Build `{pos_url}` as `https://erp.multimax.cloud/app/pos-upload/<name>` with the POS name URL-encoded as one path segment, then HTML-escape the URL for the `href`. The POS identifier itself is the link text. [Telegram HTML](https://core.telegram.org/bots/api#html-style) · [n8n Send Message options](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.telegram/message-operations/#send-message-additional-fields)

Omit the entire line for an unavailable value. Include separate **Driver** and **Recorded by** lines sourced from the Version. For To Deliver overdue, include those lines when the entry was a recorded Delivery Return. Out for Delivery overdue uses the Version for the current dispatch.

Render `{time}` in **Asia/Dubai** as `DD MMM YYYY, HH:mm`. Use signed `modified` for events and the evaluation time for overdue alerts. Show working time in hours and minutes. The Return alert displays **Delivery Return** on the Status line, and the resulting POS stage is **To Deliver**. Map Late to **Delivery delayed**, Rejected to **Rejected by customer**, and Other to **Other reason**.

Each HTML template is followed by a rendered example. The To Deliver overdue example follows a recorded Delivery Return.

#### Out for Delivery

```html
<b>{driver_name} is out to deliver POS Upload {pos}</b>
POS Upload: <a href="{pos_url}">{pos}</a>
Customer: {customer}
Delivery Note: {dn}
Driver: {driver_name}
Recorded by: {recorded_by_name}
Time: {time}
```

> **Tanveer is out to deliver POS Upload ML-2026-00123**\
> POS Upload: [ML-2026-00123](https://erp.multimax.cloud/app/pos-upload/ML-2026-00123)\
> Customer: AL FAN EMIRATES GENERAL TRADING\
> Delivery Note: MAT-DN-2026-01234\
> Driver: Tanveer\
> Recorded by: Asif\
> Time: 25 Nov 2026, 09:20

#### Delivery Return

```html
<b>Delivery attempt unsuccessful</b>
POS Upload: <a href="{pos_url}">{pos}</a>
Customer: {customer}
Delivery Note: {dn}
Driver: {driver_name}
Recorded by: {recorded_by_name}
Status: Delivery Return
Reason: {reason}
Time: {time}
```

> **Delivery attempt unsuccessful**\
> POS Upload: [ML-2026-00123](https://erp.multimax.cloud/app/pos-upload/ML-2026-00123)\
> Customer: AL FAN EMIRATES GENERAL TRADING\
> Delivery Note: MAT-DN-2026-01234\
> Driver: Tanveer\
> Recorded by: Asif\
> Status: Delivery Return\
> Reason: Rejected by customer\
> Time: 25 Nov 2026, 11:00

#### Delivered

```html
<b>Delivered</b>
POS Upload: <a href="{pos_url}">{pos}</a>
Customer: {customer}
Delivery Note: {dn}
Driver: {driver_name}
Recorded by: {recorded_by_name}
Time: {time}
```

> **Delivered**\
> POS Upload: [ML-2026-00123](https://erp.multimax.cloud/app/pos-upload/ML-2026-00123)\
> Customer: AL FAN EMIRATES GENERAL TRADING\
> Delivery Note: MAT-DN-2026-01234\
> Driver: Tanveer\
> Recorded by: Asif\
> Time: 30 Nov 2026, 17:05

#### Overdue in To Deliver

```html
<b>Overdue for dispatch</b>
POS Upload: <a href="{pos_url}">{pos}</a>
Customer: {customer}
Delivery Note: {dn}
Driver: {driver_name}
Recorded by: {recorded_by_name}
Time: {time}
Stage: To Deliver
Time in stage: {working_duration}
Threshold: 4 working hours
```

> **Overdue for dispatch**\
> POS Upload: [ML-2026-00123](https://erp.multimax.cloud/app/pos-upload/ML-2026-00123)\
> Customer: AL FAN EMIRATES GENERAL TRADING\
> Delivery Note: MAT-DN-2026-01234\
> Driver: Tanveer\
> Recorded by: Asif\
> Time: 25 Nov 2026, 16:30\
> Stage: To Deliver\
> Time in stage: 4 h 15 min\
> Threshold: 4 working hours

#### Overdue in Out for Delivery

```html
<b>Overdue for delivery</b>
POS Upload: <a href="{pos_url}">{pos}</a>
Customer: {customer}
Delivery Note: {dn}
Driver: {driver_name}
Recorded by: {recorded_by_name}
Time: {time}
Stage: Out for Delivery
Time in stage: {working_duration}
Threshold: 8 working hours
```

> **Overdue for delivery**\
> POS Upload: [ML-2026-00123](https://erp.multimax.cloud/app/pos-upload/ML-2026-00123)\
> Customer: AL FAN EMIRATES GENERAL TRADING\
> Delivery Note: MAT-DN-2026-01234\
> Driver: Tanveer\
> Recorded by: Asif\
> Time: 30 Nov 2026, 16:30\
> Stage: Out for Delivery\
> Time in stage: 8 h 15 min\
> Threshold: 8 working hours

### Working time

**Verified live.** The site timezone is **Asia/Dubai**. The four split Shift Types below use **Multimax 2026-2027**, valid 1 January 2026 to 31 December 2027, with 104 Sunday weekly-off rows and eight other holiday rows. These are attendance configurations. **Approved by the PO on 25 November 2026 as the dispatch calendar**.

| Day | Delivery windows |
|---|---|
| Monday–Thursday and Saturday | Morning 08:00–12:15, Afternoon 13:30–20:00 |
| Friday | Morning (Fri) 08:00–12:00, Afternoon (Fri) 14:30–20:00 |
| Sunday and listed holidays | No windows |

Run hourly ticks from each approved window's opening until before closing. Refresh Shift Types and the Holiday List daily. Skip listed holidays and validate each tick against the effective windows. Use the last-known-good calendar for covered dates during transient read failures and surface missing or expired coverage. Parse ERP timestamps as site-local when they have no offset. For each covered date sum the overlap of `[stage entry, now)` with the working windows. Compare inclusively to **14,400 seconds for To Deliver** and **28,800 seconds for Out for Delivery**. A threshold reached between ticks is notified at the next eligible tick. Same-stage changes leave the clock intact. Return and redispatch create distinct entries. A Wednesday 11:00 ready entry reaches four hours at 16:15. A Saturday 19:00 dispatch reaches eight hours at 16:15 on a working Monday.

## 4. Flutter changes

| Area | Implementation and verified source |
|---|---|
| Model, filters and colours | Accept the seven canonical states and normalize blank to Pending on read. Preserve unknown/legacy labels, keep list reads compatible before ERP rollout and parse optional Return Reason on detail. Update the existing status filters and tap-to-filter. Use orange for To Deliver, blue for Out for Delivery, green for Delivered and a red Return timeline event, with light/dark contrast per repo guidance. [POS model](../../../lib/app/data/models/pos_upload_model.dart) · [Filter bar](../../../lib/app/modules/pos_upload/widgets/pos_upload_status_filter_bar.dart) · [Status pill](../../../lib/app/modules/global_widgets/status_pill.dart) · [Theme guidance](../../../CLAUDE.md) |
| Actions | Replace the raw Status control on Multimax with read-only status and Return Reason plus server-returned Workflow actions. GET `frappe.model.workflow.get_transitions` by doctype/name and dedupe the three recognized actions. Prompt for an active Driver on all three actions and use the defaults in §1. Prompt for a Return reason on Delivery Return. POST `apply_workflow` using the envelope in §2 with the captured `modified`. Reuse existing provider and CSRF retry. Use one in-flight action guard, visible button spinner and required themed selectors. Refresh POS, voucher links, actions and audit after success, conflict or ambiguous result. Discard stale replies. Failed discovery leaves the delivery form read-only. Any legacy editing on other installations must be selected by an explicit unmanaged-site setting. [Current status handler](../../../lib/app/modules/pos_upload/form/pos_upload_form_controller.dart#L997) · [POS provider](../../../lib/app/data/providers/pos_upload_provider.dart) · [Async buttons](../../../lib/app/modules/global_widgets/async_action_buttons.dart) |
| DN and timeline | Apply §1 in the form and dashboard submitted-DN paths, with limit 2, explicit ambiguity and permission-aware links. Distinguish a failed or denied read from zero matches. Keep draft voucher lookup for warehouse prep. Pair docinfo Versions and Workflow summaries by comment ID when available. Display older summaries as history beyond the ten-Version window. Show action, driver, recorder, reason and event DN, preserving repeated returns. A generic To Deliver comment is a stage label. Keep packing, export, legacy Completed and realtime refresh. [Form link](../../../lib/app/modules/pos_upload/form/pos_upload_form_controller.dart#L686) · [Timeline](../../../lib/app/modules/pos_upload/widgets/pos_upload_timeline.dart) · [Draft DN reuse](../../../lib/app/modules/delivery_note/delivery_note_controller.dart#L321) · [Realtime](../../../lib/app/data/mixins/realtime_sync_mixin.dart) |
| Warehouse consumers | Keep DN preparation, MX/KX Material Issue, warehouse dashboard and digest queues on Pending/In Progress, including legacy blank where still present. Apply preparation status and ML-/KA- filters before the DN result limit. Dispatchers use the existing status filters to find delivery work. [DN controller](../../../lib/app/modules/delivery_note/delivery_note_controller.dart) · [SE controller](../../../lib/app/modules/stock_entry/stock_entry_controller.dart) · [Dashboard](../../../lib/app/modules/home/home_controller.dart) · [Digest](../../../lib/app/data/services/digest_service.dart) |

## 5. Acceptance, rollout and rollback

Keep one reproducible source per ERP record for the field, Property Setters, role, permissions, Workflow masters, task, guard, six voucher scripts, native Workflow, two Desk Client Scripts and disabled Webhook. Keep the two inactive n8n exports, apply and rollback tooling, sanitized staging before-images and the staging acceptance report with those sources. [ERP delivery sources](../../erp/pos-upload-delivery/) · [Runbook](../../erp/pos-upload-delivery/RUNBOOK.md)

### Acceptance

- **ERP staging.** Exercise all six voucher hooks, exact DN cardinalities, a different customer, posted stock return, cancellation before dispatch, during dispatch and after Delivered, replacement-DN handover protection, conflict recovery and MX/KX amendment and sibling cancellation. Verify the explicit DN submit Version, the required active Driver for each action, the required Return reason, and the recorded driver and User in comments and Versions. Test concurrent actions, voucher cancellation racing an action, stale revisions, raw REST/Desk writes, forged action data, Tally re-import and historical Completed. Test dispatcher-only, dual-role, Stock Manager without a Driver mapping and unauthorized accounts. Test choosing outsourced drivers and recording Return and Delivered with a different authorized User and Driver from dispatch. Record requests, expected and actual results, pass or fail and fixture cleanup. [Staging acceptance report](../../erp/pos-upload-delivery/STAGING_ACCEPTANCE.md)
- **Flutter.** Update model, filter, status-gate, permission, timeline, dashboard, digest and realtime tests. Cover old sites/unknown statuses, RPC envelopes, required active Driver and Return reason, both default paths, dismissal, spinner and double taps, stale refresh, DN cardinality and permissions, repeated returns with different drivers and recorders, history beyond ten Versions and theme contrast.
- **Webhook and n8n staging, once a staging target is available.** Verify signing exact JSON bytes with quotes and non-ASCII text. Expect 403 for missing or invalid signatures, 400 for malformed authenticated input and 200 before ERP GETs or Telegram for valid events. Exercise the three transition routes and verify that ordinary saves and DN submits produce no action alert. Verify selected Driver and recorded User from the action Version, DN resolution and Version verification after a later unrelated edit. Verify that a Frappe retry within the dedupe window after a successful execution produces one post, including after an n8n restart. Check bounded HTTP and Telegram retries, 429 handling where supported, and failure visibility in n8n Executions, the existing error workflow and the ERP Webhook Request Log as applicable.
- **Overdue staging.** Test Friday breaks, Sunday and holidays, inclusive thresholds, expired calendar and stale-stage suppression. Verify one alert per active stage Version on successive hourly ticks, pruning when the entry is no longer active, and rearming on Return and redispatch.
- **Telegram staging.** Post all five message types to a staging destination. Verify mobile layout, all three Return reasons, HTML escaping, omission of unavailable values, Dubai timestamps and the inline Desk link with previews disabled.

| Phase | Size | Result |
|---|---|---|
| 0. Read compatibility | S | App reads and filters both pre-rollout POS values and delivery stages. |
| 1a. ERP staging | M | Native Desk actions, voucher changes, audit and disabled Webhook accepted on ERP staging. Repo contains inactive n8n imports and reproducible ERP sources. |
| 1b. Flutter and release preparation | M | Flutter delivery actions and audit against accepted ERP staging. Test alerts in an approved staging integration before the separate live rollout. |
| 2. Device alerts | S, optional | Stock Manager one-off local OS alerts while the app is active or resumes. Reuse authorized POS docinfo and stable event IDs, gate by role and OS permission, and dedupe per site/user. |

Release the app feature as MINOR with a new app build number using the released-ancestor diff procedure. Phase 0 can ship with Phase 1b. [Versioning conventions](../../versioning_conventions.md)

1. **ERP staging.** Capture before-images of the six Server Scripts, POS-relevant metadata, Client Scripts, Custom DocPerm rows and any POS Workflow before writes. Keep keys outside the repo and sanitize any sensitive before-image content. Verify Server Scripts are enabled. Recheck status inventory, review blanks before saving the Workflow and dry-run the apply script. Apply the repo records idempotently and keep the new Webhook disabled and Workflow email alerts off. Pause any existing staging POS-insert webhook that targets production while inserting test POS records, then restore its prior setting. Run ERP acceptance with clearly marked test fixtures, disable test users and cancel test vouchers where appropriate. Require ERP staging acceptance before live changes.
2. **Release preparation.** Smoke-test the Flutter build against accepted ERP staging. Verify dispatcher grants and the n8n ERP identity's GET access. When a staging n8n target and Telegram destination are separately available and approved, bind credentials and run signed event, overdue and message checks. Keep the production n8n and Telegram configuration out of ERP staging acceptance.
3. **Separately approved live cutover.** Capture fresh live before-images and recheck status inventory and raw writers. Review open records with qualifying submitted DNs and explicitly enroll reconciled ones through the same locked To Deliver write and Version audit, with the clock starting at activation. Preserve historical Completed and Cancelled. In a short voucher maintenance window, apply status metadata and Desk updates, activate the Workflow and guard and switch all six scripts together. Record cutover. Bind credentials, enable **POS Upload Delivery Events** and then enable the ERP webhook for new revisions. Resume voucher and delivery processing after smoke checks. Check the first real event and n8n failures. Enable **POS Upload Delivery Overdue** after the first real action events look right.
4. **Rollback.** Pause the new ERP webhook and both delivery workflows if active. Pause voucher processing and export in-flight POS with resolved vouchers and attempt history. Disable the delivery Workflow, task and guard and restore the six scripts and prior Desk configuration from before-images. Retain expanded statuses, Return Reason and audit history for records that entered the workflow. Hold affected voucher processing until Stock Manager reconciles the affected POS records. Before re-enabling the delivery workflows, reconcile current active stage entries against their Versions.

### Deferred

Closed and Short-close are deferred.
