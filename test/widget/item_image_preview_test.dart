import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
// Keep the Material import used by the app's supported Flutter SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';

const _url = 'https://erp.example.com/private/files/item.png';
final _imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAGQAAAAMCAAAAACxLke/AAAAGElEQVR4nGNooANg'
  'GLVk1JJRS0YtoS4AAKfwWB+YukmJAAAAAElFTkSuQmCC',
);

class _FileApi extends Fake implements ApiProvider {
  final requests = <String>[];
  final pendingDownload = Completer<Uint8List>();

  @override
  Future<Uint8List> getFileBytes(String url) {
    requests.add(url);
    if (requests.length > 1) return pendingDownload.future;
    return SynchronousFuture(_imageBytes);
  }
}

TransformationController _transform(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

Future<void> _openPreview(WidgetTester tester) async {
  Get.put<ApiProvider>(_FileApi());
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showItemImagePreview(context, _url, 'ITEM', ''),
            child: const Text('Open image'),
          ),
        ),
      ),
    ),
  );
  final context = tester.element(find.text('Open image'));
  await tester.runAsync(() => precacheImage(MemoryImage(_imageBytes), context));
  await tester.tap(find.text('Open image'));
  await tester.pumpAndSettle();
}

Future<void> _doubleTap(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(position);
  await tester.pump();
}

void main() {
  tearDown(Get.reset);

  testWidgets('double tap animates to 2.5x at the tap and resets', (
    tester,
  ) async {
    await _openPreview(tester);
    final viewer = find.byType(InteractiveViewer);
    final tap = tester.getCenter(viewer) + const Offset(25, 3);
    final localTap = tap - tester.getTopLeft(viewer);
    final transform = _transform(tester);
    expect(transform.value.getMaxScaleOnAxis(), 1);

    await _doubleTap(tester, tap);
    await tester.pump(const Duration(milliseconds: 110));
    expect(transform.value.getMaxScaleOnAxis(), inExclusiveRange(1, 2.5));
    await tester.pumpAndSettle();
    expect(transform.value.getMaxScaleOnAxis(), closeTo(2.5, 0.001));
    expect(transform.toScene(localTap).dx, closeTo(localTap.dx, 0.001));
    expect(transform.toScene(localTap).dy, closeTo(localTap.dy, 0.001));

    await _doubleTap(tester, tap);
    await tester.pumpAndSettle();
    expect(transform.value, Matrix4.identity());
  });

  for (final axis in [
    const Offset(1, 0),
    const Offset(0, 1),
    const Offset(1, 1),
  ]) {
    testWidgets('pinch on axis $axis zooms and pan stays in bounds', (
      tester,
    ) async {
      await _openPreview(tester);
      final viewer = find.byType(InteractiveViewer);
      final center = tester.getCenter(viewer);
      final transform = _transform(tester);
      final a = await tester.startGesture(center - axis * 30);
      final b = await tester.startGesture(center + axis * 30);
      for (final distance in [45.0, 65.0, 85.0, 100.0]) {
        await a.moveTo(center - axis * distance);
        await b.moveTo(center + axis * distance);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final scale = transform.value.getMaxScaleOnAxis();
      expect(scale, greaterThan(1));

      await tester.dragFrom(center, const Offset(40, 40));
      await tester.pumpAndSettle();
      final afterPan = transform.value.getTranslation();
      await tester.dragFrom(center, const Offset(-1000, -1000));
      await tester.pumpAndSettle();
      final afterReversePan = transform.value.getTranslation();
      final viewport = tester.getSize(viewer);
      expect(afterReversePan.x, lessThan(afterPan.x));
      expect(afterReversePan.y, lessThan(afterPan.y));
      expect(
        afterReversePan.x,
        inInclusiveRange(viewport.width * (1 - scale) - 0.001, 0),
      );
      expect(
        afterReversePan.y,
        inInclusiveRange(viewport.height * (1 - scale) - 0.001, 0),
      );
      final renderedImage = find.descendant(
        of: viewer,
        matching: find.byType(RawImage),
      );
      final imageCenter = tester.getCenter(renderedImage);
      expect(tester.getRect(viewer).contains(imageCenter), isTrue);
    });
  }

  testWidgets('download spins while pending and ignores duplicate taps', (
    tester,
  ) async {
    await _openPreview(tester);
    final api = Get.find<ApiProvider>() as _FileApi;
    final action = find.byType(AsyncIconButton);
    final button = find.descendant(
      of: action,
      matching: find.byType(IconButton),
    );
    // Both taps run against the same rendered button, before it can disable.
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(api.requests, [_url, _url]);
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(
      find.descendant(
        of: action,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    api.pendingDownload.completeError(StateError('Download failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(
      find.descendant(
        of: find.byType(ItemImagePreview),
        matching: find.text('Could not download or save the file. Try again.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android download passes the original bytes to Pictures', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const gal = MethodChannel('gal');
    final messenger = tester.binding.defaultBinaryMessenger;
    final galleryCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(gal, (call) async {
      galleryCalls.add(call);
      return call.method == 'requestPermission' ? true : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(gal, null));

    await _openPreview(tester);
    await tester.tap(find.byTooltip('Download'));
    (Get.find<ApiProvider>() as _FileApi).pendingDownload.complete(_imageBytes);
    await tester.pumpAndSettle();

    expect(galleryCalls.map((call) => call.method), [
      'requestPermission',
      'putImageBytes',
    ]);
    expect(galleryCalls.last.arguments['bytes'], _imageBytes);
    expect(galleryCalls.last.arguments['name'], 'item');
    expect(
      find.descendant(
        of: find.byType(ItemImagePreview),
        matching: find.text('Image saved to Pictures.'),
      ),
      findsOneWidget,
    );
  });
}
