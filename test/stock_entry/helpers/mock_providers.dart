// Mock helpers shared across all Stock Entry unit tests.
// Uses the Fake pattern (no Mockito codegen required).
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

// ---------------------------------------------------------------------------
// Minimal Response helper
// ---------------------------------------------------------------------------
Response<dynamic> okResponse(dynamic data) => Response(
      data: {'data': data},
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    );

Response<dynamic> emptyOk() => okResponse([]);

// ---------------------------------------------------------------------------
// Fake ApiProvider — returns empty successful responses by default
// ---------------------------------------------------------------------------
class FakeApiProvider extends ApiProvider {
  @override
  Future<Response> getDocumentList(String doctype,
      {int limit = 20,
      int limitStart = 0,
      Map<String, dynamic>? filters,
      Map<String, dynamic>? orFilters,
      List<String>? fields,
      String orderBy = 'modified desc'}) async =>
      emptyOk();

  @override
  Future<Response> getDocument(String doctype, String name) async =>
      okResponse({});

  @override
  Future<Response> createDocument(
          String doctype, Map<String, dynamic> data) async =>
      okResponse({'name': 'MAT-STE-NEW-0001'});

  @override
  Future<Response> updateDocument(
          String doctype, String name, Map<String, dynamic> data) async =>
      okResponse({'name': name, 'modified': '2026-01-01 00:00:00.000000'});

  // Stock balance stubs — overridden per test when needed
  @override
  Future<Response> getStockBalance({
    required String itemCode,
    String? warehouse,
    String? batchNo,
    String? rack,
  }) async =>
      okResponse([]);

  @override
  Future<Response> getBatchWiseBalance(String itemCode, String batchNo,
          {String? warehouse}) async =>
      okResponse([]);

  @override
  Future<Response> getStockEntry(String name) async => okResponse({
        'name': name,
        'stock_entry_type': 'Material Transfer',
        'docstatus': 0,
        'purpose': 'Material Transfer',
        'total_amount': 0,
        'posting_date': '2026-01-01',
        'modified': '2026-01-01 00:00:00.000000',
        'creation': '2026-01-01 00:00:00.000000',
        'currency': 'AED',
        'items': [],
      });
}

// ---------------------------------------------------------------------------
// Fake StockEntryProvider
// ---------------------------------------------------------------------------
class FakeStockEntryProvider extends StockEntryProvider {
  @override
  Future<Response> getStockEntries(
          {int limit = 20,
          int limitStart = 0,
          Map<String, dynamic>? filters,
          String orderBy = 'modified desc'}) async =>
      emptyOk();

  @override
  Future<Response> getStockEntryTypes() async => okResponse([
        {'name': 'Material Transfer'},
        {'name': 'Material Issue'},
        {'name': 'Material Receipt'},
        {'name': 'Material Transfer for Manufacture'},
      ]);

  @override
  Future<Response> getStockEntry(String name) async => okResponse({
        'name': name,
        'stock_entry_type': 'Material Transfer',
        'docstatus': 0,
        'purpose': 'Material Transfer',
        'total_amount': 0,
        'posting_date': '2026-01-01',
        'modified': '2026-01-01 00:00:00.000000',
        'creation': '2026-01-01 00:00:00.000000',
        'currency': 'AED',
        'items': [],
      });

  @override
  Future<Response> createStockEntry(Map<String, dynamic> data) async =>
      okResponse({'name': 'MAT-STE-NEW-0001'});

  @override
  Future<Response> updateStockEntry(
          String name, Map<String, dynamic> data) async =>
      okResponse({'name': name, 'modified': '2026-01-01 00:00:00.000000'});
}

// ---------------------------------------------------------------------------
// Fake PosUploadProvider
// ---------------------------------------------------------------------------
class FakePosUploadProvider extends PosUploadProvider {
  @override
  Future<Response> getPosUploads({
    int limit = 50,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async =>
      emptyOk();
}

// ---------------------------------------------------------------------------
// Fake MaterialRequestProvider
// ---------------------------------------------------------------------------
class FakeMaterialRequestProvider extends MaterialRequestProvider {
  @override
  Future<Response> getMaterialRequests({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async =>
      emptyOk();
}

// ---------------------------------------------------------------------------
// Fake UserProvider
// ---------------------------------------------------------------------------
class FakeUserProvider extends UserProvider {
  @override
  Future<Response> getUsers(
          {int limit = 20,
          Map<String, dynamic>? filters}) async =>
      emptyOk();
}

// ---------------------------------------------------------------------------
// Fake WarehouseProvider
// ---------------------------------------------------------------------------
class FakeWarehouseProvider extends WarehouseProvider {
  @override
  Future<Response> getWarehouses(
          {int limit = 100,
          Map<String, dynamic>? filters}) async =>
      emptyOk();
}

// ---------------------------------------------------------------------------
// Fake StorageService
// ---------------------------------------------------------------------------
class FakeStorageService extends StorageService {
  @override
  bool getAutoSubmitEnabled() => false;

  @override
  int getAutoSubmitDelay() => 3;
}

// ---------------------------------------------------------------------------
// Fake ScanService
// ---------------------------------------------------------------------------
class FakeScanService extends ScanService {
  // No-op — scan results are driven directly per test
}

// ---------------------------------------------------------------------------
// Fake DataWedgeService
// ---------------------------------------------------------------------------
class FakeDataWedgeService extends DataWedgeService {
  // No-op — scannedCode is never fired in unit tests
}

// ---------------------------------------------------------------------------
// Registration helpers
// ---------------------------------------------------------------------------

/// Registers all fakes into the GetX container for form-controller tests.
void registerFormFakes() {
  Get.put<ApiProvider>(FakeApiProvider(), permanent: true);
  Get.put<StockEntryProvider>(FakeStockEntryProvider());
  Get.put<PosUploadProvider>(FakePosUploadProvider());
  Get.put<StorageService>(FakeStorageService());
  Get.put<ScanService>(FakeScanService());
  Get.put<DataWedgeService>(FakeDataWedgeService());
}

/// Registers all fakes into the GetX container for list-controller tests.
void registerListFakes() {
  Get.put<ApiProvider>(FakeApiProvider(), permanent: true);
  Get.put<StockEntryProvider>(FakeStockEntryProvider());
  Get.put<PosUploadProvider>(FakePosUploadProvider());
  Get.put<MaterialRequestProvider>(FakeMaterialRequestProvider());
  Get.put<UserProvider>(FakeUserProvider());
  Get.put<WarehouseProvider>(FakeWarehouseProvider());
}
