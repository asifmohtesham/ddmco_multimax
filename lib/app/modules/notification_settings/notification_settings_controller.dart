import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/attendance_notify_scheduler.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';

/// Requests the platform notification permission. Kept as a free function so
/// the controller can take a test seam instead of touching the plugin.
Future<bool> requestNotificationsPermission() async {
  final plugin = FlutterLocalNotificationsPlugin();
  if (!kIsWeb && Platform.isIOS) {
    final ios = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
            alert: true, badge: true, sound: true) ??
        false;
  }
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? false;
}

/// Whether the OS currently lets the app post notifications (Android 13+
/// users can revoke it after the first prompt). Named apart from the
/// constructor's `notificationsAllowed` seam so neither shadows the other.
Future<bool> notificationsAllowedNow() async {
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.areNotificationsEnabled() ?? true;
}

/// Attendance reminders are on by default, so the Dashboard asks for
/// notification permission once per linked employee on Android.
bool shouldPromptAttendancePermission({
  required User? user,
  required bool isAndroid,
  required StorageService storage,
}) =>
    isAndroid &&
    user != null &&
    (user.employeeId ?? '').trim().isNotEmpty &&
    storage.getAttendanceRemindersEnabled(user.id) &&
    !storage.getAttendancePermissionPrompted(user.id);

class NotificationSettingsController extends GetxController {
  static const int maxTimes = 4;

  final StorageService _storage;
  final DigestScheduler _scheduler;
  final Future<bool> Function() _requestPermission;
  final AttendanceNotifyScheduler _attendanceScheduler;
  final Future<bool> Function() _notificationsAllowed;
  final bool _isAndroid;

  NotificationSettingsController({
    StorageService? storage,
    DigestScheduler? scheduler,
    AttendanceNotifyScheduler? attendanceScheduler,
    Future<bool> Function()? requestPermission,
    Future<bool> Function()? notificationsAllowed,
    bool? isAndroid,
  })  : _storage = storage ?? Get.find<StorageService>(),
        _scheduler = scheduler ?? DigestScheduler(),
        _attendanceScheduler = attendanceScheduler ?? AttendanceNotifyScheduler(),
        _requestPermission = requestPermission ?? requestNotificationsPermission,
        _notificationsAllowed = notificationsAllowed ?? notificationsAllowedNow,
        _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  final enabled = false.obs;
  final times = <String>[].obs;
  final days = <int>{}.obs;
  final doctypeKeys = <String>{}.obs;
  final alarmStyle = 'standard'.obs;

  final attendanceEnabled = true.obs;
  final terminalEnabled = true.obs;

  /// The OS switch is off: the sections explain it instead of silently never
  /// notifying.
  final notificationsBlocked = false.obs;

  String get _user => _storage.getUser()?.id ?? '';
  User? get _account => _storage.getUser();
  bool get showDigest => _account?.isManager ?? false;
  bool get showAttendance =>
      _isAndroid && (_account?.employeeId ?? '').trim().isNotEmpty;
  bool get showTerminal =>
      _isAndroid && (_account?.hasRole('System Manager') ?? false);

  @override
  void onInit() {
    super.onInit();
    enabled.value = _storage.getDigestEnabled(_user);
    times.assignAll(_storage.getDigestTimes(_user));
    days.assignAll(_storage.getDigestDays(_user));
    doctypeKeys.assignAll(_storage.getDigestDoctypes(_user));
    alarmStyle.value = _storage.getDigestAlarmStyle(_user);
    attendanceEnabled.value = _storage.getAttendanceRemindersEnabled(_user);
    terminalEnabled.value = _storage.getAttendanceTerminalAlerts(_user);
    if (showAttendance || showTerminal) unawaited(_refreshBlocked());
  }

  Future<void> _refreshBlocked() async {
    try {
      notificationsBlocked.value = !await _notificationsAllowed();
    } catch (_) {
      // Plugin unavailable (tests, desktop) — assume allowed.
    }
  }

  Future<void> setAttendanceEnabled(bool value) async {
    if (value) notificationsBlocked.value = !await _requestPermission();
    attendanceEnabled.value = value;
    await _storage.saveAttendanceRemindersEnabled(_user, value);
    await _attendanceScheduler.rearm();
  }

  Future<void> setTerminalEnabled(bool value) async {
    if (value) notificationsBlocked.value = !await _requestPermission();
    terminalEnabled.value = value;
    await _storage.saveAttendanceTerminalAlerts(_user, value);
    await _attendanceScheduler.rearm();
  }

  Future<void> setEnabled(bool value) async {
    if (value) {
      final granted = await _requestPermission();
      if (!granted) {
        enabled.value = false;
        AppNotification.warning(
            'Allow notifications for Multimax in system settings');
        return;
      }
    }
    enabled.value = value;
    await _storage.saveDigestEnabled(_user, value);
    await _scheduler.rearm();
  }

  Future<void> addTime(int hour, int minute) async {
    final t = '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
    if (times.contains(t)) return;
    if (times.length >= maxTimes) {
      AppNotification.warning('Up to $maxTimes times per day');
      return;
    }
    times
      ..add(t)
      ..sort();
    await _persistTimes();
  }

  Future<void> removeTime(String time) async {
    times.remove(time);
    await _persistTimes();
  }

  Future<void> toggleDay(int weekday) async {
    days.contains(weekday) ? days.remove(weekday) : days.add(weekday);
    await _storage.saveDigestDays(_user, days.toList()..sort());
    await _scheduler.rearm();
  }

  Future<void> toggleDoctype(String key) async {
    doctypeKeys.contains(key) ? doctypeKeys.remove(key) : doctypeKeys.add(key);
    // Persist in registry order so the digest body order never varies.
    final ordered = kDigestDoctypes
        .map((d) => d.key)
        .where(doctypeKeys.contains)
        .toList();
    await _storage.saveDigestDoctypes(_user, ordered);
    await _scheduler.rearm();
  }

  Future<void> _persistTimes() async {
    await _storage.saveDigestTimes(_user, times.toList());
    await _scheduler.rearm();
  }

  /// 'standard' | 'alarm'. Re-arms because on iOS the interruption level is
  /// baked into the scheduled reminders (Android reads it at post time, where
  /// a re-arm is a harmless no-op).
  Future<void> setAlarmStyle(String style) async {
    alarmStyle.value = style;
    await _storage.saveDigestAlarmStyle(_user, style);
    await _scheduler.rearm();
  }
}
