import 'package:dio/dio.dart';
// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

const _company = 'Test Company';
const _wip = 'WH-WIP1 - KA';
const _dxb = 'WH-DXB1 - KA';
const _rack = 'KA-WH-WIP1-1A';

Map<String, dynamic> _draft({String purpose = 'Material Issue'}) => {
  'name': 'SE-1',
  'company': _company,
  'modified': '2026-11-23 08:00:00.000000',
  'docstatus': 0,
  'purpose': purpose,
  'stock_entry_type': purpose,
  'from_warehouse': purpose == 'Material Receipt' ? null : _wip,
  'to_warehouse': purpose == 'Material Receipt' ? _dxb : null,
  'items': [
    {
      'name': 'SE-ROW-1',
      'item_code': '2003050',
      'qty': 2,
      'batch_no': '20030506-4BC87Z',
      if (purpose == 'Material Receipt') ...{
        't_warehouse': _dxb,
        'to_rack': _rack,
      } else ...{
        's_warehouse': _dxb,
        'rack': _rack,
      },
    },
  ],
};

class _Storage extends Fake implements StorageService {
  @override
  String getCompany() => _company;

  @override
  int getAutoSaveDelay() => 1;
}

class _DataWedge extends GetxService implements DataWedgeService {
  @override
  final scannedCode = ''.obs;

  @override
  Future<String?> getVersion() async => null;

  @override
  void injectScan(String code) => scannedCode.value = code;
}

class _Api extends Fake implements ApiProvider {
  Map<String, dynamic> draft = _draft();
  final writes = <Map<String, dynamic>>[];

  @override
  int get rackWarehouseSession => 0;

  Response _response(Map<String, dynamic> data) =>
      Response(requestOptions: RequestOptions(), statusCode: 200, data: data);

  @override
  Future<RackWarehouseLookup> getRackWarehouse(String rack) async =>
      const RackWarehouseLookup.found(_wip, name: _rack);

  @override
  Future<Response> getDocument(String doctype, String name) async {
    expect(doctype, 'Warehouse');
    expect(Uri.decodeComponent(name), _wip);
    return _response({
      'data': {
        'name': _wip,
        'warehouse_name': 'WH-WIP1',
        'company': _company,
        'is_group': 0,
        'disabled': 0,
      },
    });
  }

  @override
  Future<Response> getStockEntry(String name) async =>
      _response({'data': draft});

  @override
  Future<Response> hasDocPermission(
    String doctype,
    String name,
    String type,
  ) async => _response({
    'message': {'has_permission': 1},
  });

  @override
  Future<Response> updateDocument(
    String doctype,
    String name,
    Map<String, dynamic> data,
  ) async {
    writes.add(data);
    draft = {...draft, ...data};
    return _response({'data': draft});
  }

  @override
  Future<Response> createDocument(
    String doctype,
    Map<String, dynamic> data,
  ) async {
    writes.add(data);
    draft = {...draft, ...data};
    return _response({'data': draft});
  }
}

void main() {
  late _Api api;
  late StockEntryFormController controller;

  setUp(() {
    api = _Api();
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(_Storage());
    Get.put<DataWedgeService>(_DataWedge());
    Get.put(ScanService());
    Get.put(StockEntryProvider());
    Get.put(PosUploadProvider());
    controller = StockEntryFormController();
  });
  tearDown(() => Get.reset());

  testWidgets(
    'direct save and autosave refuse a populated optional target rack mismatch',
    (tester) async {
      controller
        ..mode = 'new'
        ..stockEntry.value = StockEntry.fromJson(
          _draft(purpose: 'Material Receipt'),
        )
        ..stockEntryType.value = 'Material Receipt'
        ..toWarehouse.value = _dxb
        ..isDirty.value = true;

      expect(await controller.saveDocument(), isFalse);
      controller.scheduleAutoSaveForTest(Duration.zero);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(api.writes, isEmpty);
    },
  );

  testWidgets(
    'a header change and reduction retain a legacy pair, while an increase refuses it',
    (tester) async {
      controller
        ..mode = 'edit'
        ..name = 'SE-1';
      await controller.fetchDocument();
      controller.changeHeaderWarehouse('WH-DXB3 - KA', source: true);

      expect(controller.stockEntry.value!.items.single.sWarehouse, _dxb);
      expect(controller.warehouseNotice.value, contains('1 existing rows'));
      controller.updateItem(
        'SE-ROW-1',
        1,
        '20030506-4BC87Z',
        _rack,
        null,
        _dxb,
        null,
        null,
      );
      expect(await controller.saveDocument(), isTrue);
      expect(controller.warehouseNotice.value, contains('1 existing rows'));
      final row = (api.writes.single['items'] as List).single as Map;
      expect(row['s_warehouse'], _dxb);
      expect(row['rack'], _rack);
      expect(row['qty'], 1);

      controller.updateItem(
        'SE-ROW-1',
        2,
        '20030506-4BC87Z',
        _rack,
        null,
        _dxb,
        null,
        null,
      );
      expect(await controller.saveDocument(), isFalse);
      expect(api.writes, hasLength(1));
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'server-cleared header replaces the stale default change notice',
    (tester) async {
      controller
        ..mode = 'edit'
        ..name = 'SE-1';
      await controller.fetchDocument();
      controller.changeHeaderWarehouse('WH-DXB3 - KA', source: true);
      expect(
        controller.warehouseNotice.value,
        contains('changed to WH-DXB3 - KA'),
      );

      api.draft = {
        ...api.draft,
        'from_warehouse': null,
        'items': [
          ...api.draft['items'] as List,
          {
            'name': 'SE-ROW-2',
            'item_code': '2003050',
            'qty': 1,
            'batch_no': '20030506-4BC87Z',
            's_warehouse': _wip,
            'rack': _rack,
          },
        ],
      };

      await controller.fetchDocument();
      expect(controller.fromWarehouse.value, isNull);
      expect(
        controller.warehouseNotice.value,
        'Item rows use more than one source warehouse. Review $_dxb, $_wip.',
      );
      expect(controller.stockEntry.value!.items.map((row) => row.sWarehouse), [
        _dxb,
        _wip,
      ]);
    },
  );

  testWidgets('Submit refuses a mismatch on the current saved revision', (
    tester,
  ) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    controller
      ..mode = 'edit'
      ..name = 'SE-1';
    await controller.fetchDocument();

    expect(controller.canSubmit, isTrue);
    final submit = controller.submitDocument();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await submit;
    expect(api.writes, isEmpty);
    expect(
      find.text(
        'Row 1. Rack $_rack belongs to $_wip. This row’s source warehouse is $_dxb.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
