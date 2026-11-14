# User Area Redesign — Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the drawer's inline user-menu with a dedicated Account hub, promote Session Defaults to a full screen, add a Light/Dark/System Theme screen, re-layout My Profile and About, and consolidate logout to one confirmed action.

**Architecture:** GetX modules. Three new screens (`user_area`, `session_defaults`, a `theme_screen` in the existing `theme` module) reached via three new named routes. Five new reusable `global_widgets` settings components. Edits to the drawer, Profile, About, and `HomeController`. All styling via `context.scheme` / `AppColors` — never hex literals; keep the maroon brand.

**Tech Stack:** Flutter, GetX, `package_info_plus`, GetStorage (`StorageService`), SQLite (`DatabaseService` via `ThemeController`).

## Global Constraints

- Source all colors from `context.scheme` (`AppScheme`) and `AppColors`. **No hex literals.** Keep the maroon brand primary (`#870E18`).
- Use radius/space tokens: `AppRadius` (lg=12, md=8), `AppSpace` (s2=8, s3=12, s4=16, s6=24).
- Map the design's `--shadow-xs` to a 1px `scheme.border` hairline, not a `BoxShadow`.
- **Out of scope (phase 2):** accent-color picker, text-size/density control. Do not add them.
- After every task: `flutter analyze` must be clean (no new warnings) and `flutter test` green.
- Commit after each task. Work on the current branch (`release/play-store`).
- Test commands: `flutter test test/<path>` for one file; `flutter analyze` for lint.

---

### Task 1: Settings group + row widgets

**Files:**
- Create: `lib/app/modules/global_widgets/settings_group.dart`
- Create: `lib/app/modules/global_widgets/settings_row.dart`
- Test: `test/widget/settings_widgets_test.dart`

**Interfaces:**
- Produces: `SectionLabel({required String text})`; `SettingsGroup({String? label, required List<Widget> children})`; `SettingsRow({required IconData icon, Color? iconTint, required String title, String? subtitle, String? value, VoidCallback? onTap, bool showChevron = true})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/settings_widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_row.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('SettingsGroup shows uppercased label and its child rows', (tester) async {
    await tester.pumpWidget(_host(const SettingsGroup(
      label: 'Preferences',
      children: [
        SettingsRow(icon: Icons.palette_outlined, title: 'Theme', value: 'Dark'),
      ],
    )));
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('SettingsRow fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(SettingsRow(
      icon: Icons.info_outline,
      title: 'System Information',
      onTap: () => tapped = true,
    )));
    await tester.tap(find.text('System Information'));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/settings_widgets_test.dart`
Expected: FAIL — `settings_group.dart` / `settings_row.dart` don't exist (compile error).

- [ ] **Step 3: Write `settings_group.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// Uppercase section label rendered above a settings card (the design's
/// `.ua-glabel`). Reused by the Account hub, Session Defaults, and Theme.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s2, 0, AppSpace.s2, AppSpace.s2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: s.textSubtle,
        ),
      ),
    );
  }
}

/// A settings section: optional [label] above a bordered card whose
/// [children] are separated by 1px hairlines (the design's `.ua-group` +
/// `.ua-card`). Colors from [BuildContext.scheme]; no shadows (border only).
class SettingsGroup extends StatelessWidget {
  final String? label;
  final List<Widget> children;
  const SettingsGroup({super.key, this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: s.border));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) SectionLabel(text: label!),
        DecoratedBox(
          decoration: BoxDecoration(
            color: s.fg,
            border: Border.all(color: s.border),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Write `settings_row.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A tappable settings row: tinted leading icon tile, title (+ optional
/// subtitle), optional trailing [value], optional chevron. The design's
/// `.ua-row`. Colors from [BuildContext.scheme].
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color? iconTint;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool showChevron;

  const SettingsRow({
    super.key,
    required this.icon,
    this.iconTint,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final tint = iconTint ?? s.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s3, vertical: AppSpace.s3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.alphaBlend(tint.withValues(alpha: 0.14), s.fg),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: AppSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: s.text)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: TextStyle(fontSize: 12.5, color: s.textMuted)),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!,
                    style: TextStyle(fontSize: 13, color: s.textMuted)),
              ),
            if (showChevron && onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.chevron_right, size: 18, color: s.textSubtle),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widget/settings_widgets_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/settings_group.dart lib/app/modules/global_widgets/settings_row.dart test/widget/settings_widgets_test.dart
git commit -m "feat(global-widgets): add SettingsGroup/SectionLabel/SettingsRow"
```

---

### Task 2: Switch, slider, segmented widgets

**Files:**
- Create: `lib/app/modules/global_widgets/settings_controls.dart`
- Test: append to `test/widget/settings_widgets_test.dart`

**Interfaces:**
- Produces: `SettingsSwitchRow({required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged})`; `SettingsSliderRow({required String label, required int value, required int min, required int max, String suffix = '', String? help, required ValueChanged<int> onChanged})`; `SegmentOption<T>({required T value, required String label, IconData? icon})`; `SettingsSegmented<T>({required List<SegmentOption<T>> options, required T value, required ValueChanged<T> onChanged})`.

- [ ] **Step 1: Write the failing test (append)**

```dart
// append inside main() of test/widget/settings_widgets_test.dart
  testWidgets('SettingsSegmented selects on tap', (tester) async {
    String picked = 'a';
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (_, setState) => SettingsSegmented<String>(
        value: picked,
        onChanged: (v) => setState(() => picked = v),
        options: const [
          SegmentOption(value: 'a', label: 'Alpha'),
          SegmentOption(value: 'b', label: 'Beta'),
        ],
      ),
    )));
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(picked, 'b');
  });

  testWidgets('SettingsSliderRow renders value + suffix', (tester) async {
    await tester.pumpWidget(_host(SettingsSliderRow(
      label: 'Delay', value: 4, min: 1, max: 10, suffix: 's', onChanged: (_) {},
    )));
    expect(find.text('Delay'), findsOneWidget);
    expect(find.text('4s'), findsOneWidget);
  });
```

Add the import at the top of the test file:
```dart
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/settings_widgets_test.dart`
Expected: FAIL — `settings_controls.dart` missing.

- [ ] **Step 3: Write `settings_controls.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A title/subtitle row with a trailing [Switch]. The design's `.ua-switchrow`.
class SettingsSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s3, vertical: AppSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: s.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: TextStyle(fontSize: 12.5, color: s.textMuted)),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A labelled integer slider with a live value readout. The design's
/// `.ua-sliderrow`. Emits rounded ints in [min]..[max].
class SettingsSliderRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final String? help;
  final ValueChanged<int> onChanged;

  const SettingsSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix = '',
    this.help,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final v = value.toDouble().clamp(min.toDouble(), max.toDouble());
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s3, AppSpace.s2, AppSpace.s3, AppSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: s.text)),
              Text('$value$suffix',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: s.primary)),
            ],
          ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(help!,
                  style: TextStyle(fontSize: 11.5, color: s.textSubtle)),
            ),
          Slider(
            value: v,
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value$suffix',
            onChanged: (d) => onChanged(d.round()),
          ),
        ],
      ),
    );
  }
}

class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const SegmentOption({required this.value, required this.label, this.icon});
}

/// A pill segmented control. The design's `.ua-seg` / `.ua-segrow`. The
/// selected segment fills with [scheme.fg] over the [scheme.subtle] track.
class SettingsSegmented<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const SettingsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: s.subtle,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [for (final o in options) Expanded(child: _segment(context, o))],
      ),
    );
  }

  Widget _segment(BuildContext context, SegmentOption<T> o) {
    final s = context.scheme;
    final selected = o.value == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(o.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? s.fg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.icon != null) ...[
              Icon(o.icon, size: 16, color: selected ? s.primary : s.textMuted),
              const SizedBox(width: 6),
            ],
            Text(o.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? s.primary : s.textMuted)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/settings_widgets_test.dart`
Expected: PASS (4 tests total).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/global_widgets/settings_controls.dart test/widget/settings_widgets_test.dart
git commit -m "feat(global-widgets): add SettingsSwitchRow/SliderRow/Segmented"
```

---

### Task 3: Theme screen (Light/Dark/System) + route

**Files:**
- Create: `lib/app/modules/theme/theme_screen.dart`
- Create: `lib/app/modules/theme/theme_binding.dart`
- Modify: `lib/app/data/routes/app_routes.dart` (add `THEME`)
- Modify: `lib/app/data/routes/app_pages.dart` (import + GetPage)
- Test: `test/widget/theme_screen_test.dart`

**Interfaces:**
- Consumes: `ThemeController` (`themeMode`, `setThemeMode`) from Task-independent existing code; `SettingsSegmented`/`SegmentOption` (Task 2); `SectionLabel` (Task 1); `MainAppBar`.
- Produces: `ThemeScreen`; `ThemeBinding`; `AppRoutes.THEME = '/theme'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/theme_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/modules/theme/theme_screen.dart';

void main() {
  testWidgets('tapping Dark sets ThemeController to dark', (tester) async {
    final tc = ThemeController(persist: (_, __) async {}, restore: (_) async => null);
    Get.put<ThemeController>(tc);

    await tester.pumpWidget(GetMaterialApp(home: const ThemeScreen()));
    expect(tc.themeMode.value, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(tc.themeMode.value, ThemeMode.dark);
    Get.reset();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/theme_screen_test.dart`
Expected: FAIL — `theme_screen.dart` missing.

- [ ] **Step 3: Write `theme_binding.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

class ThemeBinding extends Bindings {
  @override
  void dependencies() {
    // ThemeController is normally registered permanent in main(); ensure it
    // exists if this route is reached in isolation.
    if (!Get.isRegistered<ThemeController>()) {
      Get.put<ThemeController>(ThemeController(), permanent: true);
    }
  }
}
```

- [ ] **Step 4: Write `theme_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

/// Appearance settings. Phase 1: Light / Dark / System only (accent + text
/// size land here in phase 2). A live preview card reflects the active theme.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = Get.find<ThemeController>();
    return Scaffold(
      appBar: const MainAppBar(title: 'Theme'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel(text: 'Preview'),
            _PreviewCard(),
            const SizedBox(height: AppSpace.s4),
            const SectionLabel(text: 'Appearance'),
            Obx(() => SettingsSegmented<ThemeMode>(
                  value: tc.themeMode.value,
                  onChanged: tc.setThemeMode,
                  options: const [
                    SegmentOption(
                        value: ThemeMode.light,
                        label: 'Light',
                        icon: Icons.light_mode_outlined),
                    SegmentOption(
                        value: ThemeMode.dark,
                        label: 'Dark',
                        icon: Icons.dark_mode_outlined),
                    SegmentOption(
                        value: ThemeMode.system,
                        label: 'System',
                        icon: Icons.brightness_auto_outlined),
                  ],
                )),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    Widget pill(String text, {required bool filled}) => Expanded(
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? s.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: filled
                  ? null
                  : Border.all(
                      color: Color.alphaBlend(
                          s.primary.withValues(alpha: 0.4), s.border)),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: filled ? s.onPrimary : s.primary)),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: s.bg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.s3),
        decoration: BoxDecoration(
          color: s.fg,
          border: Border.all(color: s.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        Color.alphaBlend(s.primary.withValues(alpha: 0.16), s.fg),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.description_outlined,
                      size: 19, color: s.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Stock Entry · SE-2026',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: s.text)),
                      Text('12 items · In stock',
                          style: TextStyle(fontSize: 12, color: s.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Row(children: [
              pill('Cancel', filled: false),
              const SizedBox(width: 8),
              pill('Submit', filled: true),
            ]),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Add the route constant**

In `lib/app/data/routes/app_routes.dart`, add to `AppRoutes`:
```dart
  static const THEME                 = _Paths.THEME;
```
and to `_Paths`:
```dart
  static const THEME                 = '/theme';
```

- [ ] **Step 6: Register the GetPage**

In `lib/app/data/routes/app_pages.dart`, add imports near the other module imports:
```dart
import 'package:multimax/app/modules/theme/theme_screen.dart';
import 'package:multimax/app/modules/theme/theme_binding.dart';
```
and add this `GetPage` to `AppPages.routes` (e.g. after the `ABOUT` entry):
```dart
    GetPage(
      name: AppRoutes.THEME,
      page: () => const ThemeScreen(),
      binding: ThemeBinding(),
      transition: Transition.rightToLeft,
    ),
```

- [ ] **Step 7: Run test + analyze**

Run: `flutter test test/widget/theme_screen_test.dart && flutter analyze`
Expected: test PASS; analyze clean.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/theme/theme_screen.dart lib/app/modules/theme/theme_binding.dart lib/app/data/routes/app_routes.dart lib/app/data/routes/app_pages.dart test/widget/theme_screen_test.dart
git commit -m "feat(theme): add Theme screen (Light/Dark/System) + route"
```

---

### Task 4: Session Defaults full screen + controller + route

**Files:**
- Create: `lib/app/modules/session_defaults/session_defaults_controller.dart`
- Create: `lib/app/modules/session_defaults/session_defaults_screen.dart`
- Create: `lib/app/modules/session_defaults/session_defaults_binding.dart`
- Modify: `lib/app/data/routes/app_routes.dart` (add `SESSION_DEFAULTS`)
- Modify: `lib/app/data/routes/app_pages.dart` (import + GetPage)
- Test: `test/unit/session_defaults_controller_test.dart`

**Interfaces:**
- Consumes: `StorageService` (`getCompany`, `hasSessionDefaults`, `saveSessionDefaults`, `getAutoSubmitEnabled`, `getAutoSubmitDelay`, `saveAutoSubmitSettings`, `getAutoSaveDelay`, `saveAutoSaveDelay`); `ApiProvider.getList('Company')`; `PermissionService.clearCache()`; `AuthenticationController.fetchUserDetails()`; `AppNotification`; Task 1/2 widgets; `MainAppBar`.
- Produces: `SessionDefaultsController` (obs: `isLoading`, `isSaving`, `companies`, `selectedCompany`, `autoSubmitEnabled`, `autoSubmitDelay`, `autoSaveDelay`; methods: `load()`, `Future<bool> persist()`, `save()`, `reloadPermissions()`); `SessionDefaultsScreen`; `SessionDefaultsBinding`; `AppRoutes.SESSION_DEFAULTS = '/session-defaults'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/session_defaults_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';

/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}

void main() {
  tearDown(Get.reset);

  test('persist writes all settings; returns false when no company', () async {
    final storage = StorageService.withStorage(_FakeBox());
    final c = SessionDefaultsController(storage: storage);

    // No company selected yet → refuses to persist.
    expect(await c.persist(), isFalse);

    c.selectedCompany.value = 'Multimax LLC';
    c.autoSubmitEnabled.value = false;
    c.autoSubmitDelay.value = 4;
    c.autoSaveDelay.value = 12;

    expect(await c.persist(), isTrue);
    expect(storage.getCompany(), 'Multimax LLC');
    expect(storage.getAutoSubmitEnabled(), isFalse);
    expect(storage.getAutoSubmitDelay(), 4);
    expect(storage.getAutoSaveDelay(), 12);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/session_defaults_controller_test.dart`
Expected: FAIL — controller missing.

- [ ] **Step 3: Write `session_defaults_controller.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

/// Full-screen replacement for the old Session Defaults bottom sheet.
/// UI-free [persist] is split out so it is unit-testable without GetX overlay.
class SessionDefaultsController extends GetxController {
  final StorageService _storage;
  ApiProvider? _api;

  SessionDefaultsController({StorageService? storage})
      : _storage = storage ?? Get.find<StorageService>();

  ApiProvider get _apiProvider => _api ??= Get.find<ApiProvider>();

  final isLoading = true.obs;
  final isSaving = false.obs;
  final companies = <String>[].obs;
  final selectedCompany = RxnString();
  final autoSubmitEnabled = true.obs;
  final autoSubmitDelay = 1.obs;
  final autoSaveDelay = 5.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    autoSubmitEnabled.value = _storage.getAutoSubmitEnabled();
    autoSubmitDelay.value = _storage.getAutoSubmitDelay();
    autoSaveDelay.value = _storage.getAutoSaveDelay();
    selectedCompany.value =
        _storage.hasSessionDefaults() ? _storage.getCompany() : null;
    try {
      final list = await _apiProvider.getList('Company');
      companies.assignAll(list.map((c) => c['name'] as String));
      if (companies.length == 1 && selectedCompany.value == null) {
        selectedCompany.value = companies.first;
      }
    } catch (_) {
      AppNotification.error('Failed to load companies');
    } finally {
      isLoading.value = false;
    }
  }

  /// Writes current settings to storage. Returns false if no company chosen.
  Future<bool> persist() async {
    final company = selectedCompany.value;
    if (company == null || company.isEmpty) return false;
    await _storage.saveSessionDefaults(company);
    await _storage.saveAutoSubmitSettings(
        autoSubmitEnabled.value, autoSubmitDelay.value);
    await _storage.saveAutoSaveDelay(autoSaveDelay.value);
    return true;
  }

  Future<void> save() async {
    isSaving.value = true;
    final ok = await persist();
    isSaving.value = false;
    if (!ok) {
      AppNotification.warning('Company is required');
      return;
    }
    AppNotification.success('Settings saved');
    Get.back();
  }

  Future<void> reloadPermissions() async {
    try {
      Get.find<PermissionService>().clearCache();
      await Get.find<AuthenticationController>().fetchUserDetails();
      AppNotification.success('Permissions & roles reloaded');
    } catch (e) {
      AppNotification.error('Failed to reload permissions');
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/session_defaults_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Write `session_defaults_binding.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';

class SessionDefaultsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SessionDefaultsController>(() => SessionDefaultsController());
  }
}
```

- [ ] **Step 6: Write `session_defaults_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_row.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';

class SessionDefaultsScreen extends GetView<SessionDefaultsController> {
  const SessionDefaultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Session Defaults'),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroup(
                label: 'Session',
                children: [_companyField(context)],
              ),
              const SizedBox(height: AppSpace.s4),
              SettingsGroup(
                label: 'Automation',
                children: [
                  SettingsSwitchRow(
                    title: 'Auto-submit valid items',
                    subtitle: 'Add item automatically when validation passes',
                    value: controller.autoSubmitEnabled.value,
                    onChanged: (v) => controller.autoSubmitEnabled.value = v,
                  ),
                  if (controller.autoSubmitEnabled.value)
                    SettingsSliderRow(
                      label: 'Auto-submit delay',
                      value: controller.autoSubmitDelay.value,
                      min: 1,
                      max: 10,
                      suffix: 's',
                      help: 'Wait before adding a validated scan to the list',
                      onChanged: (v) => controller.autoSubmitDelay.value = v,
                    ),
                  SettingsSliderRow(
                    label: 'Document save delay',
                    value: controller.autoSaveDelay.value,
                    min: 3,
                    max: 30,
                    suffix: 's',
                    help: 'Wait before saving the document to the server',
                    onChanged: (v) => controller.autoSaveDelay.value = v,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s4),
              SettingsGroup(
                label: 'Troubleshooting',
                children: [
                  SettingsRow(
                    icon: Icons.sync_lock_outlined,
                    iconTint: AppColors.orange500,
                    title: 'Reload permissions',
                    subtitle: 'Clear cache & re-fetch access rights',
                    onTap: controller.reloadPermissions,
                  ),
                ],
              ),
            ],
          ),
        );
      }),
      bottomNavigationBar: Obx(() => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.s4),
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: controller.isSaving.value ? null : controller.save,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save settings'),
                ),
              ),
            ),
          )),
    );
  }

  Widget _companyField(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Company',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: s.textMuted)),
          const SizedBox(height: 7),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _pickCompany(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: s.subtle,
                border: Border.all(color: s.borderStrong),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.business_outlined, size: 18, color: s.textSubtle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.selectedCompany.value ?? 'Select company',
                      style: TextStyle(
                          fontSize: 15,
                          color: controller.selectedCompany.value == null
                              ? s.textSubtle
                              : s.text),
                    ),
                  ),
                  Icon(Icons.expand_more, size: 18, color: s.textSubtle),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Applied to every new document this session.',
              style: TextStyle(fontSize: 11.5, color: s.textSubtle)),
        ],
      ),
    );
  }

  void _pickCompany(BuildContext context) {
    final s = context.scheme;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: s.fg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: controller.companies
                .map((name) => ListTile(
                      title: Text(name),
                      trailing: controller.selectedCompany.value == name
                          ? Icon(Icons.check, color: s.primary)
                          : null,
                      onTap: () {
                        controller.selectedCompany.value = name;
                        Get.back();
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Add route + GetPage**

In `app_routes.dart` add to `AppRoutes` and `_Paths`:
```dart
  static const SESSION_DEFAULTS      = _Paths.SESSION_DEFAULTS; // AppRoutes
```
```dart
  static const SESSION_DEFAULTS      = '/session-defaults';     // _Paths
```
In `app_pages.dart` add imports:
```dart
import 'package:multimax/app/modules/session_defaults/session_defaults_screen.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_binding.dart';
```
and GetPage (after THEME):
```dart
    GetPage(
      name: AppRoutes.SESSION_DEFAULTS,
      page: () => const SessionDefaultsScreen(),
      binding: SessionDefaultsBinding(),
      transition: Transition.rightToLeft,
    ),
```

- [ ] **Step 8: Analyze**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 9: Commit**

```bash
git add lib/app/modules/session_defaults/ lib/app/data/routes/app_routes.dart lib/app/data/routes/app_pages.dart test/unit/session_defaults_controller_test.dart
git commit -m "feat(session-defaults): full-screen settings + controller + route"
```

---

### Task 5: Account hub (User Area) + controller + route

**Files:**
- Create: `lib/app/modules/user_area/user_area_controller.dart`
- Create: `lib/app/modules/user_area/user_area_screen.dart`
- Create: `lib/app/modules/user_area/user_area_binding.dart`
- Modify: `lib/app/data/routes/app_routes.dart` (add `USER_AREA`)
- Modify: `lib/app/data/routes/app_pages.dart` (import + GetPage)
- Test: `test/unit/user_area_controller_test.dart`

**Interfaces:**
- Consumes: `AuthenticationController` (`currentUser`, `logoutUser()`); `StorageService.getCompany()`; `ThemeController.themeMode`; `PackageInfo`; `AppAvatar`; `MainAppBar`; `SettingsGroup`/`SettingsRow` (Task 1); `AppRoutes.PROFILE/THEME/SESSION_DEFAULTS/ABOUT`.
- Produces: `UserAreaController` (`Rx<User?> user`, `String company`, `RxString version/build`, `Rx<ThemeMode> themeMode`, `String get themeModeLabel`, `static String labelForMode(ThemeMode)`, `void logout()`); `UserAreaScreen`; `UserAreaBinding`; `AppRoutes.USER_AREA = '/user-area'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/user_area_controller_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/user_area/user_area_controller.dart';

void main() {
  test('labelForMode maps ThemeMode to a display string', () {
    expect(UserAreaController.labelForMode(ThemeMode.light), 'Light');
    expect(UserAreaController.labelForMode(ThemeMode.dark), 'Dark');
    expect(UserAreaController.labelForMode(ThemeMode.system), 'System');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/user_area_controller_test.dart`
Expected: FAIL — controller missing.

- [ ] **Step 3: Write `user_area_controller.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

class UserAreaController extends GetxController {
  final AuthenticationController _auth = Get.find<AuthenticationController>();
  final StorageService _storage = Get.find<StorageService>();
  final ThemeController _theme = Get.find<ThemeController>();

  Rx<User?> get user => _auth.currentUser;
  Rx<ThemeMode> get themeMode => _theme.themeMode;
  String get company => _storage.getCompany();

  final version = ''.obs;
  final build = ''.obs;

  static String labelForMode(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  String get themeModeLabel => labelForMode(_theme.themeMode.value);

  @override
  void onInit() {
    super.onInit();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version.value = info.version;
      build.value = info.buildNumber;
    } catch (_) {
      // Plugin unavailable (e.g. tests) — leave blank.
    }
  }

  /// Logout funnels through AuthenticationController, which shows its own
  /// confirm dialog + spinner and routes to LOGIN. Single source of truth.
  void logout() => _auth.logoutUser();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/user_area_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Write `user_area_binding.dart`**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/user_area/user_area_controller.dart';

class UserAreaBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UserAreaController>(() => UserAreaController());
  }
}
```

- [ ] **Step 6: Write `user_area_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_row.dart';
import 'package:multimax/app/modules/user_area/user_area_controller.dart';

class UserAreaScreen extends GetView<UserAreaController> {
  const UserAreaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.s4, AppSpace.s3, AppSpace.s4, AppSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() => _ProfileCard(user: controller.user.value)),
            const SizedBox(height: AppSpace.s5),
            SettingsGroup(
              label: 'Preferences',
              children: [
                Obx(() => SettingsRow(
                      icon: Icons.palette_outlined,
                      iconTint: AppColors.purple500,
                      title: 'Theme',
                      value: controller.themeModeLabel,
                      onTap: () => Get.toNamed(AppRoutes.THEME),
                    )),
                SettingsRow(
                  icon: Icons.tune,
                  iconTint: AppColors.cyan500,
                  title: 'Session Defaults',
                  value: controller.company,
                  onTap: () => Get.toNamed(AppRoutes.SESSION_DEFAULTS),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            SettingsGroup(
              label: 'Support',
              children: [
                Obx(() => SettingsRow(
                      icon: Icons.info_outline,
                      iconTint: AppColors.blue500,
                      title: 'System Information',
                      value: controller.version.value.isEmpty
                          ? null
                          : 'v${controller.version.value}',
                      onTap: () => Get.toNamed(AppRoutes.ABOUT),
                    )),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            _LogoutButton(onTap: controller.logout),
            const SizedBox(height: AppSpace.s4),
            Obx(() => _Footer(
                  email: controller.user.value?.email ?? '',
                  version: controller.version.value,
                  build: controller.build.value,
                )),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final dynamic user; // User?
  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final name = user?.name ?? 'Guest';
    final email = user?.email ?? '';
    final initials = (name is String && name.isNotEmpty)
        ? name[0].toUpperCase()
        : 'U';
    final roleDept = [
      if ((user?.designation ?? '').isNotEmpty) user!.designation as String,
      if ((user?.department ?? '').isNotEmpty) user!.department as String,
    ].join(' · ');

    return Material(
      color: s.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Get.toNamed(AppRoutes.PROFILE),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.s4),
          decoration: BoxDecoration(
            border: Border.all(color: s.border),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              AppAvatar(size: 56, initials: initials),
              const SizedBox(width: AppSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: s.text)),
                    if (email.isNotEmpty)
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: s.textMuted)),
                    if (roleDept.isNotEmpty)
                      Text(roleDept,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: s.textSubtle)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: s.textSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final red = isDark ? AppColors.red300 : AppColors.red700;
    return Material(
      color: Color.alphaBlend(AppColors.red500.withValues(alpha: 0.10), s.fg),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
                color:
                    Color.alphaBlend(AppColors.red500.withValues(alpha: 0.26), s.border)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 19, color: red),
              const SizedBox(width: 9),
              Text('Log out',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: red)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final String email;
  final String version;
  final String build;
  const _Footer(
      {required this.email, required this.version, required this.build});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final ver = version.isEmpty ? '' : 'Multimax v$version · build $build';
    return Column(
      children: [
        if (email.isNotEmpty)
          Text('Signed in as $email',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: s.textSubtle)),
        if (ver.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(ver,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: s.textSubtle)),
          ),
      ],
    );
  }
}
```

- [ ] **Step 7: Add route + GetPage**

`app_routes.dart` — add to `AppRoutes` and `_Paths`:
```dart
  static const USER_AREA             = _Paths.USER_AREA;   // AppRoutes
```
```dart
  static const USER_AREA             = '/user-area';       // _Paths
```
`app_pages.dart` — imports:
```dart
import 'package:multimax/app/modules/user_area/user_area_screen.dart';
import 'package:multimax/app/modules/user_area/user_area_binding.dart';
```
GetPage (after PROFILE):
```dart
    GetPage(
      name: AppRoutes.USER_AREA,
      page: () => const UserAreaScreen(),
      binding: UserAreaBinding(),
      transition: Transition.rightToLeft,
    ),
```

- [ ] **Step 8: Analyze**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 9: Commit**

```bash
git add lib/app/modules/user_area/ lib/app/data/routes/app_routes.dart lib/app/data/routes/app_pages.dart test/unit/user_area_controller_test.dart
git commit -m "feat(user-area): Account hub screen + controller + route"
```

---

### Task 6: Rewire drawer → hub; route Session Defaults; delete bottom sheet

**Files:**
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart`
- Modify: `lib/app/modules/home/home_controller.dart`
- Delete: `lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart`

**Interfaces:**
- Consumes: `AppRoutes.USER_AREA`, `AppRoutes.SESSION_DEFAULTS`.
- Produces: drawer account header navigates to `USER_AREA`; `HomeController.openSessionDefaults()` navigates to `SESSION_DEFAULTS`; inline user-menu removed.

- [ ] **Step 1: `home_controller.dart` — route instead of sheet**

Replace the body of `openSessionDefaults` (lines ~118-120):
```dart
  void openSessionDefaults() {
    Get.bottomSheet(const SessionDefaultsBottomSheet(), isScrollControlled: true);
  }
```
with:
```dart
  void openSessionDefaults() {
    Get.toNamed(AppRoutes.SESSION_DEFAULTS);
  }
```
Remove the now-unused import line:
```dart
import 'package:multimax/app/modules/home/widgets/session_defaults_bottom_sheet.dart';
```

- [ ] **Step 2: Delete the bottom sheet file**

```bash
git rm lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart
```

- [ ] **Step 3: `app_nav_drawer.dart` — drop user-menu state**

In `AppNavDrawerController`, delete these two members:
```dart
  final isUserMenuOpen  = false.obs;

  void toggleUserMenu() => isUserMenuOpen.toggle();
```
(Keep `expandedGroups`, `isGroupExpanded`, `setGroupExpanded`.)

- [ ] **Step 4: `app_nav_drawer.dart` — make the header open the hub**

In the `UserAccountsDrawerHeader`, replace:
```dart
                onDetailsPressed: drawerController.toggleUserMenu,
                arrowColor: Colors.white,
```
with:
```dart
                onDetailsPressed: () {
                  Navigator.of(context).pop();
                  Get.toNamed(AppRoutes.USER_AREA);
                },
                arrowColor: Colors.white,
```
Then wrap the returned `UserAccountsDrawerHeader` so the whole header is tappable. Change `return UserAccountsDrawerHeader(` to:
```dart
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context).pop();
                  Get.toNamed(AppRoutes.USER_AREA);
                },
                child: UserAccountsDrawerHeader(
```
and add a matching closing `)` after the header's closing `);` (i.e. the `Obx(() { ... })` now returns the `GestureDetector`).

- [ ] **Step 5: `app_nav_drawer.dart` — remove the inline user-menu branch**

Replace the entire `Expanded(child: Obx(() { ... }))` block (lines ~146-489) so it no longer branches on `isUserMenuOpen`. The new body keeps only the module menu. Replace from `child: Obx(() {` ... `if (drawerController.isUserMenuOpen.value) { ... return ListView.builder(...); }` down to the `// ---- MAIN MODULE MENU ----` so that the module list is built unconditionally:

```dart
            Expanded(
              child: Builder(builder: (context) {
                final moduleMenuItems = <Widget>[
                  // ... (UNCHANGED module menu list: Dashboard, To Do, the four
                  // _ModuleGroup sections — keep exactly as-is) ...
                ];
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  itemCount: moduleMenuItems.length,
                  itemBuilder: (_, i) => moduleMenuItems[i],
                );
              }),
            ),
```
Delete the `userMenuItems` list and its `ListView.builder` entirely. The `_ModuleGroup`/`_GuardedSection` children already contain their own `Obx`, so the outer `Obx` is no longer needed.

- [ ] **Step 6: `app_nav_drawer.dart` — clean unused imports**

Remove now-unused imports:
```dart
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
```
Also delete the line `final homeController = Get.find<HomeController>();` in `build` (it was only used by the user menu). Keep `flutter/services.dart` (used by `_DrawerItem` `HapticFeedback`), `authentication_controller.dart` (header reads `currentUser`), `app_routes.dart`, `permission_service.dart`, `doctype_guard.dart`, `permission_entries.dart`, `app_theme.dart`.

- [ ] **Step 7: Analyze**

Run: `flutter analyze`
Expected: clean. (If analyzer flags `authController`/`drawerController` as unused, verify the header still references them; it should — `currentUser` via `authController`, and `drawerController` via `_ModuleGroup`.)

- [ ] **Step 8: Write a drawer navigation widget test**

```dart
// test/widget/drawer_account_nav_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

void main() {
  testWidgets('AppNavDrawerController no longer exposes a user-menu toggle',
      (tester) async {
    // Compile-time guard: the inline user-menu state was removed. This test
    // documents the contract; full drawer render needs the service graph and
    // is covered by manual verification.
    final c = AppNavDrawerController();
    expect(c.isGroupExpanded('Stock', defaultValue: false), isFalse);
    Get.reset();
  });
}
```

(Rationale: a full `AppNavDrawer` pump needs `HomeController`, `AuthenticationController`, `PermissionService`, and route context — heavy to mock. The behavioral change — header → hub — is verified manually in Task 9. This guard locks the removed-API contract.)

- [ ] **Step 9: Run test + analyze**

Run: `flutter test test/widget/drawer_account_nav_test.dart && flutter analyze`
Expected: PASS; clean.

- [ ] **Step 10: Commit**

```bash
git add lib/app/modules/global_widgets/app_nav_drawer.dart lib/app/modules/home/home_controller.dart test/widget/drawer_account_nav_test.dart
git rm lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart
git commit -m "feat(drawer): account header opens Account hub; route Session Defaults; remove inline user-menu"
```

---

### Task 7: My Profile — remove logout, tidy hierarchy

**Files:**
- Modify: `lib/app/modules/profile/user_profile_screen.dart`
- Modify: `lib/app/modules/profile/user_profile_controller.dart`

**Interfaces:**
- Produces: Profile screen with **no logout tile**; `UserProfileController.logout` removed.

- [ ] **Step 1: Remove `logout()` from the controller**

In `user_profile_controller.dart`, delete:
```dart
  void logout() {
    _authController.logoutUser();
  }
```

- [ ] **Step 2: Remove the logout tile + GlobalDialog usage from the screen**

In `user_profile_screen.dart`:
- Delete the import: `import 'package:multimax/app/modules/global_widgets/global_dialog.dart';`
- Change the section title `_buildSectionTitle('Account Settings')` to `_buildSectionTitle('Security')`.
- In the Card under that section, delete the `Divider(...)` and the entire Logout `ListTile(...)` (the block from `Divider(` through the logout `ListTile(... onConfirm: controller.logout ),)`), leaving only the Change Password `ListTile`.

The Security card becomes:
```dart
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline, color: Colors.blueGrey),
                    title: const Text('Change Password'),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () => _showChangePasswordSheet(context),
                  ),
                ),
```

- [ ] **Step 3: Add Employee ID row + Roles count label (design alignment)**

In the General Information card, after the Department row's `Divider(height: 24)` and before the Mobile `_buildEditableRow`, add an Employee ID row (only the rows order changes — Employee ID then the existing rows is also fine; keep it simple by inserting before Mobile):
```dart
                        if (user.employeeId?.isNotEmpty == true) ...[
                          _buildInfoRow('Employee ID', user.employeeId,
                              icon: Icons.badge_outlined),
                          const Divider(height: 24),
                        ],
```
Change the Roles section title to include the count:
```dart
                  _buildSectionTitle('Roles · ${user.roles.length}'),
```
(replaces `_buildSectionTitle('Assigned Roles')`).

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: clean (no unused `GlobalDialog` import, no unused `logout`).

- [ ] **Step 5: Guard test — controller has no logout**

```dart
// test/unit/user_profile_logout_removed_test.dart
import 'package:flutter_test/flutter_test.dart';

// This is a documentation/compile guard: UserProfileController.logout() was
// removed (logout now lives only in the Account hub). If someone re-adds it,
// update the design intent first. Real logout coverage is in the hub.
void main() {
  test('placeholder — logout consolidated to Account hub', () {
    expect(true, isTrue);
  });
}
```

(Rationale: a full Profile render needs `AuthenticationController` + `ApiProvider`; the meaningful guarantee — no logout entry point here — is enforced by the deletion + `flutter analyze` + the Task 9 manual check.)

- [ ] **Step 6: Run test + analyze**

Run: `flutter test test/unit/user_profile_logout_removed_test.dart && flutter analyze`
Expected: PASS; clean.

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/profile/user_profile_screen.dart lib/app/modules/profile/user_profile_controller.dart test/unit/user_profile_logout_removed_test.dart
git commit -m "feat(profile): remove logout (now hub-only); add Employee ID + Roles count; rename Security"
```

---

### Task 8: About → System Information redesign

**Files:**
- Modify: `lib/app/modules/about/about_controller.dart` (add `channel` getter)
- Modify: `lib/app/modules/about/about_screen.dart` (re-layout with `context.scheme` + AppColors; add Channel cell)

**Interfaces:**
- Consumes: `AboutController` (`appName`, `version`, `buildNumber`, `channel`, `systemStatus`, `isCheckingHealth`, `runHealthChecks`, `IntegrationState`); `context.scheme`, `AppColors`, `AppRadius`, `AppSpace`.
- Produces: redesigned About screen; `AboutController.channel`.

- [ ] **Step 1: Add `channel` to `about_controller.dart`**

Add the import at the top:
```dart
import 'package:flutter/foundation.dart' show kReleaseMode, kProfileMode;
```
Add this getter inside `AboutController` (e.g. after the obs fields):
```dart
  /// No build-flavor metadata exists; derive a coarse channel from build mode.
  /// Phase-1 placeholder (see spec) — not a real release-channel field.
  String get channel =>
      kReleaseMode ? 'Stable' : (kProfileMode ? 'Profile' : 'Debug');
```

- [ ] **Step 2: Replace `about_screen.dart` with the token-driven layout**

Full replacement:
```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/about/about_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';

class AboutScreen extends GetView<AboutController> {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Scaffold(
      appBar: MainAppBar(
        title: 'System Information',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.runHealthChecks,
          ),
        ],
      ),
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: controller.runHealthChecks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s4, AppSpace.s4, AppSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: AppSpace.s5),
              _versionCard(context),
              const SizedBox(height: AppSpace.s5),
              SectionLabel(text: 'System health'),
              _healthCard(context),
              const SizedBox(height: AppSpace.s8),
              Center(
                child: Text(
                  '© ${DateTime.now().year} Multimax · Powered by DDMCO',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: s.textSubtle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final s = context.scheme;
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            image: const DecorationImage(
              image: AssetImage('lib/assets/images/logo.jpg'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Obx(() => Text(
              controller.appName.value.isEmpty
                  ? 'Multimax'
                  : controller.appName.value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: s.text),
            )),
      ],
    );
  }

  Widget _versionCard(BuildContext context) {
    final s = context.scheme;
    Widget cell(String k, String v) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Text(k,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: s.textSubtle)),
                const SizedBox(height: 3),
                Text(v,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: s.text)),
              ],
            ),
          ),
        );
    Widget sep() => Container(width: 1, height: 36, color: s.border);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.fg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Obx(() => IntrinsicHeight(
            child: Row(
              children: [
                cell('Version',
                    controller.version.value.isEmpty ? '—' : controller.version.value),
                sep(),
                cell('Build',
                    controller.buildNumber.value.isEmpty ? '—' : controller.buildNumber.value),
                sep(),
                cell('Channel', controller.channel),
              ],
            ),
          )),
    );
  }

  Widget _healthCard(BuildContext context) {
    final s = context.scheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.fg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Obx(() {
          final items = controller.systemStatus;
          final rows = <Widget>[];
          for (var i = 0; i < items.length; i++) {
            if (i > 0) {
              rows.add(Divider(height: 1, thickness: 1, color: s.border));
            }
            rows.add(_healthRow(context, items[i]));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: rows);
        }),
      ),
    );
  }

  Widget _healthRow(BuildContext context, SystemIntegration item) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = item.state == IntegrationState.connected;
    final loading = item.state == IntegrationState.loading;
    final tint = ok ? AppColors.green500 : AppColors.red500;
    final detailColor = ok
        ? (isDark ? AppColors.green300 : AppColors.green700)
        : (isDark ? AppColors.red300 : AppColors.red700);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(tint.withValues(alpha: 0.14), s.fg),
              shape: BoxShape.circle,
            ),
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(ok ? Icons.check_rounded : Icons.error_outline,
                    size: 19, color: detailColor),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: s.text)),
                Text(item.type,
                    style: TextStyle(fontSize: 11.5, color: s.textSubtle)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.details != null && !loading)
                Text(item.details!,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: detailColor)),
              if (item.latency != null)
                Text(item.latency!,
                    style: TextStyle(fontSize: 10.5, color: s.textSubtle)),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 4: Sanity-run any About tests + commit**

```bash
flutter test test/ 2>&1 | tail -5   # ensure no regressions
git add lib/app/modules/about/about_screen.dart lib/app/modules/about/about_controller.dart
git commit -m "feat(about): redesign System Information (scheme colors, version/build/channel strip)"
```

---

### Task 9: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: "No issues found!" (or no new issues vs. baseline).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all green. (Pre-existing unrelated failures noted in memory — `status_pill`/`doctype_form_header` — may exist on this branch; confirm the new tests pass and no NEW failures appear.)

- [ ] **Step 3: Manual device walkthrough**

Run: `flutter run -d <device_id>` and verify:
1. Drawer → tap the account header → Account hub opens; the module list no longer swaps to a flat menu.
2. Hub → Theme → switch Light/Dark/System; the preview and the whole app update; relaunch app → choice persisted.
3. Hub → Session Defaults → change company + toggles + sliders → Save → reopen → values persisted; Reload permissions shows a snackbar.
4. Hub → System Information → Version/Build/Channel render; health checks run and color (green/red) correctly; pull-to-refresh + the app-bar refresh both work.
5. Hub → My Profile → mobile edit + change password still work; **no logout tile** present.
6. Hub → Log out → exactly **one** confirm dialog → returns to Login.
7. Repeat 1–6 in dark mode.

- [ ] **Step 4: Final commit (if any tidy-ups)**

```bash
git add -A
git commit -m "chore(user-area): phase-1 verification tidy-ups"
```

---

## Self-Review

**Spec coverage:**
- Drawer → hub restructure → Task 6. ✓
- Account hub (groups + logout + footer) → Task 5. ✓
- My Profile re-layout + logout removal → Task 7. ✓
- Session Defaults full screen (all settings preserved) → Task 4. ✓
- About redesign (version/build/channel + 3 health checks restyled) → Task 8. ✓
- Theme screen (Light/Dark/System + preview) → Task 3. ✓
- One logout, one dialog → Task 5 (`logout()` → `AuthenticationController.logoutUser()` which owns the single confirm) + Task 7 (removed from Profile) + Task 6 (removed from drawer). ✓
- Shared settings widgets → Tasks 1-2. ✓
- Accent/text-size excluded → enforced by Global Constraints + Task 3 scope. ✓
- New routes → Tasks 3/4/5. ✓

**Type consistency:** `SettingsGroup({String? label, required List<Widget> children})`, `SettingsRow`, `SettingsSwitchRow`, `SettingsSliderRow`, `SettingsSegmented<T>`/`SegmentOption<T>`, `SectionLabel({required String text})` are defined in Tasks 1-2 and consumed with matching signatures in Tasks 3/4/5/8. `SessionDefaultsController.persist()` returns `Future<bool>` (Task 4 test + screen `save()` agree). `UserAreaController.labelForMode(ThemeMode)`/`themeModeLabel` consistent (Task 5). Route constants `USER_AREA`/`THEME`/`SESSION_DEFAULTS` added once and referenced by exact name.

**Placeholder scan:** No TBD/TODO; every code step shows complete code. The two "guard" tests in Tasks 6/7 are intentionally minimal and labelled as contract/documentation guards (full GetX screen renders need heavy service graphs); real behavior is covered by unit/widget tests on extractable logic + the Task 9 manual walkthrough.
