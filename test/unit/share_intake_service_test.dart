import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/share_intake_service.dart';
import 'package:multimax/app/modules/stock_sheet/items_from_photos_controller.dart';

/// Records [start] instead of running a job.
class _SpyItemsFromPhotosController extends ItemsFromPhotosController {
  _SpyItemsFromPhotosController()
    : super(fingerprint: (paths) async => {for (final p in paths) p: 'fp:$p'});

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
  late List<String> quickActions;
  late List<String> notices;
  late StreamController<List<String>> drops;
  late StreamController<int> dropFailures;
  late StreamController<void> resumes;
  late List<String> stranded;
  late int handled;
  _SpyItemsFromPhotosController? sheet;

  setUp(() {
    warm = StreamController<List<String>>.broadcast();
    initial = [];
    resets = 0;
    signedIn = false.obs;
    route = AppRoutes.SPLASH;
    opened = [];
    quickActions = [];
    notices = [];
    sheet = null;
    drops = StreamController<List<String>>.broadcast();
    dropFailures = StreamController<int>.broadcast();
    resumes = StreamController<void>.broadcast();
    stranded = [];
    handled = 0;
  });

  tearDown(() async {
    Get.reset();
    await warm.close();
    await drops.close();
    await dropFailures.close();
    await resumes.close();
  });

  Future<ShareIntakeService> make({
    Future<void> Function(String)? openQuickActions,
  }) async {
    final service = Get.put(
      ShareIntakeService(
        warmShares: warm.stream,
        initialShare: () async => initial,
        resetShare: () => resets++,
        isAuthenticated: signedIn,
        currentRoute: () => route,
        openItemsFromPhotos: opened.add,
        openItemQuickActions:
            openQuickActions ?? (path) async => quickActions.add(path),
        activeItemsFromPhotos: () => sheet,
        notify: notices.add,
        drops: drops.stream,
        dropFailures: dropFailures.stream,
        resumes: resumes.stream,
        strandedShare: () async {
          final taken = stranded;
          stranded = [];
          return taken;
        },
        markShareHandled: () async {
          handled++;
          stranded = [];
        },
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
    expect(quickActions, isEmpty);
    expect(resets, 1);

    route = AppRoutes.HOME;
    service.onRouteChanged();
    expect(quickActions, ['cold.jpg']);
  });

  test(
    'signing in while already on home opens it from the auth worker',
    () async {
      route = AppRoutes.HOME;
      final service = await make();
      await share(['x.jpg']);
      expect(opened, isEmpty);
      expect(quickActions, isEmpty);
      expect(service.pendingPhotos, ['x.jpg']);

      signedIn.value = true;
      await Future<void>.delayed(Duration.zero);
      expect(quickActions, ['x.jpg']);
      expect(service.pendingPhotos, isEmpty);
    },
  );

  test(
    'signed in: routes one and several photos and resets once each',
    () async {
      signedIn.value = true;
      route = AppRoutes.HOME;
      await make();

      await share(['1.jpg']);
      route = AppRoutes.STOCK_ENTRY; // any signed-in screen will do
      await share(['2.jpg', '3.jpg']);

      expect(quickActions, ['1.jpg']);
      expect(opened, [
        ['2.jpg', '3.jpg'],
      ]);
      expect(resets, 2);
    },
  );

  test('one photo while signed out waits for login to hand over', () async {
    route = AppRoutes.LOGIN;
    final service = await make();
    await share(['one.jpg']);
    signedIn.value = true;
    await pumpEventQueue();
    expect(quickActions, isEmpty);
    expect(service.pendingPhotos, ['one.jpg']);

    route = AppRoutes.HOME;
    service.onRouteChanged();
    service.onRouteChanged();
    expect(quickActions, ['one.jpg']);
    expect(opened, isEmpty);
  });

  test('a share received during quick actions opens when they close', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    final closeQuickActions = Completer<void>();
    final service = await make(
      openQuickActions: (path) {
        quickActions.add(path);
        return closeQuickActions.future;
      },
    );
    await share(['one.jpg']);
    await share(['two.jpg', 'three.jpg']);
    expect(quickActions, ['one.jpg']);
    expect(service.pendingPhotos, ['two.jpg', 'three.jpg']);
    expect(opened, isEmpty);

    closeQuickActions.complete();
    await pumpEventQueue();
    expect(opened, [
      ['two.jpg', 'three.jpg'],
    ]);
    expect(service.pendingPhotos, isEmpty);
  });

  test('an empty share is ignored', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    final service = await make();

    await share([]);
    expect(opened, isEmpty);
    expect(quickActions, isEmpty);
    expect(resets, 0);
    expect(service.pendingPhotos, isEmpty);
  });

  test(
    'a share while a sheet is being made is dropped with a message',
    () async {
      signedIn.value = true;
      route = AppRoutes.ITEMS_FROM_PHOTOS;
      final busySheet = _SpyItemsFromPhotosController()
        ..sharedPaths.assignAll(['first.jpg'])
        ..busy.value = true;
      sheet = busySheet;
      final service = await make();

      await share(['second.jpg']);

      expect(notices, ['Items from Photos is already generating a file.']);
      expect(busySheet.starts, 0);
      expect(busySheet.sharedPaths, ['first.jpg']);
      expect(busySheet.shareSerial.value, 0);
      expect(opened, isEmpty);
      expect(quickActions, isEmpty);
      expect(service.pendingPhotos, isEmpty);
      expect(resets, 1);
    },
  );

  test(
    'a share while the sheet is reviewing is held for the screen to ask',
    () async {
      signedIn.value = true;
      route = AppRoutes.ITEMS_FROM_PHOTOS;
      final reviewingSheet = _SpyItemsFromPhotosController()
        ..sharedPaths.assignAll(['first.jpg'])
        ..phase.value = ItemsFromPhotosPhase.reviewing;
      sheet = reviewingSheet;
      await make();

      await share(['second.jpg']);
      await pumpEventQueue();

      expect(notices, isEmpty);
      expect(opened, isEmpty);
      expect(quickActions, isEmpty);
      expect(reviewingSheet.pendingShare, ['second.jpg']);
      expect(reviewingSheet.sharedPaths, ['first.jpg']);
      expect(reviewingSheet.shareSerial.value, 0);
      expect(reviewingSheet.phase.value, ItemsFromPhotosPhase.reviewing);
    },
  );

  test('a share while the sheet screen is idle replaces its photos', () async {
    signedIn.value = true;
    route = AppRoutes.ITEMS_FROM_PHOTOS;
    final idleSheet = _SpyItemsFromPhotosController()
      ..sharedPaths.assignAll(['first.jpg'])
      ..phase.value = ItemsFromPhotosPhase.done;
    sheet = idleSheet;
    await make();

    await share(['second.jpg', 'third.jpg']);

    expect(notices, isEmpty);
    expect(opened, isEmpty);
    expect(idleSheet.sharedPaths, ['second.jpg', 'third.jpg']);
    expect(idleSheet.shareSerial.value, 1);
    expect(idleSheet.phase.value, ItemsFromPhotosPhase.idle);
  });

  test(
    'one photo can open quick actions above an idle Items from Photos',
    () async {
      signedIn.value = true;
      route = AppRoutes.ITEMS_FROM_PHOTOS;
      sheet = _SpyItemsFromPhotosController()
        ..sharedPaths.assignAll(['first.jpg'])
        ..phase.value = ItemsFromPhotosPhase.done;
      await make();
      await share(['second.jpg']);

      expect(quickActions, ['second.jpg']);
      expect(sheet?.sharedPaths, ['first.jpg']);
    },
  );

  test('a drop is delivered like a share', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await make();

    drops.add(['/d/a.jpg']);
    await pumpEventQueue();

    expect(quickActions, ['/d/a.jpg']);
  });

  test('a drop while a sheet is being made shows the busy message', () async {
    signedIn.value = true;
    route = AppRoutes.ITEMS_FROM_PHOTOS;
    sheet = _SpyItemsFromPhotosController()
      ..sharedPaths.assignAll(['first.jpg'])
      ..busy.value = true;
    await make();

    drops.add(['/d/b.jpg']);
    await pumpEventQueue();

    expect(notices, [ShareIntakeService.busyMessage]);
    expect(opened, isEmpty);
  });

  test('a drop with no readable photo says so and opens nothing', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await make();

    dropFailures.add(2);
    await pumpEventQueue();

    expect(notices, ["Couldn't read these photos."]);
    expect(ShareIntakeService.dropFailedMessage, "Couldn't read these photos.");
    expect(opened, isEmpty);
  });

  test('a warm share marks the share handled', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await make();

    await share(['w.jpg']);

    expect(handled, 1);
  });

  const delay = Duration(milliseconds: 20);

  Future<ShareIntakeService> makeStranded(
    Future<List<String>> Function() strandedShare, {
    Future<void> Function()? markHandled,
  }) async {
    final service = Get.put(
      ShareIntakeService(
        warmShares: warm.stream,
        initialShare: () async => [],
        resetShare: () => resets++,
        isAuthenticated: signedIn,
        currentRoute: () => route,
        openItemsFromPhotos: opened.add,
        openItemQuickActions: (path) async => quickActions.add(path),
        activeItemsFromPhotos: () => sheet,
        notify: notices.add,
        drops: drops.stream,
        dropFailures: dropFailures.stream,
        resumes: resumes.stream,
        strandedShare: strandedShare,
        markShareHandled: markHandled ?? () async => handled++,
        strandedDelay: delay,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    return service;
  }

  test('a stranded share is picked up after resume', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await makeStranded(() async => ['/g/a.jpg']);

    resumes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(quickActions, isEmpty, reason: 'still inside the delay');

    await Future<void>.delayed(delay * 3);
    expect(quickActions, ['/g/a.jpg']);
  });

  test('a stranded share is picked up at start-up without a resume', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await makeStranded(() async => ['/g/cold.jpg']);
    expect(opened, isEmpty, reason: 'still inside the delay');

    await Future<void>.delayed(delay * 3);
    expect(quickActions, ['/g/cold.jpg']);
  });

  test('a share delivered by URL is not picked up again on resume', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    var strandedLeft = ['/g/a.jpg'];
    await makeStranded(
      () async => strandedLeft,
      markHandled: () async {
        handled++;
        strandedLeft = [];
      },
    );

    await share(['/g/a.jpg']);
    resumes.add(null);
    await Future<void>.delayed(delay * 3);

    expect(quickActions, ['/g/a.jpg']);
    expect(handled, 1);
  });

  test('closing the service stops listening', () async {
    signedIn.value = true;
    route = AppRoutes.HOME;
    await make();
    expect(warm.hasListener, isTrue);

    await Get.delete<ShareIntakeService>(force: true);
    expect(warm.hasListener, isFalse);
    expect(drops.hasListener, isFalse);
    expect(dropFailures.hasListener, isFalse);
    expect(resumes.hasListener, isFalse);

    signedIn.value = false;
    signedIn.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(opened, isEmpty);
  });
}
