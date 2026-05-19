# Connect to Instance UX — Design Spec

**Date:** 2026-05-19
**Issue:** #27 — Improve "Connect to Instance" UX for Server URL entry
**Scope:** Phase 1 cleanup + Phase 2A (MRU list) + Phase 2B (QR + hardware scanner)

---

## Context

The "Connect to Instance" bottom sheet lets users configure the ERPNext server URL before login. Phase 1 of issue #27 (keyboard-safe sheet, autofocus, paste helper, submit-on-Done, current URL display) is already implemented. `DatabaseService` already has full MRU infrastructure (`saveServerUrl`, `getServerUrls`, `removeServerUrl`, capped at 10). What remains:

- `_confirmAndSave` in `LoginController` never calls `saveServerUrl`, so history is never populated.
- `LoginController` has grown to own sheet-specific state (`serverUrlController`, `isCheckingConnection`, `saveServerConfiguration`) that doesn't belong there.
- No UI for the recent instances list.
- No QR scanner.
- The sheet content in `login_screen.dart` has redundant `Container` + `SafeArea` + `SingleChildScrollView` wrapping that `KeyboardSafeBottomSheet` already provides.

---

## Architecture

### New controller: `ConnectToInstanceController`

**File:** `lib/app/modules/auth/connect/connect_to_instance_controller.dart`

Owns the entire connect-sheet lifecycle. Created by `LoginController` just before the sheet opens via `Get.put(ConnectToInstanceController())` and deleted on sheet dismiss via `Get.delete<ConnectToInstanceController>()`.

**State:**
- `serverUrlController` — `TextEditingController` for the URL input field. Populated from `DatabaseService` on init.
- `currentServerUrl` — `String`, loaded from `DatabaseService.getConfig(serverUrlKey)` on init. Shown as "Current: …" in the sheet.
- `recentUrls` — `RxList<String>`, loaded from `DatabaseService.getServerUrls()` on init. Drives the Recent list.
- `isCheckingConnection` — `RxBool`, drives the Connect button spinner.

**Methods:**
- `fillUrl(String url)` — sets `serverUrlController.text` and moves cursor to end. Used by MRU tap, hardware scan, and camera scan.
- `saveServerConfiguration()` — trims and normalises URL (add `https://` if missing, strip trailing `/`), pings `/api/method/ping` with a 5-second timeout, calls `_confirmAndSave` on 200, shows error dialog with "Save Anyway" option on failure.
- `_confirmAndSave(String url)` — saves via `DatabaseService.saveConfig(serverUrlKey, url)` **and** `DatabaseService.saveServerUrl(url)`, updates `ApiProvider.setBaseUrl(url)`, reloads `recentUrls`, pops the sheet.
- `removeRecentUrl(String url)` — calls `DatabaseService.removeServerUrl(url)`, removes from `recentUrls` in place.

**Hardware scanner integration:**
One `ever()` worker registered on `Get.find<DataWedgeService>().scannedCode` in `onInit`. Handler: if value is non-empty and looks like a URL (`startsWith('http')` or `contains('.')`) call `fillUrl(value)`. Product barcodes (EAN-8 digits, hyphenated rack codes) fail this guard and are silently dropped. Worker stored in a field and cancelled in `onClose()`.

**Lifecycle:**
`onInit` → load saved URL into field + load recent URLs + start hardware scan worker.
`onClose` → dispose `serverUrlController` + cancel worker.

---

### LoginController (after refactor)

Removes: `serverUrlController`, `currentServerUrl`, `isCheckingConnection`, `saveServerConfiguration`, `_confirmAndSave`, `_loadSavedServerUrl`.

Keeps: `emailController`, `passwordController`, `loginFormKey`, `isLoading`, `isPasswordHidden`, `showServerGuide`, `loginUser()`, `validateEmail()`, `validatePassword()`, `resetPassword()`, `togglePasswordVisibility()`.

The `loginUser()` guard still reads the saved URL via `DatabaseService.getConfig(serverUrlKey)` directly (it already does this).

Opening the sheet becomes:
```dart
Get.put(ConnectToInstanceController());
showConnectToInstanceSheet(context);
```
Sheet dismiss calls `Get.delete<ConnectToInstanceController>()`.

---

### New widget: `ConnectToInstanceSheet`

**File:** `lib/app/modules/auth/connect/connect_to_instance_sheet.dart`

A `GetView<ConnectToInstanceController>`. Opened via a top-level `showConnectToInstanceSheet(BuildContext context)` function that calls `showKeyboardSafeBottomSheet`. The sheet content is a plain `Column` — no extra `Container`/`SafeArea`/`SingleChildScrollView` wrapping (those are already provided by `KeyboardSafeBottomSheet`).

**Layout (top to bottom):**
1. Title: "Connect to Instance" (`headlineSmall`, bold)
2. Helper text: "Enter the URL of your ERP instance." (grey)
3. Current URL line: "Current: `<url>`" (12px, grey) — shown only when non-empty
4. 24px gap
5. `TextField` for Server URL:
   - `controller: c.serverUrlController`
   - `prefixIcon: Icons.link`
   - `suffixIcon`: a `Row` containing paste icon (`Icons.content_paste`) and camera icon (`Icons.qr_code_scanner`)
   - `autofocus: true`, `autocorrect: false`, `keyboardType: TextInputType.url`
   - `textInputAction: TextInputAction.done`
   - `onSubmitted: (_) => c.saveServerConfiguration()`
   - Paste handler: reads `Clipboard.getData`, calls `fillUrl`
   - Camera handler: opens `QRScanSheet`
6. 16px gap
7. "Recent" section (hidden when `recentUrls` is empty):
   - Small uppercase label "RECENT"
   - `Column` + `.map()` of URL tiles (not `ListView` — avoids nested-scroll conflict with `KeyboardSafeBottomSheet`): URL text on left, `✕` `IconButton` on right. Tap URL tile → `c.fillUrl(url)`. Tap `✕` → `c.removeRecentUrl(url)`. Show maximum 5 items (`recentUrls.take(5)`).
8. 24px gap
9. Full-width `ElevatedButton` "Connect" → `c.saveServerConfiguration()`. Shows `CircularProgressIndicator` when `c.isCheckingConnection`.

---

### New widget: `QRScanSheet`

**File:** `lib/app/modules/auth/connect/qr_scan_sheet.dart`

A `StatefulWidget` opened via `showKeyboardSafeBottomSheet` (full-height, `isScrollControlled: true`). Receives `void Function(String url) onUrlScanned` callback.

Uses `MobileScanner` from the `mobile_scanner` package (already in `pubspec.yaml`). `MobileScannerController` is created in `initState` and disposed in `dispose`.

On each barcode detect event: if the raw value starts with `http` it is treated as a URL → call `onUrlScanned(value)` then `Navigator.pop()`. Otherwise ignore.

Layout:
- Title: "Scan Instance QR Code"
- Subtitle: "Point camera at the QR code for your ERP instance"
- `MobileScanner` widget filling available height with a centre overlay crosshair
- "Cancel" `TextButton` at the bottom

---

## File Summary

| Action | File |
|---|---|
| **Create** | `lib/app/modules/auth/connect/connect_to_instance_controller.dart` |
| **Create** | `lib/app/modules/auth/connect/connect_to_instance_sheet.dart` |
| **Create** | `lib/app/modules/auth/connect/qr_scan_sheet.dart` |
| **Modify** | `lib/app/modules/auth/login_controller.dart` — remove sheet-related fields/methods; add `Get.put`/`Get.delete` calls |
| **Modify** | `lib/app/modules/auth/login_screen.dart` — remove `_showServerConfigSheet`; call `showConnectToInstanceSheet` |

---

## Out of Scope

- Changes to authentication logic or ERPNext endpoints.
- Phase 2B QR: auto-submit on scan (tap-to-fill only, consistent with MRU behaviour).
- Offline/online detection beyond the existing `/api/method/ping` check.
- Recent-instances display cap > 5 items (storage cap stays at 10 in `DatabaseService`).
