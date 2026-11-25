# POS Upload delivery ERP runbook

The [workflow design](../../superpowers/specs/2026-11-25-pos-upload-delivery-workflow-design.md) defines the delivery transitions, voucher hooks, audit data and alerts. Each JSON file in `records/` describes one Frappe record. `_script_file` and `_script_include` load code from files relative to the record. `_depends` orders records with linked dependencies. `_if_missing` preserves an existing shared master.

## Staging apply

1. Use a staging API user with permission to manage the listed ERP records, including Script Manager access. Use the external key Markdown file with its standalone backticked `key:secret` line. Keep staging and live key paths distinct.
2. Use a voucher maintenance window for the apply. Capture the original configuration before any changes. Review the POS status inventory, open vouchers, blank statuses and existing status writers. Export the names and revisions of blank POS records to the rollout scratchpad before saving the Workflow. Frappe seeds blank statuses on draft POS records to Pending even when saving an inactive Workflow. On staging this seeded 97 pre-existing POS records. The native seed runs as a direct status update, outside the delivery audit and timers. [Frappe Workflow seeding](https://github.com/frappe/frappe/blob/v16.60.2/frappe/workflow/doctype/workflow/workflow.py#L37-L81)
3. Run the capture once and review its manifest and any redactions. Review the dry run before applying. Run it again after apply to verify the configured records are current.

   ```powershell
   $env:POS_DELIVERY_ERP_URL = 'https://erp-testing.multimax.cloud'
   $env:POS_DELIVERY_ERP_KEY_PATH = 'C:/Users/asifm/.claude/projects/C--Users-asifm-StudioProjects-ddmco-multimax/memory/erp-staging-key.md'
   $posDeliveryApply = 'docs/erp/pos-upload-delivery/apply.py'
   python $posDeliveryApply --capture
   python $posDeliveryApply --dry-run
   python $posDeliveryApply --apply
   python $posDeliveryApply --dry-run
   ```

   When reusing the committed staging capture, start at the dry run. The installer checks the ERP Server Script setting and stops on HTTP 401. Investigate a disabled setting or a rotated key before proceeding. Each write request commits separately. If an update fails, inspect the current configuration with `--dry-run` and rerun the corrected apply inside the maintenance window. The output identifies the records and changes. Keep long API responses in the scratchpad after redacting secrets.

4. Keep the new delivery Webhook disabled and both delivery n8n exports inactive. Keep native Workflow email alerts off. Assign Delivery Dispatcher to approved dispatchers through normal User role management. For a test account use `send_welcome_email=0`. The existing POS Upload after-insert Webhook on staging may point at production. Check its target before creating fixtures. To isolate `ZZTEST-` inserts, temporarily disable it if it points at production, record the change, then restore its captured enabled setting immediately after the last insert.

## Staging acceptance

Use `ZZTEST-` in test remarks or names where the DocType permits. Record the request, expected result, actual result and pass/fail in [STAGING_ACCEPTANCE.md](STAGING_ACCEPTANCE.md).

- Save and submit an eligible DN. Verify In Progress, then To Deliver with an explicit status-changing Version and summary comment. Check DN matching by exact `po_no`, submitted, outbound and quantity/customer/company validity. Test zero and two submitted outbound matches and submitted stock returns.
- Verify all three actions require an active Driver. Return additionally requires one of Late, Rejected or Other and moves to To Deliver. Dispatch again and mark Delivered by a different authorized user with a different driver. Check the Version and summary comment record both driver and recorder, and the reason clears on redispatch.
- Check cancellation before dispatch, during dispatch and after Delivered. Verify the expected reversion or review comment. Check a replacement DN requires Return and a new dispatch before Delivered. Verify ambiguity and conflict recovery.
- Reject unauthorized and raw status changes, stale revisions and forged action data. Test dispatcher-only, Stock Manager, dual-role and warehouse intake accounts. Exercise simultaneous actions and cancellation racing an action when concurrent staging clients are available.
- Verify the MX/KX draft, submit and cancel path, linked amendment and submitted siblings. Check the Pending-only Tally re-import gate and a historical Completed record.
- Verify the new webhook is disabled and restore the existing webhook if it was paused. Disable test users and cancel test vouchers when practical. Record fixture IDs and remaining test data.

The n8n imports are prepared under `n8n/`. Test signed payload intake, deduplication, calendar boundaries, first-alert timing and Telegram formatting in an isolated environment with a staging destination when available. Staging ERP acceptance can proceed with the new webhook disabled.

## Live cutover after separate approval

1. After ERP staging acceptance and separate live approval, capture fresh live before-images in a separate directory with `--capture --before-dir`. Reassess metadata drift, POS status counts, blank statuses, open vouchers, role grants and current writers. Export the blank-status inventory separately and record the cutover time. Confirm read access for the n8n ERP credential and confirm the notification destination. Review the Phase 1 app against the accepted staging deployment before cutover.
2. Pause voucher and delivery processing. Use Frappe Desk or the approved live deployment procedure to apply the reviewed ERP sources. Apply the field, status metadata, roles, permissions and masters first, and then the task and guard. Use Role Permission Manager to preserve effective permissions when adding the first override. Switch all six voucher hooks within the same window, activate the Workflow, apply the Desk scripts and create the disabled webhook. Verify the production configuration after each change. The current `apply.py` permits live capture and dry run using GET and restricts its apply and rollback modes to staging.
3. Start clocks for reconciled open records through the same locked To Deliver write with Version audit. Preserve historical Completed and Cancelled. Configure the delivery HMAC secret out of band and map n8n credentials by name. Coordinate legacy after-insert signing separately and verify that insert routing still works.
4. Smoke-test the delivery workflow during the maintenance window. Activate **POS Upload Delivery Events** before enabling the new ERP webhook for new revisions. Resume voucher and delivery processing after smoke checks. Watch the first real action and failures. Activate **POS Upload Delivery Overdue** once the first action events are verified.

## Rollback

1. Pause the new ERP Webhook and any active delivery event and overdue workflows in the rollback environment. Pause voucher and delivery processing. Export affected POS records, current vouchers and delivery attempt history for Stock Manager reconciliation.
2. On staging, run `python $posDeliveryApply --rollback` with the same staging site and before-images. It parks the delivery Workflow and added Server Scripts, restores the six voucher scripts and prior Desk records and reverts delivery permission changes. A disabled webhook, inactive configuration dependencies, expanded status options, Return Reason and audit history are retained. If Role Permission Manager seeded standard permission copies, rollback checks those rows before removing the override.
3. For an approved live rollback, perform the same configuration steps through Frappe Desk or the approved live deployment process using the live before-images. Restore prior custom permission rows before resuming work. If the rollout introduced a permission override where standard permissions were effective, review any later edits before restoring that baseline. Reactivate any previously active Workflow after restoring the prior configuration.
4. Review the inactive delivery Workflow, restored configuration and affected vouchers. Treat native blank-to-Pending seeding as a separate data change. If restoring prior blanks is necessary, reconcile from the captured blank-status inventory and account for intervening changes before editing any rows. Hold affected voucher processing for Stock Manager reconciliation and resume when clear. Reconcile stage Versions before re-enabling delivery notifications.
