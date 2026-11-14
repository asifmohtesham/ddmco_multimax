# User Area — Redesign (handoff)

Imported from the claude.ai/design project **Multimax**, file `User Area - Redesign.html`.

## Overview

A revamp of the app's "User Area" — everything reachable from the nav drawer's account header. It replaces the inline drawer user-menu with a dedicated, grouped **Account hub**, gives Session Defaults and Theme real full screens, calms the Profile/About hierarchy, and consolidates logout to one confirmed action.

## About the design files

The HTML/JSX/CSS here are a **visual reference, not code to port**. Open `User Area - Redesign.html` in a browser to see the interactive prototype and the before/after artboards. Recreate the screens in Flutter using the app's existing patterns and tokens — do **not** translate CSS to Flutter literally, and never copy hex values (the prototype uses an ERPNext-blue accent for demo purposes; the app's brand is **maroon `#870E18`** and must stay maroon).

- `User Area - Redesign.html` — canvas entry (loads the JSX below).
- `ua-shared.jsx` — icons, phone frame, shared app bar, demo user (`UA_USER`).
- `ua-baseline.jsx` — recreations of the **current** screens (the "before").
- `ua-redesign.jsx` — the **redesigned** screens (the "after"): drawer, Account hub, Profile, Session Defaults, About, Theme.
- `ua-prototype.jsx` — the clickable flow + artboard wrappers.
- `ua.css` — reference styling (token-driven, `ua-*` prefixed).
- `multimax-ds/ds.css` — the Multimax × ERPNext v15 design-system tokens (same file used across all handoffs).

## Scope — PHASE 1 (this handoff)

Build the full structural redesign:

1. **Nav drawer → Account hub.** Remove the header-arrow inline user-menu swap; the account header becomes a single tap into a new Account hub. Module list always visible.
2. **Account hub (new screen).** Profile summary card → Preferences (Theme, Session Defaults) → Support (System Information) → single logout pinned at bottom → footer.
3. **My Profile.** Centered hero + grouped cards (General information, Roles · N, Security/Change password). **Logout removed.**
4. **Session Defaults.** Bottom sheet → full screen with sticky Save bar. All current settings preserved (Company, Auto-submit toggle + delay, Document Save Delay, Reload permissions).
5. **About → System Information.** Logo + app name, Version/Build/Channel strip, restyled health checks (the existing 3 — ERPNext API, SQLite DB, DataWedge scanner).
6. **Theme (new screen).** Live-preview card + Light/Dark/System segmented control.
7. **Logout.** One logout, in the hub, one confirm dialog.

## Scope — PHASE 2 (NOT in this handoff)

- **Accent-color picker.** The prototype's "Accent color" section overrides `--primary` app-wide. This conflicts with the maroon brand and needs its own design + theming infrastructure. **Omit** the accent section now.
- **Text size / density.** The "Text size" segmented control needs a persisted text-scale threaded through `ThemeData`. **Omit** now.
- A real release-channel field. The Channel cell in About is derived (`kReleaseMode → "Stable"`) for phase 1; there is no flavor metadata.

## Interactions & behavior

- Drawer account header → `Get.toNamed(USER_AREA)` (no more inline-menu swap).
- Hub rows push: Theme, Session Defaults, System Information, and the profile card → My Profile.
- Theme segmented control → `ThemeController.setThemeMode`; the preview reflects the selected mode live and the choice persists (SQLite `theme_mode`).
- Session Defaults Save → persist via `StorageService`; Reload permissions → `PermissionService.clearCache()` + `AuthenticationController.fetchUserDetails()`.
- Logout → `AuthenticationController.logoutUser()` (already shows one confirm + spinner + `Get.offAllNamed(LOGIN)`). Ensure there is exactly one confirm dialog.

## Design tokens (map, don't copy)

| Reference (ds.css) | Flutter |
| --- | --- |
| `--r-lg` (12) | `AppRadius.lg` |
| `--r-md` / `--r-full` | `AppRadius.md` / `AppRadius.full` |
| spacing 8/12/16/24 | `AppSpace.s2/s3/s4/s6` |
| `--shadow-xs` | 1px hairline border (`scheme.border`), not a box-shadow |
| `--fg` / `--bg` / `--text` / `--border` / `--primary` | `context.scheme.fg/bg/text/border/primary` |
| status ramps (`--green-500`, `--red-600`, …) | `AppColors.green500`, `AppColors.red600`, … |

All colors come from `context.scheme` / `AppColors`. Never hardcode hex.

## Implementation targets (Flutter)

- New: `lib/app/modules/user_area/` (hub), `lib/app/modules/session_defaults/` (full screen), `lib/app/modules/theme/theme_screen.dart` (+ binding).
- Edit: `lib/app/modules/global_widgets/app_nav_drawer.dart` (drop inline menu), `lib/app/modules/profile/user_profile_screen.dart` (re-layout, remove logout), `lib/app/modules/about/about_screen.dart` (re-layout), `lib/app/data/routes/app_routes.dart` + `app_pages.dart` (3 new routes).
- New shared widgets in `global_widgets/`: `SettingsGroup`, `SettingsRow`, `SettingsSwitchRow`, `SettingsSliderRow`, `SettingsSegmented`.
- Reuse: `AppAvatar`, `MainAppBar`, `GlobalDialog`, `GlobalSnackbar`, `SkeletonBox`, `AuthenticationController`, `ThemeController`, `StorageService`, `PermissionService`, `AboutController`.

Full spec: `docs/superpowers/specs/2026-06-22-user-area-redesign-design.md`.
