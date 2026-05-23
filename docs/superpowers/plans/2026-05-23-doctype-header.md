# DocType Header Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the delegating `DocTypeFormHeader` with a standalone sliver that shows a two-line collapsed toolbar, doctype label, status pill, and unsaved-changes indicator — while fixing all ERPNext v16 status-pill colours.

**Architecture:** Four independent changes applied in dependency order: (1) `SaveIconButton` gains a navy filled-state for dirty docs; (2) `StatusPill` is fully rewritten with the correct Frappe UI colour map; (3) `DocTypeFormHeader` becomes a standalone `SliverPersistentHeader` that uses both; (4) six form screens each add two params.

**Tech Stack:** Flutter, Dart, Material 3, `auto_size_text`, GetX (for `SaveResult` enum), `flutter_test`

---

## File map

| File | Action |
|---|---|
| `lib/app/modules/global_widgets/save_icon_button.dart` | Add `showFilledWhenDirty` param |
| `lib/app/modules/global_widgets/status_pill.dart` | Full rewrite — correct ERPNext v16 map |
| `lib/app/modules/global_widgets/doctype_form_header.dart` | Full rewrite — standalone sliver |
| `lib/app/modules/global_widgets/doctype_list_header.dart` | **Untouched** |
| `lib/app/modules/work_order/form/work_order_form_screen.dart` | Add `docType` + `statusLabel` |
| `lib/app/modules/stock_entry/form/stock_entry_form_screen.dart` | Add `docType` + `statusLabel` |
| `lib/app/modules/delivery_note/form/delivery_note_form_screen.dart` | Add `docType` + `statusLabel` |
| `lib/app/modules/purchase_order/form/purchase_order_form_screen.dart` | Add `docType` + `statusLabel` |
| `lib/app/modules/purchase_receipt/form/purchase_receipt_form_screen.dart` | Add `docType` + `statusLabel` |
| `lib/app/modules/material_request/form/material_request_form_screen.dart` | Add `docType` + `statusLabel` |
| `test/unit/status_pill_colour_test.dart` | New — colour-map unit tests |
| `test/widget/save_icon_button_test.dart` | New — filled-state widget tests |
| `test/widget/doctype_form_header_test.dart` | New — smoke + label tests |

---

## Task 1: Add `showFilledWhenDirty` to `SaveIconButton`

**Files:**
- Modify: `lib/app/modules/global_widgets/save_icon_button.dart`
- Test: `test/widget/save_icon_button_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widget/save_icon_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SaveIconButton.showFilledWhenDirty', () {
    testWidgets('shows plain IconButton when showFilledWhenDirty is false', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          isDirty: true,
          showFilledWhenDirty: false,
        ),
      ));
      // Plain IconButton — no filled style
      expect(find.byType(IconButton), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      // style should be null (not a filled override)
      expect(btn.style, isNull);
    });

    testWidgets('shows filled IconButton when showFilledWhenDirty is true and dirty', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          isDirty: true,
          showFilledWhenDirty: true,
        ),
      ));
      // Widget renders without error
      expect(find.byType(IconButton), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      // style is set (the filled override)
      expect(btn.style, isNotNull);
    });

    testWidgets('shows plain IconButton when showFilledWhenDirty is true but not dirty', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(
          onPressed: () {},
          isDirty: false,
          showFilledWhenDirty: true,
        ),
      ));
      expect(find.byType(IconButton), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.style, isNull);
    });

    testWidgets('no color: argument on plain IconButton (regression guard for 48e1596b)', (tester) async {
      await tester.pumpWidget(_wrap(
        SaveIconButton(onPressed: () {}, isDirty: true),
      ));
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      // The old bug: color: cs.onPrimary was set explicitly.
      // IconButton.color is the icon color override — must be null.
      expect(btn.color, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
flutter test test/widget/save_icon_button_test.dart -v
```

Expected: FAIL — `showFilledWhenDirty` named parameter does not exist yet.

- [ ] **Step 3: Add `showFilledWhenDirty` param and update the default-icon branch**

In `lib/app/modules/global_widgets/save_icon_button.dart`, make these changes:

**a) Add param to `SaveIconButton`:**

```dart
class SaveIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isSaving;
  final bool isDirty;
  final SaveResult saveResult;
  final String tooltip;
  final bool showFilledWhenDirty;   // ← ADD

  const SaveIconButton({
    super.key,
    required this.onPressed,
    this.isSaving           = false,
    this.isDirty            = true,
    this.saveResult         = SaveResult.idle,
    this.tooltip            = 'Save',
    this.showFilledWhenDirty = false,  // ← ADD, default false keeps existing callers unchanged
  });
```

**b) Replace the entire `// ── Default save icon ─────────` block** (lines 94–103) with:

```dart
    // ── Default save icon ─────────────────────────────────────────────────
    // Filled variant: navy background when dirty and caller opts in.
    // IconButton.filled picks foreground automatically; the only explicit
    // colour here is the background override.  No explicit icon `color:` is
    // ever set — that is the fix from commit 48e1596b and must not regress.
    if (widget.showFilledWhenDirty && widget.isDirty) {
      return IconButton(
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF25286F),
          foregroundColor: Colors.white,
        ),
        icon:      const Icon(Icons.save),
        tooltip:   widget.tooltip,
        onPressed: widget.onPressed,
      );
    }

    // Plain / disabled — no explicit color:
    return IconButton(
      icon:      const Icon(Icons.save),
      tooltip:   widget.tooltip,
      onPressed: widget.isDirty ? widget.onPressed : null,
    );
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/widget/save_icon_button_test.dart -v
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Run analyze**

```
flutter analyze lib/app/modules/global_widgets/save_icon_button.dart
```

Expected: No issues.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/global_widgets/save_icon_button.dart test/widget/save_icon_button_test.dart
git commit -m "feat(global-widgets): add showFilledWhenDirty to SaveIconButton

Adds an opt-in navy filled state (IconButton.filled, #25286F bg) for
when a document has unsaved changes. Default false → all existing call
sites unchanged. No explicit color: argument added to any non-filled
branch (regression guard for commit 48e1596b)."
```

---

## Task 2: Rewrite `StatusPill` with full ERPNext v16 colour map

**Files:**
- Rewrite: `lib/app/modules/global_widgets/status_pill.dart`
- Test: `test/unit/status_pill_colour_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/status_pill_colour_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

void main() {
  group('StatusPill.colourForStatus — ERPNext v16 verbatim', () {
    // Red: surface-red-2 / ink-red-4
    const redBg   = Color(0xFFFFE7E7);
    const redText = Color(0xFFCC2929);
    // Blue: surface-blue-2 / ink-blue-2
    const blueBg   = Color(0xFFE6F4FF);
    const blueText = Color(0xFF0289F7);
    // Orange (amber): surface-amber-1 / ink-amber-3
    const amberBg   = Color(0xFFFDFAED);
    const amberText = Color(0xFFDB7706);
    // Yellow: yellow/100 / yellow/700
    const yellowBg   = Color(0xFFFFF7D3);
    const yellowText = Color(0xFFAB6E05);
    // Green: surface-green-2 / ink-green-3
    const greenBg   = Color(0xFFE4FAEB);
    const greenText = Color(0xFF278F5E);
    // Gray (default): surface-gray-2 / ink-gray-6
    const grayBg   = Color(0xFFF3F3F3);
    const grayText = Color(0xFF525252);

    void expectColour(String status, Color bg, Color text) {
      final colours = StatusPill.colourForStatus(status);
      expect(colours.$1, bg,   reason: 'bg for "$status"');
      expect(colours.$2, text, reason: 'text for "$status"');
    }

    test('Red statuses', () {
      for (final s in ['Draft', 'Cancelled', 'Open', 'Not Started',
                       'Stopped', 'Rejected', 'Expired', 'Overdue']) {
        expectColour(s, redBg, redText);
      }
    });

    test('Blue statuses', () {
      for (final s in ['Submitted', 'Stock Reserved']) {
        expectColour(s, blueBg, blueText);
      }
    });

    test('Amber statuses', () {
      for (final s in ['To Bill', 'On Hold', 'Hold', 'In Process', 'Pending',
                       'Not Saved', 'To Receive and Bill', 'To Receive',
                       'Stock Partially Reserved', 'Material Returned from WIP']) {
        expectColour(s, amberBg, amberText);
      }
    });

    test('Yellow statuses', () {
      for (final s in ['Partially Billed', 'Partly Billed', 'In Transit',
                       'Partially Ordered', 'Partially Received']) {
        expectColour(s, yellowBg, yellowText);
      }
    });

    test('Green statuses', () {
      for (final s in ['Completed', 'Active', 'Paid', 'Settled', 'Enabled',
                       'Closed', 'Ordered', 'Transferred', 'Issued',
                       'Received', 'Goods Transferred']) {
        expectColour(s, greenBg, greenText);
      }
    });

    test('Gray statuses (explicit)', () {
      for (final s in ['In Progress', 'Disabled', 'Passive', 'Return',
                       'Return Issued', 'Goods In Transit', 'To Pay']) {
        expectColour(s, grayBg, grayText);
      }
    });

    test('Unknown status defaults to gray', () {
      expectColour('SomeUnknownStatus', grayBg, grayText);
    });

    // Regression: the 4 previously-wrong colour assignments
    test('Submitted is BLUE (was green)', () => expectColour('Submitted', blueBg, blueText));
    test('Open is RED (was blue)',        () => expectColour('Open',      redBg,  redText));
    test('Closed is GREEN (was gray)',    () => expectColour('Closed',    greenBg, greenText));
    test('In Progress is GRAY (was blue)', () => expectColour('In Progress', grayBg, grayText));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
flutter test test/unit/status_pill_colour_test.dart -v
```

Expected: FAIL — `StatusPill.colourForStatus` does not exist yet.

- [ ] **Step 3: Rewrite `status_pill.dart`**

Replace the entire contents of `lib/app/modules/global_widgets/status_pill.dart` with:

```dart
import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String status;

  /// When true, renders a compact 14dp-high variant for collapsed toolbars.
  final bool compact;

  const StatusPill({super.key, required this.status, this.compact = false});

  // ── Frappe UI design tokens (ERPNext v16 verbatim) ────────────────────────
  // surface-red-2 / ink-red-4
  static const _redBg    = Color(0xFFFFE7E7);
  static const _redText  = Color(0xFFCC2929);
  // surface-blue-2 / ink-blue-2
  static const _blueBg   = Color(0xFFE6F4FF);
  static const _blueText = Color(0xFF0289F7);
  // surface-amber-1 / ink-amber-3
  static const _amberBg   = Color(0xFFFDFAED);
  static const _amberText = Color(0xFFDB7706);
  // yellow/100 / yellow/700
  static const _yellowBg   = Color(0xFFFFF7D3);
  static const _yellowText = Color(0xFFAB6E05);
  // surface-green-2 / ink-green-3
  static const _greenBg   = Color(0xFFE4FAEB);
  static const _greenText = Color(0xFF278F5E);
  // surface-gray-2 / ink-gray-6  (default for unknown statuses)
  static const _grayBg   = Color(0xFFF3F3F3);
  static const _grayText = Color(0xFF525252);

  /// Returns `(background, textColour)` for the given ERPNext status string.
  ///
  /// Colour sources:
  /// - Red:    indicator.js docstatus==0/2; work_order_list.js; guess_style danger
  /// - Blue:   indicator.js docstatus==1; work_order_list.js
  /// - Amber:  delivery_note_list.js; purchase_order_list.js; work_order_list.js;
  ///           material_request_list.js; stock_entry_list.js; indicator.js __unsaved
  /// - Yellow: delivery_note_list.js; purchase_receipt_list.js;
  ///           material_request_list.js
  /// - Green:  all list views; guess_style success
  /// - Gray:   guess_style (no keyword match); explicit list view returns
  static (Color, Color) colourForStatus(String status) {
    switch (status) {
      // ── Red ───────────────────────────────────────────────────────────────
      case 'Draft':
      case 'Cancelled':
      case 'Open':
      case 'Not Started':
      case 'Stopped':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
        return (_redBg, _redText);

      // ── Blue ──────────────────────────────────────────────────────────────
      case 'Submitted':
      case 'Stock Reserved':
        return (_blueBg, _blueText);

      // ── Amber (orange) ────────────────────────────────────────────────────
      case 'To Bill':
      case 'On Hold':
      case 'Hold':
      case 'In Process':
      case 'Pending':
      case 'Not Saved':
      case 'To Receive and Bill':
      case 'To Receive':
      case 'Stock Partially Reserved':
      case 'Material Returned from WIP':
        return (_amberBg, _amberText);

      // ── Yellow ────────────────────────────────────────────────────────────
      case 'Partially Billed':
      case 'Partly Billed':
      case 'In Transit':
      case 'Partially Ordered':
      case 'Partially Received':
        return (_yellowBg, _yellowText);

      // ── Green ─────────────────────────────────────────────────────────────
      case 'Completed':
      case 'Active':
      case 'Paid':
      case 'Settled':
      case 'Enabled':
      case 'Closed':
      case 'Ordered':
      case 'Transferred':
      case 'Issued':
      case 'Received':
      case 'Goods Transferred':
        return (_greenBg, _greenText);

      // ── Gray (default) ────────────────────────────────────────────────────
      case 'In Progress':
      case 'Disabled':
      case 'Passive':
      case 'Return':
      case 'Return Issued':
      case 'Goods In Transit':
      case 'To Pay':
      default:
        return (_grayBg, _grayText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, textColour) = colourForStatus(status);
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color:      textColour,
          fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
          fontSize:   compact ? 9 : 11,
          height:     1.0,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/unit/status_pill_colour_test.dart -v
```

Expected: All tests PASS.

- [ ] **Step 5: Run analyze**

```
flutter analyze lib/app/modules/global_widgets/status_pill.dart
```

Expected: No issues.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/global_widgets/status_pill.dart test/unit/status_pill_colour_test.dart
git commit -m "fix(global-widgets): rewrite StatusPill with ERPNext v16 colour map

Fixes 4 incorrect colour assignments (Submitted was green→now blue,
Open was blue→now red, Closed was gray→now green, In Progress was
blue→now gray). Adds 20+ previously-unhandled statuses. Colour hex
values sourced verbatim from Frappe UI tailwind/colors.json tokens and
ERPNext v16 listview JS files. Adds compact variant for collapsed
toolbar pill."
```

---

## Task 3: Rewrite `DocTypeFormHeader` as standalone sliver

**Files:**
- Rewrite: `lib/app/modules/global_widgets/doctype_form_header.dart`
- Test: `test/widget/doctype_form_header_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/widget/doctype_form_header_test.dart`:

```dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

Widget _wrapInSliver(Widget sliver) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(slivers: [
        sliver,
        const SliverToBoxAdapter(
          child: SizedBox(height: 1000), // scrollable content
        ),
      ]),
    ),
  );
}

void main() {
  group('DocTypeFormHeader', () {
    testWidgets('renders doctype label when docType provided', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          docType: 'Work Order',
        ),
      ));
      expect(find.text('WORK ORDER'), findsOneWidget);
    });

    testWidgets('renders status pill when statusLabel provided', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          statusLabel: 'Draft',
        ),
      ));
      expect(find.byType(StatusPill), findsWidgets);
    });

    testWidgets('renders without docType or statusLabel (backwards compat)', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(title: 'WO-2024-00123'),
      ));
      expect(find.byType(StatusPill), findsNothing);
    });

    testWidgets('unsaved indicator visible when canSave and docStatus==0', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          canSave: true,
          docStatus: 0,
        ),
      ));
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    testWidgets('unsaved indicator hidden when canSave but docStatus==1', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(
          title: 'WO-2024-00123',
          canSave: true,
          docStatus: 1,
        ),
      ));
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('emits a single SliverPersistentHeader', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(title: 'TEST-001'),
      ));
      expect(find.byType(SliverPersistentHeader), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
flutter test test/widget/doctype_form_header_test.dart -v
```

Expected: FAIL — `DocTypeFormHeader` does not have `docType` or `statusLabel` params yet.

- [ ] **Step 3: Rewrite `doctype_form_header.dart`**

Replace the entire contents of `lib/app/modules/global_widgets/doctype_form_header.dart` with:

```dart
import 'dart:math' as math;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // clampDouble
import 'package:flutter/services.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

export 'package:multimax/app/data/enums/save_result.dart';

// ── Layout constants ──────────────────────────────────────────────────────────

/// Height of the collapsed two-line toolbar (caption + doc name).
const double _kCollapsedToolbar = 64.0;

/// Height of the single-line expanded toolbar row.
const double _kExpandedToolbar = 56.0;

/// Height of the large-title area (doctype label + doc name + status row).
const double _kExpandedExtra = 96.0;

/// Total height of expanded content = toolbar + large area.
const double _kMaxContent = _kExpandedToolbar + _kExpandedExtra; // 152dp

/// Minimum font size for AutoSizeText in the collapsed toolbar doc-name line.
const double _kAutoSizeMinFont = 11.0;

// ── Public widget ─────────────────────────────────────────────────────────────

/// A standalone sliver header for DocType **form** screens.
///
/// Produces exactly one [SliverPersistentHeader].
///
/// **Expanded state** (user at top):
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  ←  [faded title]             ↻  💾  ↗          │  56dp toolbar
/// ├──────────────────────────────────────────────────┤
/// │  WORK ORDER                                      │  11sp maroon label
/// │  WO-2024-00123                                   │  24sp bold doc name
/// │  [Draft]  ● Unsaved changes                      │  pill + amber indicator
/// └──────────────────────────────────────────────────┘
/// ```
///
/// **Collapsed state** (scrolled):
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  ←  WORK ORDER  [Draft]        ↻  💾  ↗         │  10sp maroon cap + pill
/// │     WO-2024-00123                                │  15sp bold navy name
/// └──────────────────────────────────────────────────┘  64dp total
/// ```
///
/// [docType] and [statusLabel] are nullable so existing call sites that omit
/// them compile and render without the label or pill (no breaking change).
class DocTypeFormHeader extends StatelessWidget {
  final String title;

  /// e.g. `'Work Order'` — shown as uppercase maroon label.
  /// Null → no label rendered.
  final String? docType;

  /// e.g. `'Draft'` — drives [StatusPill].
  /// Null → no pill rendered.
  final String? statusLabel;

  final VoidCallback? onReload;
  final VoidCallback? onSave;
  final VoidCallback? onShare;

  final bool canSave;
  final int docStatus;
  final bool isSaving;
  final SaveResult saveResult;

  final PreferredSizeWidget? bottom;
  final List<Widget>? extraActions;

  const DocTypeFormHeader({
    super.key,
    required this.title,
    this.docType,
    this.statusLabel,
    this.onReload,
    this.onSave,
    this.onShare,
    this.canSave    = false,
    this.docStatus  = 0,
    this.isSaving   = false,
    this.saveResult = SaveResult.idle,
    this.bottom,
    this.extraActions,
  });

  bool get _canSave => canSave && docStatus == 0;

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _DocTypeFormHeaderDelegate(
        title:           title,
        docType:         docType,
        statusLabel:     statusLabel,
        onReload:        onReload,
        onSave:          onSave,
        onShare:         onShare,
        canSave:         _canSave,
        isSaving:        isSaving,
        saveResult:      saveResult,
        bottom:          bottom,
        extraActions:    extraActions,
        statusBarHeight: statusBarHeight,
      ),
    );
  }
}

// ── Delegate ──────────────────────────────────────────────────────────────────

class _DocTypeFormHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final String? docType;
  final String? statusLabel;
  final VoidCallback? onReload;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final bool canSave;
  final bool isSaving;
  final SaveResult saveResult;
  final PreferredSizeWidget? bottom;
  final List<Widget>? extraActions;
  final double statusBarHeight;

  const _DocTypeFormHeaderDelegate({
    required this.title,
    required this.docType,
    required this.statusLabel,
    required this.onReload,
    required this.onSave,
    required this.onShare,
    required this.canSave,
    required this.isSaving,
    required this.saveResult,
    required this.bottom,
    required this.extraActions,
    required this.statusBarHeight,
  });

  double get _bottomHeight => bottom?.preferredSize.height ?? 0.0;

  @override
  double get minExtent => statusBarHeight + _kCollapsedToolbar + _bottomHeight;

  @override
  double get maxExtent => statusBarHeight + _kMaxContent + _bottomHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final shrinkRange = maxExtent - minExtent; // 88dp
    final collapseProgress = shrinkRange > 0
        ? clampDouble(shrinkOffset / shrinkRange, 0.0, 1.0)
        : 1.0;
    final expandProgress = 1.0 - collapseProgress;

    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // ── System UI ────────────────────────────────────────────────────────────
    final surfaceLuminance = colorScheme.surface.computeLuminance();
    final iconBrightness   = surfaceLuminance > 0.5 ? Brightness.dark : Brightness.light;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness:     iconBrightness == Brightness.dark
          ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: iconBrightness,
    );

    // ── Actions (same in both states) ────────────────────────────────────────
    final actions = _buildActions(context);

    // ── Toolbar (animated height 56dp → 64dp) ─────────────────────────────────
    final toolbarHeight = _kExpandedToolbar + 8.0 * collapseProgress;

    final toolbar = SizedBox(
      height: toolbarHeight,
      child: NavigationToolbar(
        leading: _buildLeading(context),
        middle: Stack(
          children: [
            // Expanded middle: faded doc name (opacity fades out on collapse)
            Positioned.fill(
              child: Opacity(
                opacity: expandProgress,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AutoSizeText(
                    title,
                    style: theme.textTheme.titleLarge,
                    maxLines: 2,
                    minFontSize: _kAutoSizeMinFont,
                    overflow: TextOverflow.clip,
                    softWrap: true,
                  ),
                ),
              ),
            ),
            // Collapsed middle: two-line caption + doc name (fades in on collapse)
            Positioned.fill(
              child: Opacity(
                opacity: collapseProgress,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (docType != null)
                          Text(
                            docType!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                              color: Color(0xFF870E18),
                              height: 1.0,
                            ),
                          ),
                        if (docType != null && statusLabel != null)
                          const SizedBox(width: 5),
                        if (statusLabel != null)
                          StatusPill(status: statusLabel!, compact: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    AutoSizeText(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF25286F),
                        height: 1.3,
                      ),
                      maxLines: 1,
                      minFontSize: _kAutoSizeMinFont,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        trailing: actions,
        centerMiddle: false,
        middleSpacing: 8,
      ),
    );

    // ── Large title area (96dp, fades with expandProgress) ───────────────────
    final largeArea = Opacity(
      opacity: expandProgress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (docType != null)
              Text(
                docType!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.77, // 0.07em × 11sp
                  color: Color(0xFF870E18),
                  height: 1.0,
                ),
              ),
            if (docType != null) const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF171717),
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (statusLabel != null) StatusPill(status: statusLabel!),
                if (statusLabel != null && canSave) const SizedBox(width: 8),
                if (canSave) ...[
                  const Text(
                    '● ',
                    style: TextStyle(
                      color: Color(0xFFDB7706),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                  const Text(
                    'Unsaved changes',
                    style: TextStyle(
                      color: Color(0xFFDB7706),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Material(
        color: colorScheme.surface,
        elevation: overlapsContent ? 1.0 : 0.0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: statusBarHeight), // status-bar shield
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: math.max(0.0, _kExpandedExtra * expandProgress),
                    child: largeArea,
                  ),
                  toolbar,
                  if (bottom != null) bottom!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Leading ───────────────────────────────────────────────────────────────
  Widget? _buildLeading(BuildContext context) {
    final parentRoute = ModalRoute.of(context);
    final canPop      = parentRoute?.canPop ?? false;
    if (canPop) {
      return IconButton(
        icon:      const Icon(Icons.arrow_back),
        tooltip:   MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.maybeOf(context)?.maybePop(),
      );
    }
    return null;
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Widget? _buildActions(BuildContext context) {
    final items = <Widget>[
      ...(extraActions ?? []),
      if (onReload != null)
        IconButton(
          icon:      const Icon(Icons.refresh),
          tooltip:   'Reload',
          onPressed: onReload,
        ),
      if (onSave != null)
        SaveIconButton(
          onPressed:          onSave,
          isSaving:           isSaving,
          isDirty:            canSave,
          saveResult:         saveResult,
          tooltip:            'Save',
          showFilledWhenDirty: true,
        ),
      if (onShare != null)
        IconButton(
          icon:      const Icon(Icons.share_outlined),
          tooltip:   'Share',
          onPressed: onShare,
        ),
    ];
    if (items.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: items);
  }

  // ── shouldRebuild ─────────────────────────────────────────────────────────
  @override
  bool shouldRebuild(covariant _DocTypeFormHeaderDelegate old) {
    return title          != old.title          ||
           docType        != old.docType        ||
           statusLabel    != old.statusLabel    ||
           canSave        != old.canSave        ||
           isSaving       != old.isSaving       ||
           saveResult     != old.saveResult     ||
           statusBarHeight != old.statusBarHeight ||
           (extraActions?.length ?? 0) != (old.extraActions?.length ?? 0);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/widget/doctype_form_header_test.dart -v
```

Expected: All 6 tests PASS.

- [ ] **Step 5: Run full test suite and analyze**

```
flutter test
flutter analyze lib/app/modules/global_widgets/doctype_form_header.dart
```

Expected: All tests pass, no analysis issues.

- [ ] **Step 6: Regression grep — no `color:.*onPrimary` in save_icon_button.dart**

```
grep -n "color:.*onPrimary" lib/app/modules/global_widgets/save_icon_button.dart
```

Expected: no output (zero lines).

- [ ] **Step 7: Regression check — doctype_list_header.dart unchanged**

```
git diff lib/app/modules/global_widgets/doctype_list_header.dart
```

Expected: empty diff.

- [ ] **Step 8: Commit**

```
git add lib/app/modules/global_widgets/doctype_form_header.dart test/widget/doctype_form_header_test.dart
git commit -m "feat(global-widgets): rewrite DocTypeFormHeader as standalone sliver

Standalone SliverPersistentHeader (no longer delegates to
DocTypeListHeader). Adds docType label (11sp maroon) and statusLabel
→ StatusPill in both expanded and collapsed states. Collapsed toolbar
is two-line 64dp; expanded toolbar is 56dp with faded title. Unsaved
indicator shown when canSave && docStatus==0. SaveIconButton uses
showFilledWhenDirty: true → navy filled state when dirty."
```

---

## Task 4: Update 6 form screens with `docType` and `statusLabel`

**Files:**
- Modify: `lib/app/modules/work_order/form/work_order_form_screen.dart`
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_screen.dart`
- Modify: `lib/app/modules/delivery_note/form/delivery_note_form_screen.dart`
- Modify: `lib/app/modules/purchase_order/form/purchase_order_form_screen.dart`
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_form_screen.dart`
- Modify: `lib/app/modules/material_request/form/material_request_form_screen.dart`

- [ ] **Step 1: Update `work_order_form_screen.dart`**

Find the `DocTypeFormHeader(` call at line ~36. Add `docType` and `statusLabel` after `title:`:

```dart
DocTypeFormHeader(
  title:       title,
  docType:     'Work Order',       // ADD
  statusLabel: wo?.status,         // ADD
  onSave: controller.canEdit ? controller.save : null,
  onReload: controller.mode != 'new' ? controller.reload : null,
  isSaving:   controller.isSaving.value,
  canSave:    controller.isDirty.value,
  docStatus:  wo?.docstatus ?? 0,
),
```

- [ ] **Step 2: Update `stock_entry_form_screen.dart`**

Find the `DocTypeFormHeader(` call at line ~54. Add `docType` and `statusLabel`:

```dart
DocTypeFormHeader(
  title:       title,
  docType:     'Stock Entry',      // ADD
  statusLabel: entry?.status,      // ADD
  canSave:    isDirty,
  docStatus:  entry?.docstatus ?? 0,
  isSaving:   isSaving,
  saveResult: saveResult,
  onSave:     onSave,
  onReload:   onReload,
  bottom: const TabBar(
    tabs: [Tab(text: 'Details'), Tab(text: 'Items & Scan')],
  ),
),
```

- [ ] **Step 3: Update `delivery_note_form_screen.dart`**

Find the `DocTypeFormHeader(` call at line ~37. Add `docType` and `statusLabel`:

```dart
DocTypeFormHeader(
  title:       note?.name ?? 'Loading...',
  docType:     'Delivery Note',    // ADD
  statusLabel: note?.status,       // ADD
  canSave:    isDirty,
  docStatus:  note?.docstatus ?? 0,
  isSaving:   isSaving,
  saveResult: saveResult,
  onSave:     (note?.docstatus == 0) ? controller.saveDeliveryNote : null,
  onReload: (controller.mode != 'new' && !isDirty)
      ? controller.reloadDocument : null,
  bottom: const TabBar(
    tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
  ),
),
```

- [ ] **Step 4: Update `purchase_order_form_screen.dart`**

Find the `DocTypeFormHeader(` call at line ~35. Add `docType` and `statusLabel`:

```dart
DocTypeFormHeader(
  title:       po?.name ?? 'Loading...',
  docType:     'Purchase Order',   // ADD
  statusLabel: po?.status,         // ADD
  canSave:    isDirty && controller.isEditable,
  docStatus:  po?.docstatus ?? 0,
  isSaving:   isSaving,
  saveResult: saveResult,
  onSave: (isDirty && controller.isEditable)
      ? controller.savePurchaseOrder : null,
  onReload: (controller.mode != 'new' && !isDirty)
      ? controller.reloadDocument : null,
  bottom: const TabBar(
    tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
  ),
),
```

- [ ] **Step 5: Update `purchase_receipt_form_screen.dart`**

Find the `DocTypeFormHeader(` call at line ~37. Add `docType` and `statusLabel`:

```dart
DocTypeFormHeader(
  title:       receipt?.name ?? 'Loading...',
  docType:     'Purchase Receipt', // ADD
  statusLabel: receipt?.status,    // ADD
  canSave:    isDirty,
  docStatus:  receipt?.docstatus ?? 0,
  isSaving:   isSaving,
  saveResult: saveResult,
  onSave: (receipt?.docstatus == 0 && isDirty)
      ? controller.savePurchaseReceipt : null,
  onReload: (controller.mode != 'new' && !isDirty)
      ? controller.reloadDocument : null,
  bottom: const TabBar(
    tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
  ),
),
```

- [ ] **Step 6: Update `material_request_form_screen.dart`**

Find the `DocTypeFormHeader(` call at line ~54. Add `docType` and `statusLabel`:

```dart
DocTypeFormHeader(
  title:       title,
  docType:     'Material Request', // ADD
  statusLabel: entry?.status,      // ADD
  canSave:    isDirty,
  docStatus:  entry?.docstatus ?? 0,
  isSaving:   isSaving,
  saveResult: saveResult,
  onSave:     onSave,
  onReload:   onReload,
```

(Leave the rest of the existing arguments and the `bottom: TabBar(...)` in place.)

- [ ] **Step 7: Run flutter analyze across all 6 screens**

```
flutter analyze lib/app/modules/work_order/form/work_order_form_screen.dart lib/app/modules/stock_entry/form/stock_entry_form_screen.dart lib/app/modules/delivery_note/form/delivery_note_form_screen.dart lib/app/modules/purchase_order/form/purchase_order_form_screen.dart lib/app/modules/purchase_receipt/form/purchase_receipt_form_screen.dart lib/app/modules/material_request/form/material_request_form_screen.dart
```

Expected: No issues.

- [ ] **Step 8: Run full test suite**

```
flutter test
```

Expected: All tests pass.

- [ ] **Step 9: Final regression checks**

```
grep -rn "color:.*onPrimary" lib/app/modules/global_widgets/save_icon_button.dart
git diff lib/app/modules/global_widgets/doctype_list_header.dart
```

Expected: Both return empty output.

- [ ] **Step 10: Commit**

```
git add lib/app/modules/work_order/form/work_order_form_screen.dart lib/app/modules/stock_entry/form/stock_entry_form_screen.dart lib/app/modules/delivery_note/form/delivery_note_form_screen.dart lib/app/modules/purchase_order/form/purchase_order_form_screen.dart lib/app/modules/purchase_receipt/form/purchase_receipt_form_screen.dart lib/app/modules/material_request/form/material_request_form_screen.dart
git commit -m "feat(form-screens): add docType and statusLabel to all 6 form headers

Each DocTypeFormHeader now receives its docType string and the live
status field from the document model so the standalone header can
display the maroon label and status pill in both expanded and
collapsed states."
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Task covering it |
|---|---|
| Two-line collapsed toolbar (64dp) | Task 3 — `_kCollapsedToolbar = 64.0`, `_kExpandedToolbar + 8*collapseProgress` |
| Doc-type label 11sp maroon `#870E18` | Task 3 — `largeArea` section, `fontSize: 11, color: Color(0xFF870E18)` |
| Doc name 24sp/800 in expanded | Task 3 — `fontSize: 24, fontWeight: FontWeight.w800` |
| Doc name 15sp/700 navy in collapsed | Task 3 — `fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF25286F)` |
| Status pill in both states | Task 3 — `StatusPill` in `largeArea` (full) and `collapsedMid` (compact) |
| Unsaved indicator amber `#DB7706` | Task 3 — `canSave` guard, `Color(0xFFDB7706)` |
| Save button navy filled when dirty | Task 1 — `showFilledWhenDirty`, Task 3 — `showFilledWhenDirty: true` on `SaveIconButton` |
| ERPNext v16 colour map verbatim | Task 2 — all 30+ statuses in `colourForStatus` |
| `DocTypeListHeader` untouched | Tasks 3/4 — only `doctype_form_header.dart` rewritten |
| 6 form screens wired | Task 4 — all 6 screens updated |
| `color: cs.onPrimary` regression guard | Task 1 step 6 grep, Task 3 step 6 grep |
| `docType`/`statusLabel` nullable | Task 3 — both `String?`, compile with/without |
| `compact` pill variant 14dp/9sp | Task 2 — `compact: true` branch |
| `shouldRebuild` correct fields | Task 3 — 8 fields compared |
| No `Obx` wrapper in form header | Task 3 — no `Obx` anywhere in `DocTypeFormHeader` |

### Placeholder scan

None — all steps have complete code.

### Type consistency

- `StatusPill` new API: `compact: bool = false` (Task 2), consumed in Task 3 `StatusPill(status: statusLabel!, compact: true)`
- `SaveIconButton` new API: `showFilledWhenDirty: bool = false` (Task 1), consumed in Task 3 `showFilledWhenDirty: true`
- `DocTypeFormHeader` new API: `docType: String?`, `statusLabel: String?` (Task 3), wired in Task 4
- `StatusPill.colourForStatus` returns `(Color, Color)` record — consumed in `build()` with destructuring `final (bg, textColour) = colourForStatus(status)`
