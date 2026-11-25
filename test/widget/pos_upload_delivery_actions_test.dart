import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pos_upload_delivery.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_binding.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_screen.dart';

class _UnusedApiProvider extends Fake implements ApiProvider {}

class _OfflineFormController extends PosUploadFormController {
  @override
  Future<void> initRealtimeSync() async {}
}

class _DeliveryProvider extends PosUploadProvider {
  static const driverOptions = PosDeliveryDriverOptions(
    drivers: [
      PosDeliveryDriver(name: 'DRV-1', fullName: 'Driver One'),
      PosDeliveryDriver(name: 'DRV-2', fullName: 'Driver Two'),
    ],
    defaultDriver: 'DRV-1',
  );

  String status = 'Out for Delivery';
  bool discoveryFails = false;
  List<PosDeliveryAction> actions = [
    PosDeliveryAction.deliveryReturn,
    PosDeliveryAction.delivered,
  ];
  Completer<PosDeliveryDriverOptions>? pendingDrivers;
  Completer<PosUpload>? pendingApply;
  DioException? applyError;
  int documentReads = 0;
  int actionReads = 0;
  int auditReads = 0;
  final driverRequests = <PosDeliveryAction>[];
  final applied = <(PosDeliveryAction, PosDeliverySelection)>[];

  Map<String, dynamic> _pos(String name) => {
    'doctype': 'POS Upload',
    'name': name,
    'status': status,
    'modified': '2026-11-25 19:20:11.123456',
  };

  @override
  Future<Response> getPosUpload(String name) async {
    documentReads++;
    return Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'data': _pos(name)},
    );
  }

  @override
  Future<List<PosDeliveryAction>> getDeliveryActions(String name) async {
    actionReads++;
    if (discoveryFails) throw StateError('Transition discovery denied');
    return actions;
  }

  @override
  Future<PosDeliveryDriverOptions> getDeliveryDrivers(
    String name,
    PosDeliveryAction action,
  ) async {
    driverRequests.add(action);
    final pending = pendingDrivers;
    return pending == null ? driverOptions : await pending.future;
  }

  @override
  Future<PosUpload> applyDeliveryAction(
    PosUpload upload,
    PosDeliveryAction action,
    PosDeliverySelection selection,
  ) async {
    applied.add((action, selection));
    if (applyError case final error?) throw error;
    if (pendingApply case final pending?) return pending.future;
    status = action.requiresReason ? 'To Deliver' : action.label;
    actions = [];
    return PosUpload.fromJson(_pos(upload.name));
  }

  @override
  Future<Map<String, dynamic>?> getDeliveryDocinfo(String name) async {
    auditReads++;
    return null;
  }

  @override
  Future<bool> canWrite(String name) async => true;

  @override
  Future<bool> canWriteStatusField(Set<String> userRoles) async => true;
}

DioException _applyFailure(int status, Map<String, dynamic> body) {
  final request = RequestOptions(
    path: '/api/method/frappe.model.workflow.apply_workflow',
  );
  return DioException.badResponse(
    statusCode: status,
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: status, data: body),
  );
}

Map<String, dynamic> _serverMessage(String message) => {
  '_server_messages': jsonEncode([
    jsonEncode({'message': message}),
  ]),
};

Future<PosDeliverySelection?> _selectDriver(
  PosDeliveryDriverOptions options,
) async => PosDeliverySelection(driver: options.defaultDriver!);

Finder _action(PosDeliveryAction action) => find.byWidgetPredicate(
  (widget) => widget is AsyncFilledButton && widget.label == action.label,
);

Finder _actionButton(PosDeliveryAction action) => find.descendant(
  of: _action(action),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

final _confirm = find.widgetWithText(FilledButton, 'Confirm');

Future<void> _animateOverlay(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

double _contrast(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  return aLuminance > bLuminance
      ? (aLuminance + 0.05) / (bLuminance + 0.05)
      : (bLuminance + 0.05) / (aLuminance + 0.05);
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(_UnusedApiProvider(), permanent: true);
  });
  tearDown(Get.reset);

  Future<PosUploadFormController> pumpForm(
    WidgetTester tester,
    _DeliveryProvider provider, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scheme = AppScheme.of(brightness);
    final theme = ThemeData(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: scheme.primary,
            brightness: brightness,
          ).copyWith(
            primary: scheme.primary,
            onPrimary: scheme.onPrimary,
            surface: scheme.fg,
            onSurface: scheme.text,
          ),
    );

    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme,
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
    Get.lazyPut<PosUploadFormController>(_OfflineFormController.new);
    Get.toNamed<void>(
      '/pos-upload-form',
      arguments: {'name': 'PU-0001', 'mode': 'edit'},
    );
    await tester.pumpAndSettle();
    return Get.find<PosUploadFormController>();
  }

  testWidgets('failed action discovery leaves status read-only with a retry', (
    tester,
  ) async {
    final provider = _DeliveryProvider()
      ..status = 'Pending'
      ..discoveryFails = true
      ..actions = [PosDeliveryAction.outForDelivery];
    final controller = await pumpForm(tester, provider);

    expect(find.byType(AsyncFilledButton), findsNothing);
    expect(controller.canWriteStatus.value, isTrue);
    expect(controller.canEditStatus, isFalse);
    final statusDropdown = find.byType(DropdownButton<String>);
    expect(
      tester.widget<DropdownButton<String>>(statusDropdown).onChanged,
      isNull,
    );

    provider.discoveryFails = false;
    await tester.tap(find.byTooltip('Retry delivery actions'));
    await tester.pumpAndSettle();
    expect(_action(PosDeliveryAction.outForDelivery), findsOneWidget);
    expect(find.byTooltip('Retry delivery actions'), findsNothing);
    expect(provider.applied, isEmpty);
  });

  testWidgets('Return preselects the driver and requires a selected reason', (
    tester,
  ) async {
    final provider = _DeliveryProvider();
    await pumpForm(tester, provider);

    await tester.tap(_action(PosDeliveryAction.deliveryReturn));
    await _animateOverlay(tester);
    final driver = find.byType(DropdownButton<String>);
    expect(tester.widget<DropdownButton<String>>(driver).value, 'DRV-1');
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);

    await tester.tap(driver);
    await _animateOverlay(tester);
    await tester.tap(find.text('Driver Two').last);
    await _animateOverlay(tester);
    expect(tester.widget<DropdownButton<String>>(driver).value, 'DRV-2');
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);

    await tester.tap(find.byType(DropdownButton<PosDeliveryReason>));
    await _animateOverlay(tester);
    await tester.tap(find.text('Rejected').last);
    await _animateOverlay(tester);
    await tester.tap(_confirm);
    await tester.pumpAndSettle();

    final (action, selection) = provider.applied.single;
    expect(action, PosDeliveryAction.deliveryReturn);
    expect(selection.driver, 'DRV-2');
    expect(selection.reason, PosDeliveryReason.rejected);
  });

  testWidgets('dismissing a driver sheet sends no action', (tester) async {
    final provider = _DeliveryProvider();
    final controller = await pumpForm(tester, provider);

    await tester.ensureVisible(_action(PosDeliveryAction.delivered));
    await tester.tap(_action(PosDeliveryAction.delivered));
    await _animateOverlay(tester);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.byType(DropdownButton<PosDeliveryReason>), findsNothing);
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(provider.applied, isEmpty);
    expect(controller.deliveryActionBusy.value, isFalse);
  });

  testWidgets('a 417 validation failure shows the server message', (
    tester,
  ) async {
    const message = 'Select an active Driver.';
    final provider = _DeliveryProvider()
      ..applyError = _applyFailure(417, _serverMessage(message));
    final controller = await pumpForm(tester, provider);

    await controller.runDeliveryAction(
      PosDeliveryAction.delivered,
      _selectDriver,
    );
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(provider.documentReads, 1);
    expect(controller.deliveryActionBusy.value, isFalse);
  });

  for (final (label, error, notice) in [
    (
      'stale revision',
      _applyFailure(
        417,
        _serverMessage(
          'This POS Upload changed. Reload it and use Actions again.',
        ),
      ),
      'This POS Upload changed. Reload it and use Actions again. Try again.',
    ),
    (
      'deadlock',
      _applyFailure(500, {'exc_type': 'QueryDeadlockError'}),
      'The POS Upload was being updated. Try the action again.',
    ),
  ]) {
    testWidgets('a $label refreshes the form and offers a retry', (
      tester,
    ) async {
      final provider = _DeliveryProvider()..applyError = error;
      final controller = await pumpForm(tester, provider);
      provider.status = 'To Deliver';
      provider.actions = [PosDeliveryAction.outForDelivery];

      await controller.runDeliveryAction(
        PosDeliveryAction.delivered,
        _selectDriver,
      );
      await tester.pumpAndSettle();

      expect(find.text(notice), findsOneWidget);
      expect(controller.posUpload.value?.status, 'To Deliver');
      expect(controller.deliveryActions, [PosDeliveryAction.outForDelivery]);
      expect(provider.documentReads, 2);
      expect(provider.actionReads, 2);
      expect(provider.auditReads, 2);
    });
  }

  testWidgets('an apply reply after reload cannot replace the current POS', (
    tester,
  ) async {
    final pending = Completer<PosUpload>();
    final provider = _DeliveryProvider()..pendingApply = pending;
    final controller = await pumpForm(tester, provider);

    final applying = controller.runDeliveryAction(
      PosDeliveryAction.delivered,
      _selectDriver,
    );
    await tester.pump();
    expect(provider.applied, hasLength(1));
    provider.status = 'To Deliver';
    provider.actions = [PosDeliveryAction.outForDelivery];
    await controller.reloadDocument();
    pending.complete(
      PosUpload.fromJson({'name': controller.name, 'status': 'Delivered'}),
    );
    await applying;
    await tester.pumpAndSettle();

    expect(controller.posUpload.value?.status, 'To Deliver');
    expect(controller.deliveryActions, [PosDeliveryAction.outForDelivery]);
    expect(provider.documentReads, 2);
    expect(find.text('Delivery action recorded'), findsNothing);
    expect(controller.deliveryActionBusy.value, isFalse);
  });

  testWidgets('an apply reply after navigating away is ignored', (
    tester,
  ) async {
    final pending = Completer<PosUpload>();
    final provider = _DeliveryProvider()
      ..pendingApply = pending
      ..actions = [PosDeliveryAction.delivered];
    final controller = await pumpForm(tester, provider);
    await tester.tap(_action(PosDeliveryAction.delivered));
    await _animateOverlay(tester);
    await tester.tap(_confirm);
    await _animateOverlay(tester);
    expect(provider.applied, hasLength(1));

    Get.to<void>(() => const Scaffold(body: Text('Another screen')));
    await _animateOverlay(tester);
    expect(find.text('Another screen'), findsOneWidget);
    pending.complete(
      PosUpload.fromJson({'name': controller.name, 'status': 'Delivered'}),
    );
    await tester.pumpAndSettle();

    expect(controller.posUpload.value?.status, 'Out for Delivery');
    expect(provider.documentReads, 1);
    expect(find.text('Delivery action recorded'), findsNothing);
    expect(controller.deliveryActionBusy.value, isFalse);
  });

  testWidgets('the header spinner repaints and two taps start one request', (
    tester,
  ) async {
    final provider = _DeliveryProvider()
      ..pendingDrivers = Completer<PosDeliveryDriverOptions>();
    final controller = await pumpForm(tester, provider);
    const action = PosDeliveryAction.deliveryReturn;
    final spinner = find.descendant(
      of: _action(action),
      matching: find.byType(CircularProgressIndicator),
    );

    expect(spinner, findsNothing);
    controller.deliveryActionBusy.value = true;
    await _animateOverlay(tester);
    expect(spinner, findsOneWidget);
    expect(
      tester.widget<FilledButton>(_actionButton(action)).onPressed,
      isNull,
    );
    expect(
      tester.widget<CircularProgressIndicator>(spinner).color,
      AppScheme.light.onPrimary,
    );
    controller.deliveryActionBusy.value = false;
    await tester.pumpAndSettle();
    expect(spinner, findsNothing);

    // Invoke both controls before their disabled state can repaint.
    final sendReturn = tester.widget<AsyncFilledButton>(_action(action));
    final sendDelivered = tester.widget<AsyncFilledButton>(
      _action(PosDeliveryAction.delivered),
    );
    sendReturn.onPressed();
    sendDelivered.onPressed();
    expect(provider.driverRequests, [action]);
    provider.pendingDrivers!.complete(_DeliveryProvider.driverOptions);
    await _animateOverlay(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  for (final brightness in Brightness.values) {
    testWidgets('header and sheet use readable ${brightness.name} colors', (
      tester,
    ) async {
      final provider = _DeliveryProvider();
      await pumpForm(tester, provider, brightness: brightness);
      const action = PosDeliveryAction.deliveryReturn;
      final scheme = AppScheme.of(brightness);
      final buttonStyle = tester
          .widget<FilledButton>(_actionButton(action))
          .style!;
      final enabledFill = buttonStyle.backgroundColor!.resolve({})!;
      final enabledInk = buttonStyle.foregroundColor!.resolve({})!;
      expect(_contrast(enabledFill, enabledInk), greaterThanOrEqualTo(4.5));

      await tester.tap(_action(action));
      await _animateOverlay(tester);
      final spinner = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: _action(action),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(
        _contrast(spinner.color!, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );

      final sheet = find.byType(BottomSheet);
      final sheetFill = tester.widget<BottomSheet>(sheet).backgroundColor!;
      expect(sheetFill, scheme.fg);
      final title = tester.widget<Text>(
        find.descendant(of: sheet, matching: find.text(action.label)),
      );
      expect(
        _contrast(title.style!.color!, sheetFill),
        greaterThanOrEqualTo(4.5),
      );
      final select = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(
        _contrast(select.style!.color!, select.dropdownColor!),
        greaterThanOrEqualTo(4.5),
      );
      final field = tester.widget<InputDecorator>(
        find.descendant(
          of: sheet,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is InputDecorator &&
                widget.decoration.labelText == 'Driver',
          ),
        ),
      );
      expect(
        _contrast(
          field.decoration.labelStyle!.color!,
          field.decoration.fillColor!,
        ),
        greaterThanOrEqualTo(4.5),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  }
}
