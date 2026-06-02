# Connect to Instance UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the "Connect to Instance" sheet into a dedicated controller, add a recent-instances MRU list, and add a QR-code + hardware scanner to fill the URL field.

**Architecture:** Extract all sheet-related state and logic from `LoginController` into a new `ConnectToInstanceController` that is created/destroyed with the sheet. A `ConnectToInstanceSheet` widget renders the URL field, MRU list, and Connect button. A `QRScanSheet` widget provides the camera scanner. `LoginController` retains only login logic and delegates sheet opening to `openConnectSheet()`.

**Tech Stack:** Flutter, GetX (GetxController + GetView), `mobile_scanner` (already in pubspec), `DataWedgeService.scannedCode` (RxString observable), SQLite via `DatabaseService`.

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `lib/app/modules/auth/connect/connect_to_instance_controller.dart` | Sheet-scoped controller: URL load, save, MRU, hardware scan |
| Create | `lib/app/modules/auth/connect/connect_to_instance_sheet.dart` | `GetView` sheet widget + `showConnectToInstanceSheet()` |
| Create | `lib/app/modules/auth/connect/qr_scan_sheet.dart` | `StatefulWidget` camera sheet + `showQRScanSheet()` |
| Modify | `lib/app/modules/auth/login_controller.dart` | Remove sheet state; add `openConnectSheet()` |
| Modify | `lib/app/modules/auth/login_screen.dart` | Remove `_showServerConfigSheet`; call `controller.openConnectSheet(context)` |
| Create | `test/unit/connect_to_instance_controller_test.dart` | Unit tests for pure URL helpers |

---

## Task 1: Controller skeleton with URL utility methods (TDD)

**Files:**
- Create: `lib/app/modules/auth/connect/connect_to_instance_controller.dart`
- Create: `test/unit/connect_to_instance_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/unit/connect_to_instance_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_controller.dart';

void main() {
  group('ConnectToInstanceController.normaliseUrl', () {
    test('adds https:// when scheme is missing', () {
      expect(
        ConnectToInstanceController.normaliseUrl('erp.example.com'),
        'https://erp.example.com',
      );
    });

    test('strips trailing slash', () {
      expect(
        ConnectToInstanceController.normaliseUrl('https://erp.example.com/'),
        'https://erp.example.com',
      );
    });

    test('leaves existing https:// scheme unchanged', () {
      expect(
        ConnectToInstanceController.normaliseUrl('https://erp.example.com'),
        'https://erp.example.com',
      );
    });

    test('leaves existing http:// scheme unchanged', () {
      expect(
        ConnectToInstanceController.normaliseUrl('http://erp.example.com'),
        'http://erp.example.com',
      );
    });

    test('trims whitespace', () {
      expect(
        ConnectToInstanceController.normaliseUrl('  https://erp.example.com  '),
        'https://erp.example.com',
      );
    });
  });

  group('ConnectToInstanceController.looksLikeUrl', () {
    test('returns true for https URL', () {
      expect(ConnectToInstanceController.looksLikeUrl('https://erp.example.com'), isTrue);
    });

    test('returns true for domain without scheme', () {
      expect(ConnectToInstanceController.looksLikeUrl('erp.example.com'), isTrue);
    });

    test('returns false for EAN-8 digit string', () {
      expect(ConnectToInstanceController.looksLikeUrl('12345678'), isFalse);
    });

    test('returns false for rack code', () {
      expect(ConnectToInstanceController.looksLikeUrl('A-01-02-03'), isFalse);
    });

    test('returns false for empty string', () {
      expect(ConnectToInstanceController.looksLikeUrl(''), isFalse);
    });
  });
}
```

- [ ] **Step 2: Create minimal controller file so the import resolves (tests will still fail)**

Create `lib/app/modules/auth/connect/connect_to_instance_controller.dart`:

```dart
import 'package:get/get.dart';

class ConnectToInstanceController extends GetxController {
  static String normaliseUrl(String raw) {
    throw UnimplementedError();
  }

  static bool looksLikeUrl(String value) {
    throw UnimplementedError();
  }
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```
flutter test test/unit/connect_to_instance_controller_test.dart -v
```

Expected: all 9 tests FAIL with `UnimplementedError`.

- [ ] **Step 4: Implement the two static methods**

Replace the stubs in `lib/app/modules/auth/connect/connect_to_instance_controller.dart`:

```dart
import 'package:get/get.dart';

class ConnectToInstanceController extends GetxController {
  static String normaliseUrl(String raw) {
    String url = raw.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  static bool looksLikeUrl(String value) {
    if (value.isEmpty) return false;
    return value.startsWith('http') || value.contains('.');
  }
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```
flutter test test/unit/connect_to_instance_controller_test.dart -v
```

Expected: all 9 tests PASS.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/auth/connect/connect_to_instance_controller.dart test/unit/connect_to_instance_controller_test.dart
git commit -m "feat: add ConnectToInstanceController skeleton with URL utility methods"
```

---

## Task 2: Complete `ConnectToInstanceController` implementation

**Files:**
- Modify: `lib/app/modules/auth/connect/connect_to_instance_controller.dart`

- [ ] **Step 1: Replace the file with the full implementation**

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_navigator.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class ConnectToInstanceController extends GetxController {
  final DatabaseService _dbService = Get.find<DatabaseService>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final DataWedgeService _dataWedge = Get.find<DataWedgeService>();

  final TextEditingController serverUrlController = TextEditingController();
  String currentServerUrl = '';
  final recentUrls = <String>[].obs;
  final isCheckingConnection = false.obs;

  Worker? _scanWorker;

  // ── URL utilities ─────────────────────────────────────────────────────────

  static String normaliseUrl(String raw) {
    String url = raw.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  static bool looksLikeUrl(String value) {
    if (value.isEmpty) return false;
    return value.startsWith('http') || value.contains('.');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _loadSavedData();
    _scanWorker = ever(_dataWedge.scannedCode, _onHardwareScan);
  }

  Future<void> _loadSavedData() async {
    final savedUrl = await _dbService.getConfig(DatabaseService.serverUrlKey);
    final targetUrl = savedUrl ?? ApiProvider.defaultBaseUrl;
    serverUrlController.text = targetUrl;
    currentServerUrl = targetUrl;
    final urls = await _dbService.getServerUrls();
    recentUrls.assignAll(urls);
    update();
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    serverUrlController.dispose();
    super.onClose();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  void fillUrl(String url) {
    serverUrlController.text = url;
    serverUrlController.selection = TextSelection.fromPosition(
      TextPosition(offset: url.length),
    );
  }

  Future<void> removeRecentUrl(String url) async {
    await _dbService.removeServerUrl(url);
    recentUrls.remove(url);
  }

  Future<void> saveServerConfiguration() async {
    final rawUrl = serverUrlController.text;
    if (rawUrl.trim().isEmpty) {
      GlobalSnackbar.error(message: 'Server URL cannot be empty');
      return;
    }

    final url = normaliseUrl(rawUrl);

    isCheckingConnection.value = true;
    update();
    try {
      _apiProvider.setBaseUrl(url);
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      final response = await dio.get('$url/api/method/ping');

      if (response.statusCode == 200) {
        await _confirmAndSave(url);
        GlobalSnackbar.success(
          title: 'Connected',
          message: 'Successfully connected to $url',
        );
      } else {
        throw Exception('Invalid response (Status: ${response.statusCode})');
      }
    } catch (e) {
      isCheckingConnection.value = false;
      update();
      Get.dialog(
        Builder(
          builder: (context) => AlertDialog(
            title: const Text('Connection Failed'),
            content: Text(
              'Could not verify connection to the server.\n\n'
              'Error: $e\n\n'
              'Do you want to save this URL anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _confirmAndSave(url);
                  GlobalSnackbar.success(
                    title: 'Saved',
                    message: 'Server URL saved (Validation skipped)',
                  );
                },
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        ),
      );
    } finally {
      isCheckingConnection.value = false;
      update();
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _onHardwareScan(String value) {
    if (looksLikeUrl(value)) fillUrl(value);
  }

  Future<void> _confirmAndSave(String url) async {
    await _dbService.saveConfig(DatabaseService.serverUrlKey, url);
    await _dbService.saveServerUrl(url);
    serverUrlController.text = url;
    currentServerUrl = url;
    _apiProvider.setBaseUrl(url);
    final urls = await _dbService.getServerUrls();
    recentUrls.assignAll(urls);
    update();
    AppNavigator.pop();
  }
}
```

- [ ] **Step 2: Run `flutter analyze` — expect zero issues**

```
flutter analyze lib/app/modules/auth/connect/connect_to_instance_controller.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Run existing unit tests to confirm nothing regressed**

```
flutter test test/unit/ -v
```

Expected: all existing tests PASS (the new controller tests also still pass).

- [ ] **Step 4: Commit**

```
git add lib/app/modules/auth/connect/connect_to_instance_controller.dart
git commit -m "feat: complete ConnectToInstanceController — MRU, save, hardware scan"
```

---

## Task 3: Create `QRScanSheet`

**Files:**
- Create: `lib/app/modules/auth/connect/qr_scan_sheet.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/core/widgets/keyboard_safe_bottom_sheet.dart';

class QRScanSheet extends StatefulWidget {
  const QRScanSheet({super.key, required this.onUrlScanned});

  final void Function(String url) onUrlScanned;

  @override
  State<QRScanSheet> createState() => _QRScanSheetState();
}

class _QRScanSheetState extends State<QRScanSheet> {
  late final MobileScannerController _scannerController;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue ?? '';
      if (value.startsWith('http')) {
        _scanned = true;
        Navigator.of(context).pop();
        widget.onUrlScanned(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Scan Instance QR Code',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Point camera at the QR code for your ERP instance',
          style: TextStyle(color: Colors.grey, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 260,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
                Center(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Opens the QR scanner sheet. [onUrlScanned] is called with the scanned URL
/// string when a valid http/https QR code is detected.
Future<void> showQRScanSheet(
  BuildContext context, {
  required void Function(String url) onUrlScanned,
}) {
  return showKeyboardSafeBottomSheet(
    context: context,
    child: QRScanSheet(onUrlScanned: onUrlScanned),
    isScrollControlled: true,
  );
}
```

- [ ] **Step 2: Run `flutter analyze`**

```
flutter analyze lib/app/modules/auth/connect/qr_scan_sheet.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add lib/app/modules/auth/connect/qr_scan_sheet.dart
git commit -m "feat: add QRScanSheet with mobile_scanner and hardware-safe guard"
```

---

## Task 4: Create `ConnectToInstanceSheet`

**Files:**
- Create: `lib/app/modules/auth/connect/connect_to_instance_sheet.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/widgets/keyboard_safe_bottom_sheet.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_controller.dart';
import 'package:multimax/app/modules/auth/connect/qr_scan_sheet.dart';

class ConnectToInstanceSheet extends GetView<ConnectToInstanceController> {
  const ConnectToInstanceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ConnectToInstanceController>(
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect to Instance',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the URL of your ERP instance.',
            style: TextStyle(color: Colors.grey),
          ),
          if (c.currentServerUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Current: ${c.currentServerUrl}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: c.serverUrlController,
            decoration: InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://erp.domain.com',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty) {
                        c.fillUrl(text);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan QR code',
                    onPressed: () =>
                        showQRScanSheet(context, onUrlScanned: c.fillUrl),
                  ),
                ],
              ),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autofocus: true,
            autocorrect: false,
            onSubmitted: (_) => c.saveServerConfiguration(),
          ),
          if (c.recentUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'RECENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            ...c.recentUrls.take(5).map(
                  (url) => _RecentUrlTile(
                    url: url,
                    onTap: () => c.fillUrl(url),
                    onDelete: () => c.removeRecentUrl(url),
                  ),
                ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: c.isCheckingConnection.value
                  ? null
                  : c.saveServerConfiguration,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: c.isCheckingConnection.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentUrlTile extends StatelessWidget {
  const _RecentUrlTile({
    required this.url,
    required this.onTap,
    required this.onDelete,
  });

  final String url;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(6),
            color: Colors.grey.shade50,
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    url,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: onDelete,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the Connect to Instance sheet.
/// Caller is responsible for registering [ConnectToInstanceController] via
/// `Get.put` before calling this and deleting it after the returned Future
/// completes.
Future<void> showConnectToInstanceSheet(BuildContext context) {
  return showKeyboardSafeBottomSheet(
    context: context,
    child: const ConnectToInstanceSheet(),
  );
}
```

- [ ] **Step 2: Run `flutter analyze`**

```
flutter analyze lib/app/modules/auth/connect/connect_to_instance_sheet.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add lib/app/modules/auth/connect/connect_to_instance_sheet.dart
git commit -m "feat: add ConnectToInstanceSheet with MRU list and QR icon"
```

---

## Task 5: Refactor `LoginController`

**Files:**
- Modify: `lib/app/modules/auth/login_controller.dart`

- [ ] **Step 1: Replace the file with the refactored version**

The new `login_controller.dart` removes all sheet-related fields/methods and adds `openConnectSheet()`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_navigator.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_controller.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class LoginController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController =
      Get.find<AuthenticationController>();
  final DatabaseService _dbService = Get.find<DatabaseService>();

  final GlobalKey<FormState> loginFormKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  var isLoading = false.obs;
  var showServerGuide = false.obs;

  final isPasswordHidden = ValueNotifier<bool>(true);

  // ── Connect-sheet lifecycle ───────────────────────────────────────────────

  void openConnectSheet(BuildContext context) {
    Get.put(ConnectToInstanceController());
    showConnectToInstanceSheet(context).then((_) async {
      Get.delete<ConnectToInstanceController>(force: true);
      final savedUrl =
          await _dbService.getConfig(DatabaseService.serverUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        showServerGuide.value = false;
        update();
      }
    });
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    isPasswordHidden.dispose();
    super.onClose();
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  void togglePasswordVisibility() =>
      isPasswordHidden.value = !isPasswordHidden.value;

  Future<void> loginUser() async {
    final storedUrl =
        await _dbService.getConfig(DatabaseService.serverUrlKey);

    if (storedUrl == null || storedUrl.isEmpty) {
      showServerGuide.value = true;
      update();
      AppNotification.warning(
        'Please set the Server URL using the settings icon above before logging in.',
      );
      return;
    }

    if (loginFormKey.currentState!.validate()) {
      isLoading.value = true;
      update();
      try {
        final response = await _apiProvider.loginWithFrappe(
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        if (response.statusCode == 200 &&
            response.data?['message'] == 'Logged In') {
          await _authController.fetchUserDetails();
          if (_authController.currentUser.value != null) {
            _authController.processSuccessfulLogin(
                _authController.currentUser.value!);
          } else {
            final String fullName =
                response.data?['full_name'] ?? 'User';
            final user = User(
              id: emailController.text.trim(),
              name: fullName,
              email: emailController.text.trim(),
              roles: [],
            );
            _authController.processSuccessfulLogin(user);
          }
        } else if (response.statusCode == 401 ||
            response.statusCode == 403) {
          GlobalSnackbar.error(
            title: 'Login Failed',
            message:
                response.data?['message'] ?? 'Invalid credentials.',
          );
        } else {
          GlobalSnackbar.error(
            title: 'Login Error',
            message: response.data?['message'] ??
                'An unknown error occurred.',
          );
        }
      } catch (e) {
        GlobalSnackbar.error(
          title: 'Login Error',
          message: 'An unexpected error occurred.',
        );
      } finally {
        isLoading.value = false;
        update();
      }
    }
  }

  Future<void> resetPassword() async {
    if (emailController.text.isEmpty) {
      GlobalSnackbar.error(
          message: 'Please enter your email address first');
      return;
    }
    isLoading.value = true;
    update();
    try {
      final response =
          await _apiProvider.resetPassword(emailController.text.trim());
      if (response.statusCode == 200) {
        AppNavigator.pop();
        GlobalSnackbar.success(
            message: 'Password reset instructions sent to your email');
      } else {
        GlobalSnackbar.error(message: 'Failed to send reset link');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Reset failed: $e');
    } finally {
      isLoading.value = false;
      update();
    }
  }
}
```

- [ ] **Step 2: Run `flutter analyze` on the auth module**

```
flutter analyze lib/app/modules/auth/
```

Expected: `No issues found!`

- [ ] **Step 3: Run all unit tests**

```
flutter test test/unit/ -v
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```
git add lib/app/modules/auth/login_controller.dart
git commit -m "refactor: extract sheet state from LoginController into ConnectToInstanceController"
```

---

## Task 6: Update `LoginScreen`

**Files:**
- Modify: `lib/app/modules/auth/login_screen.dart`

- [ ] **Step 1: Replace the file with the updated version**

Remove `_showServerConfigSheet` and the `keyboard_safe_bottom_sheet` import. Update `_buildSettingsIcon` to call `controller.openConnectSheet(context)`.

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  Widget _buildLogo() {
    return Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]);
  }

  Widget _buildSettingsIcon(BuildContext context) {
    return GetBuilder<LoginController>(
      builder: (c) {
        final showGuide = c.showServerGuide.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (showGuide)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withValues(alpha: 0.3),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
              ),
            IconButton(
              icon: Icon(
                Icons.settings,
                color: showGuide ? Colors.orange : Colors.grey,
              ),
              tooltip: 'Server Configuration',
              onPressed: () => controller.openConnectSheet(context),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: controller.loginFormKey,
                child: AutofillGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildLogo(),
                      const SizedBox(height: 48.0),
                      TextFormField(
                        controller: controller.emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email / Username',
                          hintText: 'Enter your email or username',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        validator: controller.validateEmail,
                        autovalidateMode:
                            AutovalidateMode.onUserInteraction,
                      ),
                      const SizedBox(height: 16.0),
                      ValueListenableBuilder<bool>(
                        valueListenable: controller.isPasswordHidden,
                        builder: (context, isHidden, _) => TextFormField(
                          controller: controller.passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                isHidden
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed:
                                  controller.togglePasswordVisibility,
                            ),
                          ),
                          obscureText: isHidden,
                          textInputAction: TextInputAction.done,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => controller.loginUser(),
                          validator: controller.validatePassword,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GetBuilder<LoginController>(
                          builder: (c) => TextButton(
                            onPressed: () {
                              if (c.isLoading.value) return;
                              if (controller.emailController.text.isEmpty) {
                                GlobalSnackbar.info(
                                  message:
                                      'Please enter your email address in the field above first.',
                                );
                              } else {
                                Get.defaultDialog(
                                  title: 'Reset Password',
                                  middleText:
                                      'Send password reset instructions to ${controller.emailController.text}?',
                                  textConfirm: 'Send',
                                  textCancel: 'Cancel',
                                  confirmTextColor: Colors.white,
                                  onConfirm: () {
                                    Get.back();
                                    controller.resetPassword();
                                  },
                                );
                              }
                            },
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24.0),
                      GetBuilder<LoginController>(
                        builder: (c) => ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16.0),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                          onPressed:
                              c.isLoading.value ? null : c.loginUser,
                          child: c.isLoading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: _buildSettingsIcon(context),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run `flutter analyze` on the full project**

```
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run all tests**

```
flutter test -v
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```
git add lib/app/modules/auth/login_screen.dart
git commit -m "refactor: update LoginScreen to use ConnectToInstanceSheet"
```

---

## Task 7: Smoke test on device

- [ ] **Step 1: Run the app on a connected device**

```
flutter run
```

- [ ] **Step 2: Verify golden path — connect sheet**

1. Open the app. Tap the settings icon (top-right of login screen).
2. Confirm the sheet opens with the URL field auto-focused and keyboard raised.
3. Confirm "Current: …" displays the previously saved URL (if any).
4. Tap the paste icon — confirm it fills the field from clipboard.
5. Tap the QR icon — confirm the camera sheet opens; tap Cancel to close it.
6. Type a URL and press the keyboard Done key — confirm it triggers the connection check.
7. Tap Connect with a valid URL — confirm success snackbar and sheet close.
8. Re-open the sheet — confirm the saved URL appears under "RECENT".
9. Tap a recent URL tile — confirm it fills the field.
10. Tap the ✕ on a recent URL — confirm it disappears from the list.

- [ ] **Step 3: Verify no regression on login flow**

1. Clear the server URL (set it to something invalid so login guard fires).
2. Tap Login without setting a URL — confirm the orange pulse appears on the settings icon.
3. Set a valid URL via the sheet — confirm the pulse clears after the sheet closes.
4. Log in with valid credentials — confirm normal login flow.

- [ ] **Step 4: Commit smoke test sign-off (if any minor fixes were made)**

```
git add -p
git commit -m "fix: address issues found during smoke test"
```
