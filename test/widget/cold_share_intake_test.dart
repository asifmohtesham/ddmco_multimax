import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/share_intake_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/item/widgets/share_item_quick_actions.dart';
import 'package:xml/xml.dart';

import '../helpers/auth_fakes.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('a cold single-photo share opens above the restored Home route', (
    tester,
  ) async {
    // FlutterActivity forwards Intent.data as the initial route whenever its
    // built-in deep linking is enabled. Model that native input using the
    // activity's manifest so the real Navigator sees the resulting route.
    const android = 'http://schemas.android.com/apk/res/android';
    final manifest = XmlDocument.parse(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );
    final activity = manifest
        .findAllElements('activity')
        .singleWhere(
          (element) =>
              element.getAttribute('name', namespace: android) ==
              '.MainActivity',
        );
    final handlesDeepLinks = !activity
        .findElements('meta-data')
        .any(
          (element) =>
              element.getAttribute('name', namespace: android) ==
                  'flutter_deeplinking_enabled' &&
              element.getAttribute('value', namespace: android) == 'false',
        );
    final dispatcher = tester.binding.platformDispatcher;
    if (handlesDeepLinks) {
      dispatcher.defaultRouteNameTestValue =
          'content://media/external/images/media/42';
      addTearDown(dispatcher.clearDefaultRouteNameTestValue);
    }

    final session = Completer<Response>();
    Get.put<ApiProvider>(
      FakeApiProvider()..onGetLoggedUser = () => session.future,
      permanent: true,
    );
    Get.put<UserProvider>(FakeUserProvider(), permanent: true);
    Get.put<StorageService>(FakeStorageService(), permanent: true);
    Get.put<PermissionService>(FakePermissionService(), permanent: true);
    Get.put(AuthenticationController(), permanent: true);
    Get.put(ScanService(), permanent: true);
    final intake = Get.put(
      ShareIntakeService(
        warmShares: const Stream.empty(),
        initialShare: () async => ['/shared/label.jpg'],
        resetShare: () {},
        drops: const Stream.empty(),
        dropFailures: const Stream.empty(),
        resumes: const Stream.empty(),
        strandedShare: () async => [],
        markShareHandled: () async {},
      ),
    );
    try {
      await tester.pumpWidget(
        GetMaterialApp(
          initialRoute: AppRoutes.SPLASH,
          defaultTransition: Transition.fadeIn,
          getPages: [
            AppPages.routes.firstWhere((page) => page.name == AppRoutes.SPLASH),
            GetPage(
              name: AppRoutes.HOME,
              page: () => const Scaffold(body: Text('home screen')),
            ),
          ],
          routingCallback: (_) => intake.onRouteChanged(),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(intake.pendingPhotos, ['/shared/label.jpg']);
      expect(find.byType(ShareItemQuickActions), findsNothing);

      session.complete(jsonResponse({'message': kTestEmail}));
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ShareItemQuickActions), findsOneWidget);
      expect(tester.takeException(), isNull);

      Get.key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('home screen'), findsOneWidget);
      expect(find.byType(ShareItemQuickActions), findsNothing);
      expect(Get.key.currentState!.canPop(), isFalse);
    } finally {
      await Get.delete<ShareIntakeService>(force: true);
    }
  });
}
