import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pos_upload_delivery.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/csrf_interceptor.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';

const _name = 'ML-ZZTEST-P1A-261125-A';
const _revision = '2026-11-25 19:20:11.123456';
const _getTransitions = '/api/method/frappe.model.workflow.get_transitions';
const _getDrivers = '/api/method/pos_upload_delivery_drivers';
const _apply = '/api/method/frappe.model.workflow.apply_workflow';
const _docinfo = '/api/method/frappe.desk.form.load.get_docinfo';

class _WorkflowServer implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final applyBodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    switch (options.path) {
      case _getTransitions:
        return _json({
          'message': [
            {'action': 'Out for Delivery'},
            {'action': 'Out for Delivery'},
            {'action': 'Something else'},
            {'action': 'Delivery Return'},
            {'action': 'Delivered'},
            {'action': 'Delivery Return'},
            {'action': 'Revert to Pending'},
            {'action': 'Complete'},
          ],
        });
      case _getDrivers:
        return _json({
          'message': {
            'drivers': [
              {'name': 'DRV-1', 'full_name': 'Driver One'},
              {'name': 'DRV-2', 'full_name': 'Driver Two'},
            ],
            'default_driver': 'DRV-2',
          },
        });
      case _apply:
        final body = await utf8.decoder.bind(requestStream!).join();
        applyBodies.add(body);
        if (options.headers[CsrfInterceptor.header] != 'csrf-test-token') {
          return _json({'exc_type': 'CSRFTokenError'}, status: 400);
        }
        return _json({
          'message': {
            'name': _name,
            'status': 'Out for Delivery',
            'modified': '2026-11-25 19:22:33.000001',
          },
        });
      case CsrfInterceptor.deskPath:
        return ResponseBody.fromString(
          '<script>frappe.csrf_token = "csrf-test-token";</script>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      case _docinfo:
        return _json({
          'docinfo': {'versions': [], 'workflow_logs': []},
        });
      default:
        throw StateError('Unexpected request to ${options.path}');
    }
  }

  static ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _WorkflowServer server;
  late PosUploadProvider provider;

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('pos_delivery_cookies_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(pathProvider, (_) async => dir.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(pathProvider, null);
      dir.deleteSync(recursive: true);
      Get.reset();
    });
    final api = Get.put(ApiProvider());
    await api.initDio();
    server = _WorkflowServer();
    api.dio.httpClientAdapter = server;
    provider = PosUploadProvider();
  });

  test(
    'discovery GET uses doc identity and deduplicates recognized actions',
    () async {
      expect(
        await provider.getDeliveryActions(_name),
        PosDeliveryAction.values,
      );
      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.path, _getTransitions);
      expect(request.queryParameters.keys, ['doc']);
      expect(jsonDecode(request.queryParameters['doc'] as String), {
        'doctype': 'POS Upload',
        'name': _name,
      });
    },
  );

  test('driver GET reads the server-provided default and choices', () async {
    final options = await provider.getDeliveryDrivers(
      _name,
      PosDeliveryAction.deliveryReturn,
    );
    expect(options.defaultDriver, 'DRV-2');
    expect(options.drivers.map((driver) => (driver.name, driver.fullName)), [
      ('DRV-1', 'Driver One'),
      ('DRV-2', 'Driver Two'),
    ]);
    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(request.path, _getDrivers);
    expect(request.queryParameters, {
      'name': _name,
      'action': 'Delivery Return',
    });
  });

  for (final action in PosDeliveryAction.values) {
    test(
      '${action.label} POST preserves the exact doc through a CSRF retry',
      () async {
        final result = await provider.applyDeliveryAction(
          PosUpload.fromJson({'name': _name, 'modified': _revision}),
          action,
          const PosDeliverySelection(
            driver: 'DRV-2',
            reason: PosDeliveryReason.late,
          ),
        );

        expect(result.modified, '2026-11-25 19:22:33.000001');
        expect(result.status, 'Out for Delivery');
        expect(
          server.requests.map((request) => (request.method, request.path)),
          [
            ('POST', _apply),
            ('GET', CsrfInterceptor.deskPath),
            ('POST', _apply),
          ],
        );
        expect(server.requests.last.contentType, Headers.jsonContentType);
        expect(server.applyBodies.first, server.applyBodies.last);
        expect(jsonDecode(server.applyBodies.last), {
          'action': action.label,
          'doc': {
            'doctype': 'POS Upload',
            'name': _name,
            'modified': _revision,
            if (action.requiresDriver) 'pos_delivery_driver': 'DRV-2',
            if (action.requiresReason) 'pos_delivery_reason': 'Late',
          },
        });
      },
    );
  }

  test('Revert to Pending POSTs without a driver or reason', () async {
    await provider.applyDeliveryAction(
      PosUpload.fromJson({'name': _name, 'modified': _revision}),
      PosDeliveryAction.revertToPending,
      const PosDeliverySelection(),
    );
    expect(jsonDecode(server.applyBodies.last), {
      'action': 'Revert to Pending',
      'doc': {'doctype': 'POS Upload', 'name': _name, 'modified': _revision},
    });
  });

  test('Complete POSTs without a driver or reason', () async {
    await provider.applyDeliveryAction(
      PosUpload.fromJson({'name': _name, 'modified': _revision}),
      PosDeliveryAction.complete,
      const PosDeliverySelection(),
    );
    expect(jsonDecode(server.applyBodies.last), {
      'action': 'Complete',
      'doc': {'doctype': 'POS Upload', 'name': _name, 'modified': _revision},
    });
  });

  test('a delivery action without a driver is rejected before POST', () async {
    await expectLater(
      provider.applyDeliveryAction(
        PosUpload.fromJson({'name': _name, 'modified': _revision}),
        PosDeliveryAction.outForDelivery,
        const PosDeliverySelection(),
      ),
      throwsArgumentError,
    );
    expect(server.requests, isEmpty);
  });

  test('timeline GET reads docinfo from the top-level envelope', () async {
    expect(await provider.getDeliveryDocinfo(_name), {
      'versions': [],
      'workflow_logs': [],
    });
    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(request.path, _docinfo);
    expect(request.queryParameters, {'doctype': 'POS Upload', 'name': _name});
  });
}
