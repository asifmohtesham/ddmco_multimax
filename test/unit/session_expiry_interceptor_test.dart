// test/unit/session_expiry_interceptor_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/session_expiry_interceptor.dart';

const _identityPath = '/api/method/frappe.auth.get_logged_user';

ResponseBody _json(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Frappe's body for a request made without a valid session.
ResponseBody _forbidden() => _json(403, {
      'exc_type': 'PermissionError',
      '_server_messages': '[]',
    });

/// Answers every request from a script and records what was asked.
class _ScriptedNetwork implements HttpClientAdapter {
  ResponseBody Function() identity = () => _json(200, {'message': 'Guest'});
  ResponseBody Function(RequestOptions) other = (_) => _forbidden();
  final List<String> requested = [];

  int get identityChecks => requested.where((p) => p == _identityPath).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.path);
    return options.path == _identityPath ? identity() : other(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _ScriptedNetwork network;
  late Dio dio;
  late bool signedIn;
  late int expiryReports;
  late DateTime clock;

  setUp(() {
    network = _ScriptedNetwork();
    signedIn = true;
    expiryReports = 0;
    clock = DateTime(2026, 9, 27, 8);
    dio = Dio(BaseOptions(baseUrl: 'https://erp.example.com'))
      ..httpClientAdapter = network;
    dio.interceptors.add(SessionExpiryInterceptor(
      dio: dio,
      hasActiveSession: () => signedIn,
      onSessionExpired: () {
        expiryReports++;
        signedIn = false;
      },
      now: () => clock,
    ));
  });

  Future<int?> statusOf(Future<Response> request) async {
    try {
      return (await request).statusCode;
    } on DioException catch (e) {
      return e.response?.statusCode;
    }
  }

  test('reports expiry when a 403 is followed by a Guest identity', () async {
    final status = await statusOf(dio.get('/api/resource/Item/ABC'));

    expect(expiryReports, 1);
    expect(status, 403, reason: 'the caller still sees its own failure');
  });

  test('reports expiry when the identity check is itself refused', () async {
    network.identity = _forbidden;

    await statusOf(dio.get('/api/resource/Item/ABC'));

    expect(expiryReports, 1);
  });

  test('reports expiry for a 401', () async {
    network.other = (_) => _json(401, {'exc_type': 'AuthenticationError'});

    await statusOf(dio.get('/api/resource/Item/ABC'));

    expect(expiryReports, 1);
  });

  test('treats a 403 as a permission problem while still logged in', () async {
    network.identity = () => _json(200, {'message': 'picker@example.com'});

    final status = await statusOf(dio.get('/api/resource/Salary Slip/X'));

    expect(expiryReports, 0);
    expect(status, 403);
  });

  test('reports expiry once for a burst of failures', () async {
    await Future.wait([
      for (var i = 0; i < 5; i++) statusOf(dio.get('/api/resource/Item/$i')),
    ]);

    expect(expiryReports, 1);
    expect(network.identityChecks, 1);
  });

  test('does not re-check identity right after it was confirmed', () async {
    network.identity = () => _json(200, {'message': 'picker@example.com'});

    await statusOf(dio.get('/api/resource/Salary Slip/X'));
    clock = clock.add(const Duration(seconds: 10));
    await statusOf(dio.get('/api/resource/Salary Slip/Y'));

    expect(network.identityChecks, 1);
  });

  test('checks identity again once the confirmation is stale', () async {
    network.identity = () => _json(200, {'message': 'picker@example.com'});

    await statusOf(dio.get('/api/resource/Salary Slip/X'));
    clock = clock.add(const Duration(minutes: 2));
    network.identity = () => _json(200, {'message': 'Guest'});
    await statusOf(dio.get('/api/resource/Salary Slip/Y'));

    expect(network.identityChecks, 2);
    expect(expiryReports, 1);
  });

  test('ignores failures when nobody is signed in', () async {
    signedIn = false;

    await statusOf(dio.get('/api/resource/Item/ABC'));

    expect(network.identityChecks, 0);
    expect(expiryReports, 0);
  });

  test('ignores requests that opt out', () async {
    network.other = (_) => _json(401, {'message': 'Invalid login credentials'});

    await statusOf(dio.post(
      '/api/method/login',
      options: SessionExpiryInterceptor.unchecked(),
    ));

    expect(network.identityChecks, 0);
    expect(expiryReports, 0);
  });

  test('stays quiet when the identity check cannot reach the server',
      () async {
    network.identity = () => throw const SocketException('no route to host');

    final status = await statusOf(dio.get('/api/resource/Item/ABC'));

    expect(expiryReports, 0);
    expect(status, 403);
  });

  test('leaves server errors alone', () async {
    network.other = (_) => _json(500, {'exc_type': 'ValidationError'});

    await statusOf(dio.get('/api/resource/Item/ABC'));

    expect(network.identityChecks, 0);
    expect(expiryReports, 0);
  });

  group('ApiProvider', () {
    late ApiProvider api;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dir = Directory.systemTemp.createTempSync('multimax_cookies_');
      addTearDown(() => dir.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async => dir.path,
      );
      api = ApiProvider();
      await api.initDio();
      api.dio.httpClientAdapter = network;
      api.hasActiveSession = () => signedIn;
      api.onSessionExpired = () => expiryReports++;
    });

    test('reports expiry when a document request is refused', () async {
      await statusOf(api.getDocument('Item', 'ABC'));

      expect(expiryReports, 1);
    });

    test('a wrong password is not mistaken for an expired session', () async {
      network.other =
          (_) => _json(401, {'message': 'Invalid login credentials'});

      final status = await statusOf(api.loginWithFrappe('pat', 'wrong'));

      expect(status, 401);
      expect(network.identityChecks, 0);
      expect(expiryReports, 0);
    });

    test('the identity check does not trigger a second identity check',
        () async {
      network.identity = _forbidden;

      await statusOf(api.getLoggedUser());

      expect(network.identityChecks, 1);
      expect(expiryReports, 0);
    });

    test('a failed logout call does not report expiry', () async {
      await statusOf(api.logoutApiCall());

      expect(network.identityChecks, 0);
      expect(expiryReports, 0);
    });
  });
}
