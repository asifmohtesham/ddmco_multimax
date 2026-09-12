/// One attendance notification run, in the WorkManager background isolate:
/// fetch → decide (pure) → post → save worker state → schedule the next
/// moment. No GetX. The main GetStorage box is read-only here; worker state
/// lives in the separate [kAttendanceStateBox] container.
library;

import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/attendance_notify_rules.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
import 'package:multimax/app/data/services/attendance_notify_service.dart';
import 'package:multimax/app/data/services/attendance_notify_state.dart';
import 'package:multimax/app/data/services/attendance_timeline.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

const String kAttendanceReminderChannelId = 'attendance_reminders';
const String kAttendanceTerminalChannelId = 'attendance_terminal';
const String _kReminderChannelName = 'Attendance reminders';
const String _kTerminalChannelName = 'Attendance terminal';

/// A failed fetch is retried soon rather than waiting for the next moment.
const Duration kAttendanceRetry = Duration(minutes: 15);

Future<void> runAttendanceTask() async {
  await GetStorage.init();
  await GetStorage.init(kAttendanceStateBox);
  final storage = StorageService();
  final scheduler = AttendanceNotifyScheduler(storage: storage);
  final user = storage.getUser();
  if (user == null) return; // logged out since scheduling

  final employee = (user.employeeId ?? '').trim();
  final reminders = employee.isNotEmpty && storage.getAttendanceRemindersEnabled(user.id);
  final terminal =
      user.hasRole('System Manager') && storage.getAttendanceTerminalAlerts(user.id);
  if (!reminders && !terminal) {
    await scheduler.cancel(); // switched off or role revoked since scheduling
    return;
  }

  final now = DateTime.now();
  final today = dateOnly(now);
  final todayKey = kFrappeDate.format(today);
  final box = GetStorage(kAttendanceStateBox);
  var state =
      AttendanceNotifyState.fromMap(box.read(kAttendanceStateKey), user: user.id, today: todayKey);
  var wake = planningRunAfter(now);

  try {
    final supportDir = await getApplicationSupportDirectory();
    final service = AttendanceNotifyService(
      baseUrl: storage.getBaseUrl() ?? ApiProvider.defaultBaseUrl,
      cookieDir: '${supportDir.path}/.cookies/',
    );
    final data = await service.fetch(employee: reminders ? employee : '', day: today);
    final post = <NotifyMessage>[];
    final cancel = <int>[];

    if (data == null) {
      wake = now.add(kAttendanceRetry); // transient failure: try again soon
    } else if (data.authExpired) {
      if (state.lastAuthNotice != todayKey) {
        post.add(kSessionExpiredMessage);
        state = state.copyWith(lastAuthNotice: todayKey);
      }
    } else {
      final workingDay = !data.holiday;
      final canRemind = reminders && data.tracked;
      var moments = const <ShiftMoment>[];
      var heldBack = false;

      if (canRemind) {
        final shifts = reminderShifts(
          employee: employee,
          day: today,
          assignments: data.assignments,
          ledger: data.ledgerOn(today),
          catalog: data.catalog,
        );
        final out = decideReminders(
          now: now,
          facts: EmployeeDayFacts(
            shifts: shifts,
            punches: data.punches,
            ledger: data.ledgerOn(today),
            holiday: data.holiday,
            onLeave: data.onLeave,
            syncing: isSyncing(data.sync, now),
            syncedUpTo: data.sync?.agentLastRun,
          ),
          handled: state.handled,
          posted: state.posted,
        );
        post.addAll(out.post);
        cancel.addAll(out.cancel);
        state = state.copyWith(handled: out.handled, posted: out.posted);
        moments = shiftMoments(shifts, today);
        heldBack = out.heldBack;

        if (workingDay &&
            !now.isBefore(recapTimeOn(today)) &&
            state.recapRunDay != todayKey) {
          final recap = decideRecap(
            now: now,
            rows: data.ledger,
            catalog: data.catalog,
            lastRecapped: state.lastRecapped,
          );
          if (recap.message != null) post.add(recap.message!);
          state = state.copyWith(recapRunDay: todayKey, lastRecapped: recap.recapped);
        }
      }

      if (terminal && workingDay && inWatchHours(now)) {
        final t = decideTerminal(now: now, status: data.sync, wasQuiet: state.terminalQuiet);
        if (t.message != null) post.add(t.message!);
        state = state.copyWith(terminalQuiet: t.quiet);
      }

      wake = nextAttendanceWake(
        now: now,
        moments: moments,
        workingDay: workingDay,
        recap: canRemind && state.recapRunDay != todayKey,
        terminalWatch: terminal,
      );
      if (heldBack) {
        // A reminder was withheld waiting on the sync — retry soon rather
        // than sitting until the next scheduled moment.
        wake = wake.isAfter(now.add(kAttendanceRetry)) ? now.add(kAttendanceRetry) : wake;
      }
    }

    await showAttendanceNotifications(post: post, cancel: cancel);
    await box.write(kAttendanceStateKey, state.toMap());
  } finally {
    // Always chain the next run — one failure must never end the chain.
    await scheduler.scheduleNext(wake);
  }
}

/// Posts [post] and clears [cancel] on the two attendance channels.
Future<void> showAttendanceNotifications({
  required List<NotifyMessage> post,
  required List<int> cancel,
}) async {
  if (post.isEmpty && cancel.isEmpty) return;
  final fln = FlutterLocalNotificationsPlugin();
  await fln.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  final android =
      fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(AndroidNotificationChannel(
    kAttendanceReminderChannelId,
    _kReminderChannelName,
    description: 'Check-in and check-out reminders for your shifts',
    importance: Importance.high,
    enableVibration: true,
    vibrationPattern: Int64List.fromList(<int>[0, 400]),
  ));
  await android?.createNotificationChannel(const AndroidNotificationChannel(
    kAttendanceTerminalChannelId,
    _kTerminalChannelName,
    description: 'Alerts when the attendance terminal or its sync goes quiet',
    importance: Importance.high,
  ));

  for (final id in cancel) {
    await fln.cancel(id: id);
  }
  for (final m in post) {
    final channelId = m.terminal ? kAttendanceTerminalChannelId : kAttendanceReminderChannelId;
    final channelName = m.terminal ? _kTerminalChannelName : _kReminderChannelName;
    await fln.show(
      id: m.id,
      title: m.title,
      body: m.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(m.body),
        ),
      ),
    );
  }
}

/// Logout: drop pending work and clear posted attendance notifications so the
/// next user never sees the previous one's shifts.
Future<void> cancelAttendanceOnLogout() async {
  try {
    await Workmanager().cancelByUniqueName(kAttendanceUniqueName);
    final fln = FlutterLocalNotificationsPlugin();
    await fln.initialize(
        settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    for (final id in kAttendanceNotificationIds) {
      await fln.cancel(id: id);
    }
  } catch (_) {
    // Best-effort cleanup; never block logout on notification plumbing.
  }
}
