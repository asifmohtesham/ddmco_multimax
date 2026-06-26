# Global Design System — Foundation (Tokens + Light/Dark Theme) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize the ERPNext v15 design tokens into one source of truth, bundle the Inter font, and wire full light + dark (Timeless Night) theming into the app via a persisted GetX `ThemeController` — while keeping the existing **maroon** brand primary.

**Architecture:** A new `app_theme.dart` holds token constants (`AppColors`, `AppRadius`, `AppSpace`) and a per-brightness semantic palette (`AppScheme.light` / `AppScheme.dark`) plus a `BuildContext.scheme` extension. A single `_buildTheme(AppScheme)` function in `main.dart` produces both the light and dark `ThemeData`, so they can never drift. A `ThemeController` (GetX, `permanent: true`) holds `Rx<ThemeMode>`, persists the choice through `DatabaseService`'s existing `config` key-value table, and drives `GetMaterialApp.themeMode`. A drawer entry lets the user cycle System → Light → Dark.

**Tech Stack:** Flutter (Material 3), GetX (`get: ^4.7.2`), sqflite (`DatabaseService`), bundled Inter `.ttf` assets. Dart SDK `^3.8.1`.

## Global Constraints

- **Keep maroon primary.** Light primary stays `#870E18`; do **not** switch to ERPNext blue. Adopt the neutral/status/spacing/radius tokens and dark mode only.
- **Light + dark is mandatory.** Every value added here must resolve correctly in both `AppScheme.light` and `AppScheme.dark`.
- **No hex literals at call sites.** All colors come from `AppColors` / `AppScheme`. (This plan only adds the tokens + theme; rolling existing call sites onto tokens is deferred to the Family plans.)
- **Inter is bundled as an asset** (offline warehouse app — no `google_fonts`).
- **Existing two header widgets stay separate** (`DocTypeListHeader`, `DocTypeFormHeader`). Not touched in this plan.
- **GetX patterns:** controller extends `GetxController`; observables use `.obs`; registered in `main.dart` with `permanent: true`.
- Each task ends with `flutter analyze` clean (no new warnings) and its tests passing.
- Run commands from repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`.

### Locked design values (maroon-adapted, tweakable at design review)

| Token | Light | Dark (Timeless Night) |
|---|---|---|
| bg (page) | `#F4F5F6` | `#15191D` |
| fg (card/surface) | `#FFFFFF` | `#1F262C` |
| subtle | `#F9FAFA` | `#262D34` |
| text | `#1F272E` | `#EEF1F4` |
| textMuted | `#74808B` | `#9AA5AF` |
| textSubtle | `#98A1A9` | `#6F7C87` |
| border | `#EBEEF0` | `#2E353C` |
| borderStrong | `#D8DEE3` | `#3A424A` |
| **primary** | `#870E18` (maroon) | `#D9707C` (lightened maroon) |
| **onPrimary** | `#FFFFFF` | `#2A0509` |
| secondary | `#25286F` (indigo) | `#8C8FE0` (lightened indigo) |

> Dark primary/onPrimary follow the ERPNext pattern (light accent + dark on-color) so `primary` reads correctly both as a button fill *and* as accent text on a dark surface. These two values are the only invented colors — flag them at design review.

---

### Task 1: Design tokens — `app_theme.dart`

**Files:**
- Create: `lib/app/data/constants/app_theme.dart`
- Test: `test/unit/app_theme_test.dart`

**Interfaces:**
- Produces:
  - `class AppColors` — `static const Color` ramps: `gray50..gray900`, plus `blue/green/red/orange/yellow/purple/cyan` at `300/500/700` (and `blue600`).
  - `class AppScheme` — fields `bg, fg, subtle, text, textMuted, textSubtle, border, borderStrong, primary, onPrimary, secondary` (all `Color`); `static const AppScheme light`; `static const AppScheme dark`; `static AppScheme of(Brightness b)`.
  - `class AppRadius` — `static const double xs=4, sm=6, md=8, lg=12, xl=16, full=999`.
  - `class AppSpace` — `static const double s1=4, s2=8, s3=12, s4=16, s5=20, s6=24, s8=32, s10=40`.
  - `extension AppSchemeX on BuildContext { AppScheme get scheme; }` — returns `AppScheme.of(Theme.of(this).brightness)`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/app_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

void main() {
  group('AppScheme', () {
    test('light uses maroon primary and white surface', () {
      expect(AppScheme.light.primary, const Color(0xFF870E18));
      expect(AppScheme.light.onPrimary, const Color(0xFFFFFFFF));
      expect(AppScheme.light.fg, const Color(0xFFFFFFFF));
      expect(AppScheme.light.bg, const Color(0xFFF4F5F6));
      expect(AppScheme.light.text, const Color(0xFF1F272E));
    });

    test('dark uses lightened maroon primary and dark surfaces', () {
      expect(AppScheme.dark.primary, const Color(0xFFD9707C));
      expect(AppScheme.dark.onPrimary, const Color(0xFF2A0509));
      expect(AppScheme.dark.fg, const Color(0xFF1F262C));
      expect(AppScheme.dark.bg, const Color(0xFF15191D));
      expect(AppScheme.dark.text, const Color(0xFFEEF1F4));
    });

    test('of() resolves by brightness', () {
      expect(AppScheme.of(Brightness.light), same(AppScheme.light));
      expect(AppScheme.of(Brightness.dark), same(AppScheme.dark));
    });
  });

  group('tokens', () {
    test('radius and spacing scales match the design system', () {
      expect(AppRadius.md, 8.0);
      expect(AppRadius.full, 999.0);
      expect(AppSpace.s4, 16.0);
      expect(AppSpace.s10, 40.0);
    });

    test('neutral ramp anchors match ds.css', () {
      expect(AppColors.gray50, const Color(0xFFF9FAFA));
      expect(AppColors.gray900, const Color(0xFF1F272E));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/app_theme_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../app_theme.dart'` (file not created yet).

- [ ] **Step 3: Write minimal implementation**

Create `lib/app/data/constants/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

/// ERPNext v15 design tokens — see docs/design_handoff_global_components/ds.css.
/// NOTE: the app keeps its maroon brand primary; only the neutral/status/
/// spacing/radius ramps and dark-mode surfaces come from ERPNext v15.
class AppColors {
  AppColors._();

  // Neutral ramp (Frappe gray scale)
  static const gray50 = Color(0xFFF9FAFA);
  static const gray100 = Color(0xFFF4F5F6);
  static const gray200 = Color(0xFFEBEEF0);
  static const gray300 = Color(0xFFD8DEE3);
  static const gray400 = Color(0xFFBCC4CB);
  static const gray500 = Color(0xFF98A1A9);
  static const gray600 = Color(0xFF74808B);
  static const gray700 = Color(0xFF525C66);
  static const gray800 = Color(0xFF323A45);
  static const gray900 = Color(0xFF1F272E);

  // Status ramps — 300 = dark-mode text, 500 = base/dot, 700 = light-mode text.
  static const blue300 = Color(0xFF7CC0F7);
  static const blue500 = Color(0xFF2490EF);
  static const blue600 = Color(0xFF1F75C9);
  static const blue700 = Color(0xFF18599A);
  static const green300 = Color(0xFF8FD3A8);
  static const green500 = Color(0xFF38A160);
  static const green700 = Color(0xFF1F5E34);
  static const red300 = Color(0xFFF09494);
  static const red500 = Color(0xFFE03636);
  static const red700 = Color(0xFF9A2222);
  static const orange300 = Color(0xFFF7B67A);
  static const orange500 = Color(0xFFF0851B);
  static const orange700 = Color(0xFF9E5409);
  static const yellow300 = Color(0xFFF3D08C);
  static const yellow500 = Color(0xFFE0A93A);
  static const yellow700 = Color(0xFF946817);
  static const purple300 = Color(0xFFB6A0FF);
  static const purple500 = Color(0xFF7C4DFF);
  static const purple700 = Color(0xFF4E29AB);
  static const cyan300 = Color(0xFF7FD3DF);
  static const cyan500 = Color(0xFF1AAFC4);
  static const cyan700 = Color(0xFF0D6675);
}

/// Semantic palette resolved per brightness (light / Timeless Night dark).
class AppScheme {
  final Color bg;
  final Color fg;
  final Color subtle;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color border;
  final Color borderStrong;
  final Color primary;
  final Color onPrimary;
  final Color secondary;

  const AppScheme({
    required this.bg,
    required this.fg,
    required this.subtle,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
  });

  static const light = AppScheme(
    bg: AppColors.gray100,
    fg: Color(0xFFFFFFFF),
    subtle: AppColors.gray50,
    text: AppColors.gray900,
    textMuted: AppColors.gray600,
    textSubtle: AppColors.gray500,
    border: AppColors.gray200,
    borderStrong: AppColors.gray300,
    primary: Color(0xFF870E18), // maroon brand — kept
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF25286F), // indigo
  );

  static const dark = AppScheme(
    bg: Color(0xFF15191D),
    fg: Color(0xFF1F262C),
    subtle: Color(0xFF262D34),
    text: Color(0xFFEEF1F4),
    textMuted: Color(0xFF9AA5AF),
    textSubtle: Color(0xFF6F7C87),
    border: Color(0xFF2E353C),
    borderStrong: Color(0xFF3A424A),
    primary: Color(0xFFD9707C), // lightened maroon for dark surfaces
    onPrimary: Color(0xFF2A0509),
    secondary: Color(0xFF8C8FE0), // lightened indigo
  );

  static AppScheme of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

class AppRadius {
  AppRadius._();
  static const double xs = 4, sm = 6, md = 8, lg = 12, xl = 16, full = 999;
}

class AppSpace {
  AppSpace._();
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 20, s6 = 24, s8 = 32, s10 = 40;
}

/// `context.scheme` → the active [AppScheme] for the current brightness.
extension AppSchemeX on BuildContext {
  AppScheme get scheme => AppScheme.of(Theme.of(this).brightness);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/app_theme_test.dart`
Expected: PASS (all tests green).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/data/constants/app_theme.dart test/unit/app_theme_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/constants/app_theme.dart test/unit/app_theme_test.dart
git commit -m "feat(theme): add ERPNext v15 design tokens + AppScheme (maroon primary, light/dark)"
```

---

### Task 2: Bundle the Inter font

**Files:**
- Create (binary, downloaded): `lib/assets/fonts/Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf`
- Modify: `pubspec.yaml:56-60` (add an `Inter` family under the existing `fonts:` list)

**Interfaces:**
- Produces: a Flutter font family named `Inter` with weights 400/500/600/700, available for `ThemeData.fontFamily` in Task 4.

- [ ] **Step 1: Download the four Inter weights into the fonts asset dir**

Run (PowerShell, repo root). Source is the official rsms/inter static TTFs mirrored on the Google Fonts GitHub repo:

```powershell
$base = "https://github.com/google/fonts/raw/main/ofl/inter"
$dest = "lib/assets/fonts"
$map = @{
  "Inter-Regular.ttf"  = "Inter%5Bopsz,wght%5D.ttf"
}
# Variable font fallback is messy; download the 4 static weights from rsms instead:
$rsms = "https://github.com/rsms/inter/raw/master/docs/font-files"
Invoke-WebRequest "$rsms/Inter-Regular.ttf"  -OutFile "$dest/Inter-Regular.ttf"
Invoke-WebRequest "$rsms/Inter-Medium.ttf"   -OutFile "$dest/Inter-Medium.ttf"
Invoke-WebRequest "$rsms/Inter-SemiBold.ttf" -OutFile "$dest/Inter-SemiBold.ttf"
Invoke-WebRequest "$rsms/Inter-Bold.ttf"     -OutFile "$dest/Inter-Bold.ttf"
```

Expected: four `.ttf` files present in `lib/assets/fonts/`. Verify with `Get-ChildItem lib/assets/fonts/Inter-*.ttf` (each > 200 KB). If a URL 404s, fall back to downloading from https://rsms.me/inter/font-files/ or the rsms GitHub Releases zip and extract the four static weights — the family name registered in `pubspec.yaml` must remain `Inter`.

- [ ] **Step 2: Register the family in pubspec.yaml**

Edit `pubspec.yaml` — extend the existing `fonts:` block (currently only `ShureTechMono`) to add Inter:

```yaml
  fonts:
    - family: ShureTechMono
      fonts:
        - asset: lib/assets/fonts/ShureTechMonoNerdFontMono-Regular.ttf
          style: normal
    - family: Inter
      fonts:
        - asset: lib/assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: lib/assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: lib/assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: lib/assets/fonts/Inter-Bold.ttf
          weight: 700
```

(The `lib/assets/fonts/` directory is already declared under `assets:` at line 54, so no `assets:` change is needed.)

- [ ] **Step 3: Refresh packages and verify config parses**

Run: `flutter pub get`
Expected: "Got dependencies!" with no pubspec parse error.

- [ ] **Step 4: Analyze (whole project — pubspec change)**

Run: `flutter analyze`
Expected: no new issues introduced by the pubspec edit.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml lib/assets/fonts/Inter-Regular.ttf lib/assets/fonts/Inter-Medium.ttf lib/assets/fonts/Inter-SemiBold.ttf lib/assets/fonts/Inter-Bold.ttf
git commit -m "chore(theme): bundle Inter font (400/500/600/700) as assets"
```

---

### Task 3: `ThemeController` (persisted ThemeMode)

**Files:**
- Create: `lib/app/modules/theme/theme_controller.dart`
- Test: `test/unit/theme_controller_test.dart`

**Interfaces:**
- Consumes: `DatabaseService.saveConfig(String,String)` / `getConfig(String)` (from `lib/app/data/services/database_service.dart`) — injected as function seams for testability.
- Produces:
  - `class ThemeController extends GetxController`
    - `static const String storageKey = 'theme_mode';`
    - constructor `ThemeController({Future<void> Function(String,String)? persist, Future<String?> Function(String)? restore})` — both default to `DatabaseService` lookups via `Get.find` at call time.
    - `final Rx<ThemeMode> themeMode` (initial `ThemeMode.system`).
    - `static ThemeMode themeModeFromName(String? name)` / `static String themeModeToName(ThemeMode m)`.
    - `Future<void> loadPersisted()` — restores from storage into `themeMode`.
    - `Future<void> setThemeMode(ThemeMode mode)` — updates `themeMode`, calls `Get.changeThemeMode(mode)`, persists.
    - `void cycleThemeMode()` — System → Light → Dark → System.

- [ ] **Step 1: Write the failing test**

Create `test/unit/theme_controller_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('serialization', () {
    test('round-trips every ThemeMode by name', () {
      for (final m in ThemeMode.values) {
        expect(
          ThemeController.themeModeFromName(ThemeController.themeModeToName(m)),
          m,
        );
      }
    });

    test('unknown / null name falls back to system', () {
      expect(ThemeController.themeModeFromName(null), ThemeMode.system);
      expect(ThemeController.themeModeFromName('garbage'), ThemeMode.system);
    });
  });

  group('state + persistence', () {
    test('defaults to system', () {
      final c = ThemeController();
      expect(c.themeMode.value, ThemeMode.system);
    });

    test('setThemeMode updates Rx and persists the name', () async {
      String? savedKey;
      String? savedValue;
      final c = ThemeController(
        persist: (k, v) async {
          savedKey = k;
          savedValue = v;
        },
        restore: (_) async => null,
      );

      await c.setThemeMode(ThemeMode.dark);

      expect(c.themeMode.value, ThemeMode.dark);
      expect(savedKey, ThemeController.storageKey);
      expect(savedValue, 'dark');
    });

    test('loadPersisted restores a saved mode', () async {
      final c = ThemeController(
        persist: (_, __) async {},
        restore: (_) async => 'light',
      );

      await c.loadPersisted();

      expect(c.themeMode.value, ThemeMode.light);
    });

    test('cycleThemeMode advances system -> light -> dark -> system', () async {
      final c = ThemeController(persist: (_, __) async {}, restore: (_) async => null);
      expect(c.themeMode.value, ThemeMode.system);
      c.cycleThemeMode();
      expect(c.themeMode.value, ThemeMode.light);
      c.cycleThemeMode();
      expect(c.themeMode.value, ThemeMode.dark);
      c.cycleThemeMode();
      expect(c.themeMode.value, ThemeMode.system);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/theme_controller_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../theme_controller.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/app/modules/theme/theme_controller.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/database_service.dart';

/// Holds the user's [ThemeMode] choice and persists it via [DatabaseService].
///
/// [persist]/[restore] are injectable seams so the controller is unit-testable
/// without a real SQLite database. In production they default to the registered
/// [DatabaseService].
class ThemeController extends GetxController {
  static const String storageKey = 'theme_mode';

  final Future<void> Function(String key, String value) _persist;
  final Future<String?> Function(String key) _restore;

  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;

  ThemeController({
    Future<void> Function(String, String)? persist,
    Future<String?> Function(String)? restore,
  })  : _persist = persist ??
            ((k, v) => Get.find<DatabaseService>().saveConfig(k, v)),
        _restore = restore ??
            ((k) => Get.find<DatabaseService>().getConfig(k));

  static String themeModeToName(ThemeMode m) => m.name; // 'system' | 'light' | 'dark'

  static ThemeMode themeModeFromName(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> loadPersisted() async {
    final stored = await _restore(storageKey);
    themeMode.value = themeModeFromName(stored);
    Get.changeThemeMode(themeMode.value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
    await _persist(storageKey, themeModeToName(mode));
  }

  void cycleThemeMode() {
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(themeMode.value) + 1) % order.length];
    setThemeMode(next);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/theme_controller_test.dart`
Expected: PASS.

> Note: `Get.changeThemeMode` is a no-op-safe call with no `GetMaterialApp` mounted in unit tests (it only updates internal state), so these tests do not need a pumped widget. If any test throws from `Get.changeThemeMode`, wrap the call site is unnecessary — the tests above avoid asserting on it.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/theme/theme_controller.dart test/unit/theme_controller_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/theme/theme_controller.dart test/unit/theme_controller_test.dart
git commit -m "feat(theme): add persisted ThemeController (system/light/dark)"
```

---

### Task 4: Build light + dark `ThemeData` from `AppScheme` and wire `GetMaterialApp`

**Files:**
- Modify: `lib/main.dart:52-163` (replace the inline single-theme `build()` with token-driven light+dark themes + `ThemeController` wiring)
- Modify: `lib/main.dart:42-49` (register `ThemeController` and load persisted mode before `runApp`)
- Test: `test/widget/theme_mode_switching_test.dart`

**Interfaces:**
- Consumes: `AppScheme` / `AppColors` / `AppRadius` (Task 1); `ThemeController` (Task 3); the `Inter` font family (Task 2).
- Produces: `ThemeData buildAppTheme(AppScheme scheme, Brightness brightness)` (top-level function in `main.dart`) used for both `theme:` and `darkTheme:`; `GetMaterialApp` bound to `themeMode: themeController.themeMode.value` inside an `Obx`.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/theme_mode_switching_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

void main() {
  testWidgets('buildAppTheme yields maroon primary in light, brighter in dark',
      (tester) async {
    final light = buildAppTheme(AppSchemeLightForTest, Brightness.light);
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF870E18));
    expect(light.textTheme.bodyMedium?.fontFamily, 'Inter');

    final dark = buildAppTheme(AppSchemeDarkForTest, Brightness.dark);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colorScheme.primary, const Color(0xFFD9707C));
  });

  testWidgets('GetMaterialApp reacts to ThemeController.themeMode', (tester) async {
    final controller = Get.put(ThemeController(
      persist: (_, __) async {},
      restore: (_) async => null,
    ));

    await tester.pumpWidget(const MultimaxApp(initialRoute: '/'));
    await tester.pump();

    controller.themeMode.value = ThemeMode.dark;
    await tester.pump();

    final app = tester.widget<GetMaterialApp>(find.byType(GetMaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    Get.reset();
  });
}
```

> The two `AppSchemeLightForTest`/`AppSchemeDarkForTest` symbols are just `AppScheme.light`/`AppScheme.dark`; import them. Replace the test's references with `AppScheme.light` / `AppScheme.dark` directly and add `import 'package:multimax/app/data/constants/app_theme.dart';`. (Names spelled out here only to avoid an undefined symbol if you copy verbatim — prefer the direct `AppScheme.light` form.)

Corrected imports/usage — the test file should read:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

void main() {
  testWidgets('buildAppTheme yields maroon primary in light, brighter in dark',
      (tester) async {
    final light = buildAppTheme(AppScheme.light, Brightness.light);
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF870E18));
    expect(light.textTheme.bodyMedium?.fontFamily, 'Inter');

    final dark = buildAppTheme(AppScheme.dark, Brightness.dark);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colorScheme.primary, const Color(0xFFD9707C));
  });

  testWidgets('GetMaterialApp reacts to ThemeController.themeMode', (tester) async {
    final controller = Get.put(ThemeController(
      persist: (_, __) async {},
      restore: (_) async => null,
    ));

    await tester.pumpWidget(const MultimaxApp(initialRoute: '/'));
    await tester.pump();

    controller.themeMode.value = ThemeMode.dark;
    await tester.pump();

    final app = tester.widget<GetMaterialApp>(find.byType(GetMaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    Get.reset();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/theme_mode_switching_test.dart`
Expected: FAIL — `buildAppTheme` undefined and `MultimaxApp` does not yet expose `themeMode`.

- [ ] **Step 3: Implement `buildAppTheme` + rewrite `MultimaxApp.build`**

In `lib/main.dart`:

(a) Add imports near the top (after the existing imports):

```dart
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
```

(b) Replace the entire `MultimaxApp` class body (`build` method, lines 57–162) so the theme is built from `AppScheme` and both light + dark are provided. Use this top-level function + class:

```dart
/// Builds a [ThemeData] from a semantic [AppScheme]. Used for both the light
/// and dark themes so the two can never drift. Keeps the maroon brand primary.
ThemeData buildAppTheme(AppScheme scheme, Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: scheme.primary,
    brightness: brightness,
    primary: scheme.primary,
    onPrimary: scheme.onPrimary,
    secondary: scheme.secondary,
    onSecondary: brightness == Brightness.dark
        ? const Color(0xFF0B1116)
        : Colors.white,
    surface: scheme.fg,
    onSurface: scheme.text,
    outline: scheme.borderStrong,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Inter',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scheme.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: false,
      elevation: 0,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.textMuted,
      indicatorColor: scheme.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.secondary,
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: Colors.white,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    cardTheme: CardThemeData(
      color: scheme.fg,
      elevation: brightness == Brightness.dark ? 0 : 1,
      surfaceTintColor: scheme.fg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.fg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.textMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.primary),
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: TextTheme(
      titleLarge:
          TextStyle(color: scheme.text, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: scheme.text),
    ),
  );
}

class MultimaxApp extends StatelessWidget {
  final String initialRoute;

  const MultimaxApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'KA-ML Fulfillment',
          initialRoute: initialRoute,
          getPages: AppPages.routes,
          theme: buildAppTheme(AppScheme.light, Brightness.light),
          darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
          themeMode: themeController.themeMode.value,
          defaultTransition: Transition.fadeIn,
          routingCallback: (routing) {
            if (routing?.current != null &&
                Get.isRegistered<HomeController>()) {
              Get.find<HomeController>().updateActiveScreen(routing!.current);
            }
          },
        ));
  }
}
```

(c) In `main()`, register the controller and load the persisted mode. Insert **after** the `AuthenticationController` block (line 42) and before `runApp` (line 47):

```dart
  Get.put<ThemeController>(ThemeController(), permanent: true);
  await Get.find<ThemeController>().loadPersisted();
```

- [ ] **Step 4: Run the widget test to verify it passes**

Run: `flutter test test/widget/theme_mode_switching_test.dart`
Expected: PASS.

> If the second test trips over services that `MultimaxApp` doesn't actually use at construction (it only needs `ThemeController` + `HomeController` lookup guarded by `isRegistered`), no extra registration is required. If `GetMaterialApp` route resolution throws for the `/` route, change `initialRoute: '/'` in the test to `AppRoutes.LOGIN` and add `import 'package:multimax/app/data/routes/app_routes.dart';`.

- [ ] **Step 5: Run the full test suite (guard against regressions)**

Run: `flutter test`
Expected: PASS for the new tests. Pre-existing failures in `status_pill` / `doctype_form_header` tests are known to pre-exist on `release/play-store` (see project memory) — confirm the count of failures did not increase beyond those.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/main.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart test/widget/theme_mode_switching_test.dart
git commit -m "feat(theme): build light+dark ThemeData from AppScheme; wire ThemeController to GetMaterialApp"
```

---

### Task 5: Drawer theme toggle (System → Light → Dark)

**Files:**
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart:164-169` (insert a theme `_DrawerItem` into the user menu, between "About" and the divider)
- Test: `test/widget/drawer_theme_toggle_test.dart`

**Interfaces:**
- Consumes: `ThemeController.cycleThemeMode()` and `themeMode` (Task 3); the existing private `_DrawerItem` widget in the same file.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/drawer_theme_toggle_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

void main() {
  testWidgets('cycleThemeMode advances the controller mode', (tester) async {
    final controller = ThemeController(
      persist: (_, __) async {},
      restore: (_) async => null,
    );
    expect(controller.themeMode.value, ThemeMode.system);

    controller.cycleThemeMode();
    expect(controller.themeMode.value, ThemeMode.light);

    Get.reset();
  });
}
```

> A full drawer render test would require registering `HomeController`, `AuthenticationController`, and `PermissionService`. That is heavier than this task warrants; the behavior wired into the drawer is `controller.cycleThemeMode()`, which is what this test covers. The drawer wiring itself is verified manually in Step 4.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/drawer_theme_toggle_test.dart`
Expected: PASS only if Task 3 is done; if `cycleThemeMode` were missing it would fail. (This test is a guard; it should pass once Task 3 is merged.) Proceed.

- [ ] **Step 3: Add the toggle item to the drawer user menu**

In `lib/app/modules/global_widgets/app_nav_drawer.dart`:

(a) Add the import at the top (after the existing `home_controller` import):

```dart
import 'package:multimax/app/modules/theme/theme_controller.dart';
```

(b) In the `userMenuItems` list, insert a new entry **between** the "About" `_DrawerItem` (ends line 169) and the `Padding`/`Divider` (line 170):

```dart
                    Obx(() {
                      final tc = Get.isRegistered<ThemeController>()
                          ? Get.find<ThemeController>()
                          : Get.put(ThemeController());
                      final mode = tc.themeMode.value;
                      final (icon, label) = switch (mode) {
                        ThemeMode.system => (Icons.brightness_auto_outlined, 'Theme: System'),
                        ThemeMode.light => (Icons.light_mode_outlined, 'Theme: Light'),
                        ThemeMode.dark => (Icons.dark_mode_outlined, 'Theme: Dark'),
                      };
                      return _DrawerItem(
                        icon: icon,
                        title: label,
                        route: '',
                        currentRoute: currentRoute,
                        onTap: (_) => tc.cycleThemeMode(),
                      );
                    }),
```

(Note: `_DrawerItem.onTap` does **not** auto-close the drawer, so tapping cycles the theme in place and the user sees the label update live — exactly what we want.)

- [ ] **Step 4: Manual on-device / emulator verification**

Run: `flutter run -d <device_id>` (see `.vscode/launch.json` for ids).
Verify:
1. Open drawer → tap user header chevron → user menu shows "Theme: System".
2. Tap it repeatedly → label cycles System → Light → Dark and the app's surfaces/scaffold switch between light and dark (maroon stays the brand color in light; lightened maroon accents in dark).
3. Fully close and relaunch the app → the last-selected theme is restored (persistence via `DatabaseService`).

> Known limitation (deferred to the Family A rollout): the drawer's own `Drawer(backgroundColor: Colors.white)` and its hardcoded `Colors.grey.*` text are not yet tokenized, so the drawer panel itself stays light in dark mode. The rest of the app responds correctly. Do not fix this here — it is part of the Family A header/surface rollout.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/app_nav_drawer.dart test/widget/drawer_theme_toggle_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/app_nav_drawer.dart test/widget/drawer_theme_toggle_test.dart
git commit -m "feat(theme): add System/Light/Dark toggle to drawer user menu"
```

---

## Self-Review

**1. Spec coverage (handoff §1 + §5 + commit-order steps 1 & 5):**
- Centralize tokens → Task 1 (`AppColors`/`AppScheme`/`AppRadius`/`AppSpace`). ✔
- Inter font → Task 2. ✔ (bundled asset per decision)
- `ThemeController` with persisted `ThemeMode`, default `system` → Task 3. ✔
- `theme`/`darkTheme`/`themeMode` on `GetMaterialApp`, built per `AppScheme` → Task 4. ✔
- Resolve colors per brightness via a `context.scheme` extension → Task 1 (`AppSchemeX`). ✔
- Drawer theme toggle → Task 5. ✔
- **Deferred by decision (documented):** ERPNext blue primary (kept maroon); the per-status 700/300 text resolver and `StatusBadge` (Family C); rolling existing call sites / drawer surfaces off hardcoded colors (Family A). These are intentionally **not** in this foundation plan.

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". All steps contain real code or exact commands. The one prose-heavy spot (Task 4 test import correction) is resolved by the second, corrected code block — the engineer should use the corrected block.

**3. Type consistency:**
- `buildAppTheme(AppScheme, Brightness)` — defined Task 4, called in Task 4 test with matching signature. ✔
- `ThemeController` API (`themeMode`, `setThemeMode`, `loadPersisted`, `cycleThemeMode`, `storageKey`, static `themeModeFromName/toName`) — consistent across Tasks 3, 4, 5. ✔
- `AppScheme` field names used in `buildAppTheme` (`bg/fg/subtle/text/textMuted/textSubtle/border/borderStrong/primary/onPrimary/secondary`) all exist on the class from Task 1. ✔
- `context.scheme` extension defined Task 1; not consumed in this plan (consumed by Family plans) — acceptable, it's the published foundation API.

---

## Execution Handoff

Foundation only. Once this ships and is verified in both themes, the Family A/B/C plans build on `AppScheme` + `context.scheme`.
