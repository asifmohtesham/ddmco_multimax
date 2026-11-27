/// Push notifications (Firebase Cloud Messaging) for POS Upload delivery
/// alerts. Android only for now — iOS needs its APNs setup first.
///
/// The app's only job is to keep ERP's "Mobile Push Device" register current
/// (via the mobile_push_register / mobile_push_unregister API methods) and to
/// open the right document when an alert is tapped. The sender is n8n.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart' show Response;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Android channel the sender targets (`android.notification.channel_id`) and
/// the manifest names as FCM's default.
const String kPushChannelId = 'pos_delivery';
const String _kPushChannelName = 'POS delivery';
const String _kPushChannelDescription =
    'POS Upload delivery updates: ready to dispatch, delivered, returned, overdue';

/// Roles that receive delivery alerts (see docs/erp/mobile-push/README.md).
const Set<String> kPushRoles = {'Delivery Dispatcher', 'Stock Manager'};

bool pushEligible(User? user) =>
    user != null && user.roles.any(kPushRoles.contains);

/// What a push carries for routing: the alert text and the document it is about.
class PushOpen {
  final String? title;
  final String? body;
  final String? doctype;
  final String? name;

  const PushOpen({this.title, this.body, this.doctype, this.name});

  factory PushOpen.fromMessage(RemoteMessage m) => PushOpen(
        title: m.notification?.title ?? m.data['title'] as String?,
        body: m.notification?.body ?? m.data['body'] as String?,
        doctype: m.data['doctype'] as String?,
        name: m.data['name'] as String?,
      );

  bool get opensPosUpload =>
      doctype == 'POS Upload' && (name ?? '').trim().isNotEmpty;
}

/// Seam over firebase_messaging so [PushService] is unit-testable.
abstract class PushMessaging {
  Future<void> init();
  Future<bool> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<PushOpen> get onForeground;
  Stream<PushOpen> get onOpened;
  Future<PushOpen?> initialOpen();
}

class FirebasePushMessaging implements PushMessaging {
  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  @override
  Future<void> init() async {
    await Firebase.initializeApp();
    // Background alerts are drawn by the OS on this channel, so it must exist
    // before the first one arrives.
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          kPushChannelId,
          _kPushChannelName,
          description: _kPushChannelDescription,
          importance: Importance.high,
        ));
  }

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  // getToken/onTokenRefresh still work in firebase_messaging 17; the new
  // register()/onRegistered pair is event-only and adds nothing here.
  @override
  // ignore: deprecated_member_use
  Future<String?> getToken() => _fm.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Stream<PushOpen> get onForeground =>
      FirebaseMessaging.onMessage.map(PushOpen.fromMessage);

  @override
  Stream<PushOpen> get onOpened =>
      FirebaseMessaging.onMessageOpenedApp.map(PushOpen.fromMessage);

  @override
  Future<PushOpen?> initialOpen() async {
    final m = await _fm.getInitialMessage();
    return m == null ? null : PushOpen.fromMessage(m);
  }
}

class PushService extends GetxService {
  PushService({
    PushMessaging? messaging,
    Future<void> Function(String method, Map<String, dynamic> params)? post,
    StorageService? storage,
    Future<Map<String, String>> Function()? appInfo,
    void Function(PushOpen open)? navigate,
    bool? supported,
  })  : _messaging = messaging ?? FirebasePushMessaging(),
        _post = post ?? _apiPost,
        _storageOverride = storage,
        _appInfo = appInfo ?? _packageInfo,
        _navigate = navigate ?? _openDocument,
        _supported = supported ?? (!kIsWeb && Platform.isAndroid);

  final PushMessaging _messaging;
  final Future<void> Function(String, Map<String, dynamic>) _post;
  final StorageService? _storageOverride;
  final Future<Map<String, String>> Function() _appInfo;
  final void Function(PushOpen) _navigate;
  bool _supported;

  final List<StreamSubscription> _subs = [];
  PushOpen? _pending;
  bool _homeReady = false;
  String? _token;

  StorageService get _storage => _storageOverride ?? Get.find<StorageService>();

  bool get supported => _supported;

  /// The token last sent to ERP, for tests and diagnostics.
  String? get registeredToken => _token;

  /// Starts Firebase. A failure (no google-services config, no Play
  /// services) turns push off for this run instead of blocking startup.
  Future<PushService> start() async {
    if (!_supported) return this;
    try {
      await _messaging.init();
    } catch (_) {
      _supported = false;
      return this;
    }
    _subs
      ..add(_messaging.onTokenRefresh.listen((t) => unawaited(_send(t))))
      ..add(_messaging.onForeground.listen(_showInApp))
      ..add(_messaging.onOpened.listen(_handleOpen));
    try {
      _pending = await _messaging.initialOpen();
    } catch (_) {}
    return this;
  }

  User? get _user => _storage.getUser();

  bool get _wanted =>
      _supported &&
      pushEligible(_user) &&
      _storage.getPushDeliveryAlerts(_user!.id);

  /// Registers this phone for the signed-in user when they should get alerts,
  /// and withdraws it when they shouldn't (role removed, switch turned off).
  /// Called after every sign-in and session restore. Never throws.
  Future<void> sync({bool askPermission = true}) async {
    if (!_supported || _user == null) return;
    try {
      if (!_wanted) {
        // Only phones that were registered need withdrawing; everyone else
        // must not cost a request per launch.
        if (_storage.getPushRegistered(_user!.id)) await unregister();
        return;
      }
      if (askPermission) await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) await _send(token);
    } catch (_) {
      // Best effort: the next launch tries again.
    }
  }

  Future<void> _send(String token) async {
    if (!_wanted) return;
    try {
      final info = await _appInfo();
      await _post('mobile_push_register', {
        'token': token,
        'platform': 'android',
        ...info,
      });
      _token = token;
      await _storage.savePushRegistered(_user!.id, true);
    } catch (_) {
      // 404 until the ERP site has the Mobile Push Device methods; offline;
      // session gone. All retried on the next sync.
    }
  }

  /// Stops this phone receiving the current user's alerts. Called before
  /// sign-out (while the session still exists) and when the switch goes off.
  Future<void> unregister() async {
    if (!_supported) return;
    try {
      final token = _token ?? await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _post('mobile_push_unregister', {'token': token})
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Sign-out must never wait on this; n8n also drops unknown users.
    } finally {
      _token = null;
      final user = _user;
      if (user != null) await _storage.savePushRegistered(user.id, false);
    }
  }

  /// Home is on screen: open any document whose alert launched the app.
  void homeReady() {
    _homeReady = true;
    final p = _pending;
    _pending = null;
    if (p != null) _handleOpen(p);
  }

  void _handleOpen(PushOpen open) {
    if (!open.opensPosUpload) return;
    if (!_homeReady || _user == null) {
      _pending = open;
      return;
    }
    _navigate(open);
  }

  void _showInApp(PushOpen open) {
    final text = [open.title, open.body]
        .where((s) => (s ?? '').trim().isNotEmpty)
        .join(' · ');
    if (text.isEmpty) return;
    AppNotification.withAction(
      text,
      label: 'Open',
      onPressed: open.opensPosUpload ? () => _handleOpen(open) : null,
    );
  }

  @override
  void onClose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.onClose();
  }
}

Future<void> _apiPost(String method, Map<String, dynamic> params) async {
  final Response r = await Get.find<ApiProvider>()
      .callMethodPost(method, params: params, jsonBody: true);
  if (r.statusCode != 200) throw StateError('$method → ${r.statusCode}');
}

Future<Map<String, String>> _packageInfo() async {
  final p = await PackageInfo.fromPlatform();
  return {
    'app_id': p.packageName,
    'app_version': '${p.version}+${p.buildNumber}',
  };
}

void _openDocument(PushOpen open) => Get.toNamed(
      AppRoutes.POS_UPLOAD_FORM,
      arguments: {'name': open.name, 'mode': 'view'},
    );
