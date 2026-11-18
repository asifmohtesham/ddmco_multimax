import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/share_intake_service.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';

/// Records [start] instead of running a job.
class _SpyStockSheetController extends StockSheetController {
  _SpyStockSheetController()
    : super(
        fingerprint: (paths) async => {for (final p in paths) p: 'fp:$p'},
      );

  int starts = 0;

  @override
  Future<void> start(List<String> paths) async {
    starts++;
  }
}

void main() {
  late StreamController<List<String>> warm;
  late List<String> initial;
  late int resets;
  late RxBool signedIn;
  late String route;
  late List<List<String>> opened;
  late List<String> notices;
  _SpyStockSheetController? sheet;

  setUp(() {
    warm = StreamController<List<String>>.broadcast();
    initial = [];
    resets = 0;
    signedIn = false.obs;
    route = AppRoutes.SPLASH;
    opened = [];
    notices = [];
    sheet = null;
  });

  tearDown(() async {
    Get.reset();
    await warm.close();
  });

  Future<ShareIntakeService> make() async {
    final service = Get.put(
      ShareIntakeService(
        warmShares: warm.stream,
        initialShare: () async => initial,
        resetShare: () => resets++,
        isAuthenticated: signedIn,
        currentRoute: () => route,
        openStockSheet: opened.add,
        activeStockSheet: () => sheet,
        notify: notices.add,
      ),
    );
    // Let the initial-share future and stream listeners settle.
    await Future<void>.delayed(Duration.zero);
    return service;
  }

  Future<void> share(List<String> paths) async {
    warm.add(paths);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'a share while signed out is kept until sign-in lands on home',
    () async {
      route = AppRoutes.LOGIN;
      final service = await make();

      await share(['a.jpg', 'b.jpg']);
      expect(service.pendingPhotos, ['a.jpg', 'b.jpg']);
      expect(opened, isEmpty);
      expect(resets, 1);

      // processSuccessfulLogin flips the flag before it leaves the login route.
      signedIn.value = true;
      await Future<void>.delayed(Duration.zero);
      expect(opened, isEmpty, reason: 'still on the login route');

      route = AppRoutes.HOME;
      service.onRouteChanged();
      expect(opened, [
        ['a.jpg', 'b.jpg'],
      ]);
      expect(service.pendingPhotos, isEmpty);

      // A later route change doesn't open it again.
      service.onRouteChanged();
      expect(opened, hasLength(1));
    },
  );

  test('cold start: waits for the splash to hand over to home', () async {
    initial = ['cold.jpg'];
    signedIn.value = true; // the session check succeeds while on the splash
    final service = await make();

    expect(service.pendingPhotos, ['cold.jpg']);
    expect(opened, isEmpty);
    expect(resets, 1);

    route = AppRoutes.HOME;
    service.onRouteChanged();
    expect(opened, [
      ['cold.jpg'],
    ]);
  });

  test(
    'signing in while already on home opens it from the auth worker',
    () async {
      route = AppRoutes.HOME;
      final service = await make();
      await share(['x.jpg']);
      expect(opened, isEmpty);

      signedIn.value = true;
      await Future<void>.delayed(Duration.zero);
      expect(opened, [
        ['x.jpg'],
      ]);
      expect(service.pendingPhotos, isEmpty);
    },
  );

  test('signed in: each share opens the screen and is reset once', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await make();

    await share(['1.jpg']);
    route = AppRoutes.STOCK_ENTRY; // any signed-in screen will do
    await share(['2.jpg']);

    expect(opened, [
      ['1.jpg'],
      ['2.jpg'],
    ]);
    expect(resets, 2);
  });

  test('an empty share is ignored', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    final service = await make();

    await share([]);
    expect(opened, isEmpty);
    expect(resets, 0);
    expect(service.pendingPhotos, isEmpty);
  });

  test(
    'a share while a sheet is being made is dropped with a message',
    () async {
      signedIn.value = true;
      route = AppRoutes.STOCK_SHEET;
      final busySheet = _SpyStockSheetController()
        ..sharedPaths.assignAll(['first.jpg'])
        ..busy.value = true;
      sheet = busySheet;
      final service = await make();

      await share(['second.jpg']);

      expect(notices, ['A stock sheet is already being made.']);
      expect(busySheet.starts, 0);
      expect(busySheet.sharedPaths, ['first.jpg']);
      expect(busySheet.shareSerial.value, 0);
      expect(opened, isEmpty);
      expect(service.pendingPhotos, isEmpty);
      expect(resets, 1);
    },
  );

  test(
    'a share while the sheet is reviewing is held for the screen to ask',
    () async {
      signedIn.value = true;
      route = AppRoutes.STOCK_SHEET;
      final reviewingSheet = _SpyStockSheetController()
        ..sharedPaths.assignAll(['first.jpg'])
        ..phase.value = StockSheetPhase.reviewing;
      sheet = reviewingSheet;
      await make();

      await share(['second.jpg']);
      await pumpEventQueue();

      expect(notices, isEmpty);
      expect(opened, isEmpty);
      expect(reviewingSheet.pendingShare, ['second.jpg']);
      expect(reviewingSheet.sharedPaths, ['first.jpg']);
      expect(reviewingSheet.shareSerial.value, 0);
      expect(reviewingSheet.phase.value, StockSheetPhase.reviewing);
    },
  );

  test('a share while the sheet screen is idle replaces its photos', () async {
    signedIn.value = true;
    route = AppRoutes.STOCK_SHEET;
    final idleSheet = _SpyStockSheetController()
      ..sharedPaths.assignAll(['first.jpg'])
      ..phase.value = StockSheetPhase.done;
    sheet = idleSheet;
    await make();

    await share(['second.jpg', 'third.jpg']);

    expect(notices, isEmpty);
    expect(opened, isEmpty);
    expect(idleSheet.sharedPaths, ['second.jpg', 'third.jpg']);
    expect(idleSheet.shareSerial.value, 1);
    expect(idleSheet.phase.value, StockSheetPhase.idle);
  });

  test('closing the service stops listening', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await make();
    expect(warm.hasListener, isTrue);

    await Get.delete<ShareIntakeService>(force: true);
    expect(warm.hasListener, isFalse);

    signedIn.value = false;
    signedIn.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(opened, isEmpty);
  });
}
