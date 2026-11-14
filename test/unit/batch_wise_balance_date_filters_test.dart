// test/unit/batch_wise_balance_date_filters_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';

// getBatchWiseBalance used to hardcode from_date/to_date to today, so the
// From/To chips on the Batch-Wise Balance History report did nothing. These
// tests pin the query_report.run payload: the selected dates are sent, and
// today is only the fallback when a date is unset.

/// Records every request and answers like an empty report run.
class _CapturingNetwork implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'message': {'columns': [], 'result': []},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Never touches GetStorage; getBatchWiseBalance only reads the company.
class _FakeStorage extends StorageService {
  _FakeStorage() : super.withStorage(null);

  @override
  String? getBaseUrl() => null;

  @override
  String getCompany() => 'Multimax';
}

/// Captures the arguments the report controller passes to the provider.
class _RecordingApi extends ApiProvider {
  final calls = <Map<String, String?>>[];

  @override
  Future<List<Map<String, dynamic>>> getBatchWiseBalance({
    required String itemCode,
    String? batchNo,
    String? warehouse,
    String? fromDate,
    String? toDate,
  }) async {
    calls.add({
      'itemCode': itemCode,
      'batchNo': batchNo,
      'warehouse': warehouse,
      'fromDate': fromDate,
      'toDate': toDate,
    });
    return [];
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('multimax_cookies_');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => dir.path,
    );
  });

  tearDown(() => Get.deleteAll(force: true));

  group('ApiProvider.getBatchWiseBalance request payload', () {
    late ApiProvider api;
    late _CapturingNetwork network;

    setUp(() async {
      Get.put<StorageService>(_FakeStorage());
      api = ApiProvider();
      await api.initDio();
      network = _CapturingNetwork();
      api.dio.httpClientAdapter = network;
    });

    Map<String, dynamic> sentFilters() {
      expect(network.requests, hasLength(1));
      final q = network.requests.single.queryParameters;
      expect(q['report_name'], 'Batch-Wise Balance History');
      return json.decode(q['filters'] as String) as Map<String, dynamic>;
    }

    test('carries the selected from/to dates', () async {
      await api.getBatchWiseBalance(
        itemCode: 'ITEM-1',
        fromDate: '2026-01-01',
        toDate: '2026-03-31',
      );

      final f = sentFilters();
      expect(f['from_date'], '2026-01-01');
      expect(f['to_date'], '2026-03-31');
      expect(f['item_code'], 'ITEM-1');
      expect(f['company'], 'Multimax');
    });

    test('defaults both dates to today when unset', () async {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      await api.getBatchWiseBalance(itemCode: 'ITEM-1');

      final f = sentFilters();
      expect(f['from_date'], today);
      expect(f['to_date'], today);
    });

    test('treats a blank date as unset (today)', () async {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      await api.getBatchWiseBalance(
        itemCode: 'ITEM-1',
        fromDate: '  ',
        toDate: '2026-03-31',
      );

      final f = sentFilters();
      expect(f['from_date'], today);
      expect(f['to_date'], '2026-03-31');
    });
  });

  group('BatchWiseBalanceController.runReport', () {
    test('passes the selected filter dates to the provider', () async {
      final api = _RecordingApi();
      Get.put<ApiProvider>(api);
      final ctrl = Get.put(BatchWiseBalanceController());

      ctrl.itemCodeController.text = 'ITEM-1';
      ctrl.fromDateController.text = '2026-02-01';
      ctrl.toDateController.text = '2026-02-28';
      await ctrl.runReport();

      expect(api.calls, hasLength(1));
      expect(api.calls.single['fromDate'], '2026-02-01');
      expect(api.calls.single['toDate'], '2026-02-28');
      expect(api.calls.single['itemCode'], 'ITEM-1');
    });

    test('sends null (provider defaults to today) for cleared dates',
        () async {
      final api = _RecordingApi();
      Get.put<ApiProvider>(api);
      final ctrl = Get.put(BatchWiseBalanceController());

      ctrl.itemCodeController.text = 'ITEM-1';
      ctrl.fromDateController.clear();
      ctrl.toDateController.clear();
      await ctrl.runReport();

      expect(api.calls.single['fromDate'], isNull);
      expect(api.calls.single['toDate'], isNull);
    });
  });
}
