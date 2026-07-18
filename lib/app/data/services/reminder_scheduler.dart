/// iOS scheduled digest reminders — pure spec computation plus a plugin seam.
///
/// GetX-free. The spec computation is pure (no plugin, no timezone) so it is
/// unit-tested; the actual zonedSchedule calls live in [FlnReminderScheduler].
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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

/// Seam over flutter_local_notifications so DigestScheduler stays testable.
abstract class ReminderScheduler {
  /// Cancel any prior reminders and (re)schedule the given weekly set.
  Future<void> reschedule(List<ReminderSpec> specs,
      {required bool timeSensitive});

  /// Cancel the whole reserved reminder range.
  Future<void> cancelAll();
}

class FlnReminderScheduler implements ReminderScheduler {
  static const String _title = 'Pending documents';
  static const String _body = 'You have documents to review — open Multimax';

  Future<FlutterLocalNotificationsPlugin> _plugin() async {
    final fln = FlutterLocalNotificationsPlugin();
    await fln.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    return fln;
  }

  @override
  Future<void> reschedule(List<ReminderSpec> specs,
      {required bool timeSensitive}) async {
    final fln = await _plugin();
    for (final id in reservedIosReminderIds()) {
      await fln.cancel(id: id);
    }
    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: timeSensitive
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );
    for (final s in specs) {
      await fln.zonedSchedule(
        id: s.id,
        title: _title,
        body: _body,
        scheduledDate: _nextInstanceOf(s.weekday, s.hour, s.minute),
        notificationDetails: details,
        // Required by the signature; irrelevant on iOS (this path is iOS-only).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    final fln = await _plugin();
    for (final id in reservedIosReminderIds()) {
      await fln.cancel(id: id);
    }
  }

  tz.TZDateTime _nextInstanceOf(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

/// Logout teardown for iOS: cancel every scheduled digest reminder. Best-effort.
Future<void> cancelIosDigestReminders() async {
  try {
    final fln = FlutterLocalNotificationsPlugin();
    await fln.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    for (final id in reservedIosReminderIds()) {
      await fln.cancel(id: id);
    }
  } catch (_) {
    // Never block logout on notification plumbing.
  }
}
