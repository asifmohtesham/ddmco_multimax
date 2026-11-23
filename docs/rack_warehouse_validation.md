# Rack and row warehouse validation

Multimax checks that a selected Rack belongs to the exact Warehouse on that item row, on the same side of the movement. Rows with matching pairs can use different warehouses in one document. A correction in the item sheet applies to that row.

## The rule

- Use the Warehouse linked on the Rack record when it is an active leaf in the document company. A rack label, shelf or parent Warehouse cannot override that link.
- Look up the exact rack label first. After a definitive missing record, retry without a trailing ` - <company abbreviation>` for that company. Save the canonical Rack name returned by ERP.
- An existing Rack with a blank link can use the unique longest active-leaf Warehouse prefix for the company, followed by a nonblank slot. A populated invalid link requires a correction to the Rack master.
- A lookup failure, missing rack, untrustworthy mapping or mismatch blocks a new or changed pair. A blank optional rack leaves warehouse warnings and the existing stock rules in effect.
- A saved or explicitly selected Warehouse stays pinned. A fresh physical scan or rack-picker selection can initialize an unpinned Warehouse. Typed racks check the current choice or default when known. Autofill checks racks in the current Warehouse.

## Where it applies

| Document or purpose | Row pair and existing requirements |
|---|---|
| Stock Entry · Material Issue | Source Rack and Source Warehouse. A valid Source Rack with positive balance is required. POS Upload and Material Request issue use the same checks. |
| Stock Entry · Material Receipt | Target Rack and Target Warehouse. Target Rack is optional. |
| Stock Entry · Material Transfer | Source and target are checked independently. The exact standard type requires the Target Rack as well as the Source Rack. |
| Stock Entry · Material Transfer for Manufacture | Source Rack is required. The target is the actual WIP Warehouse on the row, with an optional Target Rack. |
| Stock Entry · Manufacture or Repack | Check the source on consumption rows and the target on finished and secondary output rows using the ERP row role. |
| Stock Entry · Other purposes | Use the movement sides supported by the purpose and present on the row. A rack on a side without a movement must be cleared. |
| Delivery Note · Manual, POS Upload and Sales Order | Source Rack and row Warehouse. A persisted or explicit row choice comes first, then the Sales Order line Warehouse and the document default. Source Rack is required. |
| Delivery Note · Internal transfer | Check any populated Target Rack against the Target Warehouse and retain both fields in the payload. |

## What the user sees

The item sheet displays the Warehouse used on the row. During a lookup it shows “Checking rack warehouse…”. If the rack belongs to a different Warehouse, the field shows both warehouses. For example, “Rack KA-WH-WIP1-1A belongs to WH-WIP1 - KA. This row’s source warehouse is WH-DXB1 - KA.” Choose another rack or use **Use rack warehouse** where the row Warehouse can be changed. A transient error offers **Retry**. A missing or unmapped rack has its own field message. A document guard adds the item row number to the message.

For a matched pair with a different same-side header default, other row Warehouses or Sales Order line Warehouse, a single confirmation shows those differences. **Review row** returns to the sheet. **Keep warehouse** accepts the displayed row Warehouse. The confirmation is remembered for equivalent Warehouse context during the edit session. A change in that context can prompt again. A blank header allows the other effective rows to become the peer baseline. Changing a header retains existing row Warehouses and summarizes the difference. Drafts opened with a blank header and more than one same-side Warehouse show the mixed Warehouse summary.

## Edge cases

- An unchanged saved mismatch can remain on an unrelated draft edit or a quantity reduction. A changed item, batch, direction, warehouse, rack, quantity increase, merge or copied row requires repair. Stock Entry Submit requires a verified pair. Removing the row is allowed.
- Work Order header changes keep existing row Warehouses and their racks together. Manufacture prefill considers a prior transfer’s Target Rack for the WIP consumption row and can leave an optional rack blank when the mapping is uncertain.
- A change of effective Warehouse rechecks balance and batch age. The [oldest-stock rule](batch_age_validation.md) still uses its separate warehouse scope. Both checks must allow the row.
- Group and disabled Warehouses cannot resolve a rack. A different leaf under the same parent is still a mismatch. Goods In Transit is a rackless leaf on the audited sites.
- The app enforces the rule when editing, saving or submitting through its supported flows. Direct Desk and API clients continue to use the existing ERP checks.

## Code map

| File or area | Role |
|---|---|
| `lib/app/shared/item_sheet/rack_warehouse_rule.dart` | Pure canonical mapping, mismatch messages, divergence and saved-row checks. |
| `lib/app/shared/item_sheet/rack_warehouse_resolver.dart` | Authenticated Rack and Warehouse metadata lookup with a two-minute cache scoped to the server and login. |
| `lib/app/shared/item_sheet/widgets/rack_warehouse_controls.dart` | Active Warehouse picker, rack correction actions and divergence confirmation. |
| Stock Entry item and document controllers, provider and model | ERP movement-side classification, per-side UI, draft and Submit gates, Work Order prefill and warehouse fields on both sides of a transfer. |
| Delivery Note item and document controllers and model | Effective outbound Warehouse used by balances, batch age, row identity and JSON, plus round-tripping internal targets. |

## Server calls

| Need | Standard call |
|---|---|
| Rack name and authoritative link | `GET /api/resource/Rack/{name}`. A missing record and a failed request have separate outcomes. |
| Scoped rack picker | `GET /api/resource/Rack` filtered by Warehouse. |
| Active leaf Warehouse and rare name fallback | `GET /api/resource/Warehouse/{name}` and `GET /api/resource/Warehouse`. The fallback can read the Company abbreviation from `GET /api/resource/Company/{name}`. |
| Stock Entry purpose | `GET /api/resource/Stock Entry Type` reads purpose along with the type name. |
| Balances and age | Existing Stock Balance and Batch-Wise Balance History reports and standard Batch and document reads. |

## Permissions

The floor account needs read access to Rack and Warehouse alongside the existing stock and batch-age accesses. The rare blank-link lookup also needs Company read. On the audited sites the Rack permission includes Sales User, Stock User, Stock User - Custom, Stock Manager and System Manager. The existing Before Submit scripts on ERP check required rack presence for Delivery Note and exact-type Material Transfer. This change uses standard resource calls and applies the warehouse rule in the app.

## Live data, 23 November 2026

The Phase 1 audit found **464 racks on each site**, all with valid stored Warehouse links. All 464 also matched a unique longest active Warehouse prefix. There were zero blank links, dangling links, linked groups or disabled Warehouses. There were 463 exact company/warehouse/shelf label matches. `KA-WH-ECOM-102` has shelf `201` and its warehouse link is `WH-ECOM - KA`.

Production from 26 August through 23 November, excluding cancelled documents, had **10 mismatches among 8,391 populated Stock Entry rack sides** across nine submitted documents. One was a Material Issue source, three were Material Transfer sources and six were Material Transfer targets. Delivery Note had **0 mismatches among 5,724 populated rack sides**. There were no observed internal DN target racks. Of five draft and 2,083 submitted Stock Entries, one draft and eight submitted documents differed from a header default or contained mixed same-side Warehouses. Both mixed documents had a blank source header. Of three draft and 328 submitted Delivery Notes, none had header or peer differences.

The incident was `MAT-STE-2026-08492-1`, row 1. The `WH-WIP1 - KA` header and `KA-WH-WIP1-1A` rack remained when the amendment row Warehouse changed to `WH-DXB1 - KA`. A testing-server refresh confirmed this kind of mismatch can still have 360 Nos in the stock ledger. The matched WIP1 and DXB1 fixture pairs had 120 and 1,422 Nos respectively, with one positive batch (`20030506-4BC87Z`) in both batch-age scopes and no draft rows for item `2003050`.

## Tested on the Pixel 7

### Owner session

23 November 2026, KA-IT-SYS6. `Pixel_7` emulator on Android 17 (API 37), Flutter 3.50.0, x64 debug build with the temporary package suffix `.smoke`, against `https://erp-testing.multimax.cloud`. The device and local APK checksums matched. The existing `com.ddmco.multimax` install remained installed. The emulator ran in the user’s RDP session with `swiftshader_indirect`. The debug app used software rendering after emulator responsiveness issues. Scans were injected through the app’s DataWedge broadcast receiver via adb.

The smoke test used an existing testing session for Asif. Relevant assigned roles included Stock User, Stock Manager, Sales User, Sales Manager, Delivery User, Delivery Manager, Item Manager and System Manager. Rack and Warehouse resource GETs succeeded. Floor-only permissions, the blank-link Company fallback and a live ERPNext v15 site were outside this run.

| Case | Result | Evidence |
|---|---|---|
| Material Issue mismatch | Passed. Under a WIP1 header, pinned the row to DXB1 and scanned the WIP1 rack. The exact mismatch appeared, Add was disabled, the form still showed Not Saved and the draft was only created after entering the matching pair. | `01-stock-entry-rack-refusal.png` |
| Typed suffix alias | Passed. Entered `KA-WH-WIP1-1A - KA` on the reopened DXB1 row at quantity 1. The field showed canonical `KA-WH-WIP1-1A`, the mismatch and a disabled Update. | `01a-stock-entry-typed-alias.png` |
| Material Issue header divergence | Passed. DXB1 / `KA-WH-DXB1-125B` prompted confirmation. Review retained the sheet. Keep saved `MAT-STE-2026-08338`, and reopening and an independent testing read confirmed WIP1 header, DXB1 row/rack and quantity 1. | `02-stock-entry-warehouse-warning.png`, `02a-review-row.png`, `02b-reopened-pair.png` |
| Fresh unpinned rack scan | Passed. Under a DXB1 default, scanned the item, then the WIP1 rack and then the batch. WIP1 initialized the row and scoped its balance to 120. The dialog combined the DXB1 header and peer differences. Keep saved the WIP1 pair as a second row. | `03-fresh-rack-initialized.png`, `03a-fresh-rack-header-peer-warning.png` |
| Batch-first rapid rack replacement | Passed. Sent WIP1 and then DXB1 rack scans in rapid succession after validating the batch. The sheet finished with the final DXB1 pair and the DXB1 batch and rack balances. Discarded the unsaved form. | `03b-batch-first-rapid-rack-replacement.png` |
| Header change and mixed rows | Passed. Changing the source default retained the existing row. The test ERP normalized the persisted header to blank after saving mixed source rows. Reopening showed both original pairs and the mixed-source summary. | `04-blank-header-mixed-rows.png` |
| Manual Delivery Note | Passed. Opened disposable draft `MAT-DN-2026-01180` created on testing with the fixture and pinned DXB1 Warehouse. The matching rack enabled Update. Scanning the WIP1 rack showed the exact mismatch and disabled Update. | `05-dn-valid-rack.png`, `05a-dn-rack-refusal.png` |
| Batch-age refusal | Passed. In the Delivery Note sheet, `10028902-4CDQ9W` opened “Older stock must ship first,” listing `10028902-7CY` and `10028902-46FTRR`. “Scan older batch” cleared the field. | `06-dn-batch-age-refusal.png` |
| Material Transfer | Passed. With a DXB1 source pair and a pinned DXB3 target, the WIP1 target rack was refused at quantity 1. Use rack warehouse corrected the target to WIP1 and Keep saved `MAT-STE-2026-08339`. An independent testing read confirmed both row warehouses and racks, with the target header still DXB3. | `07-transfer-target-refusal.png`, `07a-transfer-target-warning.png`, `07b-transfer-persisted.png` |

The Material Issue scan refusal, confirmation and rack-first initialization ran on the initial integrated APK. The final APK includes live mixed-summary refresh after ERP normalizes a header. The other checks ran on that final APK. The smoke screenshots are in the task’s `shots` folder.

Created test drafts `MAT-STE-2026-08338`, `MAT-STE-2026-08339` and `MAT-DN-2026-01180` on `erp-testing.multimax.cloud`. All three were deleted and a follow-up GET returned 404 for each. All three were drafts throughout the test. The emulator remained running.

Device coverage excluded physical HID or Zebra hardware, SO/POS Delivery Note routes, internal Delivery Note transfers, Work Order/Manufacture/Repack prefill, or legacy Stock Entry Submit. The rapid replacement check used naturally timed responses.

### Floor session

23 November 2026 on the same Pixel 7 AVD, Phase 2 APK and testing site. Scans used the DataWedge broadcast receiver via adb. Created and left enabled **Floor Test** (`floor.test@multimax.cloud`). Its four assigned roles were Sales User, Delivery User, Stock User and Stock User - Custom. Copied the Company and Employee User Permissions from an active floor user who created both Stock Entries and Delivery Notes in the previous 60 days. Standard ERP account provisioning generated a linked Contact, Notification Settings and a self-share for Floor Test.

The floor account's REST login returned HTTP 200. All requested GETs also returned HTTP 200.

| GET | Floor result |
|---|---|
| `Rack/KA-WH-WIP1-1A` and Rack list filtered by `WH-WIP1 - KA` | 200 each. The detail linked to WIP1 and the list returned its rack. |
| `Warehouse/WH-DXB1 - KA` and Warehouse lists | 200 each. The general list, both document header pickers and the row picker each returned eight warehouses. |
| `Stock Entry Type` with `name` and `purpose` | 200. Thirteen types returned, including Material Issue with its purpose. |
| Stock Balance and Batch-Wise Balance History via `frappe.desk.query_report.run` | 200 each for the item-sheet and batch-age requests. Results returned for item `2003050` in DXB1. |

| Case | Floor result | Evidence |
|---|---|---|
| 1. Material Issue mismatch | Passed. WIP1 default, pinned DXB1 row and WIP1 rack produced the mismatch. Add could not save the row. A floor-session GET confirmed the user had created no draft. | `floor-01-stock-entry-rack-refusal.png` |
| 2. Matched pair under a different default | Passed. Warehouse differs showed DXB1 vs WIP1. Keep warehouse saved `MAT-STE-2026-08340`. Reopen and REST confirmed the DXB1 row and rack under the WIP1 default at quantity 1. | `floor-02-stock-entry-warehouse-warning.png`, `floor-02b-reopened-pair.png` |
| 3. Fresh rack initialization | Passed. With DXB1 as the default, scanning the WIP1 rack after the item initialized the unpinned row to WIP1. The rack and subsequently scanned batch both showed 120 available. | `floor-03-fresh-rack-initialized.png` |
| 4. Manual Delivery Note | Passed. The DXB1 rack validated at quantity 1 with rack balance 1,422. The WIP1 rack was refused on the pinned DXB1 row. REST confirmed the original matched pair was still in the draft. | `floor-04-dn-valid-rack.png`, `floor-04a-dn-rack-refusal.png` |
| 5. Batch age | Passed. The younger batch `10028902-4CDQ9W` triggered “Older stock must ship first” for `10028902-7CY` and `10028902-46FTRR`. Scan older batch cleared the batch field. | `floor-05-dn-batch-age-refusal.png` |
| 6. Material Transfer target | Passed. At quantity 1 with a valid DXB1 source pair, the WIP1 target rack was refused against the pinned DXB3 target. No transfer draft was created. | `floor-06-transfer-target-refusal.png` |
| 7. Sales Order scan-to-pick | Skipped. Testing had zero Sales Orders. This app path needs a submitted order, which would require a change outside the draft-only test scope. | |
| 8. Legacy Material Issue mismatch | Passed. Owner-created draft `MAT-STE-2026-08339` showed a saved-pair warning. Floor Test changed the source default to DXB3 and saved. REST confirmed the DXB1 row and WIP1 rack persisted. The app showed a row-specific mismatch on Submit, and REST confirmed `docstatus=0`. Successful submission after repair was outside the draft-only scope. | `floor-08-legacy-warning.png`, `floor-08a-legacy-edit-saved.png` |

The three drafts created and deleted on `erp-testing.multimax.cloud` were `MAT-STE-2026-08339`, `MAT-STE-2026-08340` and `MAT-DN-2026-01180`. Follow-up GETs returned 404 for all three. The Pixel 7 app was signed out after the run.
