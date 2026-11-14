import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/csrf_interceptor.dart';

ResponseBody _json(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

ResponseBody _csrf() => _json(400, {'exc_type': 'CSRFTokenError'});

const _desk = '<script>frappe.csrf_token = "tok123";</script>';

/// Fake server enforcing CSRF on unsafe requests.
class _Server implements HttpClientAdapter {
  String? required = 'tok123';
  String deskHtml = _desk;
  final List<String> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s,
      Future<void>? c) async {
    final sent = o.headers[CsrfInterceptor.header];
    log.add('${o.method} ${o.path} ${sent ?? '-'}');
    if (o.path == CsrfInterceptor.deskPath) {
      return ResponseBody.fromString(deskHtml, 200,
          headers: {Headers.contentTypeHeader: ['text/html']});
    }
    if (o.method != 'GET' && required != null && sent != required) {
      return _csrf();
    }
    return _json(200, {'message': 'ok'});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Server server;
  late Dio dio;
  late CsrfInterceptor csrf;

  setUp(() {
    server = _Server();
    dio = Dio(BaseOptions(baseUrl: 'https://erp.test'))..httpClientAdapter = server;
    csrf = CsrfInterceptor(dio: dio);
    dio.interceptors.add(csrf);
  });

  test('parseToken reads desk boot HTML', () {
    expect(CsrfInterceptor.parseToken(_desk), 'tok123');
    expect(CsrfInterceptor.parseToken("csrf_token = '{{ csrf_token }}'"), isNull);
    expect(CsrfInterceptor.parseToken('<html></html>'), isNull);
  });

  test('GETs are untouched and never fetch a token', () async {
    final r = await dio.get('/api/resource/Item');
    expect(r.statusCode, 200);
    expect(server.log, ['GET /api/resource/Item -']);
  });

  test('CSRF rejection fetches token, retries once, then sends it up front',
      () async {
    final r = await dio.post('/api/method/x', data: {'a': 1});
    expect(r.data['message'], 'ok');
    expect(server.log, [
      'POST /api/method/x -',
      'GET /app -',
      'POST /api/method/x tok123',
    ]);
    server.log.clear();
    await dio.put('/api/resource/DN/1', data: {'b': 2});
    expect(server.log, ['PUT /api/resource/DN/1 tok123']);
  });

  test('stale token after re-login is refreshed', () async {
    await dio.post('/api/method/x');
    server.required = 'tok999';
    server.deskHtml = 'csrf_token = "tok999"';
    server.log.clear();
    final r = await dio.post('/api/method/x');
    expect(r.statusCode, 200);
    expect(server.log.last, 'POST /api/method/x tok999');
  });

  test('gives up after one retry and surfaces the original error', () async {
    server.deskHtml = '<html>no token</html>';
    await expectLater(
      dio.post('/api/method/x'),
      throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode, 'status', 400)),
    );
    expect(server.log.where((l) => l.startsWith('POST')).length, 1);
  });

  test('server without CSRF: no extra traffic', () async {
    server.required = null;
    await dio.post('/api/method/x');
    expect(server.log, ['POST /api/method/x -']);
  });
}
