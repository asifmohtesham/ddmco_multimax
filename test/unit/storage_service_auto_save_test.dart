import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

// Mock for GetStorage to avoid requiring native platform channels
class _FakeGetStorage {
  final Map<String, dynamic> _data = {};

  Future<void> write(String key, dynamic value) async {
    _data[key] = value;
  }

  Future<void> remove(String key) async {
    _data.remove(key);
  }

  T? read<T>(String key) {
    return _data[key] as T?;
  }

  bool hasData(String key) {
    return _data.containsKey(key);
  }

  Future<void> erase() async {
    _data.clear();
  }
}

void main() {
  group('StorageService auto-save delay', () {
    late StorageService service;
    late _FakeGetStorage fakeStorage;

    setUp(() {
      fakeStorage = _FakeGetStorage();
      // Create a StorageService that uses our fake storage
      // Need to cast to GetStorage interface
      service = StorageService.withStorage(fakeStorage as dynamic);
    });

    test('getAutoSaveDelay returns default 5 when not set', () {
      fakeStorage.erase();
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
