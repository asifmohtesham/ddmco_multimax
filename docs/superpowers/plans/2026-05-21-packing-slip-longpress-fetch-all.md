# Packing Slip Long-Press "Fetch All" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Long-pressing a packing slip row opens a context menu with "Fetch all for [DN]", which replaces all active filters with a `delivery_note` filter and re-fetches from the server.

**Architecture:** Single method modification in `_buildSlipCard` inside `packing_slip_screen.dart`. A `GlobalKey` is created per card so the render box can be resolved at long-press time to position the `showMenu` popup. The existing `controller.applyFilters` method handles the filter replacement and fetch — no controller changes needed.

**Tech Stack:** Flutter (GetX), `showMenu` (Flutter Material), `RenderBox.localToGlobal` for position resolution.

---

## File Map

| File | Change |
|------|--------|
| `lib/app/modules/packing_slip/packing_slip_screen.dart` | Modify `_buildSlipCard`: add `GlobalKey`, `showContextMenu` closure, pass `key` and `onLongPress` to `GenericDocumentCard` |

No other files change.

---

### Task 1: Modify `_buildSlipCard` to add long-press context menu

**Files:**
- Modify: `lib/app/modules/packing_slip/packing_slip_screen.dart` — `_buildSlipCard` method (line ~633)

Read the current `_buildSlipCard` method first so you have the exact existing code before editing.

- [ ] **Step 1: Locate the method signature and existing return block**

Open `lib/app/modules/packing_slip/packing_slip_screen.dart`.  
Find `Widget _buildSlipCard(BuildContext context, dynamic slip)` (~line 633).  
The method currently builds `stats`, `auditStats`, then returns an `Obx(() { ... return GenericDocumentCard(...); })`.

- [ ] **Step 2: Add `GlobalKey` and `showContextMenu` closure at the top of the method**

Insert these two items immediately after the opening brace of `_buildSlipCard`, before the existing `final caseRange = ...` line:

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
        PopupMenuItem<String>(
          value: 'fetch_all',
          child: Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 18),
              const SizedBox(width: 10),
              Text('Fetch all for ${slip.deliveryNote as String}'),
            ],
          ),
        ),
      ],
    ).then((val) {
      if (val == 'fetch_all') {
        controller.applyFilters({
          'delivery_note': slip.deliveryNote as String,
        });
      }
    });
  }

  final caseRange = ... // existing code continues unchanged
```

- [ ] **Step 3: Pass `key` and `onLongPress` to `GenericDocumentCard`**

Inside the `Obx` return block, add `key: cardKey` and `onLongPress` to the existing `GenericDocumentCard(...)` call.

The existing call looks like:

```dart
return GenericDocumentCard(
  title: slip.name as String,
  subtitle: slip.deliveryNote as String,
  status: slip.status as String,
  stats: stats,
  auditStats: auditStats,
  isExpanded: isExpanded,
  isLoadingDetails: isLoadingDetails && isExpanded,
  onTap: () => controller.toggleExpand(slip.name as String),
  expandedContent: isExpanded
      ? _buildExpandedContent(context, slip.name as String)
      : null,
);
```

Change it to:

```dart
return GenericDocumentCard(
  key: cardKey,
  title: slip.name as String,
  subtitle: slip.deliveryNote as String,
  status: slip.status as String,
  stats: stats,
  auditStats: auditStats,
  isExpanded: isExpanded,
  isLoadingDetails: isLoadingDetails && isExpanded,
  onTap: () => controller.toggleExpand(slip.name as String),
  onLongPress: (slip.deliveryNote as String).isNotEmpty
      ? showContextMenu
      : null,
  expandedContent: isExpanded
      ? _buildExpandedContent(context, slip.name as String)
      : null,
);
```

- [ ] **Step 4: Run `flutter analyze` and fix any issues**

```bash
flutter analyze lib/app/modules/packing_slip/packing_slip_screen.dart
```

Expected: `No issues found!`

Common issues to watch for:
- `RelativeRect` — ensure `dart:ui` is not needed; it's in `package:flutter/material.dart` already
- `showMenu` — also in `package:flutter/material.dart`, no extra import needed

- [ ] **Step 5: Smoke test on device**

```bash
flutter run -d <your_device_id>
```

Navigate: **Nav Drawer → Stock → Packing Slip**

Verification checklist:
1. Tap a group header to expand it — slip rows appear
2. **Long-press** any slip row that has a Delivery Note in its subtitle
   - Expected: popup menu appears near the card with label `Fetch all for DN-XXXX-XXXX`
3. **Tap** the menu item
   - Expected: list reloads, a `DN: DN-XXXX-XXXX` filter chip appears in the header, results are filtered to that DN only
4. **Tap the × on the DN chip** to dismiss it
   - Expected: full list reloads unfiltered
5. Long-press a slip that has **no Delivery Note** subtitle (shows empty string)
   - Expected: nothing happens — no menu, no error
6. Long-press a slip, then **tap outside** the menu to dismiss
   - Expected: menu closes, list unchanged, no error or filter applied

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/packing_slip/packing_slip_screen.dart
git commit -m "feat: long-press slip row to fetch all slips for that delivery note"
```
