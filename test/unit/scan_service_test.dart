import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/scan_service.dart';

void main() {
  const ean = '20011369';
  const derivedCode = '2001136';
  const externalCode = '4006381333931';
  const externalItem = 'ITEM-WITH-REGISTERED-BARCODE';

  late _BarcodeApi api;
  late ScanService service;

  setUp(() {
    api = _BarcodeApi();
    service = ScanService(apiProvider: api);
  });

  test('shared and camera scans load the same direct EAN-8 Item', () async {
    api.items[derivedCode] = {
      'name': derivedCode,
      'item_code': derivedCode,
      'variant_of': 'TEMPLATE',
    };

    final shared = await service.resolveItemBarcode(' $ean ');
    final camera = await service.processScan(ean);

    expect(shared?.itemCode, derivedCode);
    expect(shared?.variantOf, 'TEMPLATE');
    expect(camera.itemData?.itemCode, shared?.itemCode);
    expect(api.calls, ['Item:$derivedCode', 'Item:$derivedCode']);
  });

  test(
    'a registered barcode resolves through the standard ERPNext lookup',
    () async {
      api.stockBarcodes[externalCode] = {'item_code': externalItem};
      api.items[externalItem] = {
        'name': externalItem,
        'item_code': externalItem,
      };

      final shared = await service.resolveItemBarcode(externalCode);
      expect(shared?.itemCode, externalItem);
      expect(api.calls, ['barcode:$externalCode', 'Item:$externalItem']);

      final camera = await service.processScan(externalCode);
      expect(camera.itemData?.itemCode, shared?.itemCode);
    },
  );

  test('a Batch whose EAN prefix misses uses the linked Item', () async {
    const batch = '$ean-ABCDEF';
    api.stockBarcodes[batch] = {'batch_no': batch, 'item_code': externalItem};
    api.items[externalItem] = {'name': externalItem, 'item_code': externalItem};

    expect((await service.resolveItemBarcode(batch))?.itemCode, externalItem);
    expect(api.calls, [
      'Item:$derivedCode',
      'barcode:$batch',
      'Item:$externalItem',
    ]);

    final camera = await service.processScan(batch);
    expect(camera.itemData?.itemCode, externalItem);
    expect(camera.batchNo, batch);
  });

  test('an unknown Batch can resolve from its registered EAN-8', () async {
    const batch = '$ean-ABSENT';
    api.stockBarcodes[ean] = {'item_code': externalItem};
    api.items[externalItem] = {'name': externalItem, 'item_code': externalItem};

    expect((await service.resolveItemBarcode(batch))?.itemCode, externalItem);
    expect(api.calls, [
      'Item:$derivedCode',
      'barcode:$batch',
      'barcode:$ean',
      'Item:$externalItem',
    ]);
  });

  test('a serialized Batch uses a direct read with its encoded name', () async {
    const batch = 'BATCH/26 #1';
    const encoded = 'BATCH%2F26%20%231';
    api.barcodeFailure = _failure(417, type: 'ValidationError');
    api.batches[encoded] = {'item': externalItem};
    api.items[externalItem] = {'name': externalItem, 'item_code': externalItem};

    expect((await service.resolveItemBarcode(batch))?.itemCode, externalItem);
    expect(api.calls, [
      'barcode:$batch',
      'Batch:$encoded',
      'Item:$externalItem',
    ]);

    final camera = await service.processScan(batch);
    expect(camera.itemData?.itemCode, externalItem);
    expect(camera.batchNo, batch);
  });

  test(
    'a missing direct Batch preserves the original validation failure',
    () async {
      final failure = _failure(417, type: 'ValidationError');
      api.barcodeFailure = failure;

      await expectLater(
        service.resolveItemBarcode(externalCode),
        throwsA(same(failure)),
      );
      expect(api.calls, ['barcode:$externalCode', 'Batch:$externalCode']);
    },
  );

  test(
    'permission, transport, and non-validation errors skip the Batch read',
    () async {
      final failures = [
        _failure(403, type: 'PermissionError'),
        _failure(417, type: 'FrappeTypeError'),
        DioException.connectionError(
          requestOptions: RequestOptions(),
          reason: 'offline',
        ),
      ];
      for (final failure in failures) {
        api.barcodeFailure = failure;
        await expectLater(
          service.resolveItemBarcode(externalCode),
          throwsA(same(failure)),
        );
      }
      expect(api.calls, List.filled(failures.length, 'barcode:$externalCode'));
    },
  );

  test(
    'camera scan continues to route known rack and variant labels',
    () async {
      api.variantCode = 'TEMPLATE';

      expect(
        (await service.processScan('KA-WH-DXB1-121D')).type,
        ScanType.rack,
      );
      expect((await service.processScan('TEMPLATE')).type, ScanType.variant_of);
      expect(api.calls, ['variant:TEMPLATE']);
    },
  );

  test('a barcode lookup returns null for an unknown value', () async {
    expect(await service.resolveItemBarcode(externalCode), isNull);
    expect(api.calls, ['barcode:$externalCode']);
  });
}

DioException _failure(int statusCode, {String? type}) =>
    DioException.badResponse(
      statusCode: statusCode,
      requestOptions: RequestOptions(),
      response: _response({'exc_type': type}, statusCode: statusCode),
    );

Response<dynamic> _response(Object data, {int statusCode = 200}) => Response(
  data: data,
  requestOptions: RequestOptions(),
  statusCode: statusCode,
);

class _BarcodeApi implements ApiProvider {
  final calls = <String>[];
  final items = <String, Map<String, dynamic>>{};
  final batches = <String, Map<String, dynamic>>{};
  final stockBarcodes = <String, Map<String, dynamic>>{};
  String? variantCode;
  DioException? barcodeFailure;

  @override
  Future<Response<dynamic>> getDocument(String doctype, String name) async {
    calls.add('$doctype:$name');
    final data = (doctype == 'Batch' ? batches : items)[name];
    if (data != null) return _response({'data': data});
    throw _failure(404);
  }

  @override
  Future<Response<dynamic>> getDocumentList(
    String doctype, {
    Map<String, dynamic>? filters,
    List<String>? fields,
    int? limit,
    int? limitStart,
    String? orderBy,
    String? groupBy,
    List<List<dynamic>>? filterTuples,
    Map<String, dynamic>? orFilters,
    List<List<dynamic>>? orFilterTuples,
  }) async {
    expect(doctype, 'Item');
    final source = (filters?['variant_of'] as List).last as String;
    final code = source.substring(1, source.length - 1);
    calls.add('variant:$code');
    return _response({
      'data': [
        if (code == variantCode) {'name': 'VARIANT'},
      ],
    });
  }

  @override
  Future<Response<dynamic>> callMethod(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    expect(method, 'erpnext.stock.utils.scan_barcode');
    final code = params?['search_value'] as String;
    calls.add('barcode:$code');
    if (barcodeFailure case final failure?) throw failure;
    return _response({'message': stockBarcodes[code] ?? {}});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
