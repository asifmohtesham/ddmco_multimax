// test/unit/api_provider_logging_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// Accepts every request, and hands out a session cookie like Frappe does.
class _AcceptingNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'message': 'ok'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'set-cookie': ['sid=cookie-secret-9; Path=/; HttpOnly'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
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
    api.dio.httpClientAdapter = _AcceptingNetwork();
  });

  /// Everything written to the console while [body] runs.
  Future<String> consoleDuring(Future<void> Function() body) async {
    final lines = <String>[];
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => lines.add(line),
      ),
    );
    return lines.join('\n');
  }

  test('a password change writes neither password to the console', () async {
    final console = await consoleDuring(
      () => api.changePassword('old secret, 1', 'new secret, 2'),
    );

    expect(console, isNot(contains('old secret')));
    expect(console, isNot(contains('new secret')));
    expect(console, isNot(contains(', 1')));
    expect(console, isNot(contains(', 2')));
  });

  test('a login writes no password to the console', () async {
    final console = await consoleDuring(
      () => api.loginWithFrappe('pat', 'login-secret-3'),
    );

    expect(console, isNot(contains('login-secret-3')));
  });

  test('the session cookie is not written to the console', () async {
    final console = await consoleDuring(() async {
      await api.getDocument('Item', 'ABC'); // receives the cookie
      await api.getDocument('Item', 'DEF'); // sends it back
    });

    expect(console, isNot(contains('cookie-secret-9')));
  });

  test('ordinary requests are still logged for debugging', () async {
    final console = await consoleDuring(
      () => api.updateDocument('Item', 'ABC', {'description': 'blue widget'}),
    );

    expect(console, contains('/api/resource/Item/ABC'));
    expect(console, contains('blue widget'));
  });

  test('a request with a hidden body is still visible in the log', () async {
    final console = await consoleDuring(
      () => api.changePassword('old secret, 1', 'new secret, 2'),
    );

    expect(console, contains('update_password'));
  });
}
