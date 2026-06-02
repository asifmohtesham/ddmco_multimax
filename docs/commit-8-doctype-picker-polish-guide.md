# Commit 8: Polish Generic DocType Picker for App-Wide Reuse

This document outlines the polishing tasks for Commit 8 of the Work Order DocType Picker implementation.

## Overview

Commit 8 focuses on polishing the generic DocTypePicker widget to ensure it's production-ready and can be reused across the entire application. The goal is to create a consistent, well-documented, and visually appealing picker that works seamlessly for all DocTypes.

## Current State

The generic DocTypePicker infrastructure is now complete with:
- ✅ Generic UI shell with search and list (Commit 1)
- ✅ Cache-first datasource with live refresh (Commit 2)
- ✅ Barcode prefill support (Commit 3)
- ✅ Item picker implementation (Commit 4)
- ✅ Item selection side effects (Commit 5)
- ✅ BOM picker implementation (Commit 6)
- ✅ Warehouse pickers implementation (Commit 7)

## Commit 8 Tasks

### 1. Improve Row Spacing and Padding Consistency

**Goal**: Ensure all rows have consistent vertical and horizontal padding across all picker types.

**Changes**:
- Review padding on list tiles in `doctype_picker_bottom_sheet.dart`
- Ensure consistent spacing between primary, secondary, and subtitle text
- Verify margins are uniform across Item, BOM, and Warehouse pickers
- Add padding constants if needed for maintainability

### 2. Fix Subtitle Truncation

**Goal**: Ensure subtitle text is clean with single-line ellipsis and no layout overflow.

**Changes**:
- Apply `maxLines: 1` and `overflow: TextOverflow.ellipsis` to subtitle text
- Test with long subtitle content (item_group, variant_of, country_of_origin)
- Ensure no horizontal overflow on narrow screens
- Verify subtitle hides completely when all fields are empty

### 3. Align Header Labels for Multi-Column Layout

**Goal**: Make column headers subtle and correctly aligned with their content.

**Changes**:
- Add header row for multi-column layouts (wide screens)
- Align headers with their respective column content
- Use subtle text style (smaller font, muted color)
- Hide headers on narrow/mobile layouts where stacked view is used

### 4. Improve Empty State

**Goal**: Show a warm, helpful message when no results are found.

**Changes**:
- Create friendly empty state message: "No {doctype} found"
- Add helpful subtext: "Try adjusting your search or tap refresh to reload"
- Include retry/refresh affordance (button or icon)
- Use appropriate icon (e.g., search icon or empty box)
- Center the empty state content

### 5. Make Refresh UX Non-Blocking

**Goal**: Show visible feedback during refresh without blocking the UI.

**Changes**:
- Use a small loading indicator (spinner) in the app bar during refresh
- Keep the list visible (dimmed) during refresh
- Don't show full-screen loading spinner
- Provide success feedback after refresh completes (optional: brief snackbar)
- Handle errors gracefully with retry option

### 6. Add Inline Dartdoc Comments

**Goal**: Document `DocTypePickerConfig` and `DocTypePickerColumn` for future reuse.

**Changes**:

In `doctype_picker_config.dart`:
```dart
/// Configuration for a generic DocType picker bottom sheet.
///
/// This class defines how a DocType should be displayed and queried
/// in the picker interface. It supports:
/// - Custom filters and search fields
/// - Multi-column layouts with flexible column definitions
/// - Subtitle metadata formatting
/// - Optional barcode scanning
/// - Cache-first loading with manual refresh
///
/// Example:
/// ```dart
/// final itemConfig = DocTypePickerConfig(
///   doctype: 'Item',
///   title: 'Select Item',
///   filters: {'disabled': 0, 'is_stock_item': 1},
///   // ... other properties
/// );
/// ```
class DocTypePickerConfig {
  // ... existing code with property documentation
}
```

In `doctype_picker_column.dart`:
```dart
/// Defines a column in the DocType picker multi-column layout.
///
/// Columns can be configured with:
/// - Flexible widths using [flex] and [minWidth]
/// - Alignment options (left, right, center)
/// - Visibility controls for mobile vs desktop
/// - Custom value builders for formatting
///
/// Example:
/// ```dart
/// DocTypePickerColumn(
///   key: 'stock_uom',
///   label: 'UOM',
///   flex: 1,
///   align: TextAlign.right,
///   visibleOnMobile: false,
/// )
/// ```
class DocTypePickerColumn {
  // ... existing code with property documentation
}
```

### 7. Verify Consistency Across All Picker Types

**Goal**: Ensure Item, BOM, and Warehouse pickers all look and behave identically.

**Test Checklist**:
- [ ] All three pickers have identical spacing and padding
- [ ] Empty states show consistent messaging
- [ ] Refresh behavior is identical across all pickers
- [ ] Subtitle truncation works correctly in all cases
- [ ] Headers (if shown) are aligned consistently
- [ ] No picker-specific hacks in the generic widget
- [ ] All pickers respect their config settings properly

## Files to Modify

1. `lib/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart`
   - UI improvements: spacing, truncation, headers, empty state, refresh UX

2. `lib/app/shared/doctype_picker/doctype_picker_config.dart`
   - Add comprehensive dartdoc comments

3. `lib/app/shared/doctype_picker/doctype_picker_column.dart`
   - Add comprehensive dartdoc comments

## Acceptance Criteria

✅ **Visual Consistency**:
- All pickers look identical in terms of spacing, padding, and layout
- No visual glitches or layout overflow
- Subtle, well-aligned headers on wide layouts

✅ **Empty State**:
- Warm, helpful message with retry affordance
- Centered and visually appealing

✅ **Refresh UX**:
- Non-blocking refresh with visible feedback
- No jarring full-screen loaders
- Graceful error handling

✅ **Documentation**:
- Comprehensive dartdoc comments on config and column classes
- Clear examples showing how to use the picker
- Ready for reuse on any DocType in the app

✅ **No Regressions**:
- All existing functionality still works
- Item, BOM, and Warehouse pickers all function correctly
- Barcode scanning, caching, and filtering still work as expected

## Commit Message

```
chore(ui): polish generic DocType picker for app-wide reuse

- Improve row spacing and padding consistency across all picker types
- Fix subtitle truncation with ellipsis to prevent layout overflow
- Add subtle, aligned column headers for multi-column layouts
- Enhance empty state with warm message and retry affordance
- Make refresh UX non-blocking with visible feedback
- Add comprehensive dartdoc comments for DocTypePickerConfig and DocTypePickerColumn
- Verify visual consistency across Item, BOM, and Warehouse pickers

The generic DocType picker is now production-ready and fully documented
for reuse across the entire application.
```

## Next Steps

After this commit:
- The generic DocType picker is ready for use with any DocType
- Other modules can easily adopt this picker pattern
- Documentation ensures maintainability and ease of use
- Consistent UX across all DocType selections in the app
