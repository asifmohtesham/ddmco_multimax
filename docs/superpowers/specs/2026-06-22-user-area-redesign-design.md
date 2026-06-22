# User Area Redesign — Design

**Date:** 2026-06-22
**Status:** Approved (phase 1 scope)
**Design source:** `docs/design_handoff_user_area/` (imported from claude.ai/design project "Multimax", file `User Area - Redesign.html`)

## Context

The app's "User Area" (everything reachable from the drawer's account header) grew piecemeal and has three problems:

1. **Discoverability / IA.** Tapping the drawer header's arrow *swaps* the module list for a flat inline user-menu (My Profile / Session Defaults / About / Theme / Logout). There is no dedicated account surface, and the swap hides navigation.
2. **Logout is duplicated and over-confirmed.** Logout lives in both the drawer user-menu and inside My Profile (next to Change Password). The Profile path shows **two** confirm dialogs back-to-back (`GlobalDialog.showConfirmation` then the `AlertDialog` inside `AuthenticationController.logoutUser`).
3. **Inconsistent surfaces.** Session Defaults is a cramped bottom sheet while Profile/About are full screens. Appearance (Light/Dark/System) is only a drawer cycle-toggle with no settled home.

This redesign turns the account header into a single entry into a dedicated, grouped **Account hub**, gives Session Defaults and Theme proper full screens, calms the Profile/About hierarchy, and consolidates logout to one confirmed action in the hub.

**Phase boundary:** The source design also includes a user-selectable **accent color** and **text-size** control. Both are greenfield (no infrastructure today) and the accent picker overrides the maroon brand (`#870E18`) app-wide, which conflicts with the standing "KEEP MAROON" rule. **Those two are explicitly deferred to phase 2.** Phase 1 builds the full structural redesign with a Theme screen limited to Light/Dark/System.

## Goals

- Drawer account header → opens a dedicated Account hub (no more inline-menu swap; module list always visible).
- New grouped Account hub: profile summary → Preferences (Theme, Session Defaults) → Support (System Information) → single logout.
- Redesigned My Profile (hero + grouped cards), logout removed.
- Session Defaults promoted from bottom sheet to full screen with a sticky Save bar; **no settings dropped**.
- Redesigned About / System Information (logo, version/build/channel strip, restyled health checks).
- New Theme screen (Light/Dark/System only) with a live-preview card.
- One logout, in the hub, one confirm dialog.

## Non-goals (phase 2)

- Accent-color picker (would override maroon brand — needs its own design + app-wide `--primary` plumbing).
- Text-size / density control (needs a persisted text-scale threaded through the theme).
- A real release-channel field (no flavor metadata exists; phase 1 derives it — see About below).

## Existing code this builds on (reuse, don't reinvent)

| Concern | Existing | Path |
| --- | --- | --- |
| User data | `AuthenticationController.currentUser` (`Rx<User?>`), `fetchUserDetails()`, role helpers | `lib/app/modules/auth/authentication_controller.dart` |
| User model | `User` (name, email, image, designation, department, mobileNo, employeeId, roles) | `lib/app/data/models/user_model.dart` |
| Logout | `AuthenticationController.logoutUser()` (owns its confirm + spinner + `Get.offAllNamed(LOGIN)`) | `authentication_controller.dart` |
| Theme | `ThemeController` (`Rx<ThemeMode>`, `setThemeMode`, persisted via `DatabaseService` key `theme_mode`) | `lib/app/modules/theme/theme_controller.dart` |
| Session settings storage | `StorageService` (GetStorage) — `getCompany`/`saveSessionDefaults`, `getAutoSubmitEnabled`/`Delay`, `getAutoSaveDelay` | `lib/app/data/services/storage_service.dart` |
| Reload permissions | `PermissionService.clearCache()` + `AuthenticationController.fetchUserDetails()` | `permission_service.dart` |
| About health/version | `AboutController` (3 checks: ERPNext API, SQLite DB, DataWedge), `PackageInfo.fromPlatform()` | `lib/app/modules/about/about_controller.dart` |
| Profile change-password | `_showChangePasswordSheet` + `controller.changePassword` → `ApiProvider.changePassword` | `lib/app/modules/profile/` |
| Tokens | `AppScheme`/`context.scheme`, `AppColors`, `AppRadius` (lg=12), `AppSpace`; `buildAppTheme` | `lib/app/data/constants/app_theme.dart`, `lib/main.dart` |
| Widgets | `AppAvatar`, `DocSectionCard`, `StatusPill`, `SkeletonBox`, `MainAppBar`, `GlobalDialog`, `GlobalSnackbar` | `lib/app/modules/global_widgets/` |

**Token mapping:** source CSS `--r-lg` → `AppRadius.lg` (12); `--shadow-xs` → a 1px hairline border (the DS is shadow-light, uses borders, not box-shadows); all colors via `context.scheme` / `AppColors`, never hex literals.

## Components

### New shared widgets — `lib/app/modules/global_widgets/`

The design's settings pattern is an **uppercase label *above* a bordered card of rows** — distinct from `DocSectionCard` (title *inside* the card). Add small, focused widgets reused by hub / Session Defaults / Theme:

- `SettingsGroup({String label, required List<Widget> children})` — uppercase label + bordered card (`fg` fill, `border` hairline, `AppRadius.lg`); inserts 1px dividers between children.
- `SettingsRow({Widget icon, Color iconTint, String title, String? subtitle, String? value, VoidCallback? onTap})` — tinted icon tile (`color-mix` ≈ `iconTint @14% over fg`), title/subtitle, optional trailing value + chevron.
- `SettingsSwitchRow({String title, String? subtitle, bool value, ValueChanged<bool> onChanged})`.
- `SettingsSliderRow({String label, int value, int min, int max, String suffix, ValueChanged<int> onChanged})`.
- `SettingsSegmented<T>({List<({T value, String label})> options, T value, ValueChanged<T> onChanged})` — used by Theme appearance + (phase 2) text-size.

### 1 · Nav drawer → Account hub — `lib/app/modules/global_widgets/app_nav_drawer.dart`

- Remove `AppNavDrawerController.isUserMenuOpen` / `toggleUserMenu` and the `Obx` branch that renders the inline user-menu.
- Account header (`UserAccountsDrawerHeader`): drop `onDetailsPressed` arrow toggle; make the whole header tappable → `Navigator.pop(ctx); Get.toNamed(AppRoutes.USER_AREA)`.
- Body always shows the module list. Theme cycle-toggle and Logout move out of the drawer entirely (now in hub/Theme).

### 2 · Account hub (new) — `lib/app/modules/user_area/`

`UserAreaScreen extends GetView<UserAreaController>`, `UserAreaController`, `UserAreaBinding`. Route `AppRoutes.USER_AREA = '/user-area'`, `Transition.rightToLeft`.

- App bar "Account" + back (`MainAppBar(title: 'Account', showBack: true)`).
- Profile summary card (`SettingsGroup`-less, a standalone tappable card) → `Get.toNamed(PROFILE)`: `AppAvatar`, name, email, `designation · department`.
- **Preferences** `SettingsGroup`: `SettingsRow` Theme (value = current mode label) → `THEME`; `SettingsRow` Session Defaults (value = active company) → `SESSION_DEFAULTS`.
- **Support** `SettingsGroup`: `SettingsRow` System Information (value = `v<version>`) → `ABOUT`.
- Logout button (red-tinted, full width) pinned after the groups → `AuthenticationController.logoutUser()` (which already confirms). Footer: `Signed in as <email>` + `Multimax v<version> · build <build>`.
- Controller exposes `user` (from `AuthenticationController`), `themeModeLabel` (from `ThemeController`), `company` (from `StorageService`), `version`/`build` (from `PackageInfo`, loaded in `onInit`), and `logout()` → `_auth.logoutUser()`.

### 3 · My Profile — `lib/app/modules/profile/user_profile_screen.dart`

Re-layout only; controller/data unchanged.

- Centered hero: large `AppAvatar`, name, email, `designation · department`.
- **General information** `SettingsGroup` of key/value rows: Employee ID, Department, Designation, Mobile (keep existing pencil inline-edit → `_showUpdateMobileDialog` / `updateMobileNumber`).
- **Roles · N** `SettingsGroup`: role chips (Wrap of tinted chips; reuse current chip styling).
- **Security** `SettingsGroup`: Change password row → keep existing `_showChangePasswordSheet`.
- **Remove** the Account Settings card's Logout tile and the now-redundant `GlobalDialog` logout path + `UserProfileController.logout`.

### 4 · Session Defaults (full screen) — `lib/app/modules/session_defaults/`

`SessionDefaultsScreen` + `SessionDefaultsController` + binding. Route `/session-defaults`. Logic extracted from the existing `session_defaults_bottom_sheet.dart` (then delete that file).

- **Session** group: Company picker (companies via `ApiProvider.getList('Company')`; persists `StorageService.saveSessionDefaults`).
- **Automation** group: `SettingsSwitchRow` Auto-submit valid items; conditional `SettingsSliderRow` Auto-submit delay (1–10s); `SettingsSliderRow` Document Save Delay (3–30s). (All three preserved from today.)
- **Troubleshooting** group: `SettingsRow` Reload permissions → `PermissionService.clearCache()` + `fetchUserDetails()`.
- Sticky `Save settings` bar → persists all values via `StorageService`, then `GlobalSnackbar` success.
- `HomeController.openSessionDefaults()` and the drawer item (if any remains) → `Get.toNamed(SESSION_DEFAULTS)` instead of opening the sheet.

### 5 · About → System Information — `lib/app/modules/about/about_screen.dart`

Re-layout; controller logic largely unchanged.

- Header: gradient logo tile + "Multimax" app name.
- Version / Build / Channel strip (`SettingsGroup`-style 3-cell card). Version/Build from `PackageInfo`. **Channel** derived: `kReleaseMode ? 'Stable' : (kProfileMode ? 'Profile' : 'Debug')` — no flavor metadata exists; documented as a phase-1 placeholder.
- **System health** group: the existing **3** checks (ERPNext API, SQLite DB, DataWedge scanner) restyled — circular status chip (green check / red alert), name + type, right-aligned detail + latency. Do **not** invent Print Service / Scan Bridge rows (no backend).
- Footer: `© <year> Multimax · Powered by DDMCO`.

### 6 · Theme screen (new) — `lib/app/modules/theme/theme_screen.dart`

`ThemeScreen` + `ThemeBinding` (reuse the permanent `ThemeController`). Route `AppRoutes.THEME = '/theme'`.

- **Preview** group: a live sample card (doc icon + "Stock Entry · SE-2026" + "12 items · In stock" + Cancel/Submit buttons) that reflects the chosen mode — rendered with `context.scheme` so it updates when the mode changes.
- **Appearance** `SettingsSegmented`: Light / Dark / System → `ThemeController.setThemeMode`.
- Accent + Text-size sections omitted in phase 1 (land here in phase 2).

### Routing — `lib/app/data/routes/app_routes.dart` + `app_pages.dart`

Add to `_Paths` + `AppRoutes`: `USER_AREA = '/user-area'`, `THEME = '/theme'`, `SESSION_DEFAULTS = '/session-defaults'`. Add three `GetPage` entries with their bindings and `Transition.rightToLeft`.

## Data flow

- Hub/Profile read `AuthenticationController.currentUser` (no new fetch beyond existing `refreshProfile`).
- Theme reads/writes `ThemeController` (persists `theme_mode` in SQLite). Hub shows the current label via `Obx`.
- Session Defaults reads/writes `StorageService` (GetStorage). Company list via `ApiProvider`.
- About uses `AboutController` (unchanged checks) + `PackageInfo`.
- Logout funnels through `AuthenticationController.logoutUser()` from exactly one place (hub).

## Error handling

- Reload permissions: keep existing behavior (snackbar on completion/failure).
- Company list fetch failure: show snackbar, keep prior selection (fail-open), matching existing sheet behavior.
- Save settings: validate slider ranges (already bounded by widgets); snackbar on success.
- Logout failure: existing `GlobalSnackbar.error` + dismiss spinner path is retained.

## Testing

- **Unit:** `UserAreaController` (exposes correct labels; `logout()` calls `AuthenticationController.logoutUser`); `SessionDefaultsController` (load → mutate → save round-trips through a fake/`withStorage` `StorageService`, defaults preserved).
- **Widget:** drawer account header navigates to `USER_AREA` and the inline-menu toggle is gone; hub renders Preferences/Support groups + exactly one logout; Theme segmented control calls `setThemeMode` and preview reflects mode; Profile renders without any logout tile; Session Defaults screen shows all three automation controls.
- **Guardrails:** existing `test/widget/drawer_theme_toggle_test.dart` and `theme_mode_switching_test.dart` must be updated (theme toggle moved out of drawer into Theme screen) and kept green.
- `flutter analyze` clean; `flutter test` green.

## Verification (end-to-end)

1. `flutter analyze` and `flutter test`.
2. `flutter run -d <device>`: open drawer → tap account header → Account hub. Verify module list no longer swaps.
3. Hub → Theme: switch Light/Dark/System, confirm preview + whole app update and the choice persists across restart.
4. Hub → Session Defaults: change company + toggles + sliders, Save, reopen to confirm persistence; Reload permissions runs.
5. Hub → System Information: version/build/channel render; health checks run and color correctly.
6. Hub → My Profile: edit mobile, change password still work; confirm no logout tile.
7. Hub → Log out: single confirm dialog → returns to Login.

## Risks

- **Drawer test churn:** moving the theme toggle and logout out of the drawer breaks two existing widget tests — update them as part of the work, don't delete coverage.
- **Double-logout regression:** ensure only `logoutUser()`'s own confirm remains (remove the `GlobalDialog` wrapper) so there's exactly one dialog.
- **Channel placeholder:** "Stable/Debug" derivation is cosmetic; flagged so it isn't mistaken for real release-channel metadata.
