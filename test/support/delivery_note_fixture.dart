import 'dart:async';

import 'package:dio/dio.dart';
// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_binding.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_screen.dart';

const deliveryNoteAutoSaveDelay = Duration(seconds: 1);

class _FakeStorage extends Fake implements StorageService {
  @override
  int getAutoSaveDelay() => deliveryNoteAutoSaveDelay.inSeconds;

  @override
  String getCompany() => 'Test Company';
}

class _FakeDataWedge extends GetxService implements DataWedgeService {
  @override
  final scannedCode = ''.obs;

  @override
  Future<String?> getVersion() async => null;

  @override
  void injectScan(String code) => scannedCode.value = code;
}

class FakeDeliveryNoteApi extends Fake implements ApiProvider {
  final creates = <Map<String, dynamic>>[];
  final pendingRacks = <String, Completer<RackWarehouseLookup>>{};
  Map<String, dynamic>? existingNote;

  @override
  Future<Response> getDeliveryNote(String name) async {
    expectSync(name, existingNote?['name']);
    return Response(
      requestOptions: RequestOptions(),
      statusCode: 200,
      data: {'data': existingNote},
    );
  }

  @override
  int get rackWarehouseSession => 0;

  @override
  Future<RackWarehouseLookup> getRackWarehouse(String rack) async {
    final pending = pendingRacks.remove(rack);
    if (pending != null) return pending.future;
    return switch (rack) {
      'RACK-PICK' => const RackWarehouseLookup.found(
        'WH-Pick',
        name: 'RACK-PICK',
      ),
      'RACK-TARGET' => const RackWarehouseLookup.found(
        'WH-Target',
        name: 'RACK-TARGET',
      ),
      'RACK-POS-PICK' => const RackWarehouseLookup.found(
        'POS-Pick',
        name: 'RACK-POS-PICK',
      ),
      'KA-WH-DXB1-101A' => const RackWarehouseLookup.found(
        'POS-Other',
        name: 'KA-WH-DXB1-101A',
      ),
      'RACK-POS-OTHER' => const RackWarehouseLookup.found(
        'POS-Other',
        name: 'RACK-POS-OTHER',
      ),
      _ => const RackWarehouseLookup.notFound(),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getList(
    String? positional, {
    String? doctype,
    Map<String, dynamic>? filters,
    List<String>? fields,
    int limit = 20,
    String orderBy = 'modified desc',
    String? groupBy = '',
    String? filterDoctype,
  }) async {
    expectSync(positional ?? doctype, 'Batch');
    return [
      {'name': filters?['name']},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getBatchWiseBalance({
    required String itemCode,
    String? batchNo,
    String? warehouse,
    String? fromDate,
    String? toDate,
  }) async => [
    {'qty': 10},
  ];

  @override
  Future<List<Map<String, dynamic>>> getStockBalanceWithDimension({
    required String itemCode,
    String? warehouse,
    List<String> warehouses = const [],
    String? batchNo,
  }) async => [
    if (warehouse == 'POS-Pick') {'rack': 'RACK-POS-PICK', 'qty': 10},
    if (warehouse == 'POS-Other') ...[
      {'rack': 'RACK-POS-OTHER', 'qty': 10},
      {'rack': 'KA-WH-DXB1-101A', 'qty': 10},
    ],
  ];

  @override
  Future<List<String>> getRacksByWarehouse(String warehouse) async => const [];

  @override
  Future<Response> getDocument(String doctype, String name) async {
    expectSync(doctype, 'Warehouse');
    return Response(
      requestOptions: RequestOptions(),
      statusCode: 200,
      data: {
        'data': {
          'name': name,
          'warehouse_name': name,
          'company': 'Test Company',
          'is_group': 0,
          'disabled': 0,
        },
      },
    );
  }

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
    expectSync(doctype, 'Warehouse');
    return Response(
      requestOptions: RequestOptions(),
      statusCode: 200,
      data: {
        'data': [
          {'name': 'WH-Pick'},
        ],
      },
    );
  }

  @override
  Future<Response> createDocument(
    String doctype,
    Map<String, dynamic> data,
  ) async {
    expectSync(doctype, 'Delivery Note');
    creates.add(data);
    return Response(
      requestOptions: RequestOptions(),
      statusCode: 200,
      data: {
        'data': {...data, 'name': 'DN-001'},
      },
    );
  }
}

FakeDeliveryNoteApi registerDeliveryNoteTestServices() {
  final api = FakeDeliveryNoteApi();
  Get.put<ApiProvider>(api, permanent: true);
  Get.put<StorageService>(_FakeStorage(), permanent: true);
  Get.put<DataWedgeService>(_FakeDataWedge(), permanent: true);
  Get.put(ScanService(), permanent: true);
  return api;
}

Future<DeliveryNoteFormController> openNewDeliveryNote(
  WidgetTester tester, {
  bool renderForm = false,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      home: const SizedBox.shrink(),
      getPages: [
        GetPage(
          name: '/note',
          binding: DeliveryNoteFormBinding(),
          page: () => renderForm
              ? const DeliveryNoteFormScreen()
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
  Get.toNamed('/note', arguments: {'name': '', 'mode': 'new'});
  await tester.pumpAndSettle();
  final controller = Get.find<DeliveryNoteFormController>();
  await tester.pump();
  expect(controller.isLoading.value, isFalse);
  return controller;
}
