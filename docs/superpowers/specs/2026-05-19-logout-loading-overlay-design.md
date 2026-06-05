# Logout Loading Overlay

**Date:** 2026-05-19  
**Status:** Approved

## Context

The logout flow already exists end-to-end:
- `AppNavDrawer` → expand user header → tap **Logout** → calls `AuthenticationController.logoutUser()`
- `logoutUser()` shows a confirmation `AlertDialog`, then calls the logout API and navigates to `AppRoutes.LOGIN`

The gap: after the confirmation dialog is dismissed, `isLoading` is set but nothing renders a loading indicator. The screen sits idle until `Get.offAllNamed` fires.

## Goal

Show a full-screen loading overlay immediately after the user confirms logout, giving clear feedback while the API call is in-flight.

## Scope

One method changes: `AuthenticationController.logoutUser()` in  
`lib/app/modules/auth/authentication_controller.dart`.

No widget tree, routing, binding, or provider changes.

## Design

### Loading overlay

- Shown via a second `Get.dialog()` call pushed immediately after the confirm dialog is dismissed
- `barrierDismissible: false` — user cannot tap through or dismiss it
- `barrierColor: Colors.black54` — semi-transparent black covers the entire screen
- Content: a centered column with a white `CircularProgressIndicator` and `"Logging out…"` label in white

### Success path

`Get.offAllNamed(AppRoutes.LOGIN)` clears the entire route stack including the overlay. No manual `Get.back()` needed.

### Error path

`Get.back()` dismisses the overlay explicitly, then `isLoading.value = false`, then `GlobalSnackbar.error()` with the existing error message. The `finally` block is removed in favour of this explicit cleanup, because in the success path the controller state is irrelevant after navigation.

### Updated `logoutUser()` — pseudocode

```
show confirm AlertDialog
  Cancel → dismiss dialog
  Logout →
    1. dismiss confirm dialog
    2. isLoading = true
    3. Get.dialog(overlay, barrierDismissible: false, barrierColor: black54)
    4. await _apiProvider.logoutApiCall()
    5. await _clearSessionAndLocalData()
    success → Get.offAllNamed(LOGIN)        // clears overlay automatically
    error   → Get.back()                   // dismiss overlay
              isLoading = false
              GlobalSnackbar.error(...)
```

## Non-goals

- No changes to `AppNavDrawer`, `AppShellScaffold`, `main.dart`, or any other file
- No new `isLoggingOut` observable — `isLoading` continues to serve both startup auth-check and logout
