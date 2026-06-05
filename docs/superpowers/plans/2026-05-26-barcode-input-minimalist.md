# BarcodeInputWidget Minimalist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `helperText` from `BarcodeInputWidget` so the field stays compact and does not change colour after a barcode scan.

**Architecture:** Single-file edit to `lib/app/modules/global_widgets/barcode_input_widget.dart`. Delete the `helperText`/`helperColor` variable block and the two `InputDecoration` properties that consume them. State feedback is retained via the existing suffix-icon logic (spinner / check / error icon). A new widget test verifies no `Text` matching the old helper strings appears in any state.

**Tech Stack:** Flutter (Dart), `flutter_test`, `flutter analyze`

---

### Task 1: Write a failing widget test for the no-helperText contract

**Files:**
- Create: `test/widget/barcode_input_widget_test.dart`

- [ ] **Step 1: Create the test file**

```dart
// test/widget/barcode_input_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';

void main() {
  Widget buildWidget({
    bool isLoading = false,
    bool isSuccess = false,
    bool hasError = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: BarcodeInputWidget(
          onScan: (_) {},
          isLoading: isLoading,
          isSuccess: isSuccess,
          hasError: hasError,
          hintText: 'Scan Item / Batch',
        ),
      ),
    );
  }

  group('BarcodeInputWidget — no helperText in any state', () {
    testWidgets('idle state shows no coloured helper text', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Scan Item / Batch'), findsNothing);
      expect(find.text('Processing...'), findsNothing);
      expect(find.text('Scan Validated'), findsNothing);
      expect(find.text('Scan Failed'), findsNothing);
    });

    testWidgets('loading state shows no helper text', (tester) async {
      await tester.pumpWidget(buildWidget(isLoading: true));
      expect(find.text('Processing...'), findsNothing);
    });

    testWidgets('success state shows no helper text', (tester) async {
      await tester.pumpWidget(buildWidget(isSuccess: true));
      expect(find.text('Scan Validated'), findsNothing);
    });

    testWidgets('error state shows no helper text', (tester) async {
      await tester.pumpWidget(buildWidget(hasError: true));
      expect(find.text('Scan Failed'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

```
flutter test test/widget/barcode_input_widget_test.dart --reporter expanded
```

Expected: FAIL — the widget currently renders "Scan Item / Batch" as helperText in the idle state, and "Processing…" / "Scan Validated" / "Scan Failed" in the other states.

---

### Task 2: Remove helperText from BarcodeInputWidget

**Files:**
- Modify: `lib/app/modules/global_widgets/barcode_input_widget.dart`

- [ ] **Step 1: Delete the helperText/helperColor variable block**

In `_BarcodeInputWidgetState.build()`, delete these lines (currently ~157–169):

```dart
// DELETE this entire block:
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

- [ ] **Step 2: Remove helperText and helperStyle from InputDecoration**

In the `TextFormField`'s `InputDecoration(...)`, delete these two properties:

```dart
// DELETE these two lines from InputDecoration:
helperText: helperText,
helperStyle: TextStyle(
  color: helperColor,
  fontWeight:
      (widget.isSuccess || widget.hasError)
          ? FontWeight.bold
          : FontWeight.normal,
),
```

The `InputDecoration` block should now jump straight from `floatingLabelBehavior: FloatingLabelBehavior.auto,` to `labelStyle: TextStyle(...)`.

- [ ] **Step 3: Run flutter analyze**

```
flutter analyze lib/app/modules/global_widgets/barcode_input_widget.dart
```

Expected: No issues. (If `helperText`/`helperColor` variables are now unused, the analyzer will flag them — confirm they were fully deleted in Step 1.)

- [ ] **Step 4: Run the new widget tests — they should now pass**

```
flutter test test/widget/barcode_input_widget_test.dart --reporter expanded
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Run the full test suite**

```
flutter test --reporter expanded
```

Expected: All existing tests pass (no regressions).

- [ ] **Step 6: Commit**

```
git add lib/app/modules/global_widgets/barcode_input_widget.dart \
        test/widget/barcode_input_widget_test.dart \
        docs/superpowers/specs/2026-05-26-barcode-input-minimalist-design.md \
        docs/superpowers/plans/2026-05-26-barcode-input-minimalist.md
git commit -m "fix(barcode-input): remove helperText to fix height and colour-change on scan"
```
