# Packing Slip — Fetch All Loading UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a snackbar with the delivery note name and a linear progress bar immediately when "Fetch all for DN-XXXX" is tapped, dismissing it automatically when the fetch completes.

**Architecture:** Three targeted edits to `_PackingSlipScreenState` in `packing_slip_screen.dart`: add two fields (`_fetchSnackBar`, `_fetchSnackBarWorker`), dispose the Worker in `dispose()`, and expand the `showContextMenu` closure to show the snackbar and register an `ever()` Worker that closes it when `isLoading` goes false.

**Tech Stack:** Flutter (Material `SnackBar`, `LinearProgressIndicator`), GetX (`ever()` Worker, `RxBool`).

---

## File Map

| File | Change |
|------|--------|
| `lib/app/modules/packing_slip/packing_slip_screen.dart` | Add two fields to `_PackingSlipScreenState`; update `dispose()`; expand `showContextMenu` closure |

No other files change.

---

### Task 1: Add state fields, update `dispose()`, and expand `showContextMenu`

**Files:**
- Modify: `lib/app/modules/packing_slip/packing_slip_screen.dart`
  - Fields: lines 38–40 (class body top)
  - `dispose()`: lines 49–53
  - `showContextMenu` `.then` block: lines 662–668

- [ ] **Step 1: Add the two fields to `_PackingSlipScreenState`**

Open `lib/app/modules/packing_slip/packing_slip_screen.dart`.

Find this block (starts at line 37):

```dart
class _PackingSlipScreenState extends State<PackingSlipScreen> {
  final PackingSlipController controller = Get.find();
  final _scrollController = ScrollController();
  final _isFarFromTop = false.obs;
```

Change it to:

```dart
class _PackingSlipScreenState extends State<PackingSlipScreen> {
  final PackingSlipController controller = Get.find();
  final _scrollController = ScrollController();
  final _isFarFromTop = false.obs;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _fetchSnackBar;
  Worker? _fetchSnackBarWorker;
```

- [ ] **Step 2: Update `dispose()` to clean up the Worker**

Find the existing `dispose()` (around line 49):

```dart
  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
```

Change it to:

```dart
  @override
  void dispose() {
    _fetchSnackBarWorker?.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
```

- [ ] **Step 3: Expand the `showContextMenu` `.then` block**

Find the existing `.then` block inside `showContextMenu` (around line 662):

```dart
      ).then((val) {
        if (val == 'fetch_all') {
          controller.applyFilters({
            'delivery_note': slip.deliveryNote as String,
          });
        }
      });
```

Replace it with:

```dart
      ).then((val) {
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
      });
```

- [ ] **Step 4: Run `flutter analyze` and fix any issues**

```bash
flutter analyze lib/app/modules/packing_slip/packing_slip_screen.dart
```

Expected: `No issues found!`

Common issues to watch for:
- `Worker` — imported via `package:get/get.dart`, already present in the file
- `ScaffoldFeatureController` — from `package:flutter/material.dart`, already present
- `LinearProgressIndicator` — from `package:flutter/material.dart`, already present

- [ ] **Step 5: Smoke test on device**

```bash
flutter run -d <your_device_id>
```

Navigate: **Nav Drawer → Stock → Packing Slip**

Verification checklist:
1. Expand a group → long-press any slip with a Delivery Note
2. Tap *"Fetch all for DN-XXXX"* in the context menu
   - Expected: snackbar appears at the bottom immediately with text *"Fetching all slips for DN-XXXX"* and a running linear progress bar
3. While the snackbar is showing the list clears and the full-screen spinner appears
4. When the list loads with filtered results the snackbar dismisses automatically
5. The DN filter chip is visible in the header
6. Long-press a second slip while the first fetch is still loading
   - Expected: the previous snackbar closes, a new one appears for the new DN

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/packing_slip/packing_slip_screen.dart
git commit -m "feat: show loading snackbar while fetching all slips for delivery note"
```
