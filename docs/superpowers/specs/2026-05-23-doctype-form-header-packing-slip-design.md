# DocTypeFormHeader Parity: Packing Slip

## Problem

`PackingSlipFormScreen` passes an incomplete set of parameters to `DocTypeFormHeader`, omitting three that `DeliveryNoteFormScreen` provides. This means the Packing Slip header renders without the doctype label, status pill, or save-result feedback animation.

## Missing Parameters

| Parameter | Delivery Note value | Fix for Packing Slip |
|-----------|--------------------|-----------------------|
| `docType` | `'Delivery Note'` | `'Packing Slip'` |
| `statusLabel` | `note?.status` | `slip?.status` |
| `saveResult` | `saveResult` (observable) | add same observable to controller |

## Changes

### 1. `packing_slip_form_controller.dart`

Add `saveResult` state machine — identical to `DeliveryNoteFormController`:

- `var saveResult = SaveResult.idle.obs;`
- `Timer? _saveResultTimer;`
- `void _setSaveResult(SaveResult result)` — sets value and starts 2-second reset timer
- `onClose`: cancel `_saveResultTimer`
- `_createDocument`: call `_setSaveResult(SaveResult.success)` on 200, `_setSaveResult(SaveResult.error)` on failure
- `_updateDocument`: same
- `_handleSaveError`: call `_setSaveResult(SaveResult.error)` at entry (covers the catch block in `savePackingSlip`)

### 2. `packing_slip_form_screen.dart`

- Add `saveResult: saveResult` to the `Obx` locals: `final saveResult = controller.saveResult.value;`
- Add three parameters to `DocTypeFormHeader`:
  - `docType: 'Packing Slip'`
  - `statusLabel: slip?.status`
  - `saveResult: saveResult`

## Scope

Two files only. No new abstractions, no model changes, no routing changes.
