import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/customer_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';

class _FakeApiProvider extends ApiProvider {
  final rows = <Map<String, dynamic>>[];

  @override
  Future<Response> getDocumentList(
    String doctype, {
    int limit = 20,
    int limitStart = 0,
    List<String>? fields,
    String? groupBy = '',
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
    Map<String, dynamic>? orFilters,
    List<List<dynamic>>? orFilterTuples,
    String orderBy = 'modified desc',
  }) async {
    Iterable<Map<String, dynamic>> results = rows;
    final statusFilter = filters?['status'] as List?;
    final nameFilter = filters?['name'] as List?;
    if (statusFilter != null) {
      expect(statusFilter.first, 'in');
      final allowed = statusFilter.last as List;
      results = results.where((row) => allowed.contains(row['status'] ?? ''));
    }
    if (nameFilter != null) {
      expect(nameFilter.first, 'like');
      results = results.where((row) => _matchesPrefix(row, nameFilter.last));
    }
    if (orFilterTuples != null) {
      for (final tuple in orFilterTuples) {
        expect(tuple.take(3), ['POS Upload', 'name', 'like']);
      }
      results = results.where(
        (row) => orFilterTuples.any((tuple) => _matchesPrefix(row, tuple.last)),
      );
    }
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype'),
      statusCode: 200,
      data: {'data': results.skip(limitStart).take(limit).toList()},
    );
  }

  bool _matchesPrefix(Map<String, dynamic> row, String pattern) {
    expect(pattern, endsWith('%'));
    return (row['name'] as String).startsWith(
      pattern.substring(0, pattern.length - 1),
    );
  }
}

Map<String, dynamic> _row(String name, String? status) => {
  'name': name,
  'status': status,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => '/tmp/test_cookies',
        );
  });

  late _FakeApiProvider api;
  setUp(() {
    api = _FakeApiProvider();
    Get.put<ApiProvider>(api);
    Get.put(PosUploadProvider());
    Get.put(UserProvider());
    Get.put(WarehouseProvider());
  });
  tearDown(Get.reset);

  test(
    'delivery note picker filters by status and family before its limit',
    () async {
      Get.put(DeliveryNoteProvider());
      Get.put(CustomerProvider());
      final controller = DeliveryNoteController();
      // Newer delivery-stage records and stock-entry work cannot displace
      // eligible ML/KA rows on the first page.
      api.rows.addAll([
        for (var i = 0; i < 100; i++) ...[
          _row('ML-ready-$i', 'To Deliver'),
          _row('KA-driving-$i', 'Out for Delivery'),
          _row('ML-delivered-$i', 'Delivered'),
          _row('MX-pending-$i', 'Pending'),
        ],
        _row('ML-pending', 'Pending'),
        _row('KA-preparing', 'In Progress'),
        _row('ML-blank', ''),
        _row('KA-unset', null),
      ]);

      await controller.fetchPosUploadsForSelection();

      expect(controller.posUploadsForSelection.map((upload) => upload.name), [
        'ML-pending',
        'KA-preparing',
        'ML-blank',
        'KA-unset',
      ]);
    },
  );

  test(
    'material issue picker shows only KX/MX warehouse preparation',
    () async {
      Get.put(StockEntryProvider());
      Get.put(MaterialRequestProvider());
      final controller = StockEntryController();
      api.rows.addAll([
        _row('KX-ready', 'To Deliver'),
        _row('MX-driving', 'Out for Delivery'),
        _row('KX-delivered', 'Delivered'),
        _row('ML-pending', 'Pending'),
        _row('KX-pending', 'Pending'),
        _row('MX-preparing', 'In Progress'),
      ]);

      await controller.fetchPosUploadsForSelection();

      expect(
        controller.posUploadsForSelection.map((upload) => upload.name),
        unorderedEquals(['KX-pending', 'MX-preparing']),
      );
    },
  );
}
