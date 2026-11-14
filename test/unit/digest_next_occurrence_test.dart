import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';

void main() {
  // Wed 2026-07-15 10:00 local.
  final wed10 = DateTime(2026, 7, 15, 10, 0);

  test('same-day later time wins', () {
    expect(
      nextDigestOccurrence(
          after: wed10, times: ['09:00', '16:00'], weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 15, 16, 0),
    );
  });

  test('all of today consumed → earliest time tomorrow', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 15, 17, 0),
          times: ['09:00', '16:00'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 16, 9, 0),
    );
  });

  test('exact-boundary time is skipped (strictly after)', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 15, 9, 0),
          times: ['09:00'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 16, 9, 0),
    );
  });

  test('skips disabled weekdays', () {
    // Wed(3) 10:00; only Mon(1) enabled → next Monday 2026-07-20.
    expect(
      nextDigestOccurrence(after: wed10, times: ['09:00'], weekdays: {1}),
      DateTime(2026, 7, 20, 9, 0),
    );
  });

  test('unsorted times are handled', () {
    expect(
      nextDigestOccurrence(
          after: wed10,
          times: ['16:00', '11:30'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 7, 15, 11, 30),
    );
  });

  test('same weekday next week when today is the only enabled day', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 15, 17, 0), times: ['09:00'], weekdays: {3}),
      DateTime(2026, 7, 22, 9, 0),
    );
  });

  test('month rollover via day arithmetic', () {
    expect(
      nextDigestOccurrence(
          after: DateTime(2026, 7, 31, 12, 0),
          times: ['09:00'],
          weekdays: {1, 2, 3, 4, 5, 6, 7}),
      DateTime(2026, 8, 1, 9, 0),
    );
  });

  test('empty times or weekdays → null', () {
    expect(
        nextDigestOccurrence(
            after: wed10, times: [], weekdays: {1, 2, 3, 4, 5, 6, 7}),
        isNull);
    expect(nextDigestOccurrence(after: wed10, times: ['09:00'], weekdays: {}),
        isNull);
  });

  test('malformed time string → null', () {
    expect(
        nextDigestOccurrence(
            after: wed10, times: ['9am'], weekdays: {1, 2, 3, 4, 5, 6, 7}),
        isNull);
  });
}
