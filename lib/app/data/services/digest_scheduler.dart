/// Digest schedule computation + WorkManager arming.
///
/// GetX-free by design — also used from the background isolate.
library;

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

/// Arms exactly one pending WorkManager task at the next schedule occurrence.
/// Cancel-then-replace semantics come from ExistingWorkPolicy.replace plus
/// the fixed unique name. Reads prefs only — never writes storage, so it is
/// safe to call from the background isolate (see digest_worker.dart).
class DigestScheduler {
  final StorageService _storage;
  final WorkScheduler _work;
  final DateTime Function() _now;

  DigestScheduler({
    StorageService? storage,
    WorkScheduler? work,
    DateTime Function()? now,
  })  : _storage = storage ?? StorageService(),
        _work = work ?? WorkmanagerScheduler(),
        _now = now ?? DateTime.now;

  Future<void> rearm() async {
    final user = _storage.getUser();
    if (user == null || !_storage.getDigestEnabled(user.id)) {
      await _work.cancel(kDigestUniqueName);
      return;
    }
    // Enabled with no doctypes selected would otherwise still wake the app
    // every tick to run a no-op auth-probe and re-arm — same dead-schedule
    // treatment as empty times/days.
    if (_storage.getDigestDoctypes(user.id).isEmpty) {
      await _work.cancel(kDigestUniqueName);
      return;
    }
    final now = _now();
    final next = nextDigestOccurrence(
      after: now,
      times: _storage.getDigestTimes(user.id),
      weekdays: _storage.getDigestDays(user.id).toSet(),
    );
    if (next == null) {
      await _work.cancel(kDigestUniqueName);
      return;
    }
    await _work.registerOneOff(
      uniqueName: kDigestUniqueName,
      taskName: kDigestTaskName,
      initialDelay: next.difference(now),
    );
  }
}
