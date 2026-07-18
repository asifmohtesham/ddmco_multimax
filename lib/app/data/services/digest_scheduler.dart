/// Digest schedule computation + arming. Android arms a WorkManager one-off;
/// iOS schedules a weekly local-notification reminder set instead.
///
/// GetX-free by design — also used from the background isolate.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:multimax/app/data/services/reminder_scheduler.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:workmanager/workmanager.dart';

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

/// Task/work identity shared between scheduler, worker, and logout teardown.
const String kDigestTaskName = 'digestTask';
const String kDigestUniqueName = 'digest-notification';

/// Thin seam over Workmanager so DigestScheduler is unit-testable.
abstract class WorkScheduler {
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
  });

  Future<void> cancel(String uniqueName);
}

class WorkmanagerScheduler implements WorkScheduler {
  @override
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
  }) =>
      Workmanager().registerOneOffTask(
        uniqueName,
        taskName,
        initialDelay: initialDelay,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );

  @override
  Future<void> cancel(String uniqueName) =>
      Workmanager().cancelByUniqueName(uniqueName);
}

/// Manager-gated digest arming, branching by platform. On Android, arms
/// exactly one pending WorkManager task at the next schedule occurrence
/// (cancel-then-replace semantics come from ExistingWorkPolicy.replace plus
/// the fixed unique name). On iOS, (re)schedules the weekly reminder set via
/// [ReminderScheduler] instead (no WorkManager on iOS). Reads prefs only —
/// never writes storage, so it is safe to call from the background isolate
/// (see digest_worker.dart).
class DigestScheduler {
  final StorageService _storage;
  final WorkScheduler _work;
  final ReminderScheduler _reminders;
  final DateTime Function() _now;
  final bool _isIos;

  DigestScheduler({
    StorageService? storage,
    WorkScheduler? work,
    ReminderScheduler? reminders,
    DateTime Function()? now,
    bool? isIos,
  })  : _storage = storage ?? StorageService(),
        _work = work ?? WorkmanagerScheduler(),
        _reminders = reminders ?? FlnReminderScheduler(),
        _now = now ?? DateTime.now,
        _isIos = isIos ?? (!kIsWeb && Platform.isIOS);

  Future<void> rearm() async {
    final user = _storage.getUser();
    // Manager-only, enabled, and at least one doctype selected — otherwise the
    // schedule is dead and everything is cancelled.
    final live = user != null &&
        user.isManager &&
        _storage.getDigestEnabled(user.id) &&
        _storage.getDigestDoctypes(user.id).isNotEmpty;
    if (!live) {
      await _cancelAll();
      return;
    }

    final times = _storage.getDigestTimes(user.id);
    final weekdays = _storage.getDigestDays(user.id).toSet();

    if (_isIos) {
      final specs = buildReminderSpecs(times: times, weekdays: weekdays);
      if (specs.isEmpty) {
        await _cancelAll();
        return;
      }
      final timeSensitive = _storage.getDigestAlarmStyle(user.id) == 'alarm';
      await _reminders.reschedule(specs, timeSensitive: timeSensitive);
      return;
    }

    final now = _now();
    final next =
        nextDigestOccurrence(after: now, times: times, weekdays: weekdays);
    if (next == null) {
      await _cancelAll();
      return;
    }
    await _work.registerOneOff(
      uniqueName: kDigestUniqueName,
      taskName: kDigestTaskName,
      initialDelay: next.difference(now),
    );
  }

  Future<void> _cancelAll() async {
    if (_isIos) {
      await _reminders.cancelAll();
    } else {
      await _work.cancel(kDigestUniqueName);
    }
  }
}
