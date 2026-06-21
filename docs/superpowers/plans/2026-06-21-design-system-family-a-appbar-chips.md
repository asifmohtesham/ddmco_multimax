# Design System — Family A: App Bar & Filter Chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the ERPNext v15 visual language to the app-bar / filter-chip surfaces using the merged design tokens: restyle the shared filter chip to the maroon-tinted "active" spec, repaint the form-screen header as a solid-maroon bar, and tokenize the drawer so it renders correctly in dark mode.

**Architecture:** The light/dark foundation is already merged (`lib/app/data/constants/app_theme.dart`: `AppColors`, `AppScheme.light/dark`, `AppRadius`, `AppSpace`, `context.scheme`). The list header (`DocTypeListHeader`) is already theme-aware and owns the filter-chip-row contract — it is NOT changed here. All list screens feed it chips through one shared widget (`FilterChipWidget`), so restyling that single widget restyles every screen. The form header (`DocTypeFormHeader`) and the drawer (`AppNavDrawer`) read colors from `Theme.of(context).colorScheme` / hardcoded literals today; this plan points the form header at a solid-primary look and the drawer at `context.scheme`.

**Tech Stack:** Flutter (Material 3), GetX, the merged `app_theme.dart` tokens.

## Global Constraints

- **Keep maroon.** Use `context.scheme.primary` (maroon `#870E18` light / `#D9707C` dark). Never introduce ERPNext blue. (Exception: the existing intentionally-blue Submit button in `DocTypeFormHeader` stays blue.)
- **Light + dark both mandatory.** Every changed surface must resolve correctly in both brightnesses — read colors from `context.scheme` (or `Theme.of(context).colorScheme`, which the merged themes already drive from `AppScheme`). No new hardcoded hex/`Colors.*` literals at the surfaces this plan touches.
- **Filter chips = maroon-tinted "active" style** (ds.css `.chip.active`): bg = `primary` @12% over `fg`, border = `primary` @40% over `border`, text+icon = `primary`, trailing `×` 15px @0.7 opacity. Height 34, radius `AppRadius.full`, font 12 / weight 500, internal gap 6, padding L12/R10.
- **Form header = solid maroon** (ds.css `.appbar.solid`): background `colorScheme.primary`; all title/label/icon content in `colorScheme.onPrimary`. Status-bar icon brightness keys off `primary` luminance.
- **Do not change** `DocTypeListHeader` or the chip-row contract (`filterChipsBuilder`/`activeFilters`/`onFilterTap`/`onClearAllFilters`). Do not change any list/form *screen* file — the shared widgets carry the change.
- Each task: `flutter analyze` clean on touched files; its tests pass. Run from repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`.
- Pre-existing unrelated suite failures (7 in `status_pill_colour_test.dart`, 1 in `doctype_form_header_test.dart`) are a known baseline — do not let the count grow beyond them.

### Token → value quick reference (from app_theme.dart)
`context.scheme` fields: `bg, fg, subtle, text, textMuted, textSubtle, border, borderStrong, primary, onPrimary, secondary`. `AppRadius.full = 999`. `AppSpace.s2=8, s3=12`.

---

### Task 1: Restyle `FilterChipWidget` to the maroon-tinted active spec

**Files:**
- Modify: `lib/app/modules/global_widgets/filter_chip_widget.dart` (full rewrite of the build; constructor unchanged)
- Test: `test/widget/filter_chip_widget_test.dart` (create)

**Interfaces:**
- Consumes: `context.scheme`, `AppRadius` from `app_theme.dart`.
- Produces: `FilterChipWidget({required IconData icon, required String label, required VoidCallback onDeleted})` — **unchanged public API** (every list screen already constructs it this way; do not add/remove params).

- [ ] **Step 1: Write the failing test**

Create `test/widget/filter_chip_widget_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('renders label, icon and a close affordance', (tester) async {
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: FilterChipWidget(
          icon: Icons.label, label: 'Status: Draft', onDeleted: () {}),
    ));
    expect(find.text('Status: Draft'), findsOneWidget);
    expect(find.byIcon(Icons.label), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('tapping the close icon calls onDeleted', (tester) async {
    var deleted = false;
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: FilterChipWidget(
          icon: Icons.label, label: 'x', onDeleted: () => deleted = true),
    ));
    await tester.tap(find.byIcon(Icons.close));
    expect(deleted, isTrue);
  });

  testWidgets('active style: maroon-tinted fill + primary text in light', (tester) async {
    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: FilterChipWidget(icon: Icons.label, label: 'x', onDeleted: () {}),
    ));
    final scheme = AppScheme.light;
    // Label text uses primary.
    final text = tester.widget<Text>(find.text('x'));
    expect(text.style?.color, scheme.primary);
    // Container fill = primary @12% over fg; border present.
    final box = tester.widget<Container>(
      find.ancestor(of: find.text('x'), matching: find.byType(Container)).first,
    );
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, Color.alphaBlend(scheme.primary.withValues(alpha: 0.12), scheme.fg));
    expect(deco.borderRadius, BorderRadius.circular(AppRadius.full));
    expect(deco.border, isNotNull);
  });

  testWidgets('resolves against dark scheme when brightness is dark', (tester) async {
    await tester.pumpWidget(_host(
      brightness: Brightness.dark,
      child: FilterChipWidget(icon: Icons.label, label: 'x', onDeleted: () {}),
    ));
    final text = tester.widget<Text>(find.text('x'));
    expect(text.style?.color, AppScheme.dark.primary);
    expect(text.style?.color, isNot(AppScheme.light.primary));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/filter_chip_widget_test.dart`
Expected: FAIL — current widget renders a Material `Chip` (no `Container`, no `Icons.close`, label color is `onSecondaryContainer` not `primary`).

- [ ] **Step 3: Rewrite the widget**

Replace the entire contents of `lib/app/modules/global_widgets/filter_chip_widget.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// An applied-filter chip (ERPNext v15 `.chip.active`): maroon-tinted fill,
/// maroon border + text, with a trailing × to clear the filter. Used by every
/// DocType list screen via [DocTypeListHeader]'s `filterChipsBuilder`.
class FilterChipWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  const FilterChipWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final fill = Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg);
    final border = Color.alphaBlend(s.primary.withValues(alpha: 0.40), s.border);

    return Container(
      height: 34,
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: s.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: s.primary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDeleted,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Opacity(
                opacity: 0.7,
                child: Icon(Icons.close, size: 15, color: s.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/filter_chip_widget_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/filter_chip_widget.dart test/widget/filter_chip_widget_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/filter_chip_widget.dart test/widget/filter_chip_widget_test.dart
git commit -m "feat(theme): restyle FilterChipWidget to ERPNext active-chip spec (tokens, light/dark)"
```

---

### Task 2: Repaint `DocTypeFormHeader` as a solid-maroon bar

**Files:**
- Modify: `lib/app/modules/global_widgets/doctype_form_header.dart` (delegate `build`: root color, content colors, status-bar brightness, action/leading icon color)
- Test: `test/widget/doctype_form_header_solid_test.dart` (create)

**Interfaces:**
- Consumes: `Theme.of(context).colorScheme.primary` / `.onPrimary` (already driven by `AppScheme`).
- Produces: no API change — `DocTypeFormHeader` constructor and `_DocTypeFormHeaderDelegate` are unchanged in shape; only the painted colors change.

**Context for the implementer:** the delegate's `build` currently paints the root `Material(color: colorScheme.surface)` (line ~325) and colors content with `colorScheme.primary` / `.secondary` / `.onSurface` / `theme.textTheme.titleLarge`. On a solid-maroon bar those become invisible/low-contrast, so each must move to `colorScheme.onPrimary`. The blue Submit `FilledButton` (lines ~372-394) and `StatusPill` (lines ~255, 316) keep their own colors. `SaveIconButton` (line ~404) renders a bare icon that will inherit an enclosing `IconTheme`.

- [ ] **Step 1: Write the failing test**

Create `test/widget/doctype_form_header_solid_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';

Widget _host({required Brightness brightness}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    home: Scaffold(
      body: CustomScrollView(
        slivers: const [
          DocTypeFormHeader(
            title: 'WO-2024-00123',
            docType: 'Work Order',
            statusLabel: 'Draft',
          ),
          SliverToBoxAdapter(child: SizedBox(height: 1200)),
        ],
      ),
    ),
  );
}

Material _headerSurface(WidgetTester tester, Color primary) {
  // The header's painted bar is the Material whose color == colorScheme.primary.
  final materials = tester.widgetList<Material>(find.byType(Material));
  return materials.firstWhere((m) => m.color == primary,
      orElse: () => throw TestFailure('No Material painted with primary color'));
}

void main() {
  testWidgets('form header bar is painted solid primary (light)', (tester) async {
    await tester.pumpWidget(_host(brightness: Brightness.light));
    await tester.pump();
    final primary = ThemeData(brightness: Brightness.light, useMaterial3: true)
        .colorScheme
        .primary;
    expect(() => _headerSurface(tester, primary), returnsNormally);
  });

  testWidgets('form header bar is painted solid primary (dark)', (tester) async {
    await tester.pumpWidget(_host(brightness: Brightness.dark));
    await tester.pump();
    final primary = ThemeData(brightness: Brightness.dark, useMaterial3: true)
        .colorScheme
        .primary;
    expect(() => _headerSurface(tester, primary), returnsNormally);
  });

  testWidgets('expanded doc-name title uses onPrimary', (tester) async {
    await tester.pumpWidget(_host(brightness: Brightness.light));
    await tester.pump();
    final cs = ThemeData(brightness: Brightness.light, useMaterial3: true).colorScheme;
    // The 24sp expanded title Text.
    final titleText = tester.widgetList<Text>(find.text('WO-2024-00123'))
        .firstWhere((t) => (t.style?.fontSize ?? 0) >= 20);
    expect(titleText.style?.color, cs.onPrimary);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/doctype_form_header_solid_test.dart`
Expected: FAIL — root Material is still `colorScheme.surface` (no Material painted `primary`); the expanded title is `colorScheme.onSurface`, not `onPrimary`.

- [ ] **Step 3: Implement the solid-maroon repaint**

In `lib/app/modules/global_widgets/doctype_form_header.dart`, inside `_DocTypeFormHeaderDelegate.build`, make these edits:

(a) Status-bar brightness should follow the bar color (now primary), not surface. Change:

```dart
    final surfaceLuminance = colorScheme.surface.computeLuminance();
```
to:
```dart
    final surfaceLuminance = colorScheme.primary.computeLuminance();
```

(b) Root Material color — change `color: colorScheme.surface` (in the `return AnnotatedRegion...Material(...)`) to:

```dart
        color: colorScheme.primary,
```

(c) Collapsed docType label color — change `color: colorScheme.primary,` (the `fontSize: 10` Text) to:

```dart
                              color: colorScheme.onPrimary,
```

(d) Collapsed doc-name color — change `color: colorScheme.secondary,` (the `fontSize: 15` AutoSizeText) to:

```dart
                        color: colorScheme.onPrimary,
```

(e) Expanded faded title — it uses `theme.textTheme.titleLarge` (the `Opacity`→`AutoSizeText` in the toolbar middle). Give it an explicit onPrimary color:

```dart
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.onPrimary,
                    ),
```

(f) Expanded large-area docType label — change its `color: colorScheme.primary,` (the `fontSize: 11` Text) to:

```dart
                  color: colorScheme.onPrimary,
```

(g) Expanded large-area doc name — change `color: colorScheme.onSurface,` (the `fontSize: 24` Text) to:

```dart
                color: colorScheme.onPrimary,
```

(h) Tint the leading + action icons onPrimary. Wrap the `NavigationToolbar(...)` (the value assigned to `toolbar`) in an `IconTheme`. Change:

```dart
    final toolbar = SizedBox(
      height: toolbarHeight,
      child: NavigationToolbar(
```
to:
```dart
    final toolbar = SizedBox(
      height: toolbarHeight,
      child: IconTheme.merge(
        data: IconThemeData(color: colorScheme.onPrimary),
        child: NavigationToolbar(
```
and add the matching closing `)` for `IconTheme.merge` after the `NavigationToolbar(...)` argument list closes (i.e. wrap it). Verify brackets with `flutter analyze`.

> Leave the blue Submit `FilledButton`, its spinner, and `StatusPill` exactly as-is — they intentionally carry their own colors and read fine on maroon. `SaveIconButton`'s bare icon will inherit the `IconTheme` onPrimary; if its filled-when-dirty state still blends on maroon, note it in your report as a follow-up (do not redesign SaveIconButton in this task).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/doctype_form_header_solid_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Run the existing form-header test (regression check)**

Run: `flutter test test/widget/doctype_form_header_test.dart`
Expected: This file has 1 known pre-existing failure ("unsaved indicator visible when canSave and docStatus==0") unrelated to color. Confirm your change does not add NEW failures beyond that one. Report the before/after.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/doctype_form_header.dart test/widget/doctype_form_header_solid_test.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/global_widgets/doctype_form_header.dart test/widget/doctype_form_header_solid_test.dart
git commit -m "feat(theme): paint DocTypeFormHeader as solid-maroon bar with onPrimary content"
```

---

### Task 3: Tokenize the drawer for dark mode

**Files:**
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart` (replace hardcoded `Colors.*` literals on the drawer panel/menu with `context.scheme`)

**Interfaces:**
- Consumes: `context.scheme` from `app_theme.dart`.
- Produces: no API change. Purely a color retheme so the drawer panel and its text/dividers/skeleton resolve correctly in dark mode.

**Why no widget test:** rendering `AppNavDrawer` requires registering `HomeController`, `AuthenticationController`, `PermissionService`, and `AppNavDrawerController` (heavyweight, service-dependent). This task is a mechanical literal→token swap with no logic change; it is verified by `flutter analyze` + diff inspection + manual dark-mode render (Step 4). Do not add a heavyweight pumped drawer test for this.

- [ ] **Step 1: Add the import**

At the top of `lib/app/modules/global_widgets/app_nav_drawer.dart`, add:

```dart
import 'package:multimax/app/data/constants/app_theme.dart';
```

- [ ] **Step 2: Tokenize `AppNavDrawer.build` (drawer shell)**

In `AppNavDrawer.build`, after the existing `final String currentRoute = Get.currentRoute;` line, add:

```dart
    final s = context.scheme;
```
Then change the `Drawer(...)` background from:
```dart
        backgroundColor: Colors.white,
```
to:
```dart
        backgroundColor: s.fg,
```
And the Stock-section divider `Divider(color: Colors.grey.shade200)` (the one inside `moduleMenuItems`) to:
```dart
                        height: 1, color: s.border),
```
(keep the surrounding `Divider(` / `Padding` structure; only swap the color).

> Leave the `UserAccountsDrawerHeader` (its `Theme.of(context).primaryColor` background and the `Colors.white70/white54` text on that colored header) AND the logout `Colors.red.shade400/600` as-is — they sit on colored/semantic surfaces that read acceptably in both modes. This task fixes the neutral drawer-panel surfaces only.

- [ ] **Step 3: Tokenize the sub-widgets**

Each private sub-widget has its own `build(context)`. Add `final s = context.scheme;` at the top of each `build` below and swap its neutral literals:

**`_SkeletonDrawerItem` (`_SkeletonDrawerItemState.build`):** change the shimmer lerp
```dart
          final shimmerColor = Color.lerp(
            Colors.grey.shade100,
            Colors.grey.shade300,
            _anim.value,
          )!;
```
to:
```dart
          final shimmerColor = Color.lerp(
            s.subtle,
            s.border,
            _anim.value,
          )!;
```
(add `final s = context.scheme;` inside this `build` before the `AnimatedBuilder`).

**`_ModuleGroup.build`** (inside the `Obx`): the group leading icon `color: Colors.grey.shade700` → `color: s.textMuted`; the group title `color: Colors.black87` → `color: s.text`. (Leave `dividerColor: Colors.transparent` and the `iconColor`/`textColor: Theme.of(context).primaryColor`.) Add `final s = context.scheme;` at the top of `build`.

**`_NavSubheading.build`:** label `color: Colors.grey.shade500` → `color: s.textSubtle`; trailing divider `color: Colors.grey.shade200` → `color: s.border`. Add `final s = context.scheme;`.

**`_DrawerItem.build`:** unselected leading icon `color: Colors.grey.shade600` → `color: s.textMuted`; unselected title `color: Colors.grey.shade800` → `color: s.text`. (Leave the `primaryColor`-based selected styling and the transparent borders.) Use the existing `theme`/`primaryColor` locals already in scope; add `final s = context.scheme;`.

- [ ] **Step 4: Manual dark-mode verification**

Run: `flutter run -d <device_id>` (ids in `.vscode/launch.json`). Switch theme to Dark via the drawer toggle, then:
1. Drawer panel background is dark (`#1F262C`), not white.
2. Module group titles/icons, subheadings, and unselected items are legible (light text on dark).
3. Dividers are subtle dark lines, not light-grey.
4. The skeleton shimmer (open a module while permissions load) shimmers in dark tones.
5. Light mode still looks identical to before.

> If you cannot run a device in this environment, state that in your report and list exactly which literals were swapped so the controller can smoke-test.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/app_nav_drawer.dart`
Expected: "No issues found!" (watch for any now-unused import or `withOpacity` lints you may have touched).

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/app_nav_drawer.dart
git commit -m "feat(theme): tokenize drawer neutrals so it renders in dark mode"
```

---

## Self-Review

**1. Spec coverage (handoff §2 + decisions):**
- Filter chips → ds.css active spec via tokens → Task 1. ✔ (one shared widget → all list screens)
- Form header → solid maroon archetype → Task 2. ✔ (user decision)
- Drawer dark-mode (the real dark-mode gap) → Task 3. ✔
- List header → already theme-aware, intentionally untouched. ✔ (documented)
- **Deferred (documented):** the `.chip-add` dashed "+Filter" chip and the neutral "default" chip variant (the app's flow has no in-row add-chip — filtering is via the appbar filter icon; YAGNI); a broad per-screen hardcoded-color sweep (most screens render via theme/shared widgets already — revisit if a specific screen shows light artifacts in dark); `SaveIconButton` appearance on the solid bar (flag-only in Task 2).

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". Every code step shows the exact edit. Task 3's per-widget swaps name the exact literal and its replacement.

**3. Type consistency:** `FilterChipWidget` constructor unchanged (Task 1) so all existing call sites compile. `context.scheme` field names (`primary/onPrimary/fg/border/subtle/text/textMuted/textSubtle`) all exist on `AppScheme` from the merged foundation. `colorScheme.primary/onPrimary` used in Task 2 are standard and driven by `AppScheme`.

---

## Execution Handoff

Family A. Builds on the merged foundation (`app_theme.dart`). After this ships and is verified in both themes, Family B (empty/loading states) and Family C (badges/avatars/tabs + status 700/300 resolver) follow as separate plans.
