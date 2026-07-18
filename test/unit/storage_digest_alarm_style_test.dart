import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class _FakeGetStorage {
  final Map<String, dynamic> _data = {};
  Future<void> write(String key, dynamic value) async => _data[key] = value;
  Future<void> remove(String key) async => _data.remove(key);
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

  test('defaults to standard', () {
    expect(service.getDigestAlarmStyle(user), 'standard');
  });

  test('round-trips per user', () async {
    await service.saveDigestAlarmStyle(user, 'alarm');
    expect(service.getDigestAlarmStyle(user), 'alarm');
    expect(service.getDigestAlarmStyle('other@x.com'), 'standard');
    expect(box.raw.containsKey('notif_digest_alarm_style::$user'), isTrue);
  });
}
