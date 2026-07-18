/// WorkManager background entry point for the scheduled digest.
///
/// Runs in a fresh background isolate with NO GetX bindings — everything here
/// is constructed directly. GetStorage is initialised read-only; this isolate
/// must NEVER write GetStorage (whole-file last-writer-wins across isolates
/// would clobber main-isolate writes).
library;

import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

const int kDigestNotificationId = 1001;
// The released default-importance channel — deleted so it doesn't linger as a
// stale, silent entry once the two new channels exist.
const String _kOldChannelId = 'pending_documents';
const String kDigestAlarmChannelId = 'pending_documents_alarm';
const String kDigestAlertChannelId = 'pending_documents_alert';
const String _kAlarmChannelName = 'Pending documents (alarm)';
const String _kAlertChannelName = 'Pending documents';
const String _kChannelDescription =
    'Scheduled digest of documents needing action';

@pragma('vm:entry-point')
void digestCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await runDigestTask();
    } catch (_) {
      // A digest must never nag about its own failures, and returning false
      // would trigger WorkManager backoff retries — the next scheduled tick
      // is the retry.
    }
    return true;
  });
}

/// One digest tick: read prefs, count, notify, chain the next occurrence.
Future<void> runDigestTask() async {
  await GetStorage.init();
  final storage = StorageService();
  final user = storage.getUser();
  if (user == null) return; // logged out since scheduling — do nothing
  if (!user.isManager) return; // role revoked since scheduling
  if (!storage.getDigestEnabled(user.id)) return;

  final enabledKeys = storage.getDigestDoctypes(user.id).toSet();
  final doctypes =
      kDigestDoctypes.where((d) => enabledKeys.contains(d.key)).toList();

  final supportDir = await getApplicationSupportDirectory();
  final service = DigestService(
    baseUrl: storage.getBaseUrl() ?? ApiProvider.defaultBaseUrl,
    cookieDir: '${supportDir.path}/.cookies/',
  );

  // Re-arm must run even if the fetch/notify block throws — otherwise a
  // single non-Dio escape (cookie-jar IO, a PlatformException) would kill
  // the one-off WorkManager chain until the app is relaunched.
  try {
    final result = await service.fetchDigest(doctypes);
    final plan = DigestNotificationPlan.forResult(result);

    if (plan.show) {
      final isAlarm = storage.getDigestAlarmStyle(user.id) == 'alarm';
      final fln = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await fln.initialize(
          settings: const InitializationSettings(android: androidInit));
      final android = fln.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Retire the old default-importance channel and (idempotently) create the
      // two new ones. Channel sound/importance is immutable after creation, so
      // each alert style gets its own pre-configured channel.
      await android?.deleteNotificationChannel(channelId: _kOldChannelId);
      await android?.createNotificationChannel(AndroidNotificationChannel(
        kDigestAlarmChannelId,
        _kAlarmChannelName,
        description: _kChannelDescription,
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern:
            Int64List.fromList(<int>[0, 500, 250, 500, 250, 500]),
      ));
      await android?.createNotificationChannel(AndroidNotificationChannel(
        kDigestAlertChannelId,
        _kAlertChannelName,
        description: _kChannelDescription,
        importance: Importance.high,
        enableVibration: true,
        vibrationPattern: Int64List.fromList(<int>[0, 400]),
      ));

      final channelId = isAlarm ? kDigestAlarmChannelId : kDigestAlertChannelId;
      final channelName = isAlarm ? _kAlarmChannelName : _kAlertChannelName;
      await fln.show(
        id: kDigestNotificationId, // fixed id: new digest replaces the old one
        title: plan.title,
        body: plan.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: _kChannelDescription,
            importance: isAlarm ? Importance.max : Importance.high,
            priority: isAlarm ? Priority.max : Priority.high,
            category:
                isAlarm ? AndroidNotificationCategory.alarm : null,
            audioAttributesUsage: isAlarm
                ? AudioAttributesUsage.alarm
                : AudioAttributesUsage.notification,
            styleInformation: BigTextStyleInformation(plan.body ?? ''),
            // FLAG_INSISTENT (4): loops the sound until dismissed/opened.
            additionalFlags:
                isAlarm ? Int32List.fromList(<int>[4]) : null,
          ),
        ),
      );
    }
  } finally {
    // Chain the next occurrence. Reads prefs only — no storage writes.
    await DigestScheduler(storage: storage).rearm();
  }
}

/// Called from the main isolate on logout: drop pending work and clear any
/// posted digest so the next user doesn't see the previous user's counts.
Future<void> cancelDigestOnLogout() async {
  try {
    await Workmanager().cancelByUniqueName(kDigestUniqueName);
    final fln = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await fln.initialize(
        settings: const InitializationSettings(android: androidInit));
    await fln.cancel(id: kDigestNotificationId);
  } catch (_) {
    // Best-effort cleanup; never block logout on notification plumbing.
  }
}
