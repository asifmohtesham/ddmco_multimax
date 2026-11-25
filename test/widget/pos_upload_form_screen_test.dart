import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pos_upload_delivery.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_binding.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_screen.dart';

class _UnusedApiProvider extends Fake implements ApiProvider {}

class _FakePosUploadProvider extends PosUploadProvider {
  _FakePosUploadProvider(this.status);

  final String status;
  String? returnReason;
  Map<String, dynamic>? deliveryDocinfo;
  final updates = <Map<String, dynamic>>[];

  @override
  Future<Response> getPosUpload(String name) async => Response(
    requestOptions: RequestOptions(path: ''),
    statusCode: 200,
    data: {
      'data': {
        'name': name,
        'status': status,
        'custom_return_reason': returnReason,
      },
    },
  );

  @override
  Future<bool> canWrite(String name) async => true;

  @override
  Future<List<PosDeliveryAction>> getDeliveryActions(String name) async => [];

  @override
  Future<Map<String, dynamic>?> getDeliveryDocinfo(String name) async =>
      deliveryDocinfo;

  @override
  Future<bool> canWriteStatusField(Set<String> userRoles) async => true;

  @override
  Future<Response> updatePosUpload(String name, Map<String, dynamic> data) {
    updates.add(data);
    throw StateError('Unexpected status write');
  }
}

class _OfflinePosUploadFormController extends PosUploadFormController {
  @override
  Future<void> initRealtimeSync() async {}
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(_UnusedApiProvider());
  });
  tearDown(Get.reset);

  Future<void> pumpForm(
    WidgetTester tester,
    _FakePosUploadProvider provider, {
    Size physicalSize = const Size(800, 1000),
    double devicePixelRatio = 1,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(),
        getPages: [
          GetPage(
            name: '/pos-upload-form',
            page: () => const PosUploadFormScreen(),
            binding: PosUploadFormBinding(),
          ),
        ],
      ),
    );

    Get.put<PosUploadProvider>(provider);
    Get.lazyPut<PosUploadFormController>(_OfflinePosUploadFormController.new);
    Get.toNamed<void>(
      '/pos-upload-form',
      arguments: {'name': 'PU-0001', 'mode': 'edit'},
    );
    await tester.pumpAndSettle();
  }

  for (final status in [
    'To Deliver',
    'Out for Delivery',
    'Delivered',
    'Draft',
    'Future Status',
  ]) {
    testWidgets(
      '$status is shown read-only even with status write permission',
      (tester) async {
        final provider = _FakePosUploadProvider(status);
        await pumpForm(tester, provider);

        expect(tester.takeException(), isNull);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        final field = tester.widget<TextField>(_field('Status'));
        expect(field.readOnly, isTrue);
        expect(field.controller!.text, status);

        final controller = Get.find<PosUploadFormController>();
        expect(controller.canWriteStatus.value, isTrue);
        expect(controller.canEditStatus, isFalse);
        await controller.updateStatus('Pending');
        expect(provider.updates, isEmpty);
      },
    );
  }

  testWidgets('manual status choices exclude the delivery stages', (
    tester,
  ) async {
    final provider = _FakePosUploadProvider('Pending');
    await pumpForm(tester, provider);

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.onChanged, isNotNull);
    expect(dropdown.items!.map((item) => item.value), [
      'Pending',
      'In Progress',
      'Completed',
      'Cancelled',
    ]);

    final controller = Get.find<PosUploadFormController>();
    await controller.updateStatus('To Deliver');
    expect(provider.updates, isEmpty);
  });

  testWidgets('Return Reason is read-only and shown only when populated', (
    tester,
  ) async {
    final provider = _FakePosUploadProvider('To Deliver')
      ..returnReason = 'Late';
    await pumpForm(tester, provider);

    final reason = _field('Return Reason');
    expect(tester.widget<TextField>(reason).readOnly, isTrue);
    expect(tester.widget<TextField>(reason).controller!.text, 'Late');

    final controller = Get.find<PosUploadFormController>();
    provider.returnReason = 'Future Reason';
    await controller.fetchPosUpload();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(reason).controller!.text, 'Future Reason');

    provider.returnReason = '';
    await controller.fetchPosUpload();
    await tester.pumpAndSettle();
    expect(reason, findsNothing);
  });

  testWidgets('last delivery event scrolls above the Android navigation bar', (
    tester,
  ) async {
    const physicalSize = Size(1080, 2408);
    const devicePixelRatio = 2.8125;
    const navigationBar = 48 * devicePixelRatio;
    tester.view.padding = const FakeViewPadding(bottom: navigationBar);
    tester.view.viewPadding = const FakeViewPadding(bottom: navigationBar);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final provider = _FakePosUploadProvider('Delivered')
      ..deliveryDocinfo = {
        'versions': [
          for (final (index, action) in [
            'Out for Delivery',
            'Delivery Return',
            'Out for Delivery',
            'Delivered',
          ].indexed)
            {
              'creation': '2026-11-25 23:0$index:02',
              'data': {
                'updater_reference': {
                  'pos_delivery': {
                    'action': action,
                    'driver_name': action == 'Delivered' ? 'Driver A' : 'Driver B',
                    'recorded_by_name': 'Dispatcher',
                    'dn': 'MAT-DN-2026-01199',
                  },
                },
              },
            },
        ],
      };
    await pumpForm(
      tester,
      provider,
      physicalSize: physicalSize,
      devicePixelRatio: devicePixelRatio,
    );

    final details = find.byType(SingleChildScrollView);
    await tester.drag(details, const Offset(0, -1000));
    await tester.pumpAndSettle();

    final recorder = find.text('Driver: Driver A\nRecorded by: Dispatcher');
    final position = Scrollable.of(tester.element(recorder)).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.extentAfter, 0);
    final navigationBarTop =
        (physicalSize.height - navigationBar) / devicePixelRatio;
    expect(tester.getRect(recorder).bottom, lessThan(navigationBarTop));
  });
}
