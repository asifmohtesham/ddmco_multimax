# Logout Loading Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a full-screen loading overlay while the logout API call is in-flight, replacing the silent pause between confirm-dialog dismiss and login-screen navigation.

**Architecture:** A second `Get.dialog()` is pushed immediately after the confirm dialog closes. It uses `barrierColor: Colors.black54` and `barrierDismissible: false` to block interaction. On success `Get.offAllNamed` clears the entire route stack (including the overlay). On error `Get.back()` dismisses it explicitly before showing the error snackbar.

**Tech Stack:** Flutter, GetX (`get: ^4.7.2`), Dart SDK `^3.8.1`

---

## Files

| Action | Path |
|--------|------|
| Modify | `lib/app/modules/auth/authentication_controller.dart` |

---

### Task 1: Add loading overlay to `logoutUser()`

**Files:**
- Modify: `lib/app/modules/auth/authentication_controller.dart:133-168`

The current method (`logoutUser`) dismisses the confirm dialog, sets `isLoading = true`,
then runs the API call in a `try/finally`. The `finally` block always resets `isLoading`
even on success (where the controller is about to be irrelevant anyway).

Replace the content of the `Logout` button's `onPressed` with the version below, which:
1. Dismisses the confirm dialog
2. Sets `isLoading = true`
3. Pushes the loading overlay dialog
4. Runs the API call
5. On success → `Get.offAllNamed` (clears overlay automatically)
6. On error → `Get.back()` + `isLoading = false` + error snackbar

- [ ] **Step 1: Replace `logoutUser()` in `authentication_controller.dart`**

Replace the entire `logoutUser()` method (lines 133–168) with:

```dart
Future<void> logoutUser() async {
  Get.dialog(
    Builder(
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            child: const Text('Logout'),
            onPressed: () async {
              Navigator.of(context).pop();
              isLoading.value = true;
              Get.dialog(
                const PopScope(
                  canPop: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Logging out…',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                barrierDismissible: false,
                barrierColor: Colors.black54,
              );
              try {
                await _apiProvider.logoutApiCall();
                await _clearSessionAndLocalData();
                Get.offAllNamed(AppRoutes.LOGIN);
              } catch (e) {
                Get.back();
                isLoading.value = false;
                GlobalSnackbar.error(
                  title: 'Logout Error',
                  message: 'Could not log out.',
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}
```

No new imports are needed — `Colors`, `PopScope`, `CircularProgressIndicator`, `Text`, and
`Column` are all from `flutter/material.dart`, which is already imported.

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze lib/app/modules/auth/authentication_controller.dart
```

Expected: `No issues found!` (or only pre-existing warnings unrelated to this file).

- [ ] **Step 3: Manual smoke test — success path**

1. `flutter run -d <device_id>`
2. Open the nav drawer → tap the user header chevron to expand the user menu
3. Tap **Logout**
4. Confirm dialog appears → tap **Logout**
5. **Expected:** black semi-transparent overlay with white spinner and "Logging out…" label appears
6. **Expected:** overlay disappears and app lands on the Login screen
7. **Expected:** no error snackbar

- [ ] **Step 4: Manual smoke test — error path**

To simulate an API error, temporarily add `throw Exception('test');` as the first line inside the `try` block, hot-restart, and repeat the logout tap sequence.

1. **Expected:** overlay appears briefly then dismisses
2. **Expected:** a red error snackbar with "Logout Error / Could not log out." appears
3. **Expected:** the user remains on the current screen (not navigated to login)

Remove the `throw` line after verifying.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/auth/authentication_controller.dart
git commit -m "feat: show full-screen loading overlay during logout"
```
