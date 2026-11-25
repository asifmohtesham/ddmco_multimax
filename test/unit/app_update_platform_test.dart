import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/app_update_platform.dart';

class _LookupAdapter implements HttpClientAdapter {
  _LookupAdapter(this.responses);

  final List<String> responses;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = responses[requests.length];
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/javascript'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AppStoreLookup _lookupUsing(_LookupAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(dio.close);
  return AppStoreLookup(dio: dio);
}

void main() {
  group('App Store version comparison', () {
    test('compares version parts numerically', () {
      expect(isNewerAppVersion('2.58.10', '2.58.9'), isTrue);
      expect(isNewerAppVersion('2.58.9', '2.58.10'), isFalse);
      expect(isNewerAppVersion('3.0', '2.99.99'), isTrue);
    });

    test('requires a strictly newer version', () {
      expect(isNewerAppVersion('2.58.9', '2.58.9'), isFalse);
    });

    test('treats missing parts as zero', () {
      expect(isNewerAppVersion('2.58', '2.58.0.0'), isFalse);
      expect(isNewerAppVersion('2.58.0', '2.58'), isFalse);
      expect(isNewerAppVersion('2.58.0.1', '2.58'), isTrue);
    });

    test('ignores invalid versions on either side', () {
      for (final invalid in ['', 'junk', '2..58', '2.58-beta', '2.+58']) {
        expect(isNewerAppVersion(invalid, '1.2'), isFalse);
        expect(isNewerAppVersion('9.5', invalid), isFalse);
      }
    });
  });

  group('App Store lookup', () {
    const emptyResults = '{"resultCount":0,"results":[]}';
    const storeUrl = 'https://apps.apple.com/app/multimax/id123';

    test('retries an empty regional result without country', () async {
      final adapter = _LookupAdapter([
        emptyResults,
        '{"resultCount":2,"results":['
            '{"version":"2.58.10","trackViewUrl":"$storeUrl"},'
            '{"version":"3.0.0","trackViewUrl":"$storeUrl"}]}',
      ]);
      final release = await _lookupUsing(adapter).lookup(country: 'AE');

      expect(release?.version, '2.58.10');
      expect(release?.url, Uri.parse(storeUrl));
      expect(adapter.requests.map((request) => request.method), ['GET', 'GET']);
      expect(adapter.requests.map((request) => request.uri), [
        Uri.parse(
          'https://itunes.apple.com/lookup?bundleId=com.ddmco.multimax&country=ae',
        ),
        Uri.parse(
          'https://itunes.apple.com/lookup?bundleId=com.ddmco.multimax',
        ),
      ]);
    });

    test('returns no release after the fallback is also empty', () async {
      final adapter = _LookupAdapter([emptyResults, emptyResults]);
      expect(await _lookupUsing(adapter).lookup(country: 'ae'), isNull);
      expect(adapter.requests, hasLength(2));
    });

    test('makes a single unscoped request when there is no region', () async {
      final adapter = _LookupAdapter([emptyResults]);
      expect(await _lookupUsing(adapter).lookup(), isNull);
      expect(adapter.requests.single.uri.queryParameters, {
        'bundleId': 'com.ddmco.multimax',
      });
    });

    test('returns no release when the JSON is malformed', () async {
      final adapter = _LookupAdapter(['{"resultCount":']);
      expect(await _lookupUsing(adapter).lookup(country: 'ae'), isNull);
      expect(adapter.requests, hasLength(1));
    });

    test(
      'returns no release when required result fields are missing',
      () async {
        final adapter = _LookupAdapter([
          '{"resultCount":1,"results":[{"version":"2.58.10"}]}',
        ]);
        expect(await _lookupUsing(adapter).lookup(country: 'ae'), isNull);
        expect(adapter.requests, hasLength(1));
      },
    );
  });
}
