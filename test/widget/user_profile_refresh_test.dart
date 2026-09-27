// test/widget/user_profile_refresh_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/profile/user_profile_controller.dart';

import '../helpers/auth_fakes.dart';

void main() {
  late FakeApiProvider api;
  late AuthenticationController auth;

  setUp(() {
    Get.testMode = false;
    api = FakeApiProvider();
    final storage = FakeStorageService()..stored = cachedUser();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put<UserProvider>(FakeUserProvider(), permanent: true);
    Get.put<StorageService>(storage, permanent: true);
    Get.put<PermissionService>(FakePermissionService(), permanent: true);
    auth = Get.put(AuthenticationController(), permanent: true)
      ..currentUser.value = cachedUser()
      ..isAuthenticated.value = true;
  });

  tearDown(Get.reset);

  /// Opens the app on home, then creates the profile controller, which
  /// refreshes the profile as soon as it is initialised.
  Future<UserProfileController> openProfile(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: AppRoutes.HOME,
      getPages: [
        GetPage(
          name: AppRoutes.HOME,
          page: () => const Scaffold(body: Text('home screen')),
        ),
        GetPage(
          name: AppRoutes.LOGIN,
          page: () => const Scaffold(body: Text('login screen')),
        ),
      ],
    ));
    final profile = Get.put(UserProfileController());
    await tester.pumpAndSettle();
    return profile;
  }

  testWidgets('a network blip while opening the profile changes nothing',
      (tester) async {
    api.onGetLoggedUser = () async => throw networkError();

    final profile = await openProfile(tester);

    expect(find.text('home screen'), findsOneWidget);
    expect(auth.isAuthenticated.value, isTrue);
    expect(api.clearCookieCalls, 0);
    expect(profile.user.value?.email, kTestEmail);
    expect(profile.isLoading.value, isFalse);
  });

  testWidgets('an expired session found while opening the profile '
      'lands on login', (tester) async {
    api.onGetLoggedUser = () async => jsonResponse({'message': 'Guest'});

    await openProfile(tester);

    expect(find.text('login screen'), findsOneWidget);
    expect(find.text('home screen'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
