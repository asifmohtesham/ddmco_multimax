import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}

void main() {
  test('default warehouse round-trips and clears', () async {
    final s = StorageService.withStorage(_FakeBox());
    expect(s.getDefaultWarehouse(), isNull);

    await s.saveDefaultWarehouse('Stores - M');
    expect(s.getDefaultWarehouse(), 'Stores - M');

    // null clears the key back to unset
    await s.saveDefaultWarehouse(null);
    expect(s.getDefaultWarehouse(), isNull);

    // whitespace-only also clears
    await s.saveDefaultWarehouse('Stores - M');
    await s.saveDefaultWarehouse('   ');
    expect(s.getDefaultWarehouse(), isNull);
  });
}
