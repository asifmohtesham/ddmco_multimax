# Commit 4: BOM Field Integration Guide

This guide shows how to replace the BOM field's custom bottom sheet picker with the generic `DocTypePickerBottomSheet`.

## Changes Required

### 1. Controller: `work_order_form_controller.dart`

#### A. Add Import
```dart
import 'package:multimax/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_config.dart';
import 'package:multimax/app/shared/doctype_picker/doctype_picker_column.dart';
```

#### B. Replace `showBomPicker()` Method

Find the existing `showBomPicker()` method (around line 499) and replace it with:

```dart
// ── BOM picker (bottom sheet) ──────────────────────────────────────────────────────
void showBomPicker() {
  if (!canEdit) return;
  
  final selectedItemCode = selectedItem.value;
  if (selectedItemCode == null || selectedItemCode.isEmpty) {
    GlobalSnackbar.info(message: 'Select an item first to load BOMs');
    return;
  }

  showDocTypePickerBottomSheet(
    config: DocTypePickerConfig(
      doctype: 'BOM',
      title: 'Select BOM',
      columns: [
        DocTypePickerColumn.primary(
          fieldname: 'name',
          label: 'BOM',
        ),
        DocTypePickerColumn.subtitle(
          fieldname: 'item',
          label: 'Item',
        ),
      ],
      filters: {
        'item': selectedItemCode,
        'is_active': 1,
        'is_default': ['in', [0, 1]],
      },
      allowRefresh: true,
    ),
    onSelect: (selected) {
      final bomName = selected['name'] as String;
      onBomSelected(bomName);
    },
  );
}
```

### 2. No Screen Changes Required

The screen (`work_order_form_screen.dart`) already calls `controller.showBomPicker()` correctly, so no changes are needed there.

## What This Does

1. **Replaces custom BOM picker** with generic DocType picker
2. **Filters by selected Item** - Only shows BOMs for the currently selected Item
3. **Filters by active status** - Only shows active BOMs (is_active = 1)
4. **Two-column layout**:
   - Primary: BOM name
   - Subtitle: Item code
5. **Enables refresh button** - Allows manual data refresh
6. **Maintains existing behavior** - Calls `onBomSelected()` on selection

## Testing Checklist

- [ ] BOM picker opens when clicking BOM field (with Item selected)
- [ ] Shows warning if no Item is selected
- [ ] Displays only BOMs for the selected Item
- [ ] Shows BOM name and Item in two-column layout
- [ ] Selecting a BOM auto-fills warehouses
- [ ] Refresh button works and reloads BOM list
- [ ] Search functionality works
- [ ] Respects edit mode (read-only when submitted)

## Files Modified

- `lib/app/modules/work_order/form/work_order_form_controller.dart` - Replace showBomPicker() method
