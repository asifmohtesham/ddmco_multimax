/// Arms the attendance notification chain: its own WorkManager one-off work,
/// separate from the digest's. GetX-free — also called from the worker.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart' show WorkScheduler, WorkmanagerScheduler;
import 'package:multimax/app/data/services/storage_service.dart';

const String kAttendanceTaskName = 'attendanceTask';
const String kAttendanceUniqueName = 'attendance-notification';

class AttendanceNotifyScheduler {
  final StorageService _storage;
  final WorkScheduler _work;
  final DateTime Function() _now;
  final bool _isAndroid;

  AttendanceNotifyScheduler({
    StorageService? storage,
    WorkScheduler? work,
    DateTime Function()? now,
    bool? isAndroid,
  })  : _storage = storage ?? StorageService(),
        _work = work ?? WorkmanagerScheduler(),
        _now = now ?? DateTime.now,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// True when [user] gets attendance reminders (a linked employee with them
  /// on) or terminal alerts (a System Manager with them on).
  bool wants(User? user) {
    if (user == null) return false;
    final reminders = (user.employeeId ?? '').trim().isNotEmpty &&
        _storage.getAttendanceRemindersEnabled(user.id);
    final terminal =
        user.hasRole('System Manager') && _storage.getAttendanceTerminalAlerts(user.id);
    return reminders || terminal;
  }

  /// App start / login / settings change: the main isolate doesn't know the
  /// day's shifts, so it schedules a planning run that works them out.
  Future<void> rearm() async {
    if (!_isAndroid) return;
    if (!wants(_storage.getUser())) {
      await _work.cancel(kAttendanceUniqueName);
      return;
    }
    await _work.registerOneOff(
      uniqueName: kAttendanceUniqueName,
      taskName: kAttendanceTaskName,
      initialDelay: const Duration(minutes: 1),
    );
  }

  /// Called by the worker with the next moment from the timeline.
  Future<void> scheduleNext(DateTime wake) async {
    if (!_isAndroid) return;
    final delay = wake.difference(_now());
    await _work.registerOneOff(
      uniqueName: kAttendanceUniqueName,
      taskName: kAttendanceTaskName,
      initialDelay: delay.isNegative ? Duration.zero : delay,
    );
  }

  Future<void> cancel() => _work.cancel(kAttendanceUniqueName);
}
