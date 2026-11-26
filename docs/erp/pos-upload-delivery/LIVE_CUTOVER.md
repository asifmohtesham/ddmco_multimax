# POS Upload delivery live cutover

The preparation run is read-only. The write commands below are for a separately approved production window. Use `erp.multimax.cloud` and Play alpha 2.60.0+158. Staging ERP acceptance recorded 53 passes and two blocked Stock Entry cases. Preparation found 24 planned creates, eight updates, one retained shared master and no live-only drift on rollout targets. [Live drift](LIVE_DRIFT.md) · [Staging acceptance](STAGING_ACCEPTANCE.md) · [Rollout and rollback spec](../../superpowers/specs/2026-11-25-pos-upload-delivery-workflow-design.md#5-acceptance-rollout-and-rollback)

## Operators and approvals

| Owner | Responsibility |
| --- | --- |
| Product owner | Approve the window and go/no-go, choose Delivery Dispatcher recipients, name a warehouse lead and Stock Manager, approve the open-POS enrolment list and a real smoke POS, and approve the staging Telegram destination and production Updates audience. Decide how to handle the acceptance gaps below. |
| Warehouse lead and Stock Manager | Confirm the voucher pause and staged smoke transaction, reconcile the open POS exceptions and check the first real delivery and any interrupted vouchers. |
| Codex or approved ERP operator | Refresh snapshots and reviews, stage the approved installer sources, run the phased deployment and verification, record events, and execute the rollback if called. A Frappe System Manager with System Console access executes the enrolment transaction. |
| Authorized n8n operator | Prepare inactive imports, bind credentials, test with the approved staging destination, publish the two production workflows in order and check the first production notifications. |

## T−1 day preparation

Run from the repo root. Reuse these variables for the window. Keep the scratch directory and secret files outside Git. A live HTTP 401 stops the run. Ask the key owner to verify rotation before repeating a request.

```powershell
$posDeliveryDir = 'docs/erp/pos-upload-delivery'
$posDeliveryUrl = 'https://erp.multimax.cloud'
$posDeliveryKey = 'C:/Users/asifm/.claude/projects/C--Users-asifm-StudioProjects-ddmco-multimax/memory/erp-api-debug-key.md'
$env:POS_DELIVERY_ERP_URL = $posDeliveryUrl
$env:POS_DELIVERY_ERP_KEY_PATH = $posDeliveryKey
$posDeliveryScratch = 'C:/Users/asifm/AppData/Local/Temp/claude/cut'
$posDeliveryStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$freshBefore = "$posDeliveryScratch/live-$posDeliveryStamp"
$posDeliveryApproved = "$posDeliveryScratch/live-approved-$posDeliveryStamp.json"
$posDeliveryConsole = "$posDeliveryScratch/live-enrol-$posDeliveryStamp.py"
New-Item -ItemType Directory -Path $posDeliveryScratch -Force | Out-Null

python -B "$posDeliveryDir/capture_live.py" --key-path $posDeliveryKey --before-dir $freshBefore
if ($LASTEXITCODE) { throw 'Live capture stopped.' }
python -B "$posDeliveryDir/apply.py" --dry-run --url $posDeliveryUrl --key-path $posDeliveryKey --before-dir $freshBefore |
    Tee-Object "$freshBefore/dry-run.txt"
if ($LASTEXITCODE) { throw 'Live dry run stopped.' }
```

Use the following GET helpers for verification with the deployment identity. For role checks repeat through an authenticated Desk session or token for the specified user. Keep response bodies containing webhook or user configuration in memory and log only the fields needed for verification.

```powershell
$posDeliveryKeyLines = @(Get-Content -LiteralPath $posDeliveryKey | Where-Object { $_ -match '^\s*`[^`\s:]+:[^`\s:]+`\s*$' })
if ($posDeliveryKeyLines.Count -ne 1) { throw 'Expected one ERP key line.' }
$posDeliveryHeaders = @{ Authorization = 'token ' + $posDeliveryKeyLines[0].Trim().Trim('`'); Accept = 'application/json' }
Remove-Variable posDeliveryKeyLines

function Get-PosDeliveryErp($Path, $Query = @{}) {
    $pairs = @($Query.GetEnumerator() | ForEach-Object {
        [uri]::EscapeDataString([string]$_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value)
    })
    $suffix = if ($pairs.Count) { '?' + ($pairs -join '&') } else { '' }
    Invoke-RestMethod -Method Get -Uri ($posDeliveryUrl + $Path + $suffix) -Headers $posDeliveryHeaders -MaximumRedirection 0 -ErrorAction Stop
}

function Get-PosDeliveryDoc($Doctype, $Name) {
    (Get-PosDeliveryErp ('/api/resource/' + [uri]::EscapeDataString($Doctype) + '/' + [uri]::EscapeDataString($Name))).data
}

function Get-PosDeliveryInfo($Name) {
    (Get-PosDeliveryErp '/api/method/frappe.desk.form.load.get_docinfo' @{ doctype = 'POS Upload'; name = $Name }).docinfo
}

(Get-PosDeliveryErp '/api/method/frappe.core.doctype.server_script.server_script.enabled').message
Get-PosDeliveryErp '/api/resource/Server%20Script' @{
    filters = '[["disabled","=",0],["reference_doctype","in",["POS Upload","Delivery Note","Stock Entry"]]]'
    fields = '["name","reference_doctype","doctype_event","modified"]'
    limit_page_length = 100
}
```

1. Confirm the Server Script setting returns `true`. Compare the fresh manifest and records with the committed live and staging before-images. Sign off every merge and collision. Check the dry-run record names and counts against the agreed plan and verify zero deletes. Check POS Upload metadata and other enabled POS/DN/SE Server Scripts, integrations and imports for status writers. Preserve the reviewed installer's exact revision and capture directory. Obtain any restoration secrets needed for redacted records from the owner's vault. Keep the plan on hold if the before-image or write grants for a touched record cannot support rollback. Before activation, confirm build 2.60.0+158 opens live POS Uploads with the existing warehouse statuses and no workflow action buttons. [Preparation dry run](before/live/dry-run.txt)
2. Run the readiness refresh in the linked report. Collect status counts, blank draft names and `modified` values, and status/`modified` pairs for historical Completed and Cancelled. Save the rollback inventories in the scratch directory. For each proposed enrolment check the POS GET and `GET /api/resource/Delivery%20Note` for exact `po_no`, `docstatus=1`, `is_return=0`, then same customer, Multimax and positive `total_qty`. Verify zero submitted stock returns using `return_against=<DN>`, `is_return=1`, `docstatus=1`. Preparation found zero blanks and zero enrolment candidates, with 11 open records to review. Five have a draft outbound DN and six have no exact-PO DN. The Stock Manager reviews the refreshed exceptions and the product owner approves the updated list. [Live readiness and refresh command](LIVE_READINESS.md)
3. Record the User GET role rows for approved dispatchers before grants. Confirm the smoke POS with the warehouse lead. Select a real outbound ML-/KA- POS still in preparation with one qualifying draft DN that the warehouse can legitimately submit in the window, no competing draft or submitted outbound DN, and a planned physical dispatch. Record the POS, DN, stock location, agreed driver, operator and actual handover plan. If no real POS is approved, arrange a pre-created `ML-ZZTEST-` or `KA-ZZTEST-` POS and one qualifying draft DN with an approved test customer, item and isolated test stock. The existing after-insert webhook can notify production on fixture creation, so agree on that existing routing with its owner before provisioning the fixture. Hold the window if neither smoke transaction is approved and ready.
4. Prepare inactive n8n imports and credential assignments using the section below. With its own read-only account, verify GET access to `POS Upload`, `Delivery Note`, `Shift Type`, `Holiday List` and POS docinfo. Capture the `get_docinfo` shape with `versions` read access. Confirm the approved Asia/Dubai dispatch calendar, bot posting rights and Updates audience. Resolve the staging acceptance gates below before publishing.

Preparation rollback consists of discarding a stale plan or inactive imports and generating a fresh capture. Preserve the original T0 rollback images after the first production write.

## Production window, about 30 minutes

| Time | Gate |
| --- | --- |
| 0–5 min | Pause traffic, confirm outstanding jobs have drained, and recheck before-images, status inventories and approvals. |
| 5–15 min | Apply the configuration, grant approved roles and activate the Workflow. |
| 15–25 min | Recheck and enrol the approved list, create the disabled Webhook and smoke ERP and the app. |
| 25–30 min | Enable the delivery Events receiver then the ERP Webhook if their gates pass, and release the pause. Monitor the actual first dispatch and subsequent events. |

### 1. Pause processing and take the final before-image

The warehouse lead announces the window and receives explicit acknowledgment from warehouse Desk and mobile users. Pause saving, submitting, cancelling and amending DNs and SEs, and pause POS Upload edits, Tally imports, delivery actions and automated jobs that perform these writes. Wait for transactions and queues already running to finish. Allow only the named smoke operator to make the agreed smoke transactions later in the window. Capture pending queue counts and confirm by GET the smoke POS and DN revisions and a second unchanged view of the in-scope open inventory. A coordinated pause keeps the old voucher hooks processing correctly until the window while avoiding untracked transitions during deployment. Disabling all six hooks would leave accepted vouchers without POS updates.

Repeat the preparation capture and dry run with a new `$posDeliveryStamp` and fresh `$freshBefore` under the confirmed pause. Keep the final capture as the rollback source. Repeat readiness GETs and revision checks. Stop on unreviewed drift or unstable input. Before any write, rollback is release of the pause after confirming it is safe to resume. After the first write use the configuration rollback below.

### 2. Apply fields, permissions, masters and scripts

Run each command only in the separately authorized window with an ERP operator who has System Manager and Script Manager access. Check the exit code immediately after each Python command. Use the same `$freshBefore` throughout. The configuration phase applies the groups in the order listed.

```powershell
python -B "$posDeliveryDir/apply.py" --apply --authorize-live-cutover --phase configuration --url $posDeliveryUrl --key-path $posDeliveryKey --before-dir $freshBefore
if ($LASTEXITCODE) { throw 'Configuration phase stopped. Keep the warehouse pause in force.' }
python -B "$posDeliveryDir/apply.py" --dry-run --phase configuration --url $posDeliveryUrl --key-path $posDeliveryKey --before-dir $freshBefore
if ($LASTEXITCODE) { throw 'Configuration verification stopped.' }
```

| Order | Expected change and verification GET | Rollback action |
| --- | --- | --- |
| 1. Fields and Property Setters | `Get-PosDeliveryDoc 'Custom Field' 'POS Upload-custom_return_reason'` shows Return Reason with Late, Rejected and Other. Use `Get-PosDeliveryDoc 'Property Setter' 'POS Upload-status-options'` and `Get-PosDeliveryDoc 'Property Setter' 'POS Upload-status-read_only'` to confirm seven states and read-only status. | Restore the prior read-only setting. Retain expanded status options and Return Reason for audit. |
| 2. Role and permissions | GET Role `Delivery Dispatcher`. List `Custom DocPerm` for `parent=POS Upload` and `parent=Driver`, keyed by parent, role, permlevel and if_owner. Compare the five targeted rules to source and the untargeted effective grants to the final snapshot or standard baseline. | Restore changed rules and remove introduced rules or reset copies of standard permissions using the installer. |
| 3. States and actions | GET each `Workflow State` and `Workflow Action Master` named in `05-*` and `06-*`. Preserve existing shared masters. | Park inactive dependencies for history or a later restart. |
| 4. Task, guard and driver API | GET `Workflow Transition Tasks` `POS Upload Delivery Action` and the three Server Scripts named in `07-*`, `09-*` and `10-*`. Verify active scripts, only the intended task, and authenticated driver API. | Disable the added scripts and leave the task association inactive. |
| 5. Six voucher hooks and both Desk scripts | GET each `Server Script` and `Client Script` named in `11-*` and `12-*`. Confirm the scripts, event and enabled settings match the reviewed plan, and that the configuration phase dry run reports `0 planned changes.` | Restore all six original hooks and both prior Desk scripts from the final before-images. |

Grant the role only to approved users in Desk → User → Roles → Add Row → Delivery Dispatcher → Save. `Get-PosDeliveryDoc 'User' $approvedUser` shows one role row per approved user. Compare other role rows with the pre-grant copy. Rollback removes just the rows added during this cutover and verifies the prior roles with GET.

### 3. Activate the Workflow

```powershell
python -B "$posDeliveryDir/apply.py" --apply --authorize-live-cutover --phase workflow --url $posDeliveryUrl --key-path $posDeliveryKey --before-dir $freshBefore
if ($LASTEXITCODE) { throw 'Workflow phase stopped. Keep the warehouse pause in force.' }
$posDeliveryWorkflow = Get-PosDeliveryDoc 'Workflow' 'POS Upload Delivery'
$posDeliveryWorkflow | Select-Object name,is_active,send_email_alert,workflow_state_field
$posDeliveryWorkflow.transitions | Select-Object state,action,next_state,allowed,transition_tasks
```

Expect `is_active=1`, `send_email_alert=0`, `workflow_state_field=status` and six transition rows. Record activation time and operator in the cutover log. Recheck the blank draft inventory by POS GET. Frappe Workflow save seeds blanks to Pending without changing their revision or adding a delivery Version. Recheck Completed and Cancelled against the final snapshot. GET Workflow list for POS Upload and confirm only the delivery Workflow is active. Rollback parks it and restores the former active workflow if captured. Reconcile any necessary correction of the native blank seed separately using the frozen blank inventory and intervening changes.

### 4. Enrol the approved POS records

After activation, use exact current revisions from the POS GET and save the reviewed JSON array as `$posDeliveryApproved`. Each entry has `pos`, `dn`, `modified`. If review still finds no approved rows, save `[]` and run the dry run to record zero eligible rows. An empty approved list skips rendering and console execution. A failed or changed entry returns to the Stock Manager for review.

```powershell
python -B "$posDeliveryDir/enrol.py" --dry-run --candidates $posDeliveryApproved --render-console $posDeliveryConsole
if ($LASTEXITCODE) { throw 'Enrolment preflight stopped.' }
```

Review the dry-run count and the generated source against the approved list. Rendering requires the enabled ERP DN-submit script to match the reviewed repository source. An authorized System Manager opens live Desk → System Console → Python, pastes the reviewed `$posDeliveryConsole` source, selects **Commit** and executes it once. Expect the enrolled count and one Version ID per row. Keep the Console Log ID. The batch revalidates the locked POS revisions, DN eligibility and absence of a submitted stock return before writing. A validation failure aborts the transaction. Verify each through `Get-PosDeliveryDoc 'POS Upload' $posName` and `Get-PosDeliveryInfo $posName`. Expect To Deliver, a new `modified` at enrolment, a status-changing Version with `updater_reference.pos_delivery.action='Delivery Note Submitted'`, the approved DN, and a linked Workflow Comment named by `comment_id`. Preserve that Version as the start of the stage clock. Rollback exports the resulting status, DN, Version and Comment and holds the enrolled records for Stock Manager review. Preserve audit history and avoid bulk status rewrites.

### 5. Create the ERP Webhook disabled

```powershell
python -B "$posDeliveryDir/apply.py" --apply --authorize-live-cutover --phase webhook --url $posDeliveryUrl --key-path $posDeliveryKey --before-dir $freshBefore
if ($LASTEXITCODE) { throw 'Webhook phase stopped.' }
$posDeliveryHook = Get-PosDeliveryDoc 'Webhook' 'POS Upload Delivery'
$posDeliveryHook | Select-Object name,webhook_doctype,webhook_docevent,enabled,enable_security
Remove-Variable posDeliveryHook
```

Expect `POS Upload`, `on_update`, `enabled=0`, security enabled and a production target of `https://automation.milanoleather.ae/webhook/pos-upload-delivery`. Check the condition and JSON against `13-webhook.json` in memory. GET the prior POS Upload Webhook and verify its enabled flag, event and visible URL against the final capture. The router owner can confirm the redacted route privately if routing is in question. Preserve existing routing and signing configuration. Rollback leaves the delivery Webhook disabled and restores its prior settings if it pre-existed. The installer keeps the new disabled record for review. [Webhook source](records/13-webhook.json)

### 6. Smoke one POS on ERP and Play alpha

1. Confirm Play alpha build **2.60.0+158** is connected to live. Open the agreed POS in Desk and the app as the approved dispatcher. The app shows the current status pill, read-only status for the managed site, the matching DN information when accessible, and eligible delivery actions returned by ERP. A user without either delivery role sees no delivery action. Verify `GET /api/method/frappe.model.workflow.get_transitions` with `doc={"doctype":"POS Upload","name":"<POS>"}` using the relevant identities.
2. If using the scheduled qualifying draft DN, have the warehouse lead save and submit it through Desk as the authorized smoke operator. GET the DN for `docstatus=1` and the named POS for To Deliver. GET POS docinfo for a `Delivery Note Submitted` Version and linked Comment. In the app, reopen or refresh the POS and verify **To Deliver**, one **Out for Delivery** button above **Details** and **Items**, the To Deliver filter includes the POS, and Pending/In Progress preparation queues exclude it. Keep the approved driver and current dispatch physically ready. If the smoke POS was enrolled, use its enrolment Version for this gate.
3. Open **Out for Delivery** in the app. `GET /api/method/pos_upload_delivery_drivers?name=<POS>&action=Out+for+Delivery` for the dispatcher supplies active `full_name` choices, the mapped default if present and otherwise requires a selection. Dismiss once and verify the POS revision remains unchanged. Confirm the real dispatch with the selected driver only after the Webhook is enabled in step 7. The app updates the status to **Out for Delivery**, shows **Delivery Return** and **Delivered**, and shows the driver and recorder in the delivery history. GET the POS and docinfo and check one matching dispatch Version and Comment. When an actual handover occurs, approve **Delivered** with its real driver and check the terminal state, no delivery buttons, and the preserved dispatch and handover identities. When an actual failure occurs, use **Delivery Return** with its real driver and reason and check **To Deliver**, the read-only reason and the additional history entry. Preserve those outcomes for the follow-up gate. [Native action and audit contract](STAGING_ACCEPTANCE.md#flutter-phase-1-contract)

For an approved `ZZTEST` fixture, exercise submit, dispatch, Return with Late, redispatch and Delivered while the delivery Webhook is disabled. Apply the same GET and app checks after each transition. Check the reason clears on redispatch and persists in the Return history. The warehouse operator then cancels the test DN and verifies that its stock is restored and the test POS retains Delivered with a cancellation review in docinfo. Record the fixture and retained audit before enabling notifications. The first production notification gate still uses a real dispatch.

On mismatch, hold the pause and save the POS, DN, revision and latest docinfo. Use the rollback procedure if the configuration caused the mismatch. Stock Manager reconciles any actual movement and subsequent status with the warehouse lead. A genuine dispatch or handover remains part of the audit.

### 7. Publish and verify delivery notifications

Prepare through the authorized n8n operator. Import both JSONs with n8n Workflows → Import from File and leave them inactive. Check the production origin in **Check event dedupe** and **Check calendar freshness**, path `pos-upload-delivery`, Asia/Dubai timezone and the production Telegram chat **Updates** (`-1002382434792`). Both imports reference the existing **Telegram account** credential and the **Multimax ERP GET** Header Auth credential. Bind Header Auth to the approved read-only ERP identity, with header name `Authorization` and value in `token <key>:<secret>` format. Confirm the identity and permissions, since the live `n8n@multimax.cloud` account in the readiness inventory has broad roles. Bind every HTTP Request and Telegram node explicitly, and select the existing operator **Error Trigger** workflow in both workflow settings. Ensure the Code runner supports the built-in `crypto` module for the signature compare. [Events import](n8n/pos-upload-delivery-events.json) · [Overdue import](n8n/pos-upload-delivery-overdue.json)

Generate one deployment secret of 32 random bytes encoded as Base64. This PowerShell command keeps it in memory. Put the value through the approved secret vault into the **ERPNext POS Upload Delivery HMAC** Crypto credential on **Calculate body HMAC** and into **Webhook Secret** on ERP **POS Upload Delivery**. Clear `$posDeliveryHmac` after vault entry. Keep the ERP Webhook disabled during this setup.

```powershell
$posDeliveryBytes = New-Object byte[] 32
$posDeliveryRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $posDeliveryRng.GetBytes($posDeliveryBytes) } finally { $posDeliveryRng.Dispose() }
$posDeliveryHmac = [Convert]::ToBase64String($posDeliveryBytes)
[Array]::Clear($posDeliveryBytes, 0, $posDeliveryBytes.Length)
```

After storing the secret and setting both credential fields, run `Remove-Variable posDeliveryHmac`.

1. Publish/enable **POS Upload Delivery Events** in n8n. Confirm the production Webhook URL, Raw Body and `Respond to Webhook` mode. Verify the workflow is active in the n8n workflow view and that GET `Webhook/POS Upload Delivery` still shows `enabled=0`. Rollback unpublishes the Events workflow.
2. In ERP Desk → Webhook → **POS Upload Delivery**, set **Enabled** and save. GET the record and confirm `enabled=1`, `enable_security=1`, the event, production URL and expected condition. Keep the prod HMAC value out of diagnostics. Rollback clears **Enabled** before unpublishing n8n.
3. Release the warehouse pause after the ERP and app preflight passes. The approved dispatcher confirms the first real dispatch. GET the POS and docinfo for the committed action revision and audit. Check **Webhook Request Log** in Desk or through `GET /api/resource/Webhook%20Request%20Log` with an authorized operator for the corresponding successful request. The Events export keeps execution payload saving disabled. Confirm exactly one post in Telegram Updates with the same POS, audit driver and recorder, resolved DN, Dubai time and working Desk link. Watch the first real Return and Delivered when they occur. A webhook HTTP 200 acknowledges intake, so check Telegram and the n8n operator error queue independently. If verification fails, disable the delivery Webhook and unpublish Events while the team investigates. Preserve the ERP statuses and audit if ERP itself passed.
4. Once the first real Events posts are correct, publish/enable **POS Upload Delivery Overdue**. Confirm the hourly window schedule and the daily `00:05` calendar refresh in Asia/Dubai. Use the read-only ERP identity to GET `Shift Type`, the referenced `Holiday List`, and active POS/docinfo. Verify a successful calendar refresh and correct first eligible working-hours post at 4 hours for To Deliver or 8 hours for Out for Delivery, with one alert per stage-entry Version. Rollback unpublishes Overdue immediately and leaves Events active if the issue is confined to Overdue. [Dispatch calendar and thresholds](../../superpowers/specs/2026-11-25-pos-upload-delivery-workflow-design.md#working-time)

## Rollback

1. Disable **POS Upload Delivery** in ERP Desk and verify `enabled=0` by GET. Unpublish **POS Upload Delivery Events** and **POS Upload Delivery Overdue** if active. Reinstate the warehouse pause and drain writers. Export the affected POS and linked DN or SE documents and POS docinfo into scratch, including each affected stage Version, Comment and driver/recorder. Protect any in-flight physical stock or delivery actions through the warehouse lead.
2. Use the exact `$freshBefore` captured at T0 on this deployment. Run this command only under the approved rollback. It parks the delivery workflow and added Server Scripts, restores voucher and Desk code, restores permissions or guarded standard baselines, and reactivates the prior workflow when captured. The expanded status options, Return Reason and audit remain available. Review any installer stop before proceeding with manual restoration from the approved baselines.

   ```powershell
   python -B "$posDeliveryDir/apply.py" --rollback --authorize-live-cutover --url $posDeliveryUrl --key-path $posDeliveryKey --before-dir $freshBefore
   if ($LASTEXITCODE) { throw 'Rollback stopped. Keep the warehouse pause in force.' }
   ```

3. Revoke only the Delivery Dispatcher grants introduced by this rollout. GET the Workflow, all six voucher Server Scripts, both POS Client Scripts, permission rows, changed metadata and the relevant Users. Compare against the before-images. Check the delivery Webhook disabled, legacy insert Webhook still at baseline and the prior active Workflow restored if one was captured. Check that subsequent operational work uses the restored hooks. Stock Manager reconciles in-flight POS and actual vouchers before the warehouse resumes their processing. Preserve historical Completed and Cancelled and the audit left by the cutover. When rollback needs to restore prior blanks, use the captured original draft names and revisions and verify each intervening change before a separately reviewed correction. Before re-enabling notifications reconcile each active stage against its latest status-changing Version.

## Remaining acceptance and minimum pre-cutover tests

| Gap | Minimum test after separate approval |
| --- | --- |
| MX Stock Entry same-reference siblings and amendment were blocked by the unique `custom_reference_no` index on staging. KX has basic draft, submit and cancel coverage. | Reproduce the unique constraint on staging for the supported business flow. If amendments or siblings are operationally required, validate the agreed reference handling in an isolated copy with a legitimate amended MX/KX draft and two submitted siblings, then cancel one and verify Completed remains. Stock Manager and product owner record whether the current constraints are acceptable for cutover. |
| Tally was checked through a mocked Desk form. Released Flutter was not exercised in the ERP staging acceptance report. | In staging Desk use a marked Pending POS for Tally import and confirm an In Progress POS blocks re-import. Run build 2.60.0+158 on two staging users and one marked fixture through the full action flow, defaults, a dismissed sheet and a stale revision. Check filters, DN link, timeline beyond ten Versions, light/dark readability, list refresh and no duplicate action on double tap. Run the repo POS model, filters, provider, timeline, permission, dashboard, digest and realtime tests against the release commit. |
| n8n imports were inspected offline. Raw-body signing, runtime routing and failure paths have no connected acceptance evidence. | Import inactive staging copies. Change both `erpBase` constants, both Desk link origins, receiver path, HMAC and Telegram chat to approved staging-only values. Sign raw JSON containing quotes and non-ASCII bytes. Observe 403 for missing/invalid signatures, 400 for a signed malformed body and 200 for valid signed intake before extra ERP reads or Telegram. Exercise Dispatch, Return and Delivered, a DN submit and ordinary save, delayed verification after an unrelated edit, and replay the same successful event after an n8n restart within the one-hour dedupe window. Inject a transient ERP or Telegram failure and a 429 in the isolated copy. Verify bounded retries, supported `retry_after`, the safe error route and applicable Frappe Webhook Request Log. |
| Overdue calendar and suppression have no connected staging execution evidence. | Run the staging overdue copy against controlled POS Versions and a deterministic clock across a Friday break, Sunday, listed holiday and the 4- and 8-hour inclusive thresholds. Exercise expired calendar, stale POS or stage change between reads, repeated ticks, pruning and Return/redispatch with new Version IDs. Verify safe error visibility. |
| Telegram templates have yet to be posted to an approved test destination. | Send the three action and two overdue templates from the staging copies. Include Late, Rejected and Other, quoted and non-ASCII text, absent optional fields and different actor and Driver. Verify labels, HTML escaping, mobile layout, Dubai timestamp and Desk link with previews disabled. |

Product owner decisions before go-live are the named dispatcher grants, enrolment and review dispositions, smoke POS and real driver, maintenance and rollback authority, staging Telegram destination, production Updates audience, approved n8n ERP read identity, and acceptance of remaining Stock Entry limitations after testing. Configure legacy insert signing separately if the owner schedules a router change.
