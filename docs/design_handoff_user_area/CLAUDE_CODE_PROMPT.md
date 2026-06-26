# Claude Code prompt — User Area Redesign (phase 1)

Paste the block below into Claude Code, run from the project root.

```
Implement PHASE 1 of the User Area redesign. The design reference is
docs/design_handoff_user_area/ (open "User Area - Redesign.html" in a browser).
The authoritative spec is docs/superpowers/specs/2026-06-22-user-area-redesign-design.md
— follow it; this prompt is the executable summary.

GOAL
Replace the drawer's inline user-menu with a dedicated Account hub; promote Session
Defaults to a full screen; add a Theme screen (Light/Dark/System only); re-layout My
Profile and About; consolidate logout to one confirmed action in the hub.

DO NOT (phase 2, omit now): accent-color picker, text-size/density control. Keep the
brand maroon (#870E18) — never introduce a user-selectable accent in this phase.

FILES — create
- lib/app/modules/user_area/user_area_screen.dart | _controller.dart | _binding.dart
- lib/app/modules/session_defaults/session_defaults_screen.dart | _controller.dart | _binding.dart
- lib/app/modules/theme/theme_screen.dart  (+ a binding; reuse the existing ThemeController)
- lib/app/modules/global_widgets/settings_group.dart, settings_row.dart,
  settings_switch_row.dart, settings_slider_row.dart, settings_segmented.dart

FILES — edit
- lib/app/modules/global_widgets/app_nav_drawer.dart  (remove isUserMenuOpen/toggleUserMenu
  + the inline-menu Obx branch; make the account header tap → Get.toNamed(USER_AREA);
  remove the in-drawer theme cycle-toggle and logout)
- lib/app/modules/profile/user_profile_screen.dart  (re-layout to hero + SettingsGroup cards;
  REMOVE the Account Settings logout tile and the GlobalDialog logout path; keep mobile edit +
  change-password sheet)
- lib/app/modules/profile/user_profile_controller.dart  (drop the now-unused logout())
- lib/app/modules/about/about_screen.dart  (re-layout: logo+name, Version/Build/Channel strip,
  restyled health rows; Channel = kReleaseMode ? 'Stable' : (kProfileMode ? 'Profile' : 'Debug'))
- lib/app/modules/home/home_controller.dart  (openSessionDefaults() → Get.toNamed(SESSION_DEFAULTS))
- lib/app/data/routes/app_routes.dart + app_pages.dart  (add USER_AREA '/user-area',
  THEME '/theme', SESSION_DEFAULTS '/session-defaults'; rightToLeft transitions)
- DELETE lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart after porting its
  load/save logic into SessionDefaultsController.

READ FOR CONTEXT (reuse, don't reinvent)
- lib/app/data/constants/app_theme.dart  (AppScheme/context.scheme, AppColors, AppRadius, AppSpace)
- lib/app/modules/auth/authentication_controller.dart  (currentUser, logoutUser, fetchUserDetails)
- lib/app/modules/theme/theme_controller.dart  (setThemeMode, themeMode, persisted theme_mode)
- lib/app/data/services/storage_service.dart  (getCompany/saveSessionDefaults, auto-submit, auto-save)
- lib/app/data/services/permission_service.dart  (clearCache)
- lib/app/modules/about/about_controller.dart  (3 health checks + PackageInfo)
- lib/app/modules/global_widgets/  (AppAvatar, MainAppBar, GlobalDialog, GlobalSnackbar, SkeletonBox,
  DocSectionCard for reference)

STATE / DATA
- Hub & Profile read AuthenticationController.currentUser (no new fetch).
- Theme reads/writes ThemeController. Session Defaults reads/writes StorageService; companies via
  ApiProvider.getList('Company'). About uses AboutController unchanged + PackageInfo.
- Logout flows through AuthenticationController.logoutUser() from the hub only. Ensure exactly ONE
  confirm dialog (logoutUser already confirms — do not wrap it in another).

SHARED WIDGETS (the design's settings pattern: uppercase label ABOVE a bordered card of rows)
- SettingsGroup({String? label, required List<Widget> children}) — label + card (fg fill,
  scheme.border hairline, AppRadius.lg), 1px dividers between children.
- SettingsRow({Widget icon, Color iconTint, String title, String? subtitle, String? value,
  VoidCallback? onTap}) — tinted icon tile + title/subtitle + optional trailing value + chevron.
- SettingsSwitchRow, SettingsSliderRow, SettingsSegmented<T>.
- Map --shadow-xs to a 1px border, not a BoxShadow (the DS is shadow-light).

CONSTRAINTS
- Source all colors from context.scheme / AppColors. No hex literals. Keep maroon brand.
- Light + dark must both look right (test both).
- Run `flutter analyze` (clean) and `flutter test` (green). Update the existing
  test/widget/drawer_theme_toggle_test.dart and theme_mode_switching_test.dart to match the
  moved theme toggle — do not delete coverage. Add widget tests for the hub (one logout, groups
  render), Theme screen (segmented calls setThemeMode), Profile (no logout tile), and a unit test
  for SessionDefaultsController round-tripping StorageService.

DELIVERABLE
All phase-1 acceptance criteria in TASK.md met, analyze clean, tests green.
```
