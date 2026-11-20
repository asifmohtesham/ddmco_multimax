import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_binding.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

const _autoSaveDelay = Duration(seconds: 1);

class _FakeStorage extends Fake implements StorageService {
  @override
  int getAutoSaveDelay() => _autoSaveDelay.inSeconds;
}

class _FakeDataWedge extends GetxService implements DataWedgeService {
  @override
  final scannedCode = ''.obs;

  @override
  Future<String?> getVersion() async => null;

  @override
  void injectScan(String code) => scannedCode.value = code;
}

class _FakeApi extends Fake implements ApiProvider {
  final creates = <Map<String, dynamic>>[];

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

void main() {
  late _FakeApi api;

  setUp(() {
    api = _FakeApi();
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(_FakeStorage());
    Get.put<DataWedgeService>(_FakeDataWedge());
    Get.put(ScanService());
  });
  tearDown(Get.reset);

  Future<DeliveryNoteFormController> openNewNote(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: const SizedBox.shrink(),
        getPages: [
          GetPage(
            name: '/note',
            binding: DeliveryNoteFormBinding(),
            page: () => const SizedBox.shrink(),
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

  testWidgets('choosing a warehouse on a new empty note creates nothing', (
    tester,
  ) async {
    final controller = await openNewNote(tester);
    controller.setWarehouse.value = controller.warehouses.single;
    await tester.pump();
    await tester.pump(_autoSaveDelay);

    expect(api.creates, isEmpty);
    expect(controller.setWarehouse.value, 'WH-Pick');
    expect(controller.bannerVisible.value, isFalse);
  });

  testWidgets('manual Save on a new empty note shows the validation banner', (
    tester,
  ) async {
    final controller = await openNewNote(tester);
    await controller.saveDocument();

    expect(api.creates, isEmpty);
    expect(controller.bannerVisible.value, isTrue);
    expect(controller.bannerMessage.value, 'Add an item before saving.');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('adding the first item auto-saves exactly once', (tester) async {
    final controller = await openNewNote(tester);
    controller.setWarehouse.value = controller.warehouses.single;
    await tester.pump();
    await tester.pump(_autoSaveDelay);
    expect(api.creates, isEmpty);

    await controller.addItem(
      DeliveryNoteItem(itemCode: 'ITEM-1', qty: 1, rate: 0),
    );
    await tester.pump(_autoSaveDelay);
    expect(controller.mode, 'edit', reason: controller.bannerMessage.value);
    await tester.pump(const Duration(seconds: 3));

    expect(api.creates, hasLength(1));
    expect(api.creates.single['set_warehouse'], 'WH-Pick');
    expect(api.creates.single['items'], hasLength(1));
  });
}
