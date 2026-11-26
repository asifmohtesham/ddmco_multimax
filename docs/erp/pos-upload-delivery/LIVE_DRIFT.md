# POS Upload delivery configuration drift

Compared the live capture with the committed pre-rollout staging capture. Records were matched by DocType and name. Custom DocPerm rows were matched by parent, role, permission level and owner condition. The comparison includes script bodies, flags, permissions and other configuration fields. It excludes Frappe record metadata such as timestamps and generated child row IDs.

All eight scripts scheduled for replacement have identical bodies and configuration on live and in the staging before-images. Their `modified` values also match. The only existing targeted master, `Pending`, matches and will be kept. All 24 create targets were absent from both captures. There are no live-only changes to merge and no configuration drift blockers. [Live manifest](before/live/manifest.json) · [Staging manifest](before/staging/manifest.json)

| DocType | Record | Live and staging before rollout | Recommendation |
|---|---|---|---|
| Custom Field | `POS Upload-custom_return_reason` | Absent on both | Safe to create |
| Property Setter | `POS Upload-status-options` | Absent on both | Safe to create |
| Property Setter | `POS Upload-status-read_only` | Absent on both | Safe to create |
| Role | `Delivery Dispatcher` | Absent on both | Safe to create |
| Custom DocPerm | `Driver \| Delivery Dispatcher \| 0` | Absent on both | Safe to create |
| Custom DocPerm | `POS Upload \| Delivery Dispatcher \| 0` | Absent on both | Safe to create |
| Custom DocPerm | `POS Upload \| Delivery Dispatcher \| 1` | Absent on both | Safe to create |
| Custom DocPerm | `POS Upload \| Stock Manager \| 0` | Absent on both | Safe to create |
| Custom DocPerm | `POS Upload \| Stock Manager \| 1` | Absent on both | Safe to create |
| Workflow State | `Cancelled` | Absent on both | Safe to create |
| Workflow State | `Completed` | Absent on both | Safe to create |
| Workflow State | `Delivered` | Absent on both | Safe to create |
| Workflow State | `In Progress` | Absent on both | Safe to create |
| Workflow State | `Out for Delivery` | Absent on both | Safe to create |
| Workflow State | `Pending` | Identical on both | Safe to keep |
| Workflow State | `To Deliver` | Absent on both | Safe to create |
| Workflow Action Master | `Delivered` | Absent on both | Safe to create |
| Workflow Action Master | `Delivery Return` | Absent on both | Safe to create |
| Workflow Action Master | `Out for Delivery` | Absent on both | Safe to create |
| Server Script | `POS Upload Apply Delivery Action` | Absent on both | Safe to create |
| Workflow Transition Tasks | `POS Upload Delivery Action` | Absent on both | Safe to create |
| Server Script | `POS Upload Delivery Drivers` | Absent on both | Safe to create |
| Server Script | `POS Upload Guard Delivery Fields` | Absent on both | Safe to create |
| Server Script | `Delivery Note updates POS Upload In Progress` | Identical on both | Safe to replace |
| Server Script | `Delivery Note updates POS Upload Completed` | Identical on both | Safe to replace |
| Server Script | `Delivery Note updates POS Upload Cancelled` | Identical on both | Safe to replace |
| Server Script | `Stock Entry updates POS Upload In Progress` | Identical on both | Safe to replace |
| Server Script | `Stock Entry updates POS Upload Completed` | Identical on both | Safe to replace |
| Server Script | `Stock Entry updates POS Upload Cancelled` | Identical on both | Safe to replace |
| Client Script | `POS Upload` (form) | Identical on both | Safe to replace |
| Client Script | `POS Upload-List` (list) | Identical on both | Safe to replace |
| Workflow | `POS Upload Delivery` | Absent on both | Safe to create and activate |
| Webhook | `POS Upload Delivery` | Absent on both | Safe to create disabled |

The capture contains 23 records. The seven existing POS Upload Custom DocPerms, six POS Upload list-view Property Setters, and standard permissions for POS Upload and Driver match the staging configuration. Four untargeted list-view Property Setters have newer `modified` and different `modified_by` values on live. They are the `customer`, `date`, `total_amount` and `total_qty` setters. Their settings are identical and the apply leaves them in place. There were no other POS Upload Custom Fields or Workflows. The existing enabled after-insert Webhook `POS Upload` was captured with its opaque URL path redacted. Its visible configuration matches staging. The new delivery Webhook has a different name and event. [Live before-images](before/live/manifest.json)

The completed live dry run lists **24 creates, eight updates and one keep**. The updates are the six voucher hooks and two Desk Client Scripts. There are no deletions or unrelated replacements. During an approved apply, Frappe's Role Permission Manager can materialize copies of the eight standard Driver permission rows when the first Driver override is created. The before-image manifest carries those standard permissions for verification and rollback. [Full live dry run](before/live/dry-run.txt)
