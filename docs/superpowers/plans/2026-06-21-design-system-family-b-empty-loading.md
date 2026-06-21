# Design System — Family B: Empty & Loading States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare first-load `CircularProgressIndicator` on every DocType list screen with skeleton cards, and bring the shared empty state onto the ERPNext v15 glyph spec — all token-driven and dark-mode correct.

**Architecture:** Build two new shared widgets — `SkeletonBox` (a token-aware shimmer rectangle, reduced-motion aware) and `DocCardSkeleton`/`DocCardSkeletonList` (a card placeholder mirroring `GenericDocumentCard`'s silhouette) — in `lib/app/modules/global_widgets/`. Polish the existing `ListEmptyState` to use the §9 `.glyph` circle + `context.scheme` tokens (constructor unchanged, so all 8 screens are unaffected). Then swap each list screen's uniform first-load branch (`if (isLoading && list.isEmpty) → SliverFillRemaining(Center(CircularProgressIndicator()))`) for `SliverToBoxAdapter(child: DocCardSkeletonList())`.

**Tech Stack:** Flutter (Material 3), GetX, merged `app_theme.dart` tokens. The in-repo shimmer precedent is the drawer's `_SkeletonDrawerItem` (token-aware `AnimationController` + `Color.lerp(s.subtle, s.border)`).

## Global Constraints

- **Keep maroon.** Use `context.scheme` / `AppRadius` / `AppSpace`. No new hardcoded hex/`Colors.*` literals in the new/changed widgets. No blue.
- **Light + dark both mandatory.** All new surfaces resolve via `context.scheme`.
- **Skeleton respects reduced motion:** when `MediaQuery.disableAnimationsOf(context)` is true, render a static `subtle` fill (no animation), per ds.css `@media (prefers-reduced-motion: reduce)`.
- **Error state is DEFERRED** (user decision) — do NOT add `hasError` observables or an error empty-variant. Errors stay as today's snackbars.
- **No public API changes** to `ListEmptyState` (8 screens call it with 8 required params), `ListEndFooter`, `ResultCountPill`. `ListEndFooter`/`ResultCountPill` are out of scope (already theme-derived).
- **Controllers are NOT modified** — Family B only swaps the view layer's loading branch. The first-load condition stays `controller.isLoading.value && <list>.isEmpty`.
- Each task: `flutter analyze` clean on touched files; tests pass. Run from repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`.
- Pre-existing unrelated suite failures (7 `status_pill_colour_test.dart`, 1 `doctype_form_header_test.dart`) are the known baseline — don't grow it.

### ds.css targets (already in repo)
- `.skeleton`: gradient `subtle → border → subtle`, 1.3s loop, sweeps left↔right; reduced-motion → no animation; radius `--r-sm` (6).
- `.empty`: column, centered, gap `--s-3` (12), padding `--s-10`/`--s-5` (40/20). `.glyph`: 56×56, radius `--r-full`, bg `--subtle`, icon color `--text-subtle`. `h4`: 17 / weight 600 / `--text`. `p`: 14 / `--text-muted` / max-width ~30ch.

---

### Task 1: `SkeletonBox` (token-aware shimmer rectangle)

**Files:**
- Create: `lib/app/modules/global_widgets/skeleton_box.dart`
- Test: `test/widget/skeleton_box_test.dart`

**Interfaces:**
- Consumes: `context.scheme`, `AppRadius`.
- Produces: `class SkeletonBox extends StatefulWidget` with `const SkeletonBox({Key? key, double? width, required double height, double radius})` (radius defaults to `AppRadius.sm`). `width == null` → fills available width.

- [ ] **Step 1: Write the failing test**

Create `test/widget/skeleton_box_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/skeleton_box.dart';

Widget _host({required bool reduceMotion, Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const Scaffold(
        body: Center(child: SizedBox(width: 200, child: SkeletonBox(height: 12))),
      ),
    ),
  );
}

void main() {
  testWidgets('animated: renders a gradient (no static solid fill)', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 100));
    final boxes = tester.widgetList<Container>(find.byType(Container));
    final hasGradient = boxes.any((c) =>
        c.decoration is BoxDecoration && (c.decoration as BoxDecoration).gradient != null);
    expect(hasGradient, isTrue);
    await tester.pump(const Duration(milliseconds: 700)); // ensure it animates without throwing
  });

  testWidgets('reduced motion: static subtle fill, no gradient', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.pump();
    final container = tester.widgetList<Container>(find.byType(Container)).firstWhere(
        (c) => c.decoration is BoxDecoration &&
               (c.decoration as BoxDecoration).color == AppScheme.light.subtle);
    final deco = container.decoration as BoxDecoration;
    expect(deco.gradient, isNull);
    expect(deco.color, AppScheme.light.subtle);
  });

  testWidgets('resolves dark subtle under dark brightness (reduced motion)', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true, brightness: Brightness.dark));
    await tester.pump();
    final match = tester.widgetList<Container>(find.byType(Container)).any((c) =>
        c.decoration is BoxDecoration &&
        (c.decoration as BoxDecoration).color == AppScheme.dark.subtle);
    expect(match, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/skeleton_box_test.dart`
Expected: FAIL — `skeleton_box.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/app/modules/global_widgets/skeleton_box.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A shimmer placeholder rectangle (ERPNext v15 `.skeleton`). Sweeps a
/// `subtle → border → subtle` gradient left→right on a 1.3s loop. Honours
/// reduced-motion (renders a static `subtle` fill). Colors come from
/// [BuildContext.scheme] so it adapts to light/dark.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = AppRadius.sm,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final radius = BorderRadius.circular(widget.radius);

    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: s.subtle, borderRadius: radius),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final dx = (_controller.value * 2.0) - 1.0; // -1 → 1
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment(dx - 1.0, 0),
              end: Alignment(dx + 1.0, 0),
              colors: [s.subtle, s.border, s.subtle],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/skeleton_box_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/skeleton_box.dart test/widget/skeleton_box_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/skeleton_box.dart test/widget/skeleton_box_test.dart
git commit -m "feat(theme): add token-aware SkeletonBox shimmer (reduced-motion aware)"
```

---

### Task 2: `DocCardSkeleton` + `DocCardSkeletonList`

**Files:**
- Create: `lib/app/modules/global_widgets/doc_card_skeleton.dart`
- Test: `test/widget/doc_card_skeleton_test.dart`

**Interfaces:**
- Consumes: `SkeletonBox` (Task 1), `context.scheme`, `AppRadius`, `AppSpace`.
- Produces:
  - `class DocCardSkeleton extends StatelessWidget` — `const DocCardSkeleton({Key? key})`. One card placeholder mirroring `GenericDocumentCard` (title line, mono subtitle line, trailing pill block, a stats row).
  - `class DocCardSkeletonList extends StatelessWidget` — `const DocCardSkeletonList({Key? key, int count = 5})`. A `Column` of `count` `DocCardSkeleton`s (for use inside `SliverToBoxAdapter`).

**Context:** `GenericDocumentCard` silhouette (mirror this): `Card` (margin h16/v6, radius 12, border) → body padding LTRB(16,14,16,14) → header row [Expanded(title `titleSmall` + 2px + mono subtitle 11) , trailing StatusPill] → stats row (icon14 + text11 chips). The skeleton approximates these as `SkeletonBox`es.

- [ ] **Step 1: Write the failing test**

Create `test/widget/doc_card_skeleton_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/skeleton_box.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('DocCardSkeleton renders several SkeletonBoxes', (tester) async {
    await tester.pumpWidget(_host(const DocCardSkeleton()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SkeletonBox), findsAtLeastNWidgets(3));
  });

  testWidgets('DocCardSkeletonList renders the requested count', (tester) async {
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: DocCardSkeletonList(count: 4)),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(DocCardSkeleton), findsNWidgets(4));
  });

  testWidgets('DocCardSkeletonList defaults to 5', (tester) async {
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: DocCardSkeletonList()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(DocCardSkeleton), findsNWidgets(5));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/doc_card_skeleton_test.dart`
Expected: FAIL — `doc_card_skeleton.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/app/modules/global_widgets/doc_card_skeleton.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/skeleton_box.dart';

/// A loading placeholder that mirrors [GenericDocumentCard]'s silhouette:
/// a title line, a shorter mono "doc-id" line, a trailing status-pill block,
/// and a stats row. Use [DocCardSkeletonList] to render several at once on a
/// list screen's first load.
class DocCardSkeleton extends StatelessWidget {
  const DocCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: 6),
      elevation: 0,
      color: s.fg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: s.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s4, 14, AppSpace.s4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.6,
                        child: SkeletonBox(height: 14),
                      ),
                      SizedBox(height: 6),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.4,
                        child: SkeletonBox(height: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.s2),
                const SkeletonBox(width: 64, height: 22, radius: AppRadius.full),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: const [
                SkeletonBox(width: 60, height: 11),
                SizedBox(width: AppSpace.s4),
                SkeletonBox(width: 48, height: 11),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A column of [DocCardSkeleton]s for a list screen's first-load state.
/// Drop into a `SliverToBoxAdapter`.
class DocCardSkeletonList extends StatelessWidget {
  final int count;
  const DocCardSkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (_) => const DocCardSkeleton()),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/doc_card_skeleton_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/doc_card_skeleton.dart test/widget/doc_card_skeleton_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/doc_card_skeleton.dart test/widget/doc_card_skeleton_test.dart
git commit -m "feat(theme): add DocCardSkeleton + DocCardSkeletonList list placeholders"
```

---

### Task 3: Polish `ListEmptyState` to the §9 glyph spec

**Files:**
- Modify: `lib/app/modules/global_widgets/list_empty_state.dart`
- Test: `test/widget/list_empty_state_glyph_test.dart` (create)

**Interfaces:**
- Consumes: `context.scheme`, `AppRadius`, `AppSpace`.
- Produces: no API change — same 8 required params. Internals move to a 56×56 `.glyph` circle + scheme tokens.

**Context:** Current build renders a bare `Icon(size: 64, color: cs.outlineVariant)`, title `titleMedium`-bold (`cs.onSurface`), message `bodyMedium` (`cs.onSurfaceVariant`), and a `FilledButton.tonalIcon`. Keep the filtered-vs-empty switching logic (icon/title/message/action) intact; only restyle the glyph + text to tokens.

- [ ] **Step 1: Write the failing test**

Create `test/widget/list_empty_state_glyph_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';

Widget _host({required bool filtered}) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: ListEmptyState(
          hasActiveFilters: filtered,
          emptyIcon: Icons.inbox_outlined,
          emptyTitle: 'No notes',
          emptyMessage: 'Nothing here yet.',
          filteredTitle: 'No matches',
          filteredMessage: 'Try clearing filters.',
          onClearFilters: () {},
          onReload: () {},
        ),
      ),
    );

void main() {
  testWidgets('renders a 56x56 subtle glyph circle around the icon', (tester) async {
    await tester.pumpWidget(_host(filtered: false));
    final glyph = tester.widget<Container>(
      find.ancestor(of: find.byIcon(Icons.inbox_outlined), matching: find.byType(Container)).first,
    );
    expect(glyph.constraints?.maxWidth, 56);
    expect(glyph.constraints?.maxHeight, 56);
    final deco = glyph.decoration as BoxDecoration;
    expect(deco.color, AppScheme.light.subtle);
    expect(deco.shape, BoxShape.circle);
  });

  testWidgets('empty title uses 17/600 in scheme text color', (tester) async {
    await tester.pumpWidget(_host(filtered: false));
    final title = tester.widget<Text>(find.text('No notes'));
    expect(title.style?.fontSize, 17);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(title.style?.color, AppScheme.light.text);
  });

  testWidgets('filtered state still shows the clear-filters action', (tester) async {
    await tester.pumpWidget(_host(filtered: true));
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Clear Filters'), findsOneWidget);
  });
}
```

> Note: keep the existing `test/widget/list_empty_state_test.dart` passing. If it asserts the old bare-icon size (64) or the old title style, those assertions may need updating to the new spec as part of this task — update them to match (do not delete coverage). Report any such change.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/list_empty_state_glyph_test.dart`
Expected: FAIL — no 56×56 circle container; title is `titleMedium`, not fontSize 17/w600.

- [ ] **Step 3: Implement**

In `lib/app/modules/global_widgets/list_empty_state.dart`:

(a) Add the import:
```dart
import 'package:multimax/app/data/constants/app_theme.dart';
```

(b) In `build`, replace the `final theme = ...; final cs = ...;` colour sourcing and the icon/title/message widgets so the icon sits in a glyph circle and text uses scheme tokens. Use `final s = context.scheme;`. The glyph:

```dart
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: s.subtle, shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: s.textSubtle),
            ),
```
the title:
```dart
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: s.text,
              ),
            ),
```
the message:
```dart
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: s.textMuted),
            ),
```
where `icon`/`title`/`message` are the existing filtered-vs-empty locals already computed in the method (keep that logic). Keep the existing action button(s) (`FilledButton.tonalIcon` for Clear Filters / Reload) unchanged. Use `AppSpace` for the vertical gaps (e.g. `SizedBox(height: AppSpace.s3)` between glyph/title/message) and outer padding `EdgeInsets.symmetric(horizontal: AppSpace.s5, vertical: AppSpace.s10)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/list_empty_state_glyph_test.dart test/widget/list_empty_state_test.dart`
Expected: the new test PASSES; the existing test passes (update its stale style assertions if needed, per Step 1 note).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/list_empty_state.dart test/widget/list_empty_state_glyph_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/list_empty_state.dart test/widget/list_empty_state_glyph_test.dart test/widget/list_empty_state_test.dart
git commit -m "feat(theme): give ListEmptyState the ERPNext glyph circle + token styling"
```

---

### Task 4: Wire `DocCardSkeletonList` into all 8 list screens' first load

**Files (modify — first-load branch only):**
- `lib/app/modules/delivery_note/delivery_note_screen.dart` (~229-234)
- `lib/app/modules/work_order/work_order_screen.dart` (~156-159)
- `lib/app/modules/purchase_order/purchase_order_screen.dart` (~170-173)
- `lib/app/modules/material_request/material_request_screen.dart` (~248-252)
- `lib/app/modules/purchase_receipt/purchase_receipt_screen.dart` (~185-189)
- `lib/app/modules/pos_upload/pos_upload_screen.dart` (~168-172)
- `lib/app/modules/stock/.../stock_entry/stock_entry_screen.dart` (~251-255 — find via `lib/app/modules` glob)
- `lib/app/modules/item/item_screen.dart` (~66-71)

**Interfaces:**
- Consumes: `DocCardSkeletonList` (Task 2).
- Produces: no API change — view-layer swap only.

**Context:** every screen has the identical first-load branch inside an `Obx` returning a sliver:
```dart
if (controller.isLoading.value && controller.<list>.isEmpty) {
  return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
}
```
Replace the `SliverFillRemaining(...)` with a skeleton sliver. Keep the surrounding `if` condition and the rest of the branch logic unchanged.

- [ ] **Step 1: Swap the first-load branch in each screen**

For EACH of the 8 files: add the import
```dart
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
```
then replace that screen's first-load `SliverFillRemaining(child: Center(child: CircularProgressIndicator()))` (the one guarded by `isLoading && <list>.isEmpty`) with:
```dart
        return const SliverToBoxAdapter(child: DocCardSkeletonList());
```
Notes:
- Match each screen's exact current expression (whitespace/`const` placement varies); only the first-load spinner changes. Do NOT touch the `ListEndFooter` pagination loader or the `ListEmptyState` empty branch.
- `item_screen.dart`: replace only the shared first-load spinner (~66-71). Leave the grid-view pagination loader (~108-114) as-is (it's pagination, not first load).

- [ ] **Step 2: Analyze all touched screens**

Run:
```bash
flutter analyze lib/app/modules/delivery_note/delivery_note_screen.dart lib/app/modules/work_order/work_order_screen.dart lib/app/modules/purchase_order/purchase_order_screen.dart lib/app/modules/material_request/material_request_screen.dart lib/app/modules/purchase_receipt/purchase_receipt_screen.dart lib/app/modules/pos_upload/pos_upload_screen.dart lib/app/modules/item/item_screen.dart
```
(plus the stock_entry screen path once located).
Expected: "No issues found!" (watch for now-unused imports if a screen imported nothing else for the spinner).

- [ ] **Step 3: Manual verification (device)**

Run the app and open 2-3 list screens cold (e.g. Delivery Note, Work Order, Item). Confirm:
1. First load shows shimmering skeleton cards (not a centered spinner), in both light and dark.
2. After data arrives, skeletons are replaced by real cards.
3. Empty (filter to no results) shows the new glyph empty state.
4. Pagination still shows the end-of-list footer/spinner.

> If you cannot run a device here, state that and list each file's exact before/after line so the controller can smoke-test.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/delivery_note/delivery_note_screen.dart lib/app/modules/work_order/work_order_screen.dart lib/app/modules/purchase_order/purchase_order_screen.dart lib/app/modules/material_request/material_request_screen.dart lib/app/modules/purchase_receipt/purchase_receipt_screen.dart lib/app/modules/pos_upload/pos_upload_screen.dart lib/app/modules/item/item_screen.dart
# plus the stock_entry screen path
git commit -m "feat(theme): show DocCardSkeleton cards on list first-load across all 8 screens"
```

---

## Self-Review

**1. Spec coverage (handoff §3 + decisions):**
- `SkeletonBox` shimmer, reduced-motion aware → Task 1. ✔
- `DocCardSkeleton` mirroring the list card; 3–5 on first load → Task 2 (+ wired in Task 4). ✔
- `EmptyState` glyph spec → Task 3 (polishing the existing `ListEmptyState`, API unchanged). ✔
- Replace ad-hoc spinners across the 8 list modules → Task 4. ✔
- **Deferred (user decision, documented):** error-state variant + `hasError` observables (errors stay snackbar-only); `ListEndFooter`/`ResultCountPill` token migration (already theme-derived, out of scope); item grid-view pagination loader (left as-is); the bottom progress-bar element from `DocCardSkeleton` (the real card has no progress bar).

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". Every step shows real code or the exact swap.

**3. Type consistency:** `SkeletonBox({width?, height, radius})` defined in Task 1, consumed in Task 2. `DocCardSkeletonList({count=5})` defined in Task 2, consumed in Task 4. `ListEmptyState` constructor unchanged (Task 3) so the 8 screens keep compiling. All colors via `context.scheme` fields (`subtle/border/fg/text/textMuted/textSubtle`) which exist on `AppScheme`.

---

## Execution Handoff

Family B. Builds on the merged foundation + Family A. After this ships, Family C (Badges/Avatars/Tabs + the status 700/300 resolver, which also gives `status_pill.dart` dark-mode support) is the last family.
