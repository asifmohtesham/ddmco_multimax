# Commit 6: Global Barcode Scanning Integration Guide

This guide provides instructions for integrating global barcode scanning into the Item field with auto-prefill and manual override capability.

## Overview

Currently, barcode scanning requires navigating to a dedicated Item scan screen, which adds unnecessary steps. This commit integrates barcode scanning directly into the Work Order form's Item field using the existing `scanWorker` infrastructure.

## Requirements Summary

Based on the original feature requirements:

- **Reuse existing scanWorker/eventSink**: Use app's existing barcode infrastructure
- **Auto-prefill search box**: Barcode scan automatically populates Item field
- **Manual override**: Users can still type/search manually
- **Seamless UX**: No navigation to separate scan screen

## Implementation Approach

### Option 1: Simple Approach (Recommended)

Since the current Item field implementation uses a custom TextField with typeahead search, we can keep this approach and note that Commit 3 (DocType picker integration for Item field) will be revisited in a future iteration.

For now, Commit 6 focuses on:
1. Adding barcode scanning capability to the existing Item TextField
2. Auto-filling the field when a barcode is scanned
3. Maintaining manual typing/search capability

### Changes Required

#### 1. Controller: `work_order_form_controller.dart`

**A. Add barcode scanning import**:
```dart
import 'package:multimax/app/services/barcode_scanner_service.dart'; // Or wherever scanWorker is defined
```

**B. Add StreamSubscription for barcode events**:
```dart
// Add to class properties
StreamSubscription<String>? _barcodeScanSubscription;
```

**C. Initialize barcode listener in `onInit()`**:
```dart
@override
void onInit() {
  super.onInit();
  // ... existing initialization code ...
  
  // Subscribe to barcode scan events
  _barcodeScanSubscription = barcodeScannerService.scanStream.listen((barcode) {
    if (canEdit && barcode.isNotEmpty) {
      // Auto-fill Item field with scanned barcode
      itemController.text = barcode;
      // Trigger search to find matching item
      searchItems(barcode);
    }
  });
}
```

**D. Cancel subscription in `onClose()`**:
```dart
@override
void onClose() {
  _barcodeScanSubscription?.cancel();
  itemController.dispose();
  // ... rest of dispose code ...
  super.onClose();
}
```

## Testing Checklist

- [ ] Barcode scan auto-fills Item field
- [ ] Manual typing still works (not blocked by scanner)
- [ ] Scanned value triggers item search
- [ ] Can clear scanned value and type manually
- [ ] Subscription properly cancelled on screen close
- [ ] No memory leaks (subscription cleanup verified)
- [ ] Works in both 'new' and 'view' modes
- [ ] Respects `canEdit` permission

## Notes

- **Commit 3 Revision**: The full Item field migration to DocType picker (Commit 3) will be revisited after this feature set is complete, as it requires barcode integration in the generic picker component
- **Scope**: This commit focuses solely on barcode scanning integration, not UI changes
- **Future Enhancement**: Consider adding visual feedback (e.g., highlight) when barcode is scanned

## Files Modified

- `lib/app/modules/work_order/form/work_order_form_controller.dart`
  - Add barcode service import
  - Add StreamSubscription property
  - Initialize barcode listener in onInit()
  - Cancel subscription in onClose()
