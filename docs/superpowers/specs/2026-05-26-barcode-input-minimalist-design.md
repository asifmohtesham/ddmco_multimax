# BarcodeInputWidget — Minimalist / No-Colour-Change Design

**Date:** 2026-05-26
**Status:** Approved

---

## Problem

`BarcodeInputWidget` in non-embedded mode (form screens: Delivery Note, Stock Entry, etc.) exhibits two issues:

1. **Extra height** — `InputDecoration.helperText` is always set (initially to `widget.hintText`), so Flutter permanently reserves a line of vertical space below the field. In `bottomNavigationBar` slots (Dashboard) this is invisible; inside a `Column` body it noticeably shrinks the item list above.

2. **Colour change on scan** — when `isLoading`, `isSuccess`, or `hasError` flip, `helperText` changes to "Processing…" / "Scan Validated" / "Scan Failed" with blue / green / red colouring. This is distracting and inconsistent with the minimalist aesthetic used on the Dashboard.

## Goal

- Form-screen `BarcodeInputWidget` should be as compact and visually stable as the Dashboard version.
- After a scan, the widget must not change colour or height.
- Subtle state feedback (loading spinner, success check, error icon) is still required via the suffix icon slot.

## Design

### Single-file change

**File:** `lib/app/modules/global_widgets/barcode_input_widget.dart`

**Remove** the `helperText`/`helperColor` variable block (~lines 157–169):

```dart
// REMOVE these lines
String? helperText = widget.hintText;
Color? helperColor = Colors.grey;

if (widget.isLoading) {
  helperText = 'Processing...';
  helperColor = Colors.blue;
} else if (widget.isSuccess) {
  helperText = 'Scan Validated';
  helperColor = Colors.green;
} else if (widget.hasError) {
  helperText = 'Scan Failed';
  helperColor = Colors.red;
}
```

**Remove** the `helperText` and `helperStyle` entries from `InputDecoration`:

```dart
// REMOVE from InputDecoration(...)
helperText: helperText,
helperStyle: TextStyle(
  color: helperColor,
  fontWeight: (widget.isSuccess || widget.hasError)
      ? FontWeight.bold
      : FontWeight.normal,
),
```

### What stays unchanged

| Prop | Role | Kept? |
|------|------|-------|
| `isLoading` | Shows CircularProgressIndicator in suffix | Yes |
| `isSuccess` | Shows green check_circle in suffix | Yes |
| `hasError` | Shows red error icon in suffix | Yes |
| `hintText` | Passed through but no longer used as helperText | Retained in signature (callers pass it); can be repurposed as `hintText` on the field in a future pass |
| `isEmbedded` | Controls decoration style (tinted bg, left icon) | Yes |

### Out of scope

- Changing `hintText` wiring (kept for backward compat)
- Adjusting suffix icon colours or animations
- Any callsite changes

## Effects

- Field height drops by one text-line (~20 dp) in all contexts
- Widget appearance does not change during or after a scan
- Dashboard, form screens, and ItemSheet all benefit uniformly
- No API surface added or removed
