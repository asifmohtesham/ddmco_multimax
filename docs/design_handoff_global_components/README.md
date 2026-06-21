# Handoff: Global UI Components — App Bar & Filter Chips · Empty & Loading States · Badges / Avatars / Tabs

> **For:** a developer using Claude Code (or Cowork) working inside the **`multimax` Flutter app** (`ddmco_multimax`, package name `multimax`, "KA-ML Fulfillment").
> **Goal:** roll out three families of shared widgets **globally** across all 16 feature modules, styled to the Multimax × ERPNext v15 design system, with **full light + dark (Timeless Night) support** as a hard requirement.

---

## 0. About the design files in this bundle

The two files here are **design references created in HTML/CSS** — a prototype showing the intended look and behavior of the ERPNext v15 visual language. **They are not code to ship.** Your task is to **recreate these designs as Flutter widgets** inside the existing app, using its established patterns:

- **Flutter + Material 3** (`useMaterial3: true`) — the app already themes via `ThemeData` in `lib/main.dart`.
- **GetX** for state/DI — `GetxController`, `Get.lazyPut` bindings, `GetView<T>` screens, `.obs` observables, `ever()` workers (cancel in `onClose()`).
- Shared widgets live in `lib/app/modules/global_widgets/` and `lib/app/shared/`.
- The existing unified header is **`DocTypeListHeader`** (a `SliverAppBar.large` wrapper). See `docs/app_bar_conventions.md` and `docs/doctype_list_view_conventions.md`.

Files:
- `Multimax Design System.html` — open in a browser; toggle light/dark in the header. Sections **Components → "App bar · Filter chips"**, **"Empty & loading states"**, **"Badges · Avatars · Tabs"** are the targets here.
- `ds.css` — the canonical token + component CSS. Treat the `:root` / `[data-theme="dark"]` blocks as the source of truth for every value below.

**Fidelity: High.** Colors, type, spacing, and radii are final. Recreate pixel-faithfully, but express everything through Flutter `ThemeData` + reusable widgets (do **not** hard-code hex values at call sites — centralize them as described in §1).

---

## 1. Prerequisite — centralize design tokens

Before building widgets, create a single source of truth so the three component families (and the rest of the app) read from one place. The app currently hard-codes colors inline in `lib/main.dart` (`primaryColour = 0xFF870E18`, etc.). Replace/extend with the ERPNext v15 token set.

Create `lib/app/data/constants/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

/// ERPNext v15 design tokens — see design_handoff_global_components/ds.css
class AppColors {
  // Neutral ramp
  static const gray50  = Color(0xFFF9FAFA);
  static const gray100 = Color(0xFFF4F5F6);
  static const gray200 = Color(0xFFEBEEF0);
  static const gray300 = Color(0xFFD8DEE3);
  static const gray400 = Color(0xFFBCC4CB);
  static const gray500 = Color(0xFF98A1A9);
  static const gray600 = Color(0xFF74808B);
  static const gray700 = Color(0xFF525C66);
  static const gray800 = Color(0xFF323A45);
  static const gray900 = Color(0xFF1F272E);

  // Accent / status ramps (300 = dark-mode text, 500 = base, 700 = light-mode text)
  static const blue500   = Color(0xFF2490EF); static const blue600 = Color(0xFF1F75C9);
  static const blue300   = Color(0xFF7CC0F7); static const blue700 = Color(0xFF18599A);
  static const green500  = Color(0xFF38A160); static const green300 = Color(0xFF8FD3A8); static const green700 = Color(0xFF1F5E34);
  static const red500    = Color(0xFFE03636); static const red300 = Color(0xFFF09494);  static const red700 = Color(0xFF9A2222);
  static const orange500 = Color(0xFFF0851B); static const orange300 = Color(0xFFF7B67A); static const orange700 = Color(0xFF9E5409);
  static const yellow500 = Color(0xFFE0A93A); static const yellow300 = Color(0xFFF3D08C); static const yellow700 = Color(0xFF946817);
  static const purple500 = Color(0xFF7C4DFF); static const purple300 = Color(0xFFB6A0FF); static const purple700 = Color(0xFF4E29AB);
  static const cyan500   = Color(0xFF1AAFC4); static const cyan300 = Color(0xFF7FD3DF); static const cyan700 = Color(0xFF0D6675);
}

/// Resolve semantic colors per brightness (light / Timeless Night dark).
class AppScheme {
  final Color bg, fg, subtle, text, textMuted, textSubtle, border, borderStrong, primary, onPrimary;
  const AppScheme({required this.bg, required this.fg, required this.subtle, required this.text,
    required this.textMuted, required this.textSubtle, required this.border, required this.borderStrong,
    required this.primary, required this.onPrimary});

  static const light = AppScheme(
    bg: AppColors.gray100, fg: Colors.white, subtle: AppColors.gray50,
    text: AppColors.gray900, textMuted: AppColors.gray600, textSubtle: AppColors.gray500,
    border: AppColors.gray200, borderStrong: AppColors.gray300,
    primary: AppColors.blue500, onPrimary: Colors.white);

  static const dark = AppScheme(
    bg: Color(0xFF15191D), fg: Color(0xFF1F262C), subtle: Color(0xFF262D34),
    text: Color(0xFFEEF1F4), textMuted: Color(0xFF9AA5AF), textSubtle: Color(0xFF6F7C87),
    border: Color(0xFF2E353C), borderStrong: Color(0xFF3A424A),
    primary: Color(0xFF3B9BF2), onPrimary: Color(0xFF0B1116));
}

class AppRadius {
  static const xs = 4.0, sm = 6.0, md = 8.0, lg = 12.0, xl = 16.0, full = 999.0;
}

class AppSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0, s8 = 32.0, s10 = 40.0;
}
```

**Type:** font family is **Inter** (add `Inter` to `pubspec.yaml` assets or `google_fonts`). Scale (px → logical): `xs 11 / sm 12 / base 14 / md 15 / lg 17 / xl 20 / 2xl 24 / 3xl 30`. Labels/buttons weight 500; titles 600; IDs use a monospace-ish style.

> **Light + dark is mandatory for this task.** Every widget in families A/B/C must render correctly in both `AppScheme.light` and `AppScheme.dark` and react live to brightness changes — verify each against both HTML themes (toggle in the reference header). Wire a real theme switch:
> - Build a `ThemeController` (GetX) holding `Rx<ThemeMode>`, persisted via the existing `DatabaseService` (SQLite) so the choice survives restarts; default to `ThemeMode.system`.
> - Provide both `theme:` (light) and `darkTheme:` (dark) `ThemeData` to `GetMaterialApp` in `lib/main.dart`, each built from the corresponding `AppScheme`, and bind `themeMode:` to the controller.
> - Resolve semantic colors at build time via `Theme.of(context).brightness` (or a `context.scheme` extension that returns `AppScheme.light`/`AppScheme.dark`). **Never** bake `Colors.white`/hex literals into the three widget families — read everything from `AppScheme`.
> - Add a theme toggle in the app drawer / profile screen.
> - Note the per-brightness swaps that aren't a simple invert: indicator/badge **text** uses `<status>700` in light and `<status>300` in dark; the form header stays **solid `primary`** in both but `primary` itself shifts (`#2490EF` → `#3B9BF2`); skeleton shimmer gradient uses the theme's own `subtle`/`border`.

---

## 2. Component family A — App Bar & Filter Chips

Reference: HTML section **"App bar · Filter chips"** and the two device screens at the bottom. Authority doc: `docs/app_bar_conventions.md`.

### A1. `DocTypeListHeader` (extend the existing widget — do not fork)

There are **two archetypes** that must remain distinct:

| | List View header | Form View header |
|---|---|---|
| Background | `AppScheme.fg` (surface) — title in `text` color | **Solid `primary`** (`#2490EF`) — title/icons in `onPrimary` |
| Leading | ☰ hamburger (drawer) — `automaticallyImplyLeading: false` | ← back arrow (default `true`) |
| Actions | filter icon · search icon | reload · save · share |
| Title | Large title, `--t-2xl` (24), weight 600 | Large title, `--t-xl` (20), weight 600 |

Visual spec (both):
- Toolbar (collapsed) height **56**, icon buttons **44×44** circular, ripple `subtle` (list) / `rgba(255,255,255,.16)` (solid form).
- Large title row padding: `2px 16px 12px`.
- **No elevation** when collapsed — ERPNext leans on a 1px bottom `border` hairline, not shadow. (`SliverAppBar.large` → `elevation: 0`, `scrolledUnderElevation: 0`; draw a `Border(bottom: BorderSide(color: border))`.)
- Icons: Material `menu`, `filter_alt_outlined` / `tune`, `search`, `arrow_back`, `refresh`, `save_outlined`, `share_outlined`.

Add an `archetype` enum so the same widget renders both:

```dart
enum HeaderKind { list, form }

DocTypeListHeader({
  required String title,
  HeaderKind kind = HeaderKind.list,
  RxMap<String, dynamic>? activeFilters,
  VoidCallback? onFilterTap,
  Widget Function()? filterChipsBuilder,
  VoidCallback? onClearAllFilters,
  List<Widget> extraActions = const [],
  ...
})
```
- `kind == list` → `automaticallyImplyLeading: false`, surface bg, `[filter, search]` actions, renders the **chip row** in the `bottom`/flexible area.
- `kind == form` → back arrow, **solid primary** bg, `extraActions` = `[reload, save, share]`, no chip row.

### A2. Filter chips (`FilterChipRow` + `DocTypeFilterChip`)

A horizontally scrollable row directly beneath the large title (only on list headers).

Per-chip spec:
- Height ~**34**, padding `7px 10px 7px 12px`, radius **full (999)**, font `--t-sm` (12) weight 500, gap 6 between chips.
- **Default** chip: bg `subtle`, 1px `border`, text `text`.
- **Active** chip (a value is applied): bg = `primary @ 12%` over `fg`, border = `primary @ 40%` over `border`, text = `primary`, trailing **× clear** icon (15px, opacity .7).
- **"+ Filter"** chip: dashed 1px border, text `textMuted`, leading `+` — opens the filter bottom sheet.
- Tapping a chip's × removes that key from `activeFilters`; "+ Filter" calls `onFilterTap`. `onClearAllFilters` clears the map. Use the existing `RxMap activeFilters` so chips rebuild via `Obx`.

### A3. Roll-out (global)

Apply to every list screen with `automaticallyImplyLeading: false` and to every form screen as `kind: form`:

- List: `work_order`, `material_request`, `purchase_order`, `purchase_receipt`, `delivery_note`, `stock_entry`, `pos_upload`, `manufacturing/reports/bom_search`.
- Form: `*/form/*_form_screen.dart` for work_order, stock_entry, material_request, purchase_order, purchase_receipt, delivery_note.

(See the full screen tables in `docs/app_bar_conventions.md`.)

---

## 3. Component family B — Empty & Loading States

Reference: HTML section **"Empty & loading states"** and `docs/doctype_list_view_conventions.md` (empty state, end-of-list footer).

### B1. `EmptyState` widget

```dart
EmptyState({ required IconData icon, required String title, String? message, Widget? action })
```
- Center column, vertical padding `s10` (40), gap `s3` (12), `textMuted`.
- **Glyph**: 56×56 circle, bg `subtle`, icon 26px in `textSubtle`.
- **Title**: `--t-lg` (17), weight 600, `text` color.
- **Message**: `--t-base` (14), `textMuted`, `max-width ~30ch`, centered.
- Optional **action**: a `btn-secondary` small button (e.g. "Clear filters").
- Use for: no results after filters, empty list on first load, no search matches, offline-with-no-cache.

### B2. Loading skeletons (`SkeletonBox` + `DocCardSkeleton`)

- `SkeletonBox(width, height, radius)` — a shimmer rectangle. Gradient sweeps `subtle → border → subtle`, 1.3s ease-in-out loop, **left↔right** (200% background-size). **Respect reduced-motion**: if `MediaQuery.disableAnimations`, render a static `subtle` fill (no animation).
- `DocCardSkeleton` mirrors the real list card layout (see §4 of the design system / `doc-card`): a pill-sized box (74×22, radius full) + a 60×12 id box on the top row, then a 70%×18 title, 45%×12 subtitle, and a 100%×6 (radius full) progress bar. Show **3–5** while the first page loads; never spin a bare `CircularProgressIndicator` on list screens.
- Pagination: show one `DocCardSkeleton` (or a slim row) as the load-more footer while the next page fetches; show an **end-of-list footer** (muted centered caption) when exhausted — per `doctype_list_view_conventions.md`.

### B3. Roll-out (global)

Standardize every list `controller` to expose `isLoading`/`isLoadingMore`/`items.isEmpty`/`hasError` observables and switch body between: skeletons (initial load) → list → `EmptyState` (empty) → error variant of `EmptyState` (with a "Retry" action). Replace any ad-hoc spinners/empty `Center(child: Text(...))` across the 8 list modules.

---

## 4. Component family C — Badges · Avatars · Tabs

Reference: HTML section **"Badges · Avatars · Tabs"**.

### C1. Badges

- **`StatusBadge`** (informational chip): height ~22, padding `3px 8px`, radius `sm` (6), `--t-xs` (11) weight 600. Neutral = bg `subtle`, 1px `border`, text `textMuted`. Colored = bg `<status>@12%` over `fg`, text `<status>700` (light) / `<status>300` (dark), no border. Reuse the same status palette as indicator pills.
- **`CountBadge`** (notification count): min 18×18, radius full, `red500` bg, white 10px weight 700. Also a muted variant (`textSubtle` bg) for tab counts. This replaces the maroon header badge in the current mockups.

> Note: keep the existing **indicator pills** (`.pill` / `.indicator`) as the canonical *document-status* component (separate widget, already implied by list cards). Badges here are for metadata/counts, not doc status.

### C2. Avatars (`AppAvatar` + `AvatarGroup`)

- `AppAvatar({ String? initials, ImageProvider? image, double size = 36, bool square = false })`.
- Circle (or radius `md` (8) if `square`), bg = `primary @ 16%` over `fg`, text `primary`, weight 600, `--t-sm` (12). Derive 1–2 letter initials when no image.
- `AvatarGroup` overlaps avatars by **-10px**, each with a 2px `fg`-colored ring; first child no negative margin. Use for assignees / "shared with".

### C3. Tabs (`DocTabBar`)

- Underline tabs (not Material filled). Row with 1px bottom `border`; each tab padding `12px 14px`, `--t-base` (14) weight 500, `textMuted`.
- **Selected**: text `primary`, 2px bottom border `primary` (sits on the row's hairline via -1px margin).
- Optional trailing `CountBadge` (muted variant) inside a tab label, e.g. "Items 6".
- Use on form screens for **Details / Items / Connections / Activity**. Can wrap Flutter `TabBar` with a custom `indicator` + `labelColor`/`unselectedLabelColor`, or build bespoke for full control of the badge-in-label.

### C4. Roll-out (global)

- Replace ad-hoc count chips in headers/lists with `CountBadge`.
- Use `AppAvatar` anywhere an owner/assignee/user appears (profile, todo, activity).
- Adopt `DocTabBar` on multi-section form screens (work_order, stock_entry forms).

---

## 5. Design tokens quick reference (light → dark)

| Token | Light | Dark (Timeless Night) |
|---|---|---|
| bg (page) | `#F4F5F6` | `#15191D` |
| fg (card/surface) | `#FFFFFF` | `#1F262C` |
| subtle (hover/inset) | `#F9FAFA` | `#262D34` |
| text | `#1F272E` | `#EEF1F4` |
| text-muted | `#74808B` | `#9AA5AF` |
| text-subtle | `#98A1A9` | `#6F7C87` |
| border | `#EBEEF0` | `#2E353C` |
| border-strong | `#D8DEE3` | `#3A424A` |
| primary | `#2490EF` | `#3B9BF2` |
| on-primary | `#FFFFFF` | `#0B1116` |

**Status hues** (dot/base = 500; pill text = 700 light / 300 dark): gray `#98A1A9`, blue `#2490EF`, green `#38A160`, orange `#F0851B`, yellow `#E0A93A`, red `#E03636`, purple `#7C4DFF`, cyan `#1AAFC4`.

**Radius:** xs 4 · sm 6 · md 8 · lg 12 · xl 16 · full 999.
**Spacing (4px grid):** 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40.
**Elevation:** ERPNext is shadow-light. Cards/headers use 1px borders; reserve soft shadows (`md`) only for FAB, sheets, dialogs.
**Min tap target:** 44px (warehouse/gloved use).

---

## 6. Suggested commit order

1. `app_theme.dart` tokens + wire Inter + `AppScheme` (both light and dark). _(prereq)_
2. Family A — extend `DocTypeListHeader` with `HeaderKind`, build `FilterChipRow`; migrate one list + one form screen as the reference, then the rest.
3. Family B — `EmptyState`, `SkeletonBox`, `DocCardSkeleton`; wire into list controllers' loading/empty/error states.
4. Family C — `StatusBadge`, `CountBadge`, `AppAvatar`, `AvatarGroup`, `DocTabBar`; replace ad-hoc usages.
5. Theme plumbing — `ThemeController` + persisted `ThemeMode`, `theme`/`darkTheme`/`themeMode` on `GetMaterialApp`, drawer/profile toggle. (Stand this up alongside step 1 so every widget is built and reviewed in both themes from the start — not bolted on at the end.)

Each step: `flutter analyze` clean, run on a device, and verify the widget against the matching HTML section in **both** light and dark (the reference header toggles themes). A step is not done until both themes match.

---

## 7. Files in this bundle
- `Multimax Design System.html` — interactive design reference (open in browser; header toggles light/dark).
- `ds.css` — canonical tokens + component styles (source of truth for all values).
