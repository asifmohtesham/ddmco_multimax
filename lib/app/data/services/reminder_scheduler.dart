/// iOS scheduled digest reminders — pure spec computation plus a plugin seam.
///
/// GetX-free. The spec computation is pure (no plugin, no timezone) so it is
/// unit-tested; the actual zonedSchedule calls live in [FlnReminderScheduler].
library;

/// First id of the reserved range for iOS digest reminders (distinct from the
/// Android digest notification id 1001).
const int kIosReminderIdBase = 2000;

/// 8 id slots per weekday leaves headroom above the 4-times cap while keeping
/// the whole reserved range (7 x 8 = 56 ids) well under iOS's 64-pending limit.
const int _slotsPerDay = 8;

/// One scheduled weekly reminder: fire on [weekday] (1=Mon..7=Sun) at
/// [hour]:[minute], under notification id [id].
class ReminderSpec {
  final int id;
  final int weekday;
  final int hour;
  final int minute;
  const ReminderSpec({
    required this.id,
    required this.weekday,
    required this.hour,
    required this.minute,
  });
}

/// Deterministic (weekday x time) reminder set. Times are parsed/validated and
/// sorted; invalid `HH:mm` strings and out-of-range weekdays are skipped.
List<ReminderSpec> buildReminderSpecs({
  required List<String> times,
  required Set<int> weekdays,
}) {
  final parsed = <(int, int)>[];
  for (final t in times) {
    final parts = t.split(':');
    if (parts.length != 2) continue;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) continue;
    parsed.add((h, m));
  }
  parsed.sort((a, b) => (a.$1 * 60 + a.$2).compareTo(b.$1 * 60 + b.$2));

  final days = weekdays.where((d) => d >= 1 && d <= 7).toList()..sort();

  final specs = <ReminderSpec>[];
  for (final wd in days) {
    for (var i = 0; i < parsed.length; i++) {
      specs.add(ReminderSpec(
        id: kIosReminderIdBase + (wd - 1) * _slotsPerDay + i,
        weekday: wd,
        hour: parsed[i].$1,
        minute: parsed[i].$2,
      ));
    }
  }
  return specs;
}

/// Every id the reminder set could ever occupy — cancel these to fully clear a
/// prior schedule before rescheduling (or on logout).
List<int> reservedIosReminderIds() =>
    [for (var i = 0; i < 7 * _slotsPerDay; i++) kIosReminderIdBase + i];
