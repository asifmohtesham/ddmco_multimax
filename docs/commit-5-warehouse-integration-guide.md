# Commit 5: Warehouse Field Integration Guide

This guide shows how to replace the Warehouse field's custom bottom sheet picker with the generic `DocTypePickerBottomSheet`.

## Changes Required

### 1. Controller: `work_order_form_controller.dart`

#### A. Replace `showWarehousePicker()` Method

Find the existing `showWarehousePicker()` method (around line 415) and replace it with:

```dart
// ── Warehouse picker (bottom sheet) ──────────────────────────────────────────────────────
void showWarehousePicker(TextEditingController ctrl) {
  if (!canEdit) return;

  showDocTypePickerBottomSheet(
    config: DocTypePickerConfig(
      doctype: 'Warehouse',
      title: 'Select Warehouse',
      columns: [
        DocTypePickerColumn.primary(
          fieldname: 'name',
          label: 'Warehouse',
        ),
      ],
      filters: {
        'is_group': 0,
      },
      allowRefresh: true,
    ),
    onSelect: (selected) {
      ctrl.text = selected['name'] as String;
      markDirty();
    },
  );
}
```

#### B. Remove obsolete warehouse fetching code

Remove the following from the controller:

1. **Remove warehouse state** (around line 35):
   ```dart
   final warehouses = <String>[].obs;  // DELETE THIS LINE
   ```

2. **Remove fetchWarehouses() method** (around line 260):
   ```dart
   // DELETE THIS ENTIRE METHOD
   Future<void> fetchWarehouses() async {
     // ... entire method body ...
   }
   ```

3. **Remove fetchWarehouses() call from onInit()** (around line 70):
   ```dart
   fetchWarehouses();  // DELETE THIS LINE
   ```

### 2. No Screen Changes Required

The screen (`work_order_form_screen.dart`) already calls `controller.showWarehousePicker()` correctly, so no changes are needed there.

## What This Does

1. **Replaces custom warehouse picker** with generic DocType picker
2. **Filters warehouse groups** - Only shows actual warehouses (is_group = 0)
3. **Single-column layout** - Warehouse name only
4. **Enables refresh button** - Allows manual data refresh
5. **Removes obsolete code** - Eliminates redundant warehouse fetching logic
6. **Cache-first loading** - Uses DocTypePickerProvider for efficient data loading

## Testing Checklist

- [ ] Warehouse picker opens when clicking WIP/FG Warehouse fields
- [ ] Displays only non-group warehouses (actual warehouses)
- [ ] Shows warehouse names in single-column layout
- [ ] Selecting a warehouse updates the field
- [ ] Refresh button works and reloads warehouse list
- [ ] Search functionality works
- [ ] Respects edit mode (read-only when submitted)
- [ ] Cache works (fast second load)

## Files Modified

- `lib/app/modules/work_order/form/work_order_form_controller.dart`
  - Replace showWarehousePicker() method
  - Remove warehouses observable
  - Remove fetchWarehouses() method
  - Remove fetchWarehouses() call from onInit()
