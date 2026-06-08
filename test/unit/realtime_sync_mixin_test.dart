import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/mixins/realtime_sync_mixin.dart';
import 'package:multimax/app/data/services/frappe_socket.dart';

class _TestController extends GetxController with RealtimeSyncMixin {
  @override String get realtimeDoctype => 'Stock Entry';
  @override String get realtimeDocname => 'MAT-STE-001';

  @override final isDirty  = false.obs;
  @override final isSaving = false.obs;

  int saveCallCount   = 0;
  int reloadCallCount = 0;

  @override Future<void> saveDocument() async => saveCallCount++;
  @override Future<void> reloadDocument() async => reloadCallCount++;

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

      expect(ctrl.saveCallCount, 1);
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

      ctrl.scheduleAutoSaveForTest(const Duration(milliseconds: 50));
      await ctrl.triggerRemoteUpdateForTest();
      await Future.delayed(const Duration(milliseconds: 100));

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
