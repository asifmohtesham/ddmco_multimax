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
    if (kDebugMode) debugPrint('[RealtimeSync] initRealtimeSync — docname="${realtimeDocname}"');
    if (realtimeDocname.isEmpty) return;
    try {
      final api    = Get.find<ApiProvider>();
      if (kDebugMode) debugPrint('[RealtimeSync] baseUrl="${api.baseUrl}" dioInit=${api.isDioInitialised}');
      final cookie = await api.getSessionCookieHeader();
      if (kDebugMode) debugPrint('[RealtimeSync] cookie="${cookie.isEmpty ? "<empty>" : "<present>"}"');
      _frappeSocket.connect(
        baseUrl:      api.baseUrl,
        cookieHeader: cookie,
        doctype:      realtimeDoctype,
        docname:      realtimeDocname,
        onDocUpdate:  _onRemoteUpdate,
        onConnected:  () => isRealtimeConnected.value = true,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[RealtimeSync] initRealtimeSync ERROR: $e\n$st');
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
}
