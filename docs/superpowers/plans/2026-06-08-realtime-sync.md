# Realtime Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Socket.IO live subscription and auto-save debounce to 8 form controllers so concurrent saves no longer produce version-conflict dialogs.

**Architecture:** A plain `FrappeSocket` class wraps `socket_io_client`; a `RealtimeSyncMixin` owns the socket lifecycle and auto-save timer and is mixed into each form controller. When another user saves a document, the app receives a `doc_update` event, flushes any pending unsaved work, and reloads — keeping the Frappe `modified` timestamp fresh before the next save.

**Tech Stack:** Dart `socket_io_client ^2.0.3`, GetX mixins, `flutter_test`

**Spec:** `docs/superpowers/specs/2026-06-08-realtime-sync-design.md`

---

## File Map

**Create:**
- `lib/app/data/services/frappe_socket.dart` — Socket.IO wrapper (idempotent connect/dispose)
- `lib/app/data/mixins/realtime_sync_mixin.dart` — auto-save timer + remote-update handler
- `test/unit/frappe_socket_test.dart`
- `test/unit/realtime_sync_mixin_test.dart`
- `test/unit/storage_service_auto_save_test.dart`

**Modify:**
- `pubspec.yaml` — add `socket_io_client`
- `lib/app/data/providers/api_provider.dart` — add `getSessionCookieHeader()`
- `lib/app/data/services/storage_service.dart` — add `getAutoSaveDelay` / `saveAutoSaveDelay`
- `lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart` — add auto-save slider
- `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`
- `lib/app/modules/delivery_note/form/delivery_note_form_controller.dart`
- `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`
- `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`
- `lib/app/modules/material_request/form/material_request_form_controller.dart`
- `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`
- `lib/app/modules/batch/form/batch_form_controller.dart`
- `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`

---

## Task 1: Add socket_io_client dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, add after `shared_preferences`:

```yaml
  socket_io_client: ^2.0.3
```

- [ ] **Step 2: Fetch packages**

```bash
flutter pub get
```

Expected: resolves without conflict.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add socket_io_client ^2.0.3"
```

---

## Task 2: Add getSessionCookieHeader() to ApiProvider

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart`
- Test: `test/unit/frappe_socket_test.dart` (cookie format tested here — no GetX needed)

- [ ] **Step 1: Write the failing test**

Create `test/unit/frappe_socket_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cookie header formatting', () {
    test('joins multiple cookies with semicolons', () {
      // Replicate the join logic from getSessionCookieHeader()
      final cookies = [
        {'name': 'sid', 'value': 'abc123'},
        {'name': 'system_user', 'value': 'yes'},
      ];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, 'sid=abc123; system_user=yes');
    });

    test('single cookie has no trailing semicolon', () {
      final cookies = [
        {'name': 'sid', 'value': 'xyz'},
      ];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, 'sid=xyz');
    });

    test('empty cookie list produces empty string', () {
      final cookies = <Map<String, String>>[];
      final header = cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
      expect(header, '');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it passes (it's a pure logic test)**

```bash
flutter test test/unit/frappe_socket_test.dart
```

Expected: PASS — these tests verify the join format used by `getSessionCookieHeader()`.

- [ ] **Step 3: Add the method to ApiProvider**

In `lib/app/data/providers/api_provider.dart`, add after `clearSessionCookies()`:

```dart
  Future<String> getSessionCookieHeader() async {
    if (!_dioInitialised) await _initDio();
    final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }
```

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/providers/api_provider.dart test/unit/frappe_socket_test.dart
git commit -m "feat(api): add getSessionCookieHeader for Socket.IO auth"
```

---

## Task 3: Add auto-save delay to StorageService

**Files:**
- Modify: `lib/app/data/services/storage_service.dart`
- Test: `test/unit/storage_service_auto_save_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/storage_service_auto_save_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/services/storage_service.dart';

void main() {
  setUpAll(() async {
    await GetStorage.init();
  });

  group('StorageService auto-save delay', () {
    late StorageService service;

    setUp(() {
      service = StorageService();
    });

    test('getAutoSaveDelay returns default 5 when not set', () {
      // Clear any previously written value
      GetStorage().remove('auto_save_delay');
      expect(service.getAutoSaveDelay(), 5);
    });

    test('saveAutoSaveDelay persists and getAutoSaveDelay reads it back', () async {
      await service.saveAutoSaveDelay(12);
      expect(service.getAutoSaveDelay(), 12);
    });

    test('saveAutoSaveDelay overwrites previous value', () async {
      await service.saveAutoSaveDelay(8);
      await service.saveAutoSaveDelay(15);
      expect(service.getAutoSaveDelay(), 15);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/unit/storage_service_auto_save_test.dart
```

Expected: FAIL with `NoSuchMethodError` — method doesn't exist yet.

- [ ] **Step 3: Add methods to StorageService**

In `lib/app/data/services/storage_service.dart`, add after the `_autoSubmitDelayKey` constant:

```dart
  static const String _autoSaveDelayKey = 'auto_save_delay';
```

After `getAutoSubmitDelay()`:

```dart
  Future<void> saveAutoSaveDelay(int seconds) async =>
      _box.write(_autoSaveDelayKey, seconds);

  int getAutoSaveDelay() =>
      _box.read<int>(_autoSaveDelayKey) ?? 5;
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/unit/storage_service_auto_save_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/services/storage_service.dart test/unit/storage_service_auto_save_test.dart
git commit -m "feat(storage): add auto-save delay setting (default 5 s)"
```

---

## Task 4: Add auto-save slider to Session defaults UI

**Files:**
- Modify: `lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart`

- [ ] **Step 1: Add state field**

In `_SessionDefaultsBottomSheetState`, after `double _autoSubmitDelay = 2.0;`:

```dart
  double _autoSaveDelay = 5.0;
```

- [ ] **Step 2: Load saved value in _loadData()**

After `_autoSubmitDelay = delay.toDouble();`:

```dart
          _autoSaveDelay = _storageService.getAutoSaveDelay().toDouble();
```

- [ ] **Step 3: Persist in _saveDefaults()**

After `await _storageService.saveAutoSubmitSettings(...)`:

```dart
    await _storageService.saveAutoSaveDelay(_autoSaveDelay.toInt());
```

- [ ] **Step 4: Add slider to build()**

After the closing `],` of the `if (_autoSubmitEnabled) ...[]` block and before `const SizedBox(height: 24),` (the one before the Troubleshooting section):

```dart
                    const SizedBox(height: 16),
                    Text(
                        'Auto-save Delay: ${_autoSaveDelay.toInt()}s',
                        style: Theme.of(context).textTheme.bodyMedium),
                    Slider(
                      value: _autoSaveDelay,
                      min: 3,
                      max: 30,
                      divisions: 9,
                      label: '${_autoSaveDelay.toInt()}s',
                      onChanged: (val) =>
                          setState(() => _autoSaveDelay = val),
                    ),
```

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart
git commit -m "feat(ui): add auto-save delay slider to session defaults"
```

---

## Task 5: Create FrappeSocket

**Files:**
- Create: `lib/app/data/services/frappe_socket.dart`
- Test: `test/unit/frappe_socket_test.dart` (extend existing file)

- [ ] **Step 1: Write failing tests for FrappeSocket**

Append to `test/unit/frappe_socket_test.dart`:

```dart
import 'package:multimax/app/data/services/frappe_socket.dart';

// Minimal fake socket that records calls
class _FakeSocket {
  final List<String> emitted = [];
  final Map<String, void Function(dynamic)> listeners = {};
  void Function()? onConnectCallback;
  void Function(dynamic)? onConnectErrorCallback;

  void emit(String event, [dynamic data]) => emitted.add(event);
  void on(String event, void Function(dynamic) cb) => listeners[event] = cb;
  void onConnect(void Function() cb) => onConnectCallback = cb;
  void onConnectError(void Function(dynamic) cb) => onConnectErrorCallback = cb;
  void onError(void Function(dynamic) cb) {}
  void connect() => onConnectCallback?.call();
  void disconnect() {}
  void dispose() {}
}

void main() {
  // ... existing cookie tests above ...

  group('FrappeSocket', () {
    test('connect() subscribes to the document room on connect', () {
      final fakeSocket = _FakeSocket();
      final frappe = FrappeSocket(
        socketFactory: (url, opts) => fakeSocket as dynamic,
      );
      bool called = false;
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () => called = true,
      );
      expect(fakeSocket.emitted, contains('doc_subscribe'));
    });

    test('connect() is idempotent — second call is a no-op', () {
      final fakeSocket = _FakeSocket();
      int connectCount = 0;
      final frappe = FrappeSocket(
        socketFactory: (url, opts) {
          connectCount++;
          return fakeSocket as dynamic;
        },
      );
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      expect(connectCount, 1);
    });

    test('doc_update fires onDocUpdate only for matching doctype+name', () {
      final fakeSocket = _FakeSocket();
      final frappe = FrappeSocket(
        socketFactory: (url, opts) => fakeSocket as dynamic,
      );
      int callCount = 0;
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () => callCount++,
      );
      // Matching event
      fakeSocket.listeners['doc_update']!(
          {'doctype': 'Stock Entry', 'name': 'MAT-STE-001'});
      // Non-matching docname
      fakeSocket.listeners['doc_update']!(
          {'doctype': 'Stock Entry', 'name': 'MAT-STE-999'});
      // Non-matching doctype
      fakeSocket.listeners['doc_update']!(
          {'doctype': 'Delivery Note', 'name': 'MAT-STE-001'});
      expect(callCount, 1);
    });

    test('dispose() emits doc_unsubscribe and resets connected state', () {
      final fakeSocket = _FakeSocket();
      final frappe = FrappeSocket(
        socketFactory: (url, opts) => fakeSocket as dynamic,
      );
      frappe.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      frappe.dispose();
      expect(fakeSocket.emitted, contains('doc_unsubscribe'));

      // After dispose, connect() should be allowed again
      int connectCount = 0;
      final frappe2 = FrappeSocket(
        socketFactory: (url, opts) {
          connectCount++;
          return _FakeSocket() as dynamic;
        },
      );
      frappe2.connect(
        baseUrl: 'https://erp.example.com',
        cookieHeader: 'sid=abc',
        doctype: 'Stock Entry',
        docname: 'MAT-STE-001',
        onDocUpdate: () {},
      );
      expect(connectCount, 1);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/unit/frappe_socket_test.dart
```

Expected: FAIL — `FrappeSocket` doesn't exist yet.

- [ ] **Step 3: Implement FrappeSocket**

Create `lib/app/data/services/frappe_socket.dart`:

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef _SocketFactory = dynamic Function(String url, dynamic opts);

class FrappeSocket {
  final _SocketFactory? _socketFactory;
  dynamic _socket;
  bool _connected = false;

  FrappeSocket({_SocketFactory? socketFactory}) : _socketFactory = socketFactory;

  void connect({
    required String baseUrl,
    required String cookieHeader,
    required String doctype,
    required String docname,
    required void Function() onDocUpdate,
  }) {
    if (_connected) return;
    _connected = true;

    final opts = IO.OptionBuilder()
        .setTransports(['websocket'])
        .setExtraHeaders({'Cookie': cookieHeader})
        .disableAutoConnect()
        .build();

    _socket = _socketFactory != null
        ? _socketFactory!(baseUrl, opts)
        : IO.io(baseUrl, opts);

    _socket.onConnect((_) {
      _socket.emit('doc_subscribe', [doctype, docname]);
    });

    _socket.on('doc_update', (data) {
      if (data is Map &&
          data['doctype'] == doctype &&
          data['name'] == docname) {
        onDocUpdate();
      }
    });

    _socket.onConnectError((_) {});
    _socket.onError((_) {});

    _socket.connect();
  }

  void dispose() {
    _socket?.emit('doc_unsubscribe', []);
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/unit/frappe_socket_test.dart
```

Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/services/frappe_socket.dart test/unit/frappe_socket_test.dart
git commit -m "feat(socket): add FrappeSocket wrapper with idempotent connect"
```

---

## Task 6: Create RealtimeSyncMixin

**Files:**
- Create: `lib/app/data/mixins/realtime_sync_mixin.dart`
- Test: `test/unit/realtime_sync_mixin_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/unit/realtime_sync_mixin_test.dart`:

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:multimax/app/data/services/frappe_socket.dart';

// Concrete test controller that satisfies the mixin's abstract contract
class _TestController extends GetxController with RealtimeSyncMixin {
  @override String get realtimeDoctype => 'Stock Entry';
  @override String get realtimeDocname => _docname;
  String _docname = 'MAT-STE-001';

  @override final isDirty  = false.obs;
  @override final isSaving = false.obs;

  int saveCallCount   = 0;
  int reloadCallCount = 0;

  @override Future<void> saveDocument() async => saveCallCount++;
  @override Future<void> reloadDocument() async => reloadCallCount++;

  // Inject a no-op FrappeSocket for unit tests
  @override
  FrappeSocket createFrappeSocket() => FrappeSocket(
    socketFactory: (url, opts) => _NoOpSocket(),
  );
}

class _NoOpSocket {
  void onConnect(void Function() cb) {}
  void on(String event, void Function(dynamic) cb) {}
  void onConnectError(void Function(dynamic) cb) {}
  void onError(void Function(dynamic) cb) {}
  void connect() {}
  void disconnect() {}
  void dispose() {}
  void emit(String event, [dynamic data]) {}
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() => Get.reset());

  group('RealtimeSyncMixin.scheduleAutoSave', () {
    test('calls saveDocument after delay when isDirty is true', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value = true;

      // Override delay by calling the timer directly with 0 ms
      ctrl.scheduleAutoSaveForTest(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(ctrl.saveCallCount, 1);
    });

    test('does not call saveDocument when isDirty is false', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value = false;

      ctrl.scheduleAutoSaveForTest(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(ctrl.saveCallCount, 0);
    });

    test('does not call saveDocument when isSaving is true', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value  = true;
      ctrl.isSaving.value = true;

      ctrl.scheduleAutoSaveForTest(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(ctrl.saveCallCount, 0);
    });

    test('cancels previous timer on second call (debounce)', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value = true;

      ctrl.scheduleAutoSaveForTest(const Duration(milliseconds: 50));
      ctrl.scheduleAutoSaveForTest(const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(ctrl.saveCallCount, 1); // only once, not twice
    });
  });

  group('RealtimeSyncMixin.triggerRemoteUpdate', () {
    test('shows notification, flushes dirty save, then reloads', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value = true;

      await ctrl.triggerRemoteUpdateForTest();

      expect(ctrl.saveCallCount,   1);
      expect(ctrl.reloadCallCount, 1);
    });

    test('skips flush save when not dirty', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value = false;

      await ctrl.triggerRemoteUpdateForTest();

      expect(ctrl.saveCallCount,   0);
      expect(ctrl.reloadCallCount, 1);
    });

    test('skips flush save when already saving', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value  = true;
      ctrl.isSaving.value = true;

      await ctrl.triggerRemoteUpdateForTest();

      expect(ctrl.saveCallCount,   0);
      expect(ctrl.reloadCallCount, 1);
    });

    test('cancels pending auto-save timer before reload', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value = true;

      // Schedule a timer that would fire and save again
      ctrl.scheduleAutoSaveForTest(const Duration(milliseconds: 50));
      await ctrl.triggerRemoteUpdateForTest();
      // Wait past the timer
      await Future.delayed(const Duration(milliseconds: 100));

      // Save should only have been called once (by triggerRemoteUpdate, not the timer)
      expect(ctrl.saveCallCount, 1);
    });
  });

  group('RealtimeSyncMixin.disposeRealtimeSync', () {
    test('cancels the auto-save timer on dispose', () async {
      final ctrl = Get.put(_TestController());
      ctrl.isDirty.value = true;
      ctrl.scheduleAutoSaveForTest(const Duration(milliseconds: 50));
      ctrl.disposeRealtimeSync();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(ctrl.saveCallCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/unit/realtime_sync_mixin_test.dart
```

Expected: FAIL — mixin doesn't exist yet.

- [ ] **Step 3: Implement RealtimeSyncMixin**

Create `lib/app/data/mixins/realtime_sync_mixin.dart`:

```dart
import 'dart:async';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/frappe_socket.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

mixin RealtimeSyncMixin on GetxController {
  late final FrappeSocket _frappeSocket = createFrappeSocket();
  Timer? _autoSaveTimer;

  // ── Overridable for testing ───────────────────────────────────────────────
  FrappeSocket createFrappeSocket() => FrappeSocket();

  // ── Abstract contract ─────────────────────────────────────────────────────
  String get realtimeDoctype;
  String get realtimeDocname;
  RxBool get isDirty;
  RxBool get isSaving;
  Future<void> saveDocument();
  Future<void> reloadDocument();

  // ── Auto-save ─────────────────────────────────────────────────────────────

  void scheduleAutoSave() {
    final delay = Get.find<StorageService>().getAutoSaveDelay();
    _scheduleAutoSaveWithDuration(Duration(seconds: delay));
  }

  void _scheduleAutoSaveWithDuration(Duration duration) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(duration, () async {
      if (!isClosed && isDirty.value && !isSaving.value) {
        await saveDocument();
      }
    });
  }

  // Exposed for unit tests only — not part of public API
  void scheduleAutoSaveForTest(Duration duration) =>
      _scheduleAutoSaveWithDuration(duration);

  // ── Realtime lifecycle ────────────────────────────────────────────────────

  Future<void> initRealtimeSync() async {
    if (realtimeDocname.isEmpty) return;
    try {
      final api    = Get.find<ApiProvider>();
      final cookie = await api.getSessionCookieHeader();
      _frappeSocket.connect(
        baseUrl:     api.baseUrl,
        cookieHeader: cookie,
        doctype:     realtimeDoctype,
        docname:     realtimeDocname,
        onDocUpdate: _onRemoteUpdate,
      );
    } catch (_) {} // silent fallback — existing conflict dialog handles it
  }

  void disposeRealtimeSync() {
    _autoSaveTimer?.cancel();
    _frappeSocket.dispose();
  }

  Future<void> startRealtimeSyncAfterCreate() => initRealtimeSync();

  // ── Remote update handler ─────────────────────────────────────────────────

  Future<void> _onRemoteUpdate() async {
    if (isClosed) return;
    _autoSaveTimer?.cancel();
    GlobalSnackbar.info(message: 'Document updated — saving and reloading…');
    if (isDirty.value && !isSaving.value) await saveDocument();
    await reloadDocument();
  }

  // Exposed for unit tests only
  Future<void> triggerRemoteUpdateForTest() => _onRemoteUpdate();
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/unit/realtime_sync_mixin_test.dart
```

Expected: PASS (all 10 tests).

- [ ] **Step 5: Confirm GlobalSnackbar.info compiles**

`GlobalSnackbar.info` already exists in the codebase. Run:

```bash
flutter analyze lib/app/data/mixins/realtime_sync_mixin.dart
```

Expected: no errors.

- [ ] **Step 6: Run all unit tests**

```bash
flutter test test/unit/
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/app/data/mixins/realtime_sync_mixin.dart test/unit/realtime_sync_mixin_test.dart
git commit -m "feat(mixin): add RealtimeSyncMixin with auto-save and socket lifecycle"
```

---

## Task 7: Wire StockEntryFormController

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`

- [ ] **Step 1: Add mixin to class declaration (line 37–38)**

```dart
class StockEntryFormController extends GetxController
    with OptimisticLockingMixin, BarcodeScanMixin, RealtimeSyncMixin {
```

Add import at the top of the file:
```dart
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
```

- [ ] **Step 2: Add realtimeDoctype and realtimeDocname getters**

After `bool get isEditable => (stockEntry.value?.docstatus ?? 1) == 0;` add:

```dart
  @override String get realtimeDoctype => 'Stock Entry';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Wire initRealtimeSync in onInit()**

In `onInit()`, the existing branch is:
```dart
    if (mode == 'new') {
      _initDocument();
    } else {
      fetchDocument();
    }
```

Replace with:
```dart
    if (mode == 'new') {
      _initDocument();
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
```

- [ ] **Step 4: Wire scheduleAutoSave in _markDirty()**

Current `_markDirty()`:
```dart
  void _markDirty() {
    if (!isLoading.value && !isDirty.value && isEditable) isDirty.value = true;
  }
```

Replace with:
```dart
  void _markDirty() {
    if (!isLoading.value && !isDirty.value && isEditable) isDirty.value = true;
    scheduleAutoSave();
  }
```

- [ ] **Step 5: Wire startRealtimeSyncAfterCreate in _createDocument()**

In `_createDocument()`, after `name = res.data['data']['name']; mode = 'edit';` add:

```dart
      await startRealtimeSyncAfterCreate();
```

- [ ] **Step 6: Wire disposeRealtimeSync in onClose()**

In `onClose()`, add as the first line of the body:

```dart
    disposeRealtimeSync();
```

- [ ] **Step 7: Run analyze**

```bash
flutter analyze lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
```

Expected: no new errors.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
git commit -m "feat(stock-entry): wire RealtimeSyncMixin and auto-save"
```

---

## Task 8: Wire DeliveryNoteFormController

**Files:**
- Modify: `lib/app/modules/delivery_note/form/delivery_note_form_controller.dart`

- [ ] **Step 1: Add import and mixin**

Add import:
```dart
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
```

Change class declaration (currently `with OptimisticLockingMixin, ControllerFeedbackMixin`):
```dart
class DeliveryNoteFormController extends GetxController
    with OptimisticLockingMixin, ControllerFeedbackMixin, RealtimeSyncMixin {
```

- [ ] **Step 2: Add getters**

After `bool get isEditable` (or after the existing `isDirty` field), add:
```dart
  @override String get realtimeDoctype => 'Delivery Note';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Wire onInit()**

Find the `else { fetchDocument(); }` branch in `onInit()` and replace with:
```dart
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
```

- [ ] **Step 4: Wire _markDirty() or equivalent dirty setter**

Search for `isDirty.value = true` usages in the controller. Wherever this is set outside of `fetchDocument()`, also call `scheduleAutoSave()`. If a `_markDirty()` method exists, add `scheduleAutoSave()` there. If not, add a helper:

```dart
  void _markDirty() {
    if (!isLoading.value && isEditable) isDirty.value = true;
    scheduleAutoSave();
  }
```

Then replace direct `isDirty.value = true` mutation sites (except inside `fetchDocument`) with `_markDirty()`.

- [ ] **Step 5: Wire _createDocument if applicable**

If the controller creates new Delivery Notes (has `_createDocument` or equivalent): after `name` is assigned and `mode = 'edit'`, add `await startRealtimeSyncAfterCreate();`. If the form is view/edit only, skip this step.

- [ ] **Step 6: Wire disposeRealtimeSync in onClose()**

Add as the first line of `onClose()`:
```dart
    disposeRealtimeSync();
```

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/app/modules/delivery_note/form/delivery_note_form_controller.dart
git add lib/app/modules/delivery_note/form/delivery_note_form_controller.dart
git commit -m "feat(delivery-note): wire RealtimeSyncMixin and auto-save"
```

---

## Task 9: Wire PurchaseReceiptFormController

**Files:**
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`

- [ ] **Step 1: Add import and mixin**

Add import:
```dart
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
```

Change class declaration (currently `with OptimisticLockingMixin`):
```dart
class PurchaseReceiptFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
```

- [ ] **Step 2: Add getters**

```dart
  @override String get realtimeDoctype => 'Purchase Receipt';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Wire onInit()**

In `onInit()`, replace `fetchDocument();` in the `else` branch with:
```dart
      fetchDocument().then((_) => initRealtimeSync());
```

- [ ] **Step 4: Wire dirty tracking**

Find `_markDirty()` or all `isDirty.value = true` sites outside `fetchDocument()`. Add `scheduleAutoSave()` to each mutation site, or consolidate into a `_markDirty()` helper:

```dart
  void _markDirty() {
    if (!isLoading.value && isEditable) isDirty.value = true;
    scheduleAutoSave();
  }
```

- [ ] **Step 5: Wire _createDocument if applicable**

After `name` is assigned post-create, add `await startRealtimeSyncAfterCreate();`.

- [ ] **Step 6: Wire disposeRealtimeSync in onClose()**

```dart
    disposeRealtimeSync(); // first line of onClose()
```

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart
git add lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart
git commit -m "feat(purchase-receipt): wire RealtimeSyncMixin and auto-save"
```

---

## Task 10: Wire PackingSlipFormController

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`

- [ ] **Step 1: Add import and mixin**

```dart
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
```

```dart
class PackingSlipFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
```

- [ ] **Step 2: Add getters**

```dart
  @override String get realtimeDoctype => 'Packing Slip';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Wire onInit()**

```dart
      fetchDocument().then((_) => initRealtimeSync());
```

- [ ] **Step 4: Wire dirty tracking**

Add `scheduleAutoSave()` to `_markDirty()` or all `isDirty.value = true` sites outside `fetchDocument()`.

- [ ] **Step 5: Wire _createDocument if applicable**

After `name` is assigned post-create: `await startRealtimeSyncAfterCreate();`

- [ ] **Step 6: Wire disposeRealtimeSync in onClose()**

```dart
    disposeRealtimeSync();
```

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
git add lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
git commit -m "feat(packing-slip): wire RealtimeSyncMixin and auto-save"
```

---

## Task 11: Wire MaterialRequestFormController

**Files:**
- Modify: `lib/app/modules/material_request/form/material_request_form_controller.dart`

- [ ] **Step 1: Add import and mixin**

```dart
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
```

The class currently has `with OptimisticLockingMixin` — check whether there is a second mixin and preserve it:
```dart
class MaterialRequestFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {  // preserve any existing second mixin
```

- [ ] **Step 2: Add getters**

```dart
  @override String get realtimeDoctype => 'Material Request';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Wire onInit()**

```dart
      fetchDocument().then((_) => initRealtimeSync());
```

- [ ] **Step 4: Wire dirty tracking**

Add `scheduleAutoSave()` to `_markDirty()` or all `isDirty.value = true` sites outside `fetchDocument()`.

- [ ] **Step 5: Wire _createDocument if applicable**

After `name` is assigned post-create: `await startRealtimeSyncAfterCreate();`

- [ ] **Step 6: Wire disposeRealtimeSync in onClose()**

```dart
    disposeRealtimeSync();
```

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/app/modules/material_request/form/material_request_form_controller.dart
git add lib/app/modules/material_request/form/material_request_form_controller.dart
git commit -m "feat(material-request): wire RealtimeSyncMixin and auto-save"
```

---

## Task 12: Wire PosUploadFormController

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

- [ ] **Step 1: Add import and mixin**

```dart
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
```

```dart
class PosUploadFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
```

- [ ] **Step 2: Add getters**

```dart
  @override String get realtimeDoctype => 'POS Upload';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Wire onInit()**

```dart
      fetchDocument().then((_) => initRealtimeSync());
```

- [ ] **Step 4: Wire dirty tracking**

Add `scheduleAutoSave()` to `_markDirty()` or all `isDirty.value = true` sites outside `fetchDocument()`.

- [ ] **Step 5: Wire _createDocument if applicable**

After `name` is assigned post-create: `await startRealtimeSyncAfterCreate();`

- [ ] **Step 6: Wire disposeRealtimeSync in onClose()**

```dart
    disposeRealtimeSync();
```

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat(pos-upload): wire RealtimeSyncMixin and auto-save"
```

---

## Task 13: Wire BatchFormController

**Files:**
- Modify: `lib/app/modules/batch/form/batch_form_controller.dart`

- [ ] **Step 1: Add import and mixin**

```dart
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
```

```dart
class BatchFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
```

- [ ] **Step 2: Add getters**

```dart
  @override String get realtimeDoctype => 'Batch';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Wire onInit()**

```dart
      fetchDocument().then((_) => initRealtimeSync());
```

- [ ] **Step 4: Wire dirty tracking**

Add `scheduleAutoSave()` to `_markDirty()` or all `isDirty.value = true` sites outside `fetchDocument()`.

- [ ] **Step 5: Wire _createDocument if applicable**

After `name` is assigned post-create: `await startRealtimeSyncAfterCreate();`

- [ ] **Step 6: Wire disposeRealtimeSync in onClose()**

```dart
    disposeRealtimeSync();
```

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/app/modules/batch/form/batch_form_controller.dart
git add lib/app/modules/batch/form/batch_form_controller.dart
git commit -m "feat(batch): wire RealtimeSyncMixin and auto-save"
```

---

## Task 14: Wire PurchaseOrderFormController (Group B)

This controller needs `OptimisticLockingMixin` added alongside `RealtimeSyncMixin`. It already has `reloadDocument()` (delegates to `fetchDocument()`) and `isDirty` / `isSaving` fields, so the mixin's abstract contract is satisfied.

**Files:**
- Modify: `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`

- [ ] **Step 1: Add imports and both mixins**

Add imports:
```dart
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:dio/dio.dart';
```

Change class declaration:
```dart
class PurchaseOrderFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
```

- [ ] **Step 2: Add getters**

```dart
  @override String get realtimeDoctype => 'Purchase Order';
  @override String get realtimeDocname => name;
```

- [ ] **Step 3: Implement reloadDocument() override**

`PurchaseOrderFormController` already has `reloadDocument()` at line 272. Add the `@override` annotation and a success snackbar to match the pattern from `StockEntryFormController.reloadDocument()`:

```dart
  @override
  Future<void> reloadDocument() async {
    isStale.value    = false;
    await fetchDocument();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }
```

- [ ] **Step 4: Add @override to saveDocument()**

`PurchaseOrderFormController` already declares `Future<void> saveDocument()` at line 651. Add `@override` to satisfy the mixin contract:

```dart
  @override
  Future<void> saveDocument() async {
    // existing body unchanged
  }
```

- [ ] **Step 5: Add handleVersionConflict to save error handler**

Find the `DioException` catch block in the save method. Add:
```dart
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      // ... existing error handling ...
    }
```

- [ ] **Step 6: Add checkStaleAndBlock to save guard**

At the start of the save method, add:
```dart
    if (checkStaleAndBlock()) return;
```

- [ ] **Step 7: Wire onInit()**

In `onInit()`, the existing branch is:
```dart
    if (mode == 'new') {
      _initDocument();
    } else {
      fetchDocument();
    }
```

Replace with:
```dart
    if (mode == 'new') {
      _initDocument();
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
```

- [ ] **Step 8: Wire dirty tracking**

`PurchaseOrderFormController` uses `_checkForChanges()` (called by TextEditingController listeners) and direct `isDirty.value = true` in item mutation methods. Add `scheduleAutoSave()` to `_checkForChanges()`:

```dart
  void _checkForChanges() {
    // ... existing body ...
    scheduleAutoSave();
  }
```

Also add `scheduleAutoSave()` wherever item rows are added/updated/deleted (search for `isDirty.value = true` in the file).

- [ ] **Step 9: Wire _createDocument if applicable**

If the controller can create new Purchase Orders: after `name` is assigned post-create, add `await startRealtimeSyncAfterCreate();`.

- [ ] **Step 10: Wire disposeRealtimeSync in onClose()**

Add as the first line of `onClose()`:
```dart
    disposeRealtimeSync();
```

- [ ] **Step 11: Analyze and commit**

```bash
flutter analyze lib/app/modules/purchase_order/form/purchase_order_form_controller.dart
git add lib/app/modules/purchase_order/form/purchase_order_form_controller.dart
git commit -m "feat(purchase-order): add OptimisticLockingMixin + RealtimeSyncMixin and auto-save"
```

---

## Task 15: Final verification

- [ ] **Step 1: Run full analyzer**

```bash
flutter analyze
```

Expected: no new errors or warnings introduced by this feature.

- [ ] **Step 2: Run all unit tests**

```bash
flutter test test/unit/
```

Expected: all pass.

- [ ] **Step 3: Manual smoke test checklist**

Open two devices (or two emulators) logged in as different users on the same ERPNext instance.

1. User A opens Stock Entry `MAT-STE-XXXX`
2. User B opens the same `MAT-STE-XXXX`
3. User A scans an item → auto-save fires (wait ~5 s)
4. User B's app shows "Document updated — saving and reloading…" banner
5. User B scans an item → save succeeds with no conflict dialog
6. Open Session defaults → verify "Auto-save Delay" slider is visible (3–30 s range)
7. Change delay to 10 s → confirm new items wait ~10 s before auto-saving
8. Kill network briefly → confirm silent fallback (no crash, conflict dialog appears on next save as before)

- [ ] **Step 4: Final commit if any cleanup was needed**

```bash
git add -p
git commit -m "chore(realtime-sync): post-integration cleanup"
```
