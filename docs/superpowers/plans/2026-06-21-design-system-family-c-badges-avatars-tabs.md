# Design System — Family C: Badges · Avatars · Tabs (+ StatusPill dark mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring status pills, badges, avatars, and tabs onto the ERPNext v15 token system with full dark-mode support — the most impactful piece being `StatusPill`, which is hardcoded light tints used in 15+ places and currently breaks in dark mode.

**Architecture:** Migrate `StatusPill` to compute colors from the merged `AppColors` status ramp (status @13% over `scheme.fg` for bg; text `<hue>700` in light / `<hue>300` in dark, by `Theme.of(context).brightness`) and add the ds.css `.pill` leading dot. Update `status_pill_colour_test.dart` to the new canonical palette (this resolves the 7 long-standing failing tests). Add two new shared widgets — `CountBadge` and `AppAvatar`/`AvatarGroup` — and adopt them at safe, clearly-beneficial sites. Polish the global `tabBarTheme` to the ds.css tab spec.

**Tech Stack:** Flutter (Material 3), GetX, merged `app_theme.dart` (`AppColors`, `AppScheme`, `AppRadius`, `AppSpace`, `context.scheme`).

## Global Constraints

- **Keep maroon.** Brand primary stays maroon. Status hues come from `AppColors` (red/blue/green/orange/yellow/gray ramps at 300/500/700). No blue-as-primary.
- **Light + dark both mandatory.** New/changed widgets resolve via `context.scheme` + `Theme.of(context).brightness`. No new hardcoded hex/`Colors.*` literals — EXCEPT the two intrinsic badge colors the spec mandates: `CountBadge` uses `AppColors.red500` bg + `Colors.white` text (ds.css `.count-badge` = red500/#fff). Document that inline.
- **ds.css status dark-mode swap:** only the *text* color changes light→dark (`<hue>700` → `<hue>300`); the bg formula (`<hue>500` @13% over `fg`) and the dot color (`<hue>500`) are the same in both — `fg` itself differs by theme. Pill bg blend is **13%** (ds.css authoritative).
- **Do NOT touch `home_screen.dart`** (it has fresh unrelated dashboard work) — adopt `CountBadge` only at the header filter badge.
- **No blanket CircleAvatar sweep** — build `AppAvatar`/`AvatarGroup` and adopt only in the drawer header + profile screen.
- **Public APIs:** `StatusPill` keeps its constructor (`{required String status, bool compact}`); the static `colourForStatus` gains an optional `{Brightness brightness}` param (default `Brightness.light`) so existing callers and the test keep working.
- Each task: `flutter analyze` clean on touched files; tests pass. Run from repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`.
- After Task 1, the 7 `status_pill_colour_test.dart` failures should be GONE (rewritten to the new palette). The 1 `doctype_form_header_test.dart` failure remains pre-existing/out of scope.

### Status hue mapping (preserve current assignments)
red: Draft, Cancelled, Canceled, Open, Stopped, Rejected, Expired, Overdue · blue: Submitted, Enabled, Stock Reserved, Material Transferred · orange: Not Saved, Not Started, To Bill, On Hold, Hold, In Process, Work In Progress, Pending, To Receive and Bill, To Receive, Stock Partially Reserved, Material Returned from WIP · yellow: Partially Billed, Partly Billed, In Transit, Partially Ordered, Partially Received · green: Completed, Active, Paid, Settled, Closed, Ordered, Transferred, Issued, Received, Goods Transferred · gray (default): In Progress, Disabled, Passive, Return, Return Issued, Goods In Transit, To Pay, + unknown.

---

### Task 1: `StatusPill` dark mode + ramp colors + leading dot (+ test rewrite)

**Files:**
- Modify: `lib/app/modules/global_widgets/status_pill.dart`
- Modify: `test/unit/status_pill_colour_test.dart` (rewrite expected values to the new canonical palette)

**Interfaces:**
- Consumes: `AppColors` (status ramps), `AppScheme` (`.fg`), `context.scheme`.
- Produces:
  - `static (Color bg, Color text) colourForStatus(String status, {Brightness brightness = Brightness.light})` — bg = `Color.alphaBlend(<hue>500.withValues(alpha: 0.13), AppScheme.of(brightness).fg)`; text = brightness dark ? `<hue>300` : `<hue>700`.
  - `static Color dotColorForStatus(String status)` — the `<hue>500` base (for the leading dot).
  - `StatusPill` build renders a leading dot + label, colors resolved for the active brightness.

- [ ] **Step 1: Rewrite the failing test to the canonical palette**

Replace the body of `test/unit/status_pill_colour_test.dart` with assertions computed from the ramp (self-consistent, so they stay correct if the ramp changes). Keep the status→hue group coverage and add a dark-mode case:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

(Color, Color) _expected(Color base500, Color text700, Color text300, Brightness b) {
  final fg = AppScheme.of(b).fg;
  final bg = Color.alphaBlend(base500.withValues(alpha: 0.13), fg);
  return (bg, b == Brightness.dark ? text300 : text700);
}

void main() {
  group('StatusPill.colourForStatus — ERPNext v15 ramp (light)', () {
    test('Red statuses', () {
      expect(StatusPill.colourForStatus('Open'),
          _expected(AppColors.red500, AppColors.red700, AppColors.red300, Brightness.light));
    });
    test('Blue statuses', () {
      expect(StatusPill.colourForStatus('Submitted'),
          _expected(AppColors.blue500, AppColors.blue700, AppColors.blue300, Brightness.light));
    });
    test('Orange statuses', () {
      expect(StatusPill.colourForStatus('On Hold'),
          _expected(AppColors.orange500, AppColors.orange700, AppColors.orange300, Brightness.light));
    });
    test('Yellow statuses', () {
      expect(StatusPill.colourForStatus('In Transit'),
          _expected(AppColors.yellow500, AppColors.yellow700, AppColors.yellow300, Brightness.light));
    });
    test('Green statuses', () {
      expect(StatusPill.colourForStatus('Completed'),
          _expected(AppColors.green500, AppColors.green700, AppColors.green300, Brightness.light));
    });
    test('Gray default for unknown', () {
      expect(StatusPill.colourForStatus('Wibble'),
          _expected(AppColors.gray500, AppColors.gray700, AppColors.gray300, Brightness.light));
    });
  });

  group('dark mode swaps text to the 300 ramp', () {
    test('Open in dark uses red300 text on dark-fg blend', () {
      expect(StatusPill.colourForStatus('Open', brightness: Brightness.dark),
          _expected(AppColors.red500, AppColors.red700, AppColors.red300, Brightness.dark));
    });
  });

  group('status group assignments preserved', () {
    test('Open=red, Submitted=blue, Closed=green, In Progress=gray', () {
      expect(StatusPill.colourForStatus('Open').$2, AppColors.red700);
      expect(StatusPill.colourForStatus('Submitted').$2, AppColors.blue700);
      expect(StatusPill.colourForStatus('Closed').$2, AppColors.green700);
      expect(StatusPill.colourForStatus('In Progress').$2, AppColors.gray700);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/status_pill_colour_test.dart`
Expected: FAIL — current `colourForStatus` returns the old Frappe-v15 constants and has no `brightness` param.

- [ ] **Step 3: Rewrite `StatusPill`**

Replace `lib/app/modules/global_widgets/status_pill.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// ERPNext v15 status indicator pill. Colors come from the [AppColors] status
/// ramp: background = `<hue>500` @13% over the surface, text = `<hue>700` in
/// light / `<hue>300` in dark, with a leading `<hue>500` dot. Resolves to the
/// active brightness so it renders correctly in both themes.
class StatusPill extends StatelessWidget {
  final String status;

  /// Compact 14dp-high variant for collapsed toolbars.
  final bool compact;

  const StatusPill({super.key, required this.status, this.compact = false});

  /// The status ramp triple `(base500, text700, text300)` for a status string.
  static (Color, Color, Color) _ramp(String status) {
    switch (status) {
      case 'Draft':
      case 'Cancelled':
      case 'Canceled':
      case 'Open':
      case 'Stopped':
      case 'Rejected':
      case 'Expired':
      case 'Overdue':
        return (AppColors.red500, AppColors.red700, AppColors.red300);
      case 'Submitted':
      case 'Enabled':
      case 'Stock Reserved':
      case 'Material Transferred':
        return (AppColors.blue500, AppColors.blue700, AppColors.blue300);
      case 'Not Saved':
      case 'Not Started':
      case 'To Bill':
      case 'On Hold':
      case 'Hold':
      case 'In Process':
      case 'Work In Progress':
      case 'Pending':
      case 'To Receive and Bill':
      case 'To Receive':
      case 'Stock Partially Reserved':
      case 'Material Returned from WIP':
        return (AppColors.orange500, AppColors.orange700, AppColors.orange300);
      case 'Partially Billed':
      case 'Partly Billed':
      case 'In Transit':
      case 'Partially Ordered':
      case 'Partially Received':
        return (AppColors.yellow500, AppColors.yellow700, AppColors.yellow300);
      case 'Completed':
      case 'Active':
      case 'Paid':
      case 'Settled':
      case 'Closed':
      case 'Ordered':
      case 'Transferred':
      case 'Issued':
      case 'Received':
      case 'Goods Transferred':
        return (AppColors.green500, AppColors.green700, AppColors.green300);
      case 'In Progress':
      case 'Disabled':
      case 'Passive':
      case 'Return':
      case 'Return Issued':
      case 'Goods In Transit':
      case 'To Pay':
      default:
        return (AppColors.gray500, AppColors.gray700, AppColors.gray300);
    }
  }

  /// `(background, textColour)` for [status] at the given [brightness].
  static (Color, Color) colourForStatus(String status,
      {Brightness brightness = Brightness.light}) {
    final (base, text700, text300) = _ramp(status);
    final fg = AppScheme.of(brightness).fg;
    final bg = Color.alphaBlend(base.withValues(alpha: 0.13), fg);
    return (bg, brightness == Brightness.dark ? text300 : text700);
  }

  /// The leading-dot color (`<hue>500`) for [status].
  static Color dotColorForStatus(String status) => _ramp(status).$1;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final (bg, textColour) = colourForStatus(status, brightness: brightness);
    final dot = dotColorForStatus(status);
    final dotSize = compact ? 6.0 : 7.0;

    return Container(
      constraints: compact ? const BoxConstraints(minHeight: 14) : null,
      // ds.css .pill padding 5/11/5/9 (less left because of the dot); compact scales down.
      padding: compact
          ? const EdgeInsets.fromLTRB(7, 2, 9, 2)
          : const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 5 : 7),
          Flexible(
            child: Text(
              status,
              style: TextStyle(
                color: textColour,
                fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                fontSize: compact ? 9 : 11,
                height: 1.0,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/status_pill_colour_test.dart`
Expected: PASS (all groups). The previously-failing 7 are now aligned to the ramp.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/status_pill.dart test/unit/status_pill_colour_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/status_pill.dart test/unit/status_pill_colour_test.dart
git commit -m "feat(theme): StatusPill dark-mode via AppColors ramp + leading dot; align colour test"
```

---

### Task 2: `CountBadge`

**Files:**
- Create: `lib/app/modules/global_widgets/count_badge.dart`
- Test: `test/widget/count_badge_test.dart`
- Modify: `lib/app/modules/global_widgets/doctype_list_header.dart` (replace the Material `Badge` on the filter button)

**Interfaces:**
- Consumes: `AppColors.red500`, `context.scheme`, `AppRadius`.
- Produces: `class CountBadge extends StatelessWidget` — `const CountBadge({Key?, required int count, bool muted = false})`. Default = red500 bg + white text; `muted` = `scheme.textSubtle` bg (for tab counts).

- [ ] **Step 1: Write the failing test**

Create `test/widget/count_badge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';

Widget _host(Widget child, {Brightness b = Brightness.light}) =>
    MaterialApp(theme: ThemeData(brightness: b), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders the count', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 3)));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('default variant uses red500 background', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 1)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('1'), matching: find.byType(Container)).first);
    expect((box.decoration as BoxDecoration).color, AppColors.red500);
  });

  testWidgets('muted variant uses scheme.textSubtle background', (tester) async {
    await tester.pumpWidget(_host(const CountBadge(count: 9, muted: true)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('9'), matching: find.byType(Container)).first);
    expect((box.decoration as BoxDecoration).color, AppScheme.light.textSubtle);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/count_badge_test.dart`
Expected: FAIL — `count_badge.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/app/modules/global_widgets/count_badge.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A notification/count badge (ERPNext v15 `.count-badge`): 18px min, pill
/// shaped, red500 bg + white text by default; [muted] uses `scheme.textSubtle`
/// for quieter tab counts.
class CountBadge extends StatelessWidget {
  final int count;
  final bool muted;

  const CountBadge({super.key, required this.count, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    // ds.css .count-badge is intrinsically red500/#fff; muted swaps the bg only.
    final bg = muted ? s.textSubtle : AppColors.red500;
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/count_badge_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Adopt in the list header filter badge**

In `lib/app/modules/global_widgets/doctype_list_header.dart`, the filter button currently wraps its `IconButton.filled` in a Material `Badge(label: Text('$count'), child: ...)` (~line 632). Add the import:
```dart
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
```
and replace the `Badge(label: Text('$count'), child: <button>)` with a `Stack` placing a `CountBadge(count: <count>)` at the top-right of the button:
```dart
            Stack(
              clipBehavior: Clip.none,
              children: [
                <the existing IconButton.filled widget>,
                if (<count> > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: CountBadge(count: <count>),
                  ),
              ],
            )
```
Use the same count expression the existing `Badge` used (`activeFilters!.length`). Keep the surrounding `Obx`/active-filter gating intact. Do not change the non-filtered (plain `Icons.filter_list`) branch.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/count_badge.dart test/widget/count_badge_test.dart lib/app/modules/global_widgets/doctype_list_header.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/global_widgets/count_badge.dart test/widget/count_badge_test.dart lib/app/modules/global_widgets/doctype_list_header.dart
git commit -m "feat(theme): add CountBadge; use it for the list-header filter count"
```

---

### Task 3: `AppAvatar` + `AvatarGroup`

**Files:**
- Create: `lib/app/modules/global_widgets/app_avatar.dart`
- Test: `test/widget/app_avatar_test.dart`
- Modify: `lib/app/modules/profile/user_profile_screen.dart` (the main header avatar, ~line 54)

**Interfaces:**
- Consumes: `context.scheme` (`primary`, `fg`), `AppRadius`.
- Produces:
  - `class AppAvatar extends StatelessWidget` — `const AppAvatar({Key?, String? initials, ImageProvider? image, double size = 36, bool square = false})`. Circle (or `AppRadius.md` if square), bg = `primary` @16% over `fg`, initials in `primary` w600.
  - `class AvatarGroup extends StatelessWidget` — `const AvatarGroup({Key?, required List<Widget> children})`. Overlaps children by -10 with a 2px `fg` ring each.

- [ ] **Step 1: Write the failing test**

Create `test/widget/app_avatar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';

Widget _host(Widget child, {Brightness b = Brightness.light}) =>
    MaterialApp(theme: ThemeData(brightness: b), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows initials in primary over a primary-tinted bg', (tester) async {
    await tester.pumpWidget(_host(const AppAvatar(initials: 'AM')));
    expect(find.text('AM'), findsOneWidget);
    final txt = tester.widget<Text>(find.text('AM'));
    expect(txt.style?.color, AppScheme.light.primary);
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('AM'), matching: find.byType(Container)).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color,
        Color.alphaBlend(AppScheme.light.primary.withValues(alpha: 0.16), AppScheme.light.fg));
    expect(deco.shape, BoxShape.circle);
  });

  testWidgets('square uses rounded rect not circle', (tester) async {
    await tester.pumpWidget(_host(const AppAvatar(initials: 'X', square: true)));
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('X'), matching: find.byType(Container)).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.shape, BoxShape.rectangle);
    expect(deco.borderRadius, BorderRadius.circular(AppRadius.md));
  });

  testWidgets('AvatarGroup renders all children', (tester) async {
    await tester.pumpWidget(_host(const AvatarGroup(children: [
      AppAvatar(initials: 'A'), AppAvatar(initials: 'B'), AppAvatar(initials: 'C'),
    ])));
    expect(find.byType(AppAvatar), findsNWidgets(3));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/app_avatar_test.dart`
Expected: FAIL — `app_avatar.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/app/modules/global_widgets/app_avatar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// ERPNext v15 avatar: primary-tinted circle (or rounded square) showing 1–2
/// letter initials in `primary`, or an image. Colors from [BuildContext.scheme].
class AppAvatar extends StatelessWidget {
  final String? initials;
  final ImageProvider? image;
  final double size;
  final bool square;

  const AppAvatar({
    super.key,
    this.initials,
    this.image,
    this.size = 36,
    this.square = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final bg = Color.alphaBlend(s.primary.withValues(alpha: 0.16), s.fg);
    final label = (initials ?? '').trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: image == null ? bg : null,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(AppRadius.md) : null,
        image: image != null
            ? DecorationImage(image: image!, fit: BoxFit.cover)
            : null,
      ),
      child: image != null || label.isEmpty
          ? null
          : Text(
              label.length > 2 ? label.substring(0, 2).toUpperCase() : label.toUpperCase(),
              style: TextStyle(
                color: s.primary,
                fontWeight: FontWeight.w600,
                fontSize: size * 0.34,
                height: 1.0,
              ),
            ),
    );
  }
}

/// A row of overlapping [AppAvatar]s (assignees / shared-with). Each overlaps
/// the previous by [overlap] px and carries a 2px `fg` ring; rendered with a
/// Stack so the overlap actually reclaims horizontal space (a Row cannot do
/// negative spacing). Assumes each child is [avatarSize] wide.
class AvatarGroup extends StatelessWidget {
  final List<Widget> children;
  final double avatarSize;
  final double overlap;

  const AvatarGroup({
    super.key,
    required this.children,
    this.avatarSize = 36,
    this.overlap = 10,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    const ring = 2.0;
    final step = avatarSize - overlap; // horizontal advance per avatar
    final ringed = avatarSize + ring * 2;
    final width = children.isEmpty ? 0.0 : ringed + step * (children.length - 1);
    return SizedBox(
      height: ringed,
      width: width,
      child: Stack(
        children: [
          for (var i = 0; i < children.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: s.fg, width: ring),
                ),
                child: children[i],
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/app_avatar_test.dart`
Expected: PASS (3/3). If the `AvatarGroup` overlap implementation trips a layout error, switch to the `Stack`+`Positioned` approach noted above.

- [ ] **Step 5: Adopt in the profile header**

In `lib/app/modules/profile/user_profile_screen.dart` (~line 54), the header `CircleAvatar(radius: 56, backgroundColor: primary.withValues(alpha: 0.1), backgroundImage: ..., child: ...)` wrapped in a primary ring is the closest existing match. Replace it with `AppAvatar(size: 112, initials: <existing initial(s)>, image: <existing NetworkImage if present>)`. Add the import. Preserve the surrounding layout (the outer ring `Container` may be kept or dropped — AppAvatar already renders the tinted circle). Keep behavior identical (tap/edit affordances, if any, stay).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/app_avatar.dart test/widget/app_avatar_test.dart lib/app/modules/profile/user_profile_screen.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/global_widgets/app_avatar.dart test/widget/app_avatar_test.dart lib/app/modules/profile/user_profile_screen.dart
git commit -m "feat(theme): add AppAvatar + AvatarGroup; adopt in profile header"
```

---

### Task 4: Polish the tab theme to the ds.css spec

**Files:**
- Modify: `lib/main.dart` (`buildAppTheme` → `tabBarTheme`)
- Test: `test/widget/theme_mode_switching_test.dart` (add tab-theme assertions to the existing file)

**Interfaces:**
- Consumes: `AppScheme` (`primary`, `textMuted`, `border`).
- Produces: a `tabBarTheme` matching ds.css `.tab`: selected `primary` text + 2px primary indicator (sized to the tab), unselected `textMuted`, a 1px `border` divider under the tab row, label weight 500.

**Context:** current `buildAppTheme` sets `tabBarTheme: TabBarThemeData(labelColor: scheme.primary, unselectedLabelColor: scheme.textMuted, indicatorColor: scheme.primary, labelStyle: TextStyle(fontWeight: FontWeight.w600))`. This applies to all 9 form-screen TabBars at once.

- [ ] **Step 1: Add failing assertions to the theme test**

In `test/widget/theme_mode_switching_test.dart`, add a test:

```dart
  testWidgets('tabBarTheme matches ds.css tab spec', (tester) async {
    final t = buildAppTheme(AppScheme.light, Brightness.light);
    final tb = t.tabBarTheme;
    expect(tb.labelColor, AppScheme.light.primary);
    expect(tb.unselectedLabelColor, AppScheme.light.textMuted);
    expect(tb.indicatorColor, AppScheme.light.primary);
    expect(tb.indicatorSize, TabBarIndicatorSize.tab);
    expect(tb.dividerColor, AppScheme.light.border);
    expect(tb.labelStyle?.fontWeight, FontWeight.w500);
  });
```
(Ensure `import 'package:multimax/app/data/constants/app_theme.dart';` and `main.dart` are imported — they already are in this file.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/theme_mode_switching_test.dart`
Expected: the new test FAILS (no `indicatorSize`/`dividerColor`; labelStyle weight is w600).

- [ ] **Step 3: Update `tabBarTheme` in `buildAppTheme`**

In `lib/main.dart`, change the `tabBarTheme:` to:

```dart
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.textMuted,
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: scheme.border,
      labelStyle: const TextStyle(fontWeight: FontWeight.w500),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
    ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/theme_mode_switching_test.dart`
Expected: PASS (existing theme tests + the new tab-theme test).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/main.dart test/widget/theme_mode_switching_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart test/widget/theme_mode_switching_test.dart
git commit -m "feat(theme): tab theme to ds.css spec (2px tab indicator, border divider, weight 500)"
```

---

## Self-Review

**1. Spec coverage (handoff §4 + decisions):**
- `StatusBadge`/status dark mode → Task 1 polishes the canonical status component `StatusPill` (the handoff's "indicator pill") onto the ramp with the 700/300 dark swap + leading dot. ✔ (also fixes the 7 failing tests)
- `CountBadge` → Task 2 (+ adopted in the header filter badge). ✔
- `AppAvatar` + `AvatarGroup` → Task 3 (+ adopted in profile). ✔
- `DocTabBar` → Task 4 (global `tabBarTheme` polish, which is how all 9 form TabBars are styled). ✔
- **Deferred (documented, YAGNI / risk):** a separate `StatusBadge` metadata-chip widget distinct from `StatusPill` (the handoff notes pills are the canonical status component; no current consumer needs a separate metadata badge); a bespoke count-in-label `DocTabBar` widget (no tab currently shows a count — `CountBadge` exists for when one is added); blanket `CircleAvatar` migration across the ~15 sites (they work via theme; only profile adopted); `CountBadge` adoption in `home_screen.dart` (avoided — fresh dashboard work there).

**2. Placeholder scan:** No "TBD"/"add error handling". Every step has real code or the exact edit. The one intentionally-flexible spot is `AvatarGroup`'s overlap (Transform vs Stack) — both concrete options given with the passing-test criterion.

**3. Type consistency:** `colourForStatus(status, {brightness})` defined in Task 1, consumed by its test + `StatusPill.build`. `CountBadge({count, muted})` defined Task 2, consumed in header. `AppAvatar({initials, image, size, square})` / `AvatarGroup({children})` defined Task 3, consumed in profile. All colors via `context.scheme`/`AppColors` fields that exist on the merged foundation.

---

## Execution Handoff

Family C — the final family. Builds on the merged foundation + Families A & B. After this ships, the global-components rollout (handoff families A/B/C) is complete; remaining items are the documented on-device smoke checks.
