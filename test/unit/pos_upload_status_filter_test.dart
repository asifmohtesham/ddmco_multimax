import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/customer_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';

/// The POS Upload DocType's `status` options on the server, without the
/// blank one (production v16, read 16/11/2026). The DocType is not
/// submittable, so there is no Draft or Submitted.
const _serverStatuses = ['Pending', 'In Progress', 'Completed', 'Cancelled'];

Response _ok(List<Map<String, dynamic>> rows) => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'data': rows},
    );

/// Records the filters each list query sends to the server.
class _RecordingPosUploadProvider extends PosUploadProvider {
  final sent = <Map<String, dynamic>>[];

  @override
  Future<Response> getPosUploads({
    int limit = 50,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    sent.add(Map<String, dynamic>.from(filters ?? const {}));
    return _ok(const []);
  }
}

class _FakeCustomerProvider extends CustomerProvider {
  @override
  Future<Response> getCustomers({int limit = 0, String? searchTerm}) async =>
      _ok(const []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PosUpload.statusOptions', () {
    test('are exactly the DocType status options, in option order', () {
      expect(PosUpload.statusOptions, _serverStatuses);
    });

    test('offer no Draft or Submitted, which no upload can have', () {
      expect(PosUpload.statusOptions, isNot(contains('Draft')));
      expect(PosUpload.statusOptions, isNot(contains('Submitted')));
    });
  });

  group('POS Upload list status filter', () {
    late _RecordingPosUploadProvider provider;
    late PosUploadController controller;

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async => r'C:\temp\test_cookies',
      );
    });

    setUp(() async {
      Get.testMode = true;
      Get.put(ApiProvider());
      provider = Get.put<PosUploadProvider>(_RecordingPosUploadProvider())
          as _RecordingPosUploadProvider;
      Get.put<CustomerProvider>(_FakeCustomerProvider());
      controller = Get.put(PosUploadController());
      await pumpEventQueue();
      provider.sent.clear(); // drop the unfiltered first load
    });
    tearDown(Get.reset);

    for (final choice in PosUpload.statusOptions) {
      test('the status bar choice "$choice" asks for status = $choice',
          () async {
        controller.toggleStatusFilter(choice);
        await pumpEventQueue();
        expect(provider.sent.single, {'status': choice});
        expect(_serverStatuses, contains(provider.sent.single['status']));
      });

      test('the filter sheet choice "$choice" asks for status = $choice',
          () async {
        controller.applyFilters({'status': choice, 'customer': 'CUST-A'});
        await pumpEventQueue();
        expect(provider.sent.single, {'status': choice, 'customer': 'CUST-A'});
      });
    }

    test('a second tap on the same choice clears the status filter', () async {
      controller.toggleStatusFilter('Pending');
      controller.toggleStatusFilter('Pending');
      await pumpEventQueue();
      expect(provider.sent.last, isEmpty);
      expect(controller.activeFilters.containsKey('status'), isFalse);
    });
  });
}
