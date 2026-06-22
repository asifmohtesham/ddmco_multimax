import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';

/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}

void main() {
  tearDown(Get.reset);

  test('persist writes all settings; returns false when no company', () async {
    final storage = StorageService.withStorage(_FakeBox());
    final c = SessionDefaultsController(storage: storage);

    // No company selected yet → refuses to persist.
    expect(await c.persist(), isFalse);

    c.selectedCompany.value = 'Multimax LLC';
    c.autoSubmitEnabled.value = false;
    c.autoSubmitDelay.value = 4;
    c.autoSaveDelay.value = 12;

    expect(await c.persist(), isTrue);
    expect(storage.getCompany(), 'Multimax LLC');
    expect(storage.getAutoSubmitEnabled(), isFalse);
    expect(storage.getAutoSubmitDelay(), 4);
    expect(storage.getAutoSaveDelay(), 12);
  });
}
