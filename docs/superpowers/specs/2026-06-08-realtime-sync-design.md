# Realtime Sync — Socket.IO Live Subscription + Auto-save

**Date:** 2026-06-08
**Status:** Approved for implementation

## Problem

When two users edit the same Stock Entry or Delivery Note concurrently, the second save is rejected by Frappe's optimistic lock (TimestampMismatchError). The user sees a "Reload document" dialog and loses their scan progress. This is an operational bottleneck on the fulfillment floor.

## Solution

Two complementary mechanisms:

1. **Socket.IO live subscription** — each form subscribes to its document room on the Frappe server. When another user saves, the app is notified instantly, shows a banner, and reloads the document before the next save — keeping the `modified` timestamp fresh.
2. **Auto-save debounce** — every change (item add, item update, header field change) schedules a debounced document save. Combined with proactive socket reloads, the conflict window shrinks to near-zero.

## Scope

8 form controllers across 8 DocTypes:

| Controller | DocType | Group |
|---|---|---|
| `StockEntryFormController` | Stock Entry | A |
| `DeliveryNoteFormController` | Delivery Note | A |
| `PurchaseReceiptFormController` | Purchase Receipt | A |
| `PackingSlipFormController` | Packing Slip | A |
| `MaterialRequestFormController` | Material Request | A |
| `PosUploadFormController` | POS Upload | A |
| `BatchFormController` | Batch | A |
| `PurchaseOrderFormController` | Purchase Order | B |

**Group A** — already have `OptimisticLockingMixin`; add `RealtimeSyncMixin` only.
**Group B** — need `OptimisticLockingMixin` added first, then `RealtimeSyncMixin`.

Excluded (assigned-single-user or master data): Work Order, Job Card, BOM, Item.

## Architecture

### New files

#### `lib/app/data/services/frappe_socket.dart`

Plain Dart class (no GetX). Wraps `socket_io_client`. Knows nothing about documents — only sockets. Connection is idempotent — calling `connect()` a second time is a no-op, preventing duplicate sockets during document reloads.

```dart
class FrappeSocket {
  IO.Socket? _socket;
  bool _connected = false;

  void connect({
    required String baseUrl,
    required String cookieHeader,
    required String doctype,
    required String docname,
    required void Function() onDocUpdate,
  }) {
    if (_connected) return; // idempotent — reloads do not re-subscribe
    _connected = true;
    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .setExtraHeaders({'Cookie': cookieHeader})
        .disableAutoConnect()
        .build(),
    );

    _socket!.onConnect((_) {
      _socket!.emit('doc_subscribe', [doctype, docname]);
    });

    _socket!.on('doc_update', (data) {
      if (data is Map &&
          data['doctype'] == doctype &&
          data['name'] == docname) {
        onDocUpdate();
      }
    });

    // Silent fallback — connection errors are swallowed
    _socket!.onConnectError((_) {});
    _socket!.onError((_) {});

    _socket!.connect();
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

- `disableAutoConnect()` — connection is explicit and controllable.
- `doc_update` filtered by both `doctype` and `name` — guards stale callbacks.
- `onConnectError` / `onError` swallowed — silent fallback requirement.
- `dispose()` emits `doc_unsubscribe` as server courtesy before disconnecting.

#### `lib/app/data/mixins/realtime_sync_mixin.dart`

Mixin on `GetxController`. Owns the `FrappeSocket` instance, the auto-save debounce timer, and the notify-then-merge flow.

```dart
mixin RealtimeSyncMixin on GetxController {
  final FrappeSocket _frappeSocket = FrappeSocket();
  Timer? _autoSaveTimer;

  // ── Abstract contract ─────────────────────────────────────────────────────

  String get realtimeDoctype;
  String get realtimeDocname;   // empty string → new document, skip subscribe
  RxBool get isDirty;
  RxBool get isSaving;
  Future<void> saveDocument();
  Future<void> reloadDocument(); // already declared by OptimisticLockingMixin

  // ── Auto-save ─────────────────────────────────────────────────────────────

  void scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    final delay = Get.find<StorageService>().getAutoSaveDelay();
    _autoSaveTimer = Timer(Duration(seconds: delay), () async {
      if (!isClosed && isDirty.value && !isSaving.value) {
        await saveDocument();
      }
    });
  }

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
    } catch (_) {} // silent fallback
  }

  void disposeRealtimeSync() {
    _autoSaveTimer?.cancel();
    _frappeSocket.dispose();
  }

  // Called after _createDocument() assigns a server name
  Future<void> startRealtimeSyncAfterCreate() => initRealtimeSync();

  // ── Remote update handler ─────────────────────────────────────────────────

  Future<void> _onRemoteUpdate() async {
    if (isClosed) return;
    _autoSaveTimer?.cancel();
    GlobalSnackbar.info(message: 'Document updated — saving and reloading…');
    if (isDirty.value && !isSaving.value) await saveDocument();
    await reloadDocument();
  }
}
```

Key behaviours:
- `_onRemoteUpdate` cancels the pending debounce and flushes any unsaved work before reloading. User's items are never lost.
- `isClosed` guard prevents callbacks firing after controller disposal.
- `reloadDocument()` is not re-declared — it is satisfied by `OptimisticLockingMixin` on all Group A controllers.

### Modified files

#### `pubspec.yaml`

Add dependency:
```yaml
socket_io_client: ^2.0.3
```

#### `lib/app/data/providers/api_provider.dart`

Add one method to expose the session cookie string for Socket.IO handshake auth:

```dart
Future<String> getSessionCookieHeader() async {
  if (!_dioInitialised) await _initDio();
  final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
  return cookies.map((c) => '${c.name}=${c.value}').join('; ');
}
```

#### `lib/app/data/services/storage_service.dart`

Add auto-save delay alongside the existing auto-submit keys:

```dart
static const String _autoSaveDelayKey = 'auto_save_delay';

Future<void> saveAutoSaveDelay(int seconds) async =>
    _box.write(_autoSaveDelayKey, seconds);

int getAutoSaveDelay() =>
    _box.read<int>(_autoSaveDelayKey) ?? 5; // default 5 s
```

#### `lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart`

Add auto-save delay slider to the "Automation" section (no toggle — always on):

```dart
// State field
double _autoSaveDelay = 5.0;

// In _loadData()
_autoSaveDelay = _storageService.getAutoSaveDelay().toDouble();

// In _saveDefaults()
await _storageService.saveAutoSaveDelay(_autoSaveDelay.toInt());

// In build() — after existing Auto-Submit block
const SizedBox(height: 16),
Text('Auto-save Delay: ${_autoSaveDelay.toInt()}s'),
Slider(
  value: _autoSaveDelay,
  min: 3, max: 30, divisions: 9,
  label: '${_autoSaveDelay.toInt()}s',
  onChanged: (val) => setState(() => _autoSaveDelay = val),
),
```

## Controller Wiring (all 8 controllers)

Every controller receives the same four changes. `PurchaseOrderFormController` (Group B) additionally gets `OptimisticLockingMixin`.

### Class declaration

```dart
// Group A (example: StockEntry)
class StockEntryFormController extends GetxController
    with OptimisticLockingMixin, BarcodeScanMixin, RealtimeSyncMixin {

// Group B (PurchaseOrder — adds OptimisticLockingMixin too)
class PurchaseOrderFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
```

### Getters

```dart
@override String get realtimeDoctype => 'Stock Entry'; // DocType name per controller
@override String get realtimeDocname => name;          // existing name field
```

### `onInit()` — subscribe once after initial load

`initRealtimeSync()` is called **once** from `onInit()` after the initial `fetchDocument()` completes — not inside `fetchDocument()` itself. This prevents duplicate socket connections on every reload. `FrappeSocket.connect()` is idempotent as a second safety net.

```dart
@override
void onInit() {
  super.onInit();
  // ... existing init ...
  if (mode == 'new') {
    _initDocument();
  } else {
    fetchDocument().then((_) => initRealtimeSync());
  }
}
```

### `_createDocument()` — subscribe after first save

```dart
// After name is assigned and mode = 'edit':
await startRealtimeSyncAfterCreate();
```

### `_markDirty()` — schedule auto-save on every change

```dart
void _markDirty() {
  if (!isLoading.value && !isDirty.value && isEditable) isDirty.value = true;
  scheduleAutoSave(); // ← only addition
}
```

Controllers without `_markDirty()` (e.g. Purchase Order) get an equivalent debounce call at each mutation point.

### `onClose()` — disconnect

```dart
@override
void onClose() {
  disposeRealtimeSync(); // ← added first
  // ... existing dispose body ...
}
```

### Group B — `reloadDocument()` implementation (Purchase Order only)

Since `PurchaseOrderFormController` does not currently have `OptimisticLockingMixin`, it gains:
- `reloadDocument()` — delegates to existing `fetchDocument()`
- `handleVersionConflict()` called in the save error handler
- `checkStaleAndBlock()` called at the start of save

## Error Handling

| Scenario | Behaviour |
|---|---|
| Socket.IO fails to connect | Silent fallback — existing conflict dialog handles conflicts as before |
| Save flush fails on remote update | `handleVersionConflict()` in `OptimisticLockingMixin` catches it; conflict dialog shown |
| `_onRemoteUpdate` fires after controller closed | `isClosed` guard returns early, no crash |
| Save in-flight when socket event fires | `isSaving.value` guard skips the flush save; reload proceeds with fresh timestamp |

## Frappe Socket.IO Protocol

- **Endpoint:** `wss://<baseUrl>` (same host as REST API, default namespace)
- **Auth:** `Cookie` header from `PersistCookieJar` (session `sid` cookie)
- **Subscribe:** emit `doc_subscribe` with `[doctype, docname]`
- **Event:** listen on `doc_update`; payload `{doctype, name, modified}`
- **Unsubscribe:** emit `doc_unsubscribe` on dispose

## Dependencies

- `socket_io_client: ^2.0.3` — Dart Socket.IO client

## Files Created

- `lib/app/data/services/frappe_socket.dart`
- `lib/app/data/mixins/realtime_sync_mixin.dart`

## Files Modified

- `pubspec.yaml`
- `lib/app/data/providers/api_provider.dart`
- `lib/app/data/services/storage_service.dart`
- `lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart`
- `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`
- `lib/app/modules/delivery_note/form/delivery_note_form_controller.dart`
- `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`
- `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`
- `lib/app/modules/material_request/form/material_request_form_controller.dart`
- `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`
- `lib/app/modules/batch/form/batch_form_controller.dart`
- `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`
