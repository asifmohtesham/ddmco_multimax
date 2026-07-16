/// Digest schedule computation + WorkManager arming.
///
/// GetX-free by design — also used from the background isolate.
library;

/// Earliest local instant strictly after [after] matching an enabled weekday
/// (`DateTime.monday == 1` … `DateTime.sunday == 7`) and an `HH:mm` entry of
/// [times]. Null when the schedule can never fire. Day stepping uses
/// component arithmetic (`DateTime(y, m, d + n)`), which Dart normalises
/// across month ends and DST shifts.
DateTime? nextDigestOccurrence({
  required DateTime after,
  required List<String> times,
  required Set<int> weekdays,
}) {
  if (times.isEmpty || weekdays.isEmpty) return null;

  final minutes = <(int, int)>[];
  for (final t in times) {
    final parts = t.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    minutes.add((h, m));
  }
  minutes.sort((a, b) => (a.$1 * 60 + a.$2).compareTo(b.$1 * 60 + b.$2));

  for (var day = 0; day <= 7; day++) {
    final date = DateTime(after.year, after.month, after.day + day);
    if (!weekdays.contains(date.weekday)) continue;
    for (final (h, m) in minutes) {
      final candidate = DateTime(date.year, date.month, date.day, h, m);
      if (candidate.isAfter(after)) return candidate;
    }
  }
  return null;
}
