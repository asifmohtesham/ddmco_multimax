# Packing Slip — Long-Press "Fetch All" Feature

**Date:** 2026-05-21  
**Status:** Approved

## Overview

When the user long-presses a packing slip row in the Packing Slip list screen, a context menu popup appears with a single action: **"Fetch all for [Delivery Note]"**. Selecting it replaces all active filters with a `delivery_note` filter for that slip's DN, triggering a fresh server-side fetch that shows every packing slip for that delivery note.

## Interaction Model

**Entry point:** `Nav Drawer → Stock → Packing Slip → List View`

**Trigger:** Long-press on any individual slip row inside an expanded group. Group-header rows are not affected.

**On long-press:**
1. A `PopupMenuItem` context menu appears anchored below the card's bounding box.
2. Single item: *"Fetch all for [deliveryNote]"* with `Icons.local_shipping_outlined`.
3. If the slip has no `deliveryNote` (empty string), long-press is a no-op — menu is not shown.

**On menu item tap:**
- Calls `controller.applyFilters({'delivery_note': slip.deliveryNote})`.
- This clears all existing active filters (status, PO, date, sort, search) and applies only the DN filter.
- A fresh paginated fetch is triggered automatically.
- The existing **"DN: [value]"** dismissible filter chip appears in the header, letting the user clear the filter to return to the unfiltered list.

## Implementation

### Files changed

**Only one file changes:** `lib/app/modules/packing_slip/packing_slip_screen.dart`

No changes to `GenericDocumentCard`, `PackingSlipController`, `PackingSlipProvider`, or any other file.

### `_buildSlipCard` — key changes

1. Create a `GlobalKey` inside `_buildSlipCard`, keyed to the slip's name for stability across rebuilds.
2. Define a `_showContextMenu` closure that:
   - Resolves the card's `RenderBox` via `cardKey.currentContext?.findRenderObject()`
   - Computes a `RelativeRect` anchored below the card
   - Calls `showMenu<String>` with one `PopupMenuItem`
   - On result `'fetch_all'`: calls `controller.applyFilters({'delivery_note': slip.deliveryNote})`
3. Pass `key: cardKey` and `onLongPress: slip.deliveryNote.isNotEmpty ? _showContextMenu : null` to `GenericDocumentCard`.

```dart
Widget _buildSlipCard(BuildContext context, dynamic slip) {
  final cardKey = GlobalKey();

  void showContextMenu() {
    final box = cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final rect = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height,
      offset.dx + size.width,
      offset.dy + size.height + 8,
    );
    showMenu<String>(
      context: context,
      position: rect,
      items: [
        PopupMenuItem(
          value: 'fetch_all',
          child: Row(children: [
            const Icon(Icons.local_shipping_outlined, size: 18),
            const SizedBox(width: 10),
            Text('Fetch all for ${slip.deliveryNote}'),
          ]),
        ),
      ],
    ).then((val) {
      if (val == 'fetch_all') {
        controller.applyFilters({'delivery_note': slip.deliveryNote as String});
      }
    });
  }

  // ... existing stats / auditStats build ...

  return Obx(() {
    // ... existing Obx content ...
    return GenericDocumentCard(
      key: cardKey,
      // ... existing params ...
      onLongPress: (slip.deliveryNote as String).isNotEmpty ? showContextMenu : null,
    );
  });
}
```

## Edge Cases

| Case | Behaviour |
|------|-----------|
| Slip has no delivery note | `onLongPress` is null — InkWell shows no long-press feedback |
| RenderBox lookup returns null | Early return, menu not shown; no crash |
| User long-presses while a filter is already active | `applyFilters` replaces all existing filters |
| User dismisses menu (taps outside) | `showMenu` returns `null`; `.then` guard ignores it |
| Group is collapsed (slips hidden) | Long-press is physically unreachable; no handling needed |

## What Does Not Change

- `GenericDocumentCard` — API unchanged
- `PackingSlipController` — `applyFilters` already handles this use case
- `PackingSlipProvider` — no changes
- All other list screens (Stock Entry, Delivery Note) — unaffected
