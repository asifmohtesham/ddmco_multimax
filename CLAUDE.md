# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Flutter mobile app ("KA-ML Fulfillment") for supply-chain operations against a Frappe/ERPNext backend at `https://erp.domain.com`. Covers stock, purchase orders, delivery notes, work orders, job cards, packing slips, and manufacturing. Primary platform is Android (USB/WiFi device), but configured for iOS, desktop, and web.

## Common Commands

```bash
flutter pub get              # Install/refresh dependencies
flutter analyze              # Lint (analysis_options.yaml, Flutter recommended rules)
flutter test                 # Run all tests (test/ directory)
flutter run -d <device_id>   # Run on device (see .vscode/launch.json for configured devices)
flutter build apk --release  # Android release APK
```

## Architecture

### State Management & DI: GetX

All state is managed with GetX. The core patterns are:

- **Controllers** extend `GetxController`; observables use `.obs` suffix
- **Bindings** (`*_binding.dart`) register controllers/providers via `Get.lazyPut()` per route
- **Screens** extend `GetView<SomeController>` (stateless) and access state via `controller.*`
- **Global services** are registered in `main.dart` with `permanent: true` (survive route changes)
- **Workers** (e.g., `ever(...)`) must be stored in a field and cancelled in `onClose()`

Global services registered at startup: `DatabaseService` (SQLite config), `ApiProvider` (Dio HTTP), `DataWedgeService` (barcode hardware), `ScanService` (scan event router), `AuthenticationController`.

### Routing

Named routes defined in `lib/app/data/routes/app_pages.dart` and `app_routes.dart`. All routes are wrapped with a `Binding`. Default transition: `Transition.fadeIn`; form screens use `rightToLeftWithFade`.

### API Layer

- `ApiProvider` wraps a `Dio` client with a `CookieJar` for session persistence
- `DatabaseService` stores the base URL in SQLite; the app can point at different ERPNext instances
- Feature-specific REST calls live in `lib/app/data/providers/*_provider.dart`

### Module Structure

Each of the 16 feature modules under `lib/app/modules/` follows this pattern:

```
module_name/
  module_name_binding.dart       # GetX dependency registration
  module_name_screen.dart        # List/overview UI (GetView)
  module_name_controller.dart    # Business logic, pagination, search
  form/
    module_name_form_screen.dart
    module_name_form_controller.dart
  widgets/                       # Module-scoped reusable widgets
```

Shared form components (used across modules) live in `lib/app/modules/global_widgets/`.

### Barcode / Hardware

`DataWedgeService` opens a native EventChannel to the Android DataWedge service. `ScanService` receives raw scan events and exposes `lastScan` as an observable. Feature controllers subscribe via a `BarcodeListenerMixin` or `ever()` worker. DataWedge is registered in `main.dart` (not in bindings) so the stream persists across navigation.

### Key Shared Widgets

- `DocTypeListHeader` — standard AppBar for list screens; see `docs/app_bar_conventions.md`
- `ItemSheet` — bottom-sheet for inline item selection within form screens
- `RackField` / `SharedRackField` — warehouse rack picker (universal delegate pattern)
- `DocTypeGuard` — wraps a widget and hides it when the user lacks access to a DocType
- `AsyncIconButton` / `AsyncFilledButton` — action controls that bake in spinner + disabled state + repaint-safe loading feedback (see Async feedback below)

### Async feedback

Any control that triggers async work (network/disk/heavy compute) MUST give immediate loading feedback. Prefer `AsyncIconButton` / `AsyncFilledButton` (`lib/app/modules/global_widgets/async_action_buttons.dart`), driven by a controller `RxBool` busy flag that the controller sets and clears in a `finally`, with a re-entrancy guard (`if (busy.value) return;`) before launching the work.

When hand-rolling instead of using those widgets, three things must hold:

- **Disabled + guarded** while in flight, so a double-tap can't fire duplicate work.
- **Actually repaints.** Beware render layers that skip rebuilds for content-only changes — a `SliverPersistentHeader` whose `shouldRebuild` keys on action *count* will not repaint an icon→spinner swap. Wrap the reactive control in its own `Obx`.
- **Visible.** A bare `CircularProgressIndicator` renders in `colorScheme.primary` (maroon) and is invisible on the solid-maroon form header. Use `colorScheme.onPrimary` (or the ambient `IconTheme` colour) on primary-coloured surfaces.

Verify by toggling the flag in a widget test or on-device — a clean `flutter analyze` proves nothing here.

## List / report screen conventions

Any vertically-scrollable result list (list screens, report screens) MUST:

- **Scrollbar.** Wrap the `CustomScrollView`/`ListView` in a `Scrollbar` sharing a single `ScrollController` with the scroll view — users need a scroll-position indicator on long result sets. (No screen did this before the POS & DN Item Rate report; it is now the standard.)
- **Clear the system nav bar.** The last item must not sit under the Android gesture/nav bar. Read `MediaQuery.of(context).padding.bottom` once and add it to the trailing padding or footer (see `delivery_note_screen` and the POS & DN Item Rate report).
- **End-of-list marker.** End the list with an "End of list" marker so the user knows they've reached the bottom. **Report** lists put a totals summary there — sum the quantity columns, **never** rate columns (summing rates across items is meaningless).

## Contrast / colour usage

Never hardcode surface or ink colours — they break in the other theme mode. The rules (enforced by `test/unit/theme_contrast_test.dart` and the dark-mode widget tests):

- **Surfaces**: bottom sheets, cards, and input fills use `context.scheme.fg` / `colorScheme.surface` / `scheme.subtle` — never `Colors.white` or `grey.shade50/100`. A hardcoded white sheet renders theme-default text invisible in dark mode (~1.1:1).
- **Inks**: body text `scheme.text`/`onSurface`, secondary text `scheme.textMuted` (AA at all sizes), decorative icons only `scheme.textSubtle`. Never `Colors.black87`, `Colors.grey`, or `grey.shadeX` as text.
- **Status colours as text**: use the `AppColors` ramp — x700 in light mode, x300 in dark (`isDark ? AppColors.orange300 : AppColors.orange700`). The x500 bases and material shades (`green.shade600`, `amber.shade700`) fall below 4.5:1 on light surfaces.
- **Status tints**: fill = `x500.withValues(alpha: 0.13)` over the surface, border ≈ alpha 0.35 — the StatusPill convention. Never pastel `shade50` fills (light islands in dark mode).
- **Filled buttons/snackbars on status colours**: fill with x700 + white foreground (all ≥4.9:1). White-on-`orange.shade700` is 2.9:1; white-on-`amber.shade700` is 1.75:1.

## Codebase Docs

The `docs/` folder contains important design and architecture notes:

- `docs/app_bar_conventions.md` — AppBar/header standards for list vs. form screens
- `docs/stock_entry_flow.md` — Dual-rack (source/target) logic for Stock Entry
- `docs/STATEFUL_WIDGET_AUDIT.md` — Known widget lifecycle issues (orphaned Workers, setState conflicts)
- `docs/pos_delivery_note_item_rate_report.md` — Backend ERPNext Script Report + Client Script (customer-code ↔ item-code mapping); reproducible source for a Desk-only artifact
