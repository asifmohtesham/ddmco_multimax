import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/frappe_socket.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

mixin RealtimeSyncMixin on GetxController {
  late final FrappeSocket _frappeSocket = createFrappeSocket();
  Timer? _autoSaveTimer;
  // Tracks whether the socket has ever successfully connected during this
  // controller lifetime, so we can distinguish initial connect from reconnect.
  bool _realtimeEverConnected = false;

  final isRealtimeConnected = false.obs;
  final isRemoteSyncing     = false.obs;

  FrappeSocket createFrappeSocket() => FrappeSocket();

  String get realtimeDoctype;
  String get realtimeDocname;
  RxBool get isDirty;
  RxBool get isSaving;
  Future<void> saveDocument();
  Future<void> reloadDocument();

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

  void scheduleAutoSaveForTest(Duration duration) =>
      _scheduleAutoSaveWithDuration(duration);

  Future<void> initRealtimeSync() async {
    if (realtimeDocname.isEmpty) return;
    try {
      final api    = Get.find<ApiProvider>();
      final cookie = await api.getSessionCookieHeader();
      _frappeSocket.connect(
        baseUrl:        api.baseUrl,
        cookieHeader:   cookie,
        doctype:        realtimeDoctype,
        docname:        realtimeDocname,
        onDocUpdate:    _onRemoteUpdate,
        onConnected: () {
          // On reconnect after a disconnect, reload immediately to pick up any
          // updates that arrived while the socket was offline — socket.io does
          // not queue missed events, so we must poll once on re-connect.
          final isReconnect = _realtimeEverConnected;
          _realtimeEverConnected = true;
          isRealtimeConnected.value = true;
          if (isReconnect) _onRemoteUpdate();
        },
        onDisconnected: () => isRealtimeConnected.value = false,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[RealtimeSync] initRealtimeSync error: $e\n$st');
    }
  }

  void disposeRealtimeSync() {
    _autoSaveTimer?.cancel();
    _frappeSocket.dispose();
    isRealtimeConnected.value = false;
    isRemoteSyncing.value     = false;
  }

  Future<void> startRealtimeSyncAfterCreate() => initRealtimeSync();

  Future<void> _onRemoteUpdate() async {
    if (isClosed) return;
    _autoSaveTimer?.cancel();
    isRemoteSyncing.value = true;
    try {
      GlobalSnackbar.info(message: 'Document updated — saving and reloading…');
    } catch (_) {}
    if (isDirty.value && !isSaving.value) await saveDocument();
    await reloadDocument();
    isRemoteSyncing.value = false;
  }

  Future<void> triggerRemoteUpdateForTest() => _onRemoteUpdate();

  Future<void> triggerConnectedForTest() async {
    final isReconnect = _realtimeEverConnected;
    _realtimeEverConnected = true;
    isRealtimeConnected.value = true;
    if (isReconnect) await _onRemoteUpdate();
  }
}
