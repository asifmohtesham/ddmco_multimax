# POS Upload delivery: live cutover log, 2026-11-26

The cutover ran on `erp.multimax.cloud` and on n8n at `automation.milanoleather.ae`. The operator was Claude, using the `asif@multimax.cloud` API identity (System Manager, Script Manager). The product owner approved an in-shift start instead of the planned off-shift window, and the warehouse was asked to hold voucher work. The playbook is [LIVE_CUTOVER.md](LIVE_CUTOVER.md). **Outcome: live.** No rollback was needed. The T0 rollback source is [before/live-20261126-105342](before/live-20261126-105342/).

## Decisions applied

- **Delivery Dispatcher:** granted to nobody at cutover. At 11:32 it was granted to the five Stock User-only accounts (see the timeline). Stock Managers act through their own role.
- **Enrolment:** the list was empty. None of the 10 open POS Uploads had a submitted outbound Delivery Note.
- **Smoke test:** ZZTEST fixtures on live, with a dedicated non-stock item, so no stock moved.
- **Telegram:** a one-time test of all five alert types went to the production Updates channel, on ZZTEST POS Uploads only.
- **Overdue workflow:** imported, tested through a temporary copy, then activated at 11:06 once the product owner approved it.

## Timeline (Asia/Dubai)

| Time | Step | Result |
| --- | --- | --- |
| 09:01–09:05 | n8n prep | Backup `~/n8n-backups/pos-delivery-cutover-20261126-050113` (30 workflows, 19 credentials, encrypted). Credentials created: **Multimax ERP GET** and **ERPNext POS Upload Delivery HMAC**. Events and Overdue imported inactive, with the operator Error Workflow selected. Receiver checks passed: unsigned 403, bad signature 403, signed malformed body 400. The Code node signature compare no longer uses `require('crypto')` (commit 3ef40bb1). |
| 10:53 | Activity check | Two DN, two SE and four POS writes in the previous hour. The warehouse was asked to hold. |
| 10:53 | T0 capture and dry-run | 23 before-images, identical to the prep images (only manifest timestamps differ). 32 planned changes, 0 deletes. |
| 10:54 | Pre-write check | No DN, SE or POS writes in the previous 3 minutes. |
| 10:54:51–10:55:49 | Configuration phase | 30 changes applied. The phase dry-run then shows 0 planned changes. |
| 10:55:52 | Workflow phase | `POS Upload Delivery` is active: `send_email_alert=0`, field `status`, six transitions (Stock Manager and Delivery Dispatcher). It is the only active POS Upload workflow. All 10 open POS kept their status, and there were 0 blanks. |
| 10:56 | Enrolment | `[]`. `enrol.py --dry-run`: 0 eligible, 0 to review. |
| 10:56 | Webhook phase | `POS Upload Delivery` created on `on_update`, disabled, security on. The legacy `POS Upload` after-insert Webhook is unchanged. |
| 10:58–10:59 | Fixtures | Customer `ZZTEST Delivery Customer`. Non-stock item `1005003` ("ZZTEST delivery workflow test", group Services); the item code comes from the naming series. POS `ML-ZZTEST-261126-A/B/C`, created with the legacy insert Webhook paused for about 3 seconds and then restored. |
| 10:59 | Smoke A (alerts off) | DN save moved A to In Progress. DN submit moved it to To Deliver. Out for Delivery (MR.ZAFAR), then Return Late (reason set), then Out for Delivery (TANVEER, reason cleared), then Delivered. Each step wrote one Version with action, driver, recorder, reason, DN and comment ID. The app contract checks passed: `get_transitions` offered Out for Delivery in To Deliver and nothing after Delivered, and the driver API listed HAFIZ FAYYAZ, MR.ZAFAR and TANVEER with no default. |
| 10:59 | Stage B and C | B moved to To Deliver. C moved to To Deliver, then Out for Delivery (HAFIZ FAYYAZ). |
| 10:59:55–10:59:58 | Alerts on | HMAC secret copied from the n8n credential to the ERP Webhook (never printed). **Events** activated, then the ERP Webhook enabled. |
| 11:00 | TEST alert 1 | B: Out for Delivery. n8n recorded the send. |
| 11:00 | TEST alert 2 | B: Delivery Return, Rejected. n8n recorded the send. |
| 11:01 | TEST alerts 3 and 4 | A temporary Overdue copy ran once (execution 73145), with its clock pinned to 2026-11-28 11:00 and scope limited to ZZTEST rows. It sent "Overdue for dispatch" for B (To Deliver, 20 h 14 min against a 4 h threshold) as Telegram message 5680, and "Overdue for delivery" for C (Out for Delivery, 20 h 15 min against 8 h) as message 5681. The copy was then deleted. |
| 11:02 | TEST alert 5 | C: Delivered. n8n recorded the send. No n8n error executions. |
| 11:03:15–11:03:19 | Finish B | The delivery Webhook was disabled for 4 seconds while B went Out for Delivery, then Delivered, and was then re-enabled. No real POS changed in that window. |
| 11:03 | Cleanup | DNs MAT-DN-2026-01213, 01214 and 01215 cancelled. All three POS stay Delivered, each with a "Delivery Note was cancelled" review comment. No Sales Orders were created. The test customer and item are disabled. |
| 11:06 | Overdue on | The product owner approved it, and **POS Upload Delivery Overdue** was activated. First scheduled tick: 12:00. |
| 11:10 | Test records removed | The product owner asked for cleanup. Deleted: DNs MAT-DN-2026-01213, 01214 and 01215 (cancelled), the auto-created Item Price, POS `ML-ZZTEST-261126-A/B/C`, item `1005003` and `ZZTEST Delivery Customer`. No comments or Versions remain. Frappe keeps Deleted Document copies. |
| 11:15 | TEST posts removed | The product owner asked for removal, and MilanoLeatherBot deleted all five TEST posts from Updates (messages 5678, 5679, 5680, 5681, 5682). The product owner confirmed which messages they were. |
| 11:32 | Delivery Dispatcher granted | The product owner decided that Stock Manager and Stock User holders record deliveries. Stock Managers already qualify. Delivery Dispatcher was added to the five enabled users who have Stock User without Stock Manager: abdulmunayeem, jaffar, maqbool, mujahid and tajammulahmed (each `@multimax.cloud`). Each grant added one role row and removed none. The `n8n` service account was excluded. Role permissions verified: POS Upload read/write at permlevels 0 and 1, Driver select only, and the three delivery transitions. The first real POS, KA-2026-03764, reached To Deliver after the cutover. |
| 11:43 | Revert to Pending added | The product owner asked for this so a POS can be edited (re-imported) again, which is only allowed in Pending. The new Workflow transition In Progress → **Revert to Pending** → Pending is allowed for Stock Manager only, through the same task script, with no driver, reason or alert. Its Version and comment read "POS delivery · Revert to Pending · recorded by …", and it clears Return Reason. Staging checks passed: a Stock Manager sees and runs it; a Delivery Dispatcher-only user sees no action and a forced call is refused; the POS was edited in Pending; re-saving the draft DN moved it back to In Progress; a stale revision was refused. On live: 3 changes (Action Master, task script, Workflow). Rollback copies are in [before/live-20261126-revert](before/live-20261126-revert/). A Stock Manager sees the action on a real In Progress POS (not executed). It is Desk-only for now: app 2.60 shows only the three delivery actions. |

## Final state

- **ERP:** Workflow active. The six voucher scripts, the POS guard, task, driver API and both Desk scripts match the repository sources. A full `apply.py --dry-run` reports a single difference: `Webhook / POS Upload Delivery`, which is enabled with its secret set, while the source keeps it disabled.
- **Webhooks:** `POS Upload Delivery` is enabled (`on_update`, signed). Legacy `POS Upload` is enabled (`after_insert`) and unchanged.
- **n8n:** **POS Upload Delivery Events** (`SAGB1lowDclIJQqz`) is active. **POS Upload Delivery Overdue** (`t7gxOq9mWzr2Skub`) is active (since 11:06).
- **Fixtures:** all deleted at 11:10. Frappe's Deleted Document copies are the only record.

## Follow-ups

1. Brief the Stock Managers to record Out for Delivery and Delivered in the app. Overdue alerts fire after 4 working hours in To Deliver and 8 in Out for Delivery.
2. **Multimax ERP GET** reuses the `n8n@multimax.cloud` ERP key, which has broad roles. Replace it with a read-only identity.
3. The HMAC secret also lives in `~/n8n/run/pud-hmac` (mode 0600) on the n8n server. Delete it once a vault copy exists.
4. Rotate the live write key used for this cutover.
5. Watch the first real dispatch, Return and Delivered alerts in Updates.
