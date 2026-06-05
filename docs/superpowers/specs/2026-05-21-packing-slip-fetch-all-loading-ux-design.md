# Packing Slip — "Fetch All" Loading UX

**Date:** 2026-05-21  
**Status:** Approved

## Overview

When the user taps "Fetch all for [DN]" from the long-press context menu, a snackbar appears immediately with the delivery note name and a `LinearProgressIndicator`. It dismisses automatically when the fetch completes. This bridges the gap between menu dismissal and the existing full-screen spinner.

## Interaction Flow

1. User taps *"Fetch all for DN-XXXX"* in the context menu
2. A `SnackBar` appears at the bottom immediately (before `applyFilters` is called):
   - First line: *"Fetching all slips for DN-XXXX"*
   - Second line: `LinearProgressIndicator()`
   - Duration: 30 s (dismissed programmatically, not by timeout)
3. An `ever(controller.isLoading, ...)` Worker is registered; when `isLoading` transitions to `false` it closes the snackbar and disposes itself
4. `controller.applyFilters({'delivery_note': dn})` is called to start the fetch
5. The existing full-screen spinner shows as the list clears and reloads
6. When loading completes: snackbar closes, filtered list and DN chip are visible

If a second long-press "Fetch all" is triggered while the first is still loading, any in-flight snackbar and Worker are closed/disposed before the new ones are created.

## Implementation

### Files changed

**Only one file changes:** `lib/app/modules/packing_slip/packing_slip_screen.dart`

### `_PackingSlipScreenState` — new fields

```dart
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _fetchSnackBar;
Worker? _fetchSnackBarWorker;
```

### `dispose()` — cleanup

```dart
@override
void dispose() {
  _fetchSnackBarWorker?.dispose();
  _scrollController.removeListener(_onScroll);
  _scrollController.dispose();
  super.dispose();
}
```

### `showContextMenu` closure — snackbar + worker

Inside the `.then((val) { ... })` block, replace the bare `controller.applyFilters(...)` call with:

```dart
if (val == 'fetch_all') {
  final dn = slip.deliveryNote as String;

  _fetchSnackBarWorker?.dispose();
  _fetchSnackBar?.close();

  _fetchSnackBar = ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 30),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fetching all slips for $dn'),
          const SizedBox(height: 6),
          const LinearProgressIndicator(),
        ],
      ),
    ),
  );

  _fetchSnackBarWorker = ever(controller.isLoading, (bool loading) {
    if (!loading) {
      _fetchSnackBar?.close();
      _fetchSnackBar = null;
      _fetchSnackBarWorker?.dispose();
      _fetchSnackBarWorker = null;
    }
  });

  controller.applyFilters({'delivery_note': dn});
}
```

## Edge Cases

| Case | Behaviour |
|------|-----------|
| Second "Fetch all" tapped while first is loading | Previous snackbar closed and Worker disposed before new ones are created |
| User navigates away mid-fetch | `dispose()` calls `_fetchSnackBarWorker?.dispose()` — Worker cleaned up safely |
| Fetch fails (error notification shown) | `isLoading` still goes false → snackbar dismissed, error toast shown by existing `AppNotification.error` |
| `context` is no longer mounted when `.then` fires | `ScaffoldMessenger.of(context)` will throw; guarded by the existing mounted lifecycle of the screen |

## What Does Not Change

- `PackingSlipController` — no changes
- `PackingSlipProvider` — no changes
- `GenericDocumentCard` — no changes
- All other list screens — unaffected
