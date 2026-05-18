# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Flutter mobile app ("KA-ML Fulfillment") for supply-chain operations against a Frappe/ERPNext backend at `https://erp.multimax.cloud`. Covers stock, purchase orders, delivery notes, work orders, job cards, packing slips, and manufacturing. Primary platform is Android (USB/WiFi device), but configured for iOS, desktop, and web.

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

## Codebase Docs

The `docs/` folder contains important design and architecture notes:

- `docs/app_bar_conventions.md` — AppBar/header standards for list vs. form screens
- `docs/stock_entry_flow.md` — Dual-rack (source/target) logic for Stock Entry
- `docs/STATEFUL_WIDGET_AUDIT.md` — Known widget lifecycle issues (orphaned Workers, setState conflicts)
