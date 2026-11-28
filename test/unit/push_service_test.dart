import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/services/push_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/user_area/user_area_screen.dart';

class _Box {
  final Map<String, dynamic> data = {};
  Future<void> write(String key, dynamic value) async => data[key] = value;
  Future<void> remove(String key) async => data.remove(key);
  T? read<T>(String key) => data[key] as T?;
  bool hasData(String key) => data.containsKey(key);
}

class _FakeMessaging implements PushMessaging {
  bool failInit = false;
  String? token = 'tok-1';
  int permissionAsks = 0;
  PushOpen? launchedBy;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushOpen>.broadcast();
  final opened = StreamController<PushOpen>.broadcast();

  @override
  Future<void> init() async {
    if (failInit) throw StateError('no google-services.json');
  }

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return true;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<PushOpen> get onForeground => foreground.stream;

  @override
  Stream<PushOpen> get onOpened => opened.stream;

  @override
  Future<PushOpen?> initialOpen() async => launchedBy;
}

const _pos = PushOpen(
    title: 'Delivered', body: 'KA-2026-03835', doctype: 'POS Upload', name: 'KA-2026-03835');

void main() {
  const user = 'disp@example.com';
  late _Box box;
  late StorageService storage;
  late _FakeMessaging messaging;
  late List<(String, Map<String, dynamic>)> posts;
  late List<PushOpen> opened;
  Object? postError;

  void signIn(List<String> roles) => box.data['currentUser'] = {
        'name': user,
        'full_name': 'Dispatcher',
        'email': user,
        'roles': [for (final r in roles) {'role': r}],
      };

  Future<PushService> start({bool supported = true, String? platform}) => PushService(
        messaging: messaging,
        storage: storage,
        supported: supported,
        platform: platform,
        appInfo: () async => {'app_id': 'com.ddmco.multimax', 'app_version': '2.63.0+167'},
        navigate: opened.add,
        post: (method, params) async {
          posts.add((method, params));
          if (postError != null) throw postError!;
        },
      ).start();

  setUp(() {
    box = _Box();
    storage = StorageService.withStorage(box as dynamic);
    messaging = _FakeMessaging();
    posts = [];
    opened = [];
    postError = null;
  });

  tearDown(() => Get.deleteAll(force: true));

  test('an iPhone registers with platform ios', () async {
    signIn(['Stock Manager']);
    final push = await start(platform: 'ios');
    await push.sync();
    expect(posts.single.$1, 'mobile_push_register');
    expect(posts.single.$2['platform'], 'ios');
  });

  test('registers a Delivery Dispatcher with token, platform and app info', () async {
    signIn(['Stock User', 'Delivery Dispatcher']);
    final push = await start();
    await push.sync();

    expect(messaging.permissionAsks, 1);
    expect(posts.single.$1, 'mobile_push_register');
    expect(posts.single.$2, {
      'token': 'tok-1',
      'platform': 'android',
      'app_id': 'com.ddmco.multimax',
      'app_version': '2.63.0+167',
    });
    expect(push.registeredToken, 'tok-1');
    expect(storage.getPushRegistered(user), isTrue);
  });

  test('a user without a delivery role costs no request', () async {
    signIn(['Stock User']);
    final push = await start();
    await push.sync();
    expect(posts, isEmpty);
    expect(messaging.permissionAsks, 0);
  });

  test('turning the switch off withdraws a registered phone', () async {
    signIn(['Stock Manager']);
    final push = await start();
    await push.sync();
    await storage.savePushDeliveryAlerts(user, false);
    await push.sync();

    expect(posts.map((p) => p.$1), ['mobile_push_register', 'mobile_push_unregister']);
    expect(posts.last.$2, {'token': 'tok-1'});
    expect(storage.getPushRegistered(user), isFalse);
  });

  test('a failed register (site without the method) is silent and not recorded', () async {
    signIn(['Stock Manager']);
    postError = StateError('mobile_push_register → 404');
    final push = await start();
    await push.sync();
    expect(push.registeredToken, isNull);
    expect(storage.getPushRegistered(user), isFalse);
  });

  test('sign-out unregister never throws', () async {
    signIn(['Stock Manager']);
    final push = await start();
    await push.sync();
    postError = StateError('offline');
    await push.unregister();
    expect(push.registeredToken, isNull);
  });

  test('Firebase failing to start turns push off for the run', () async {
    signIn(['Stock Manager']);
    messaging.failInit = true;
    final push = await start();
    await push.sync();
    expect(push.supported, isFalse);
    expect(posts, isEmpty);
  });

  test('unsupported platform does nothing', () async {
    signIn(['Stock Manager']);
    final push = await start(supported: false);
    await push.sync();
    await push.unregister();
    expect(posts, isEmpty);
  });

  test('a refreshed token is re-registered', () async {
    signIn(['Stock Manager']);
    final push = await start();
    messaging.refresh.add('tok-2');
    await pumpEventQueue();
    expect(posts.single.$2['token'], 'tok-2');
    expect(push.registeredToken, 'tok-2');
  });

  test('an alert that launched the app opens its POS Upload once home is ready', () async {
    signIn(['Stock Manager']);
    messaging.launchedBy = _pos;
    final push = await start();
    expect(opened, isEmpty);
    push.homeReady();
    expect(opened.single.name, 'KA-2026-03835');
    push.homeReady();
    expect(opened, hasLength(1), reason: 'opened only once');
  });

  test('a tapped alert opens at once when home is up; other doctypes are ignored', () async {
    signIn(['Stock Manager']);
    final push = await start();
    push.homeReady();
    messaging.opened
      ..add(_pos)
      ..add(const PushOpen(doctype: 'Delivery Note', name: 'X'))
      ..add(const PushOpen(doctype: 'POS Upload', name: ' '));
    await pumpEventQueue();
    expect(opened.map((o) => o.name), ['KA-2026-03835']);
  });

  group('who gets alerts', () {
    User u(List<String> roles) => User(id: 'x', name: 'X', email: 'x', roles: roles);

    test('pushEligible covers Delivery Dispatcher and Stock Manager only', () {
      expect(pushEligible(u(['Delivery Dispatcher'])), isTrue);
      expect(pushEligible(u(['Stock Manager'])), isTrue);
      expect(pushEligible(u(['Stock User'])), isFalse);
      expect(pushEligible(null), isFalse);
    });

    test('a Delivery Dispatcher without an employee sees Notifications on Android and iOS', () {
      final d = u(['Stock User', 'Delivery Dispatcher']);
      expect(showNotificationsEntry(user: d, platform: TargetPlatform.android, isWeb: false), isTrue);
      expect(showNotificationsEntry(user: d, platform: TargetPlatform.iOS, isWeb: false), isTrue);
      expect(showNotificationsEntry(user: d, platform: TargetPlatform.iOS, isWeb: true), isFalse);
    });
  });
}
