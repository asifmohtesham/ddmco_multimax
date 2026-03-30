# Commit 3 Integration Guide

## Objective
Integrate `DocTypePickerProvider` into `DocTypePickerBottomSheet` to replace the temporary `loader` function with real ERPNext API queries, cache-first loading, and manual refresh.

## Files to modify
- `lib/app/shared/doctype_picker/doctype_picker_bottom_sheet.dart`

## Changes

### 1. Add imports (after line 3)
```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/doctype_picker_provider.dart';
```

### 2. Add provider instance in `_DocTypePickerBottomSheetState` (after line 51)
```dart
final DocTypePickerProvider _provider = Get.find<DocTypePickerProvider>();
```

### 3. Replace `_load()` method (lines 62-91)

**Remove the old implementation entirely and replace with:**

```dart
Future<void> _load({bool forceRefresh = false}) async {
  // If config has a temporary loader, use it (dev/testing path)
  if (widget.config.loader != null) {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final rows = await widget.config.loader!(_searchController.text);
      if (mounted) {
        setState(() {
          _rows = rows;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
    return;
  }

  // Production path: use DocTypePickerProvider
  setState(() {
    _isLoading = true;
    _error = '';
  });

  try {
    final result = await _provider.queryDocType(
      doctype: widget.config.doctype,
      fields: widget.config.resolvedFields,
      filters: widget.config.filters,
      searchText: _searchController.text.trim(),
      cacheKey: widget.config.cacheKey,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      setState(() {
        _rows = List<Map<String, dynamic>>.from(result['data'] ?? []);
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _error = e.toString();
      });
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
```

### 4. Add refresh button in header (replace lines 161-181)

**Find the header Row widget and update to:**

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
  child: Row(
    children: [
      Expanded(
        child: Text(
          widget.config.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ),
      if (widget.config.allowRefresh)
        IconButton(
          onPressed: () => _load(forceRefresh: true),
          icon: const Icon(Icons.refresh),
          style: IconButton.styleFrom(
            backgroundColor: cs.surfaceContainerHigh,
            foregroundColor: cs.onSurfaceVariant,
          ),
          tooltip: 'Refresh',
        ),
      const SizedBox(width: 8),
      IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close),
        style: IconButton.styleFrom(
          backgroundColor: cs.surfaceContainerHigh,
          foregroundColor: cs.onSurfaceVariant,
        ),
      ),
    ],
  ),
),
```

## Acceptance criteria

- [ ] Picker loads data from cache on first open
- [ ] Manual refresh button bypasses cache and fetches live data
- [ ] Search text triggers re-query with filters
- [ ] Temporary `loader` function still works for testing/dev
- [ ] No regressions in UI layout or row rendering
- [ ] Refresh shows feedback during loading (button disabled or spinner)

## Testing

1. Open picker with `cacheKey` set → data loads from cache
2. Tap refresh button → data reloads from API
3. Type in search → results filter correctly
4. Check cache expiry after 15 minutes → fresh fetch happens automatically
5. Test with `loader` set → temporary loader still works

## Notes

- The `forceRefresh` parameter defaults to `false` for normal loads
- The refresh button only appears when `config.allowRefresh == true`
- Cache TTL is 15 minutes (defined in `DocTypePickerProvider.cacheTTLMinutes`)
- Search text is trimmed before being sent to the provider
