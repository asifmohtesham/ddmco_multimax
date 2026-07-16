import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

// Mirrors _FakeGetStorage in storage_service_auto_save_test.dart.
class _FakeGetStorage {
  final Map<String, dynamic> _data = {};
  Future<void> write(String key, dynamic value) async {
    _data[key] = value;
  }

  Future<void> remove(String key) async {
    _data.remove(key);
  }

  T? read<T>(String key) => _data[key] as T?;
  bool hasData(String key) => _data.containsKey(key);
  Map<String, dynamic> get raw => _data;
}

void main() {
  late StorageService service;
  late _FakeGetStorage box;
  const user = 'asif@example.com';

  setUp(() {
    box = _FakeGetStorage();
    service = StorageService.withStorage(box as dynamic);
  });

  group('digest enabled', () {
    test('defaults to false', () {
      expect(service.getDigestEnabled(user), isFalse);
    });
    test('round-trips per user', () async {
      await service.saveDigestEnabled(user, true);
      expect(service.getDigestEnabled(user), isTrue);
      expect(service.getDigestEnabled('other@example.com'), isFalse);
      expect(box.raw.containsKey('notif_digest_enabled::$user'), isTrue);
    });
  });

  group('digest times', () {
    test('defaults to 09:00', () {
      expect(service.getDigestTimes(user), ['09:00']);
    });
    test('round-trips and survives List<dynamic> storage', () async {
      await service.saveDigestTimes(user, ['08:30', '16:00']);
      // GetStorage returns List<dynamic> after a JSON round-trip.
      box.raw['notif_digest_times::$user'] =
          List<dynamic>.from(box.raw['notif_digest_times::$user'] as List);
      expect(service.getDigestTimes(user), ['08:30', '16:00']);
    });
  });

  group('digest days', () {
    test('defaults to all seven weekdays', () {
      expect(service.getDigestDays(user), [1, 2, 3, 4, 5, 6, 7]);
    });
    test('round-trips', () async {
      await service.saveDigestDays(user, [1, 2, 3]);
      expect(service.getDigestDays(user), [1, 2, 3]);
    });
  });

  group('digest doctypes', () {
    test('defaults to all five', () {
      expect(service.getDigestDoctypes(user), [
        'purchase_order',
        'purchase_receipt',
        'delivery_note',
        'stock_entry',
        'pos_upload',
      ]);
    });
    test('round-trips', () async {
      await service.saveDigestDoctypes(user, ['stock_entry']);
      expect(service.getDigestDoctypes(user), ['stock_entry']);
    });
  });
}
