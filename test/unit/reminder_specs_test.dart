import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/reminder_scheduler.dart';

void main() {
  group('buildReminderSpecs', () {
    test('one spec per weekday x time, sorted, correct ids', () {
      final specs = buildReminderSpecs(
          times: ['16:00', '09:00'], weekdays: {3, 1});
      // weekdays sorted [1,3]; times sorted [09:00(idx0), 16:00(idx1)].
      expect(specs.map((s) => (s.weekday, s.hour, s.minute)).toList(), [
        (1, 9, 0),
        (1, 16, 0),
        (3, 9, 0),
        (3, 16, 0),
      ]);
      // id = base + (weekday-1)*8 + timeIndex
      expect(specs.map((s) => s.id).toList(), [
        kIosReminderIdBase + 0 * 8 + 0,
        kIosReminderIdBase + 0 * 8 + 1,
        kIosReminderIdBase + 2 * 8 + 0,
        kIosReminderIdBase + 2 * 8 + 1,
      ]);
      // ids are unique
      expect(specs.map((s) => s.id).toSet().length, specs.length);
    });

    test('invalid time strings are skipped', () {
      final specs =
          buildReminderSpecs(times: ['9am', '09:00'], weekdays: {1});
      expect(specs.length, 1);
      expect(specs.single.hour, 9);
    });

    test('empty times or weekdays -> empty', () {
      expect(buildReminderSpecs(times: [], weekdays: {1}), isEmpty);
      expect(buildReminderSpecs(times: ['09:00'], weekdays: {}), isEmpty);
    });

    test('out-of-range weekdays skipped', () {
      final specs = buildReminderSpecs(times: ['09:00'], weekdays: {0, 8, 5});
      expect(specs.map((s) => s.weekday).toList(), [5]);
    });
  });

  group('reservedIosReminderIds', () {
    test('covers every possible spec id and is distinct from 1001', () {
      final ids = reservedIosReminderIds();
      expect(ids, contains(kIosReminderIdBase));
      expect(ids.contains(1001), isFalse);
      // every buildable id is inside the reserved set
      final built = buildReminderSpecs(
              times: ['00:00', '06:00', '12:00', '18:00'],
              weekdays: {1, 2, 3, 4, 5, 6, 7})
          .map((s) => s.id);
      expect(built.every(ids.contains), isTrue);
    });
  });
}
