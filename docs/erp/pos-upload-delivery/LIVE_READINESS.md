# POS Upload delivery live data readiness

Read-only snapshot of **erp.multimax.cloud** at **23:49–23:50 GST on 25 November 2026**. The Frappe Server Script setting endpoint returned `message: true` for `server_script_enabled`.

## POS Upload status

| Status | Count |
| --- | ---: |
| Blank | 0 |
| Pending | 2 |
| In Progress | 9 |
| Completed | 2,147 |
| Cancelled | 10 |
| Other | 0 |
| **Total** | **2,168** |

Workflow save would seed **0** draft blanks to Pending at this snapshot. Workflow save can seed blanks even with the Workflow inactive. Capture blank record names and revisions again at the start of the window. [ERP runbook](RUNBOOK.md)

## Open POS and submitted outbound Delivery Notes

**0 enrolment candidates and 11 open records for review.** All 11 have zero exact-PO submitted outbound Delivery Notes. Five have one draft outbound Delivery Note. Six have no exact-PO Delivery Note. No open POS has multiple submitted outbound DNs, a sole submitted DN with a company/customer/quantity mismatch, or a submitted stock return against a linked submitted outbound DN.

The scan paged all POS Uploads and checked Pending, In Progress and blank statuses for exact `Delivery Note.po_no = POS Upload.name`, `docstatus = 1` and `is_return = 0`. It counts those matches before testing Multimax company, matching customer and positive `total_qty`. The DN-submit hook also requires an ML- or KA- POS reference and excludes an outbound DN with a submitted stock return. The enrolment check uses the draft POS docstatus required by the Workflow. A second set of exact-PO GETs confirmed the 11 open records. When a later candidate has a submit Version, use its creation time for submission. If ERP lacks a submit Version, report the voucher posting time separately and verify the actual submission time with the warehouse. [Voucher script](scripts/voucher.py) · [Workflow design](../../superpowers/specs/2026-11-25-pos-upload-delivery-workflow-design.md)

| POS Upload | Status | Exact-PO Delivery Note check | Cutover handling |
| --- | --- | --- | --- |
| KA-2026-03764 | Pending | Zero | Keep current status and review in the DN preparation queue. |
| KA-2026-03835 | In Progress | One draft outbound, zero submitted | Keep In Progress and process the draft through the usual submission path. |
| KA-2026-03836 | In Progress | One draft outbound, zero submitted | Keep In Progress and process the draft through the usual submission path. |
| KX-2026-0723 | In Progress | Zero | Keep current status and review in the Material Issue queue. |
| KX-2026-0726 | In Progress | Zero | Keep current status and review in the Material Issue queue. |
| KX-2026-0730 | In Progress | Zero | Keep current status and review in the Material Issue queue. |
| KX-2026-0737 | Pending | Zero | Keep current status and review in the Material Issue queue. |
| KX-2026-0743 | In Progress | Zero | Keep current status and review in the Material Issue queue. |
| ML-2026-04905 | In Progress | One draft outbound, zero submitted | Keep In Progress and process the draft through the usual submission path. |
| ML-2026-04906 | In Progress | One draft outbound, zero submitted | Keep In Progress and process the draft through the usual submission path. |
| ML-2026-04909 | In Progress | One draft outbound, zero submitted | Keep In Progress and process the draft through the usual submission path. |

## Active Drivers

All **3** active Drivers have a full name. The delivery picker script would return all three choices to a Delivery Dispatcher, Stock Manager or Administrator who can read the POS. Direct User and active Employee mappings determine the unique default, with the latest active dispatch Driver as fallback for Delivery Return or Delivered. [Driver picker script](scripts/driver-defaults.py)

| Driver | Full name |
| --- | --- |
| HR-DRI-2026-00002 | HAFIZ FAYYAZ |
| HR-DRI-2026-00001 | MR.ZAFAR |
| HR-DRI-2026-00003 | TANVEER |

## Delivery Dispatcher candidates

**16 of 30** enabled System Users currently hold at least one of Stock Manager, Stock User, Delivery User or Delivery Manager. The table shows assigned role rows from each User record, including roles outside the filter. The product owner chooses the User accounts that receive Delivery Dispatcher. Stock Manager already qualifies for the delivery actions under the staged Workflow. The n8n account appears because it meets the inventory filter. [Workflow record](records/14-workflow.json)

| User name | Full name | Current assigned roles |
| --- | --- | --- |
| abdulaziz@multimax.cloud | Abdul Aziz | **Delivery Manager**, **Delivery User**, Employee, Item Manager, Purchase Manager, Purchase Master Manager, Purchase User, Sales Manager, Sales Master Manager, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom, System User |
| abdulmunayeem@multimax.cloud | Abdul Munayeem Durga | Employee, **Stock User**, Stock User - Custom |
| adnan@multimax.cloud | Adnan Ashraf Kolsawala | **Delivery Manager**, **Delivery User**, Employee, HR Manager, HR User, Item Manager, Manufacturing User, Prepared Report User, Purchase Manager, Purchase Master Manager, Purchase User, Sales Master Manager, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom, System User, Workspace Manager |
| arif@multimax.cloud | Arif Khan | **Delivery Manager**, **Delivery User**, Employee, Item Manager, Manufacturing User, Purchase User, Sales Manager, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom |
| asif@multimax.cloud | Muhammad Asif Mohtesham | Academics User, Accounts Manager, Accounts User, Analytics, Auditor, Blogger, Dashboard Manager, **Delivery Manager**, **Delivery User**, Employee, Fleet Manager, Fulfillment User, HR Manager, HR User, Inbox User, Item Manager, Knowledge Base Contributor, Knowledge Base Editor, Maintenance Manager, Maintenance User, Manufacturing Manager, Manufacturing User, Newsletter Manager, Prepared Report User, Projects Manager, Projects User, Purchase Manager, Purchase Master Manager, Purchase User, Quality Manager, Report Manager, Sales Manager, Sales Master Manager, Sales User, Script Manager, **Stock Manager**, **Stock User**, Support Team, System Manager, Translator, Website Manager, Workspace Manager |
| asim@multimax.cloud | Asim Usman Sukri | **Delivery Manager**, **Delivery User**, Employee, HR User, Item Manager, Manufacturing Manager, Manufacturing User, Purchase Manager, Purchase Master Manager, Purchase User, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom, Supplier, System User |
| asrar@multimax.cloud | Asrar Akrami | **Delivery Manager**, **Delivery User**, Employee, Item Manager, Manufacturing User, Purchase User, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom, System User |
| jaffar@multimax.cloud | Jaffer Potey | Employee, Sales Manager, Sales User, **Stock User**, Stock User - Custom, System User |
| jawwad@multimax.cloud | Jawwad Bilgi | **Delivery Manager**, **Delivery User**, Employee, Manufacturing User, Purchase User, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom, System User |
| maqbool@multimax.cloud | Maqbool Barmawer | **Delivery User**, Employee, Sales User, **Stock User**, Stock User - Custom, System User |
| mujahid@multimax.cloud | Mujahid | **Delivery User**, Employee, Purchase User, Sales User, **Stock User**, Stock User - Custom, System User |
| n8n@multimax.cloud | n8n | Academics User, Accounts Manager, Accounts User, Analytics, Auditor, Blogger, Customer, Dashboard Manager, **Delivery Manager**, **Delivery User**, Drive Admin, Expense Approver, Fleet Manager, Fulfillment User, HR Manager, HR User, Inbox User, Insights User, Interviewer, Item Manager, Knowledge Base Contributor, Knowledge Base Editor, Leave Approver, Maintenance Manager, Maintenance User, Manufacturing Manager, Manufacturing User, Marketing User, Newsletter Manager, Prepared Report User, Projects Manager, Projects User, Purchase Manager, Purchase Master Manager, Purchase User, Quality Manager, Raven Admin, Raven User, Report Manager, Sales Manager, Sales Master Manager, Sales User, Script Manager, **Stock Manager**, **Stock User**, Stock User - Custom, Supplier, Support Team, System Manager, System User, Translator, Website Manager, Workspace Manager |
| sajid@multimax.cloud | Mohammed Sajid Damda | **Delivery Manager**, **Delivery User**, Employee, Item Manager, Manufacturing User, Purchase Manager, Purchase Master Manager, Purchase User, Sales Manager, Sales Master Manager, Sales User, **Stock Manager**, **Stock User**, Supplier, System Manager, System User |
| saqib@multimax.cloud | Saqib Rahman | **Delivery Manager**, **Delivery User**, Employee, Purchase User, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom, System User |
| tajammulahmed@multimax.cloud | Tajammul Ahmed | Employee, Item Manager, **Stock User** |
| tanveer@multimax.cloud | Tanveer Shaikh | **Delivery Manager**, **Delivery User**, Employee, HR User, Item Manager, Purchase User, Sales User, **Stock Manager**, **Stock User**, Stock User - Custom, System User |

## Refresh at T-1 and during the voucher pause

From this checkout on the cutover workstation, run the GET-only preparation scanner. It reads the external live key file used during preparation and exits on HTTP 401. Use a fresh scratch directory for each scan.

```powershell
$posReadinessTemp = Join-Path $env:LOCALAPPDATA 'Temp\claude\cut'
$posReadinessDir = Join-Path $posReadinessTemp ('readiness-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$posReadinessKey = 'C:/Users/asifm/.claude/projects/C--Users-asifm-StudioProjects-ddmco-multimax/memory/erp-api-debug-key.md'
python -B docs/erp/pos-upload-delivery/readiness_live.py --key-path $posReadinessKey --output-dir $posReadinessDir
if ($LASTEXITCODE) { throw 'Live readiness scan stopped.' }
```

In the scratch directory, `readiness-data.json` holds POS totals, candidate and review lists, exact-PO draft DN details for smoke selection, the driver roster and dispatcher candidates. `readiness-blanks.json` holds blank-status names, docstatus and revisions. `readiness-history.json` holds the same fields for Completed and Cancelled records. Keep the final inventory from the confirmed voucher pause for comparison after Workflow save. Compare the two snapshots and obtain Stock Manager confirmation of any new candidate before preparing the enrolment input.
