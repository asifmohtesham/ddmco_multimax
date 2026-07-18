import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
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

class NotificationSettingsController extends GetxController {
  static const int maxTimes = 4;

  final StorageService _storage;
  final DigestScheduler _scheduler;
  final Future<bool> Function() _requestPermission;

  NotificationSettingsController({
    StorageService? storage,
    DigestScheduler? scheduler,
    Future<bool> Function()? requestPermission,
  })  : _storage = storage ?? Get.find<StorageService>(),
        _scheduler = scheduler ?? DigestScheduler(),
        _requestPermission = requestPermission ?? requestNotificationsPermission;

  final enabled = false.obs;
  final times = <String>[].obs;
  final days = <int>{}.obs;
  final doctypeKeys = <String>{}.obs;
  final alarmStyle = 'standard'.obs;

  String get _user => _storage.getUser()?.id ?? '';

  @override
  void onInit() {
    super.onInit();
    enabled.value = _storage.getDigestEnabled(_user);
    times.assignAll(_storage.getDigestTimes(_user));
    days.assignAll(_storage.getDigestDays(_user));
    doctypeKeys.assignAll(_storage.getDigestDoctypes(_user));
    alarmStyle.value = _storage.getDigestAlarmStyle(_user);
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
