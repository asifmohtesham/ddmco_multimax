import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_service.dart';

/// Hand-written fake (repo convention): overrides the single HTTP seam.
class _FakeDigestService extends DigestService {
  _FakeDigestService() : super(baseUrl: 'https://erp.test', cookieDir: '/x/');

  /// message returned by the session probe; null → probe throws [probeError].
  String? loggedUser = 'asif@example.com';
  DioException? probeError;

  /// Non-Dio throw for the probe (cookie-jar IO, a PlatformException, etc.).
  /// Checked before [probeError] so tests can inject either shape.
  Object? probeThrow;

  /// doctype name → count, DioException, or Exception.
  final Map<String, Object> countResults = {};
  final List<String> countedDoctypes = [];

  static DioException _dioError(int? statusCode) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: statusCode == null
            ? null
            : Response(
                requestOptions: RequestOptions(path: '/x'),
                statusCode: statusCode),
        type: statusCode == null
            ? DioExceptionType.connectionError
            : DioExceptionType.badResponse,
      );

  static DioException forbidden() => _dioError(403);
  static DioException unauthorized() => _dioError(401);
  static DioException network() => _dioError(null);

  @override
  Future<Response> callGet(String path, Map<String, dynamic> query) async {
    if (path == '/api/method/frappe.auth.get_logged_user') {
      if (probeThrow != null) throw probeThrow!;
      if (probeError != null) throw probeError!;
      return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'message': loggedUser},
      );
    }
    // count call
    final doctype = query['doctype'] as String;
    countedDoctypes.add(doctype);
    final r = countResults[doctype];
    if (r is DioException) throw r;
    if (r is Exception) throw r;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'message': r ?? 0}, // int, or any raw value a test injects
    );
  }
}

void main() {
  late _FakeDigestService svc;

  setUp(() => svc = _FakeDigestService());

  test('happy path counts every requested doctype with its filters', () async {
    svc.countResults['Purchase Order'] = 2;
    svc.countResults['POS Upload'] = 5;
    final result = await svc
        .fetchDigest([kDigestDoctypes.first, kDigestDoctypes.last]);
    expect(result.status, DigestStatus.ok);
    expect(result.counts, {'purchase_order': 2, 'pos_upload': 5});
    expect(result.total, 7);
    expect(svc.countedDoctypes, ['Purchase Order', 'POS Upload']);
  });

  test('per-doctype 403 is a permission skip, not a failure', () async {
    svc.countResults['Purchase Order'] = _FakeDigestService.forbidden();
    svc.countResults['POS Upload'] = 3;
    final result =
        await svc.fetchDigest([kDigestDoctypes.first, kDigestDoctypes.last]);
    expect(result.status, DigestStatus.ok);
    expect(result.counts, {'pos_upload': 3});
  });

  test('probe returning Guest → authExpired, no counts attempted', () async {
    svc.loggedUser = 'Guest';
    final result = await svc.fetchDigest(kDigestDoctypes);
    expect(result.status, DigestStatus.authExpired);
    expect(svc.countedDoctypes, isEmpty);
  });

  test('probe 401/403 → authExpired', () async {
    svc.probeError = _FakeDigestService.unauthorized();
    expect((await svc.fetchDigest(kDigestDoctypes)).status,
        DigestStatus.authExpired);
    svc.probeError = _FakeDigestService.forbidden();
    expect((await svc.fetchDigest(kDigestDoctypes)).status,
        DigestStatus.authExpired);
  });

  test('probe network error → failed', () async {
    svc.probeError = _FakeDigestService.network();
    expect(
        (await svc.fetchDigest(kDigestDoctypes)).status, DigestStatus.failed);
  });

  test('count network error → failed', () async {
    svc.countResults['Purchase Order'] = _FakeDigestService.network();
    expect((await svc.fetchDigest([kDigestDoctypes.first])).status,
        DigestStatus.failed);
  });

  test('non-int count payload is ignored, others still counted', () async {
    svc.countResults['Purchase Order'] = 'weird'; // malformed server body
    svc.countResults['POS Upload'] = 4;
    final result =
        await svc.fetchDigest([kDigestDoctypes.first, kDigestDoctypes.last]);
    expect(result.status, DigestStatus.ok);
    expect(result.counts, {'pos_upload': 4}); // PO absent, not crashed
  });

  test('probe non-Dio throw → failed (must not escape fetchDigest)',
      () async {
    svc.probeThrow = Exception('boom');
    final result = await svc.fetchDigest(kDigestDoctypes);
    expect(result.status, DigestStatus.failed);
    expect(svc.countedDoctypes, isEmpty);
  });

  test('count non-Dio throw → failed, not a permission skip', () async {
    svc.countResults['Purchase Order'] = Exception('boom');
    svc.countResults['POS Upload'] = 4;
    final result =
        await svc.fetchDigest([kDigestDoctypes.first, kDigestDoctypes.last]);
    expect(result.status, DigestStatus.failed);
  });
}
