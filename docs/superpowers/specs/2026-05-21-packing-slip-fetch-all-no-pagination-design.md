# Packing Slip — Fetch All for DN Without Pagination

**Date:** 2026-05-21  
**Status:** Approved

## Overview

When the user triggers "Fetch all for DN-XXXX" via long-press, all packing slips for that delivery note must be returned in a single server call. The current behaviour routes through the standard paginated fetch (`_limit = 20`), requiring the user to scroll to the end to load more. This spec replaces that call with a dedicated non-paginated path.

## Behaviour

| Trigger | Current | Expected |
|---------|---------|----------|
| Long-press → Fetch all for DN | Paginated (20/page), scroll-to-load-more active | All slips in one fetch (limit 500), no scroll-to-load-more |

The DN filter chip still appears in the header (dismissible). The existing snackbar loading UX is unaffected — it still listens on `isLoading` going false.

## Implementation

### Files changed

| File | Change |
|------|--------|
| `lib/app/modules/packing_slip/packing_slip_controller.dart` | Add `fetchAllForDeliveryNote(String dn)` method |
| `lib/app/modules/packing_slip/packing_slip_screen.dart` | Replace `controller.applyFilters(...)` with `controller.fetchAllForDeliveryNote(dn)` in `showContextMenu` |

### New controller method

Add to `PackingSlipController`:

```dart
Future<void> fetchAllForDeliveryNote(String dn) async {
  activeFilters.value = {'delivery_note': dn};
  isLoading.value = true;
  packingSlips.clear();
  _currentPage = 0;
  hasMore.value = false;

  try {
    final response = await _provider.getPackingSlips(
      limit: 500,
      limitStart: 0,
      filters: {'delivery_note': dn},
      orderBy: '${sortField.value} ${sortOrder.value}',
    );
    if (response.statusCode == 200 && response.data['data'] != null) {
      final newSlips = (response.data['data'] as List)
          .map((json) => PackingSlip.fromJson(json))
          .toList();
      packingSlips.value = newSlips;
      _fetchAssociatedCustomers(newSlips);
    } else {
      AppNotification.error('Failed to fetch packing slips');
    }
  } catch (e) {
    AppNotification.error(e.toString());
  } finally {
    isLoading.value = false;
  }
}
```

Key behaviours:
- `hasMore.value = false` is set **before** the fetch — the scroll-to-load-more spinner never appears
- `activeFilters` is set to `{'delivery_note': dn}` so the dismissible DN chip renders in the header
- `_currentPage = 0` resets pagination state so a subsequent normal fetch starts cleanly
- Uses `limit: 500` — safe upper bound for packing slips per delivery note

### Screen call site change

In `showContextMenu` inside `_buildSlipCard`, replace:

```dart
controller.applyFilters({'delivery_note': dn});
```

With:

```dart
controller.fetchAllForDeliveryNote(dn);
```

## What Does Not Change

- `applyFilters` — untouched; still used by the filter sheet
- `fetchPackingSlips` — untouched; normal pagination path unchanged
- Snackbar / `ever()` Worker — unchanged; still driven by `isLoading`
- `PackingSlipProvider` — no changes
- `GenericDocumentCard` — no changes
