# Server-side ERP material lives in `erp-scripts`

Desk-only material (Server Scripts, Client Scripts, Script Report source, workflow
apply tools, runbooks, before-snapshots) is kept in the private repository
[`asifmohtesham/erp-scripts`](https://github.com/asifmohtesham/erp-scripts), not
here. This repository is public and follows the app's releases; that one does not.

What stays here: anything the app depends on (a report's filters, columns and
row contract, the screens that use it, v15/v16 notes).

| Was here until 2026-11-28 | Now in `erp-scripts` |
|---|---|
| `docs/erp/pos-upload-delivery/` | `pos-upload-delivery/` |
| `docs/erp/mobile-push/` | `mobile-push/` |
| `docs/erp/batch-wise-balance-history-custom/`, `docs/batch_wise_balance_history_custom_report.md` | `reports/batch-wise-balance-history-custom/` |
| `docs/item_image_virtual_field.md` | `item-image-virtual-field/README.md` |
| Python and JavaScript inside `docs/pos_delivery_note_item_rate_report.md` | `reports/pos-and-delivery-note-item-rate/` |
| Python and JavaScript inside `docs/suppliers_by_item_report.md` | `reports/suppliers-by-item/` |

When you change something on the ERP site, put its source and notes there. If the
change alters what the app receives, update the matching doc here as well.
