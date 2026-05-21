# Packing Slip — Fetch All for DN Without Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the paginated DN filter applied by "Fetch all for DN" with a single server call that returns all packing slips for that delivery note, suppressing scroll-to-load-more.

**Architecture:** Add `fetchAllForDeliveryNote(String dn)` to `PackingSlipController` (uses `limit: 500`, sets `hasMore = false` before fetching), then replace the `applyFilters` call in `showContextMenu` with the new method. No changes to the existing pagination path.

**Tech Stack:** Flutter, GetX (`RxList`, `RxBool`), Frappe/ERPNext REST API via `PackingSlipProvider`.

---

## File Map

| File | Change |
|------|--------|
| `lib/app/modules/packing_slip/packing_slip_controller.dart` | Add `fetchAllForDeliveryNote(String dn)` before `openCreateDialog()` (line ~399) |
| `lib/app/modules/packing_slip/packing_slip_screen.dart` | Replace `controller.applyFilters(...)` with `controller.fetchAllForDeliveryNote(dn)` in `showContextMenu` (line 698) |

---

### Task 1: Add `fetchAllForDeliveryNote` to the controller

**Files:**
- Modify: `lib/app/modules/packing_slip/packing_slip_controller.dart` — insert before `openCreateDialog()` at line 400

- [ ] **Step 1: Insert the new method**

Open `lib/app/modules/packing_slip/packing_slip_controller.dart`.

Find this line (around line 399–400):

```dart
  void openCreateDialog() {
```

Insert the following block immediately before it (leave the existing `openCreateDialog` untouched):

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

- [ ] **Step 2: Run `flutter analyze` on the controller**

```bash
flutter analyze lib/app/modules/packing_slip/packing_slip_controller.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit the controller change**

```bash
git add lib/app/modules/packing_slip/packing_slip_controller.dart
git commit -m "feat: add fetchAllForDeliveryNote to PackingSlipController"
```

---

### Task 2: Wire up the call site in the screen

**Files:**
- Modify: `lib/app/modules/packing_slip/packing_slip_screen.dart` — line 698

- [ ] **Step 1: Replace the call in `showContextMenu`**

Open `lib/app/modules/packing_slip/packing_slip_screen.dart`.

Find this line (around line 698):

```dart
          controller.applyFilters({'delivery_note': dn});
```

Replace it with:

```dart
          controller.fetchAllForDeliveryNote(dn);
```

- [ ] **Step 2: Run `flutter analyze` on the screen**

```bash
flutter analyze lib/app/modules/packing_slip/packing_slip_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Smoke test on device**

```bash
flutter run -d <your_device_id>
```

Navigate: **Nav Drawer → Stock → Packing Slip**

Verification checklist:
1. Expand a group → long-press any slip with a Delivery Note
2. Tap *"Fetch all for DN-XXXX"* → snackbar appears, list reloads
3. All slips for that DN appear in one load — **no scroll-to-load-more spinner at the bottom**
4. The DN filter chip is visible and dismissible in the header
5. Dismiss the DN chip → full paginated list reloads normally (scroll-to-load-more returns)
6. Use the filter sheet to apply a DN filter manually (not via long-press) → normal paginated behaviour is unchanged

- [ ] **Step 4: Commit the screen change**

```bash
git add lib/app/modules/packing_slip/packing_slip_screen.dart
git commit -m "feat: use fetchAllForDeliveryNote in long-press context menu"
```
