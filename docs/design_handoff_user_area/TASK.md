# ToDo — User Area Redesign

- **Area:** User Area (drawer account header, Account hub, My Profile, Session Defaults, About/System Information, Theme)
- **Priority:** Medium
- **Phase:** 1 of 2 (structural; accent-color + text-size deferred to phase 2)
- **Reference:** `User Area - Redesign.html` (this folder) · spec `docs/superpowers/specs/2026-06-22-user-area-redesign-design.md`

## Description

Replace the drawer's inline user-menu (header-arrow swap) with a dedicated, grouped **Account hub**. Promote Session Defaults from a bottom sheet to a full screen, add a Theme screen (Light/Dark/System only), re-layout My Profile and About with calmer hierarchy, and consolidate logout to one confirmed action in the hub.

## Why

- The header-arrow swap hides the module list and there is no settled account surface.
- Logout is duplicated (drawer + Profile) and the Profile path shows two confirm dialogs back-to-back.
- Session Defaults is a cramped sheet while sibling screens are full-screen; appearance has no home beyond a drawer cycle-toggle.

## Acceptance criteria

- [ ] Drawer account header opens the Account hub; the inline user-menu toggle (`isUserMenuOpen`/`toggleUserMenu`) is gone and the module list is always visible.
- [ ] Account hub shows: profile summary card → Preferences (Theme w/ current mode, Session Defaults w/ company) → Support (System Information w/ version) → single logout → footer.
- [ ] My Profile: hero + General information / Roles · N / Security groups; **no logout tile**; mobile inline-edit and change-password still work.
- [ ] Session Defaults is a full screen with a sticky Save bar; **all** current settings preserved and persisted; Reload permissions works.
- [ ] About: logo + name, Version/Build/Channel strip, the existing 3 health checks restyled; refresh works.
- [ ] Theme screen: live-preview card + Light/Dark/System segmented control wired to `ThemeController`; choice persists across restart.
- [ ] Exactly one logout confirm dialog; logout returns to Login.
- [ ] Accent-color and text-size controls are **omitted** (phase 2).
- [ ] `flutter analyze` clean; `flutter test` green (existing drawer/theme widget tests updated, not deleted).

## Design reference

Open `User Area - Redesign.html` in a browser. The "before" artboards recreate today's screens; the "after" artboards and the interactive prototype show the target. Ignore the prototype's blue accent + the accent/text-size sections (phase 2).
